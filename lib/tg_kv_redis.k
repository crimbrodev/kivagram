// lib/tg_kv_redis.k — V5-C: Redis-бэкенд KV поверх RESP2 (Serialization Protocol).
//
// Контракт (повторяет tg_kv_get/set/del из lib/tg_kv.k):
//   tg_kv_redis_connect(host, port, password|0) → 1/0 — socket+connect,
//     SO_RCVTIMEO 5с (recv не виснет), AUTH при password != 0 (иначе 0 —
//     закрытый сокет). host — ТОЛЬКО IPv4-литерал ("127.0.0.1"): резолв имён
//     (gethostbyname/inet_addr) вне спайка линковки, не используется.
//   tg_kv_redis_get(key)   → указатель на NUL-строку в общем буфере значений
//     либо 0 (нет ключа / nil / ошибка). Жизнь указателя — до следующего
//     get/set/del/close (слот-кэш, как у tg_kv_get).
//   tg_kv_redis_set(key, val) → 1 — сервер ответил +OK, 0 — ошибка.
//   tg_kv_redis_del(key)      → 1 — ключ удалён (:N, N>0), 0 — не был/ошибка.
//   tg_kv_redis_close()       → закрыть сокет (1).
//
// Изоляция I/O: ЯДРО ПРОТОКОЛА (кодировщик tg_kv_redis_enc_cmd и декодер
// tg_kv_redis_parse[_at]/_bulk) работает БЕЗ сети и покрыто детерминированным
// тестом tests/t_v5_kvredis.k. Сетевой слой (tg_redis_send/read,
// tg_kv_redis_connect/get/set/del/close) требует живого redis-server —
// локально его нет, поэтому эти функции тестом не покрываются (ручная
// проверка: connect("127.0.0.1", 6379, 0) → set/get/del).
//
// RESP-кодирование: `*<n>\r\n` + на каждый аргумент `$<len>\r\n<data>\r\n`,
// len = strlen(data) в БАЙТАХ (UTF-8). Подстановки нет НИКАКОЙ: длина
// считается по данным, поэтому пробел, \r\n или кавычка в ключе/значении не
// могут разорвать команду — инъекция в RESP невозможна по построению
// (в отличие от SQL, здесь bulk-длина изолирует данные от протокола).
// Литералы Kiva не умеют \r — везде "\x0d\n".
//
// RESP-декодер, слот &tg_rslot:
//   [0] type: 1 '+' simple, 2 '$' bulk, 3 ':' integer, 4 '-' error,
//       5 '*' array (только счётчик — элементы через parse_at(end)),
//       0 — нет элемента/неверный;
//   [1] val*  — копия значения (0 у nil и у не-строковых типов);
//   [2] num   — integer / длина bulk / счётчик массива; -1 у nil ($-1);
//   [3] end   — смещение сразу за элементом (для потоков и массивов);
//   [4] status: 0 ок, 1 неполный (читать дальше), 2 неверный,
//       3 транспортная ошибка (нет соединения/ответа).
// Ограничения (документировано): значения — C-строки, bulk с внутренним NUL
// разбор прекращает как «неполный» (контракт KV — строки); ответ читается в
// NUL-терминированный буфер до 1 МБ (128 × 8 КБ).

extern strlen
extern memcpy
extern malloc
extern free
extern printf
extern socket
extern connect
extern send
extern recv
extern close
extern setsockopt

tg_rslot[8];       // слот результата разбора (см. шапку)
tg_redis_enc[4];   // Buf: последняя закодированная команда RESP
tg_redis_rbuf[4];  // Buf: сырой ответ сервера (NUL за данными)
tg_redis_vbuf[4];  // Buf: копия значения элемента ответа
tg_redis_tmp[1024];// 8 КБ: приёмный чанк recv
tg_redis_args[8];  // слот-массив аргументов текущей команды (GET/SET/DEL/AUTH)
tg_redis_fd;       // дескриптор сокета (0 — закрыт)
tg_redis_on;       // 1 — соединение установлено
tg_redis_sa[2];    // sockaddr_in (16 байт)
tg_redis_optv[1];  // int для setsockopt

// ===== Разбор RESP =====

// tg_r_crlf(s, off): смещение "\r" пары \r\n начиная с off; -1 — не найдено
tg_r_crlf(s, off) {
    auto i;
    auto c;
    auto r;
    auto done;
    i = off;
    r = 0 - 1;
    done = 0;
    while done == 0 {
        c = @8 *(s + i);
        if c == 0 done = 1;
        else if c == 13 {
            if @8 *(s + i + 1) == 10 {
                r = i;
                done = 1;
            } else i = i + 1;
        } else i = i + 1;
    }
    r;
}

// tg_r_num(s, off, stop): число со знаком из [off, stop); прочие байты —
// пропуск (значения сравнений БЕЗЗНАКОВЫЕ — stop обязан быть >= 0)
tg_r_num(s, off, stop) {
    auto i;
    auto c;
    auto v;
    auto neg;
    i = off;
    v = 0;
    neg = 0;
    if i < stop {
        if @8 *(s + i) == 45 {
            neg = 1;
            i = i + 1;
        }
    }
    while i < stop {
        c = @8 *(s + i);
        if c >= 48 {
            if c <= 57 v = v * 10 + (c - 48);
        }
        i = i + 1;
    }
    if neg != 0 v = 0 - v;
    v;
}

// tg_r_slot_reset(status): обнулить слот результата
tg_r_slot_reset(st) {
    tg_rslot[0] = 0;
    tg_rslot[1] = 0;
    tg_rslot[2] = 0;
    tg_rslot[3] = 0;
    tg_rslot[4] = st;
    1;
}

// tg_rv_set(src, n): копия ровно n байт + NUL в общий буфер значения
tg_rv_set(src, n) {
    auto b;
    auto need;
    auto np;
    b = &tg_redis_vbuf;
    need = n + 1;
    if need > b[2] {
        np = malloc(need + need);
        if np == 0 return 0;
        if b[0] memcpy(np, b[0], b[1]);
        if b[0] free(b[0]);
        b[0] = np;
        b[2] = need + need;
    }
    if n > 0 memcpy(b[0], src, n);
    *(b[0] + n) !8 0;
    b[1] = n;
    1;
}

// tg_kv_redis_parse_at(s, off): один RESP-элемент начиная с off → &tg_rslot
tg_kv_redis_parse_at(s, off) {
    auto t;
    auto cr;
    auto len;
    auto ds;
    auto i;
    auto ok;

    tg_r_slot_reset(2);
    t = @8 *(s + off);
    if t == 0 {
        tg_rslot[4] = 1;        // данных нет — неполный
        return &tg_rslot;
    }

    if t == 43 {                // "+строка"
        cr = tg_r_crlf(s, off + 1);
        if cr > 4000000000 {
            tg_rslot[4] = 1;
            return &tg_rslot;
        }
        tg_rv_set(s + off + 1, cr - off - 1);
        tg_rslot[0] = 1;
        tg_rslot[1] = tg_redis_vbuf[0];
        tg_rslot[2] = cr - off - 1;
        tg_rslot[3] = cr + 2;
        tg_rslot[4] = 0;
    } else if t == 45 {         // "-ошибка"
        cr = tg_r_crlf(s, off + 1);
        if cr > 4000000000 {
            tg_rslot[4] = 1;
            return &tg_rslot;
        }
        tg_rv_set(s + off + 1, cr - off - 1);
        tg_rslot[0] = 4;
        tg_rslot[1] = tg_redis_vbuf[0];
        tg_rslot[3] = cr + 2;
        tg_rslot[4] = 0;
    } else if t == 58 {         // ":int"
        cr = tg_r_crlf(s, off + 1);
        if cr > 4000000000 {
            tg_rslot[4] = 1;
            return &tg_rslot;
        }
        tg_rslot[0] = 3;
        tg_rslot[2] = tg_r_num(s, off + 1, cr);
        tg_rslot[3] = cr + 2;
        tg_rslot[4] = 0;
    } else if t == 36 {         // "$len\r\n<data>\r\n"
        cr = tg_r_crlf(s, off + 1);
        if cr > 4000000000 {
            tg_rslot[4] = 1;
            return &tg_rslot;
        }
        len = tg_r_num(s, off + 1, cr);
        if len > 4000000000 {   // отрицательная длина (сравнения беззнаковые)
            if len == 0 - 1 {
                tg_rslot[0] = 2;    // $-1 → nil
                tg_rslot[1] = 0;
                tg_rslot[2] = 0 - 1;
                tg_rslot[3] = cr + 2;
                tg_rslot[4] = 0;
            } else tg_rslot[4] = 2; // $-2 и прочее — неверный ответ
        } else {
            ds = cr + 2;
            ok = 1;
            i = 0;
            while i < len {
                if @8 *(s + ds + i) == 0 ok = 0;  // буфер обрывается раньше
                i = i + 1;
            }
            if ok == 0 tg_rslot[4] = 1;
            else if @8 *(s + ds + len) != 13 tg_rslot[4] = 1;
            else if @8 *(s + ds + len + 1) != 10 tg_rslot[4] = 1;
            else {
                tg_rv_set(s + ds, len);
                tg_rslot[0] = 2;
                tg_rslot[1] = tg_redis_vbuf[0];
                tg_rslot[2] = len;
                tg_rslot[3] = ds + len + 2;
                tg_rslot[4] = 0;
            }
        }
    } else if t == 42 {         // "*n" — только счётчик, элементы — parse_at
        cr = tg_r_crlf(s, off + 1);
        if cr > 4000000000 {
            tg_rslot[4] = 1;
            return &tg_rslot;
        }
        tg_rslot[0] = 5;
        tg_rslot[2] = tg_r_num(s, off + 1, cr);
        tg_rslot[3] = cr + 2;
        tg_rslot[4] = 0;
    }
    &tg_rslot;                  // иначе остаётся status=2 (неизвестный тип)
}

// tg_kv_redis_parse(s): элемент с начала строки → &tg_rslot
tg_kv_redis_parse(s) {
    auto r;
    r = tg_kv_redis_parse_at(s, 0);
    r;
}

// tg_kv_redis_parse_bulk(s, off): значение bulk-элемента или 0 (не bulk).
// ВНИМАНИЕ: перезаписывает слот результата.
tg_kv_redis_parse_bulk(s, off) {
    auto r;
    r = 0;
    tg_kv_redis_parse_at(s, off);
    if tg_rslot[0] == 2 r = tg_rslot[1];
    r;
}

// ===== Кодировщик RESP =====

// tg_kv_redis_enc_cmd(n, ptrs): n аргументов из слот-массива указателей
// (ptrs[i] — NUL-строка) → строка-команда в общем буфере (указатель живёт
// до следующего вызова). Длины считаются strlen — данные в протокол не
// подставляются.
tg_kv_redis_enc_cmd(n, ptrs) {
    auto b;
    auto i;
    auto s;
    b = &tg_redis_enc;
    tg_buf_reset(b);
    tg_buf_add(b, "*");
    tg_buf_addnum(b, n);
    tg_buf_add(b, "\x0d\n");
    i = 0;
    while i < n {
        s = ptrs[i];
        tg_buf_add(b, "$");
        tg_buf_addnum(b, strlen(s));
        tg_buf_add(b, "\x0d\n");
        tg_buf_add(b, s);
        tg_buf_add(b, "\x0d\n");
        i = i + 1;
    }
    b[0];
}

// ===== Сетевой слой (требует живой redis-server) =====

// tg_redis_append(b, src, n): сырые n байт в Buf + NUL
tg_redis_append(b, src, n) {
    auto need;
    auto np;
    if n <= 0 return 1;
    need = b[1] + n + 1;
    if need > b[2] {
        np = malloc(need + need);
        if np == 0 return 0;
        if b[0] memcpy(np, b[0], b[1]);
        if b[0] free(b[0]);
        b[0] = np;
        b[2] = need + need;
    }
    memcpy(b[0] + b[1], src, n);
    b[1] = b[1] + n;
    *(b[0] + b[1]) !8 0;
    1;
}

// tg_redis_send(s): отправить строку целиком (MSG_NOSIGNAL=16384)
tg_redis_send(s) {
    auto n;
    auto len;
    auto off;
    len = strlen(s);
    off = 0;
    while off < len {
        n = send(tg_redis_fd, s + off, len - off, 16384);
        if n > 4000000000 return 0;
        if n == 0 return 0;
        off = off + n;
    }
    1;
}

// tg_redis_read(): прочитать ОДИН ответ до полноты → данные или 0.
// Полота определяется разбором: элемент разобран и end == прочитано.
tg_redis_read() {
    auto b;
    auto n;
    auto guard;
    auto done;
    b = &tg_redis_rbuf;
    tg_buf_reset(b);
    guard = 0;
    done = 0;
    while done == 0 {
        if guard > 128 return 0;        // > 1 МБ ответа — отказ
        guard = guard + 1;
        n = recv(tg_redis_fd, &tg_redis_tmp, 8192, 0);
        if n > 4000000000 return 0;     // ошибка/таймаут сокета
        if n == 0 return 0;             // сервер закрыл соединение
        if tg_redis_append(b, &tg_redis_tmp, n) == 0 return 0;
        tg_kv_redis_parse_at(b[0], 0);
        if tg_rslot[4] == 2 {
            printf("kv: redis: malformed reply\n");
            return 0;
        }
        if tg_rslot[4] == 0 {
            if tg_rslot[3] == b[1] done = 1;
        }
    }
    b[0];
}

// tg_redis_call(n, ptrs): enc → send → read → parse → &tg_rslot
tg_redis_call(n, ptrs) {
    auto cmd;
    tg_r_slot_reset(3);
    if tg_redis_on == 0 {
        printf("kv: redis: not connected (tg_kv_redis_connect first)\n");
        return &tg_rslot;
    }
    cmd = tg_kv_redis_enc_cmd(n, ptrs);
    if tg_redis_send(cmd) == 0 {
        printf("kv: redis: send failed\n");
        return &tg_rslot;
    }
    if tg_redis_read() == 0 {
        printf("kv: redis: no reply\n");
        tg_r_slot_reset(3);
        return &tg_rslot;
    }
    &tg_rslot;
}

// tg_r_ip4(host): IPv4-литерал → 32-бит адрес (network order) либо 0
// (ошибка разбора; 0.0.0.0 адресом сервера не считаем)
tg_r_ip4(host) {
    auto i;
    auto c;
    auto oct;
    auto part;
    auto v;
    auto bad;
    auto done;
    if host == 0 return 0;
    i = 0;
    oct = 0;
    part = 0;
    v = 0;
    bad = 0;
    done = 0;
    while done == 0 {
        c = @8 *(host + i);
        if c >= 48 {
            if c <= 57 {
                oct = oct * 10 + (c - 48);
                if oct > 255 bad = 1;
                i = i + 1;
            } else {
                bad = 1;
                done = 1;
            }
        } else {
            if c == 46 {
                part = part + 1;
                v = (v << 8) | oct;
                oct = 0;
                i = i + 1;
            } else done = 1;
        }
    }
    if bad == 1 return 0;
    if part != 3 return 0;
    if c != 0 return 0;
    v = (v << 8) | oct;
    if v == 0 return 0;
    v;
}

// tg_kv_redis_connect(host, port, password|0) → 1/0
tg_kv_redis_connect(host, port, password) {
    auto fd;
    auto r;
    auto ip;
    auto p;
    auto i;
    auto slot;

    tg_kv_redis_close();
    if host == 0 {
        printf("kv: redis: no host\n");
        return 0;
    }
    ip = tg_r_ip4(host);
    if ip == 0 {
        printf("kv: redis: bad host '%s' (нужен IPv4-литерал)\n", host);
        return 0;
    }
    fd = socket(2, 1, 0);
    if fd > 4000000000 {
        printf("kv: redis: socket() failed (no network?)\n");
        return 0;
    }
    p = &tg_redis_sa;
    i = 0;
    while i < 16 {
        *p !8 0;
        p = p + 1;
        i = i + 1;
    }
    p = &tg_redis_sa;
    *p !8 2;                        // AF_INET
    *(p + 2) !8 (port >> 8);        // порт в network order (побайтово)
    *(p + 3) !8 (port & 255);
    *(p + 4) !8 (ip >> 24);
    *(p + 5) !8 ((ip >> 16) & 255);
    *(p + 6) !8 ((ip >> 8) & 255);
    *(p + 7) !8 (ip & 255);
    r = connect(fd, &tg_redis_sa, 16);
    if r > 4000000000 {
        printf("kv: redis: connect %s:%ld failed\n", host, port);
        close(fd);
        return 0;
    }
    tg_redis_optv[0] = 5;           // SO_RCVTIMEO 5с — recv не зависнет
    setsockopt(fd, 1, 20, &tg_redis_optv, 4);
    tg_redis_fd = fd;
    tg_redis_on = 1;
    if password != 0 {
        tg_redis_args[0] = "AUTH";
        tg_redis_args[1] = password;
        slot = tg_redis_call(2, &tg_redis_args);
        if slot[4] != 0 {
            printf("kv: redis: AUTH: no reply\n");
            tg_kv_redis_close();
            return 0;
        }
        if slot[0] != 1 {
            printf("kv: redis: AUTH rejected\n");
            tg_kv_redis_close();
            return 0;
        }
    }
    1;
}

// tg_kv_redis_close(): закрыть сокет (1)
tg_kv_redis_close() {
    if tg_redis_on != 0 close(tg_redis_fd);
    tg_redis_fd = 0;
    tg_redis_on = 0;
    1;
}

// tg_kv_redis_get(key): значение в общем буфере или 0
tg_kv_redis_get(key) {
    auto r;
    auto slot;
    r = 0;
    tg_redis_args[0] = "GET";
    tg_redis_args[1] = key;
    slot = tg_redis_call(2, &tg_redis_args);
    if slot[4] == 0 {
        if slot[0] == 4 printf("kv: redis: %s\n", slot[1]);
        else if slot[0] == 2 r = slot[1];   // 0 у nil ($-1)
    }
    r;
}

// tg_kv_redis_set(key, val): 1 — +OK, 0 — ошибка
tg_kv_redis_set(key, val) {
    auto r;
    auto slot;
    r = 0;
    tg_redis_args[0] = "SET";
    tg_redis_args[1] = key;
    tg_redis_args[2] = val;
    slot = tg_redis_call(3, &tg_redis_args);
    if slot[4] == 0 {
        if slot[0] == 1 r = 1;
        else if slot[0] == 4 printf("kv: redis: %s\n", slot[1]);
    }
    r;
}

// tg_kv_redis_del(key): 1 — ключ был удалён (:N, N>0), 0 — иначе
tg_kv_redis_del(key) {
    auto r;
    auto slot;
    r = 0;
    tg_redis_args[0] = "DEL";
    tg_redis_args[1] = key;
    slot = tg_redis_call(2, &tg_redis_args);
    if slot[4] == 0 {
        if slot[0] == 4 printf("kv: redis: %s\n", slot[1]);
        else if slot[0] == 3 {
            if slot[2] != 0 r = 1;
        }
    }
    r;
}
