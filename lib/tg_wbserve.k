// tg_wbserve.k — W3-3: HTTP-сервер приёма апдейтов (webhook) на сокетах libc.
//
// Входные точки:
//   tg_webhook_serve(bot, port, secret*|0) — bind+listen + цикл шагов;
//   tg_wb_open(bot, port, secret*|0)       — только открытие listen-сокета
//      (SO_REUSEADDR, bind 0.0.0.0:port, listen backlog 8);
//   tg_wb_step(bot, sfd, secret*|0)        — ОДНА итерация: accept одного
//      соединения с select-таймаутом 1с → чтение → ответ → диспетчер;
//   tg_wb_parse(buf, len)                  — чистый парсер запроса без сети,
//      результат — статический слот tg_wbslot (unit-тестится отдельно).
//
// Секрет: tg_wb_open / tg_wb_step кладут secret* в глобальный tg_wb_secret,
// tg_wb_parse сверяет заголовок X-Telegram-Bot-Api-Secret-Token с ним
// (регистр имён заголовков не важен, значение — точно). secret==0 → без сверки.
//
// Диспетчер — ТА ЖЕ точка, что в tg_polling: tg_handle_update(bot, upd)
// (ctx внутри собирает tg_ctx_build); тело вебхука — готовый JSON апдейта.
// Ответ 200+ok уходит СРАЗУ, до диспатча (Telegram требует быстрый 200).
//
// Статусы: не POST → 404; секрет мимо/отсутствует → 403; тело обрезанное
// или пустое (нет Content-Length) → 400; иначе 200 + диспетчер (только 200).
//
// Языковые ловушки: сравнения БЕЗЗНАКОВЫЕ — ошибка int-extern выглядит как
// 4294967295 (eax нулевое расширение), ssize_t-recv-1 — как 0xFFFF...F;
// ловим обоих единым порогом >4000000000 (легитимные значения ≤ 1056769).
// В литералах НЕТ \r — только "\x0d\n". send с MSG_NOSIGNAL(16384), иначе
// SIGPIPE от отключённого клиента убивает процесс.

extern socket
extern bind
extern listen
extern accept
extern close
extern shutdown
extern recv
extern send
extern select
extern setsockopt

// Результат tg_wb_parse — статический слот (по образцу слотов ядра):
//  0 valid, 1 method (1 POST / 2 GET / 3 иное), 2 content_length,
//  3 body_ptr*, 4 body_len, 5 secret_present, 6 secret_ok, 7 incomplete,
//  8 hend (позиция после \r\n\r\n), 9 cl_present; 10..15 — резерв.
tg_wbslot[16];
tg_wb_secret;    // ожидаемый secret* (0 — сверка не требуется)
tg_wb_fds[16];   // fd_set: 1024 бита = 128 байт
tg_wb_tv[2];     // timeval (сек, микросек)
tg_wb_sa[2];     // sockaddr_in (16 байт)
tg_wb_optv[1];   // int для setsockopt

// tg_wb_find_hdr(buf, len): позиция ПОСЛЕ первого "\r\n\r\n" либо 0
tg_wb_find_hdr(buf, len) {
    auto i;
    auto done;
    i = 0;
    done = 0;
    if len > 3 {
        while i <= len - 4 {
            if @8 *(buf+i) == 13 {
                if @8 *(buf+i+1) == 10 {
                    if @8 *(buf+i+2) == 13 {
                        if @8 *(buf+i+3) == 10 {
                            done = i + 4;
                            i = len;
                        }
                    }
                }
            }
            i = i + 1;
        }
    }
    done;
}

// tg_wb_ci_eq(s, n, lit): n байт s == литерал lit без регистра (ASCII)
tg_wb_ci_eq(s, n, lit) {
    auto i;
    auto a;
    auto b;
    if n != strlen(lit) return 0;
    i = 0;
    while i < n {
        a = @8 *(s+i);
        b = @8 *(lit+i);
        if a > 64 {
            if a < 91 a = a + 32;
        }
        if b > 64 {
            if b < 91 b = b + 32;
        }
        if a != b return 0;
        i = i + 1;
    }
    1;
}

// tg_wb_sec_eq(v, n, secret*): n байт v == secret (точно, по длине —
// значение в заголовке не NUL-терминировано). secret==0 → 0 (нет сверки).
tg_wb_sec_eq(v, n, secret) {
    auto i;
    if secret == 0 return 0;
    if n != strlen(secret) return 0;
    i = 0;
    while i < n {
        if @8 *(v+i) != @8 *(secret+i) return 0;
        i = i + 1;
    }
    1;
}

// tg_wb_num(s, n): число из n цифр; нецифры → 0 (битое значение → пусто)
tg_wb_num(s, n) {
    auto i;
    auto c;
    auto v;
    auto ok;
    v = 0;
    ok = 1;
    i = 0;
    while i < n {
        c = @8 *(s+i);
        if c < 48 ok = 0;
        else if c > 57 ok = 0;
        else v = v * 10 + (c - 48);
        i = i + 1;
    }
    if ok == 0 v = 0;
    v;
}

// tg_wb_parse(buf, len): чистый парсер HTTP-запроса → &tg_wbslot.
// Нет \r\n\r\n → valid==0. Нет Content-Length → пустое тело (cl_present==0,
// body_len==0). len < hend+Content-Length → incomplete==1 (ответ 400).
tg_wb_parse(buf, len) {
    auto i;
    auto hend;
    auto ls;
    auto le;
    auto colon;
    auto cn;
    auto n;
    auto c;
    auto v;
    auto done;

    i = 0;
    while i < 16 {
        tg_wbslot[i] = 0;
        i = i + 1;
    }
    hend = tg_wb_find_hdr(buf, len);
    tg_wbslot[8] = hend;
    if hend == 0 return &tg_wbslot;

    // метод: первый токен строки запроса (до пробела)
    le = 0;
    done = 0;
    while done == 0 {
        if le >= hend done = 1;
        else if @8 *(buf+le) == 32 done = 1;
        else le = le + 1;
    }
    n = le;
    if n > 0 {
        tg_wbslot[0] = 1;
        tg_wbslot[1] = 3;
        if n == 4 {
            if tg_wb_ci_eq(buf, 4, "POST") tg_wbslot[1] = 1;
        }
        if n == 3 {
            if tg_wb_ci_eq(buf, 3, "GET") tg_wbslot[1] = 2;
        }
    }

    // начало заголовков — после конца строки запроса
    ls = 0;
    done = 0;
    while done == 0 {
        if ls + 1 >= hend done = 1;
        else if @8 *(buf+ls) == 13 {
            if @8 *(buf+ls+1) == 10 {
                done = 1;
                ls = ls + 2;
            } else ls = ls + 1;
        } else ls = ls + 1;
    }

    // строки заголовков [ls, le)
    while ls < hend {
        le = ls;
        done = 0;
        while done == 0 {
            if le >= hend done = 1;
            else if @8 *(buf+le) == 13 done = 1;
            else le = le + 1;
        }
        n = le - ls;
        if n > 0 {
            colon = ls;
            done = 0;
            while done == 0 {
                if colon >= le done = 1;
                else if @8 *(buf+colon) == 58 done = 1;
                else colon = colon + 1;
            }
            if colon < le {
                cn = colon - ls;
                v = colon + 1;
                done = 0;
                while done == 0 {
                    if v >= le done = 1;
                    else {
                        c = @8 *(buf+v);
                        if c == 32 v = v + 1;
                        else if c == 9 v = v + 1;
                        else done = 1;
                    }
                }
                if tg_wb_ci_eq(buf+ls, cn, "content-length") {
                    tg_wbslot[9] = 1;
                    tg_wbslot[2] = tg_wb_num(buf+v, le - v);
                }
                if tg_wb_ci_eq(buf+ls, cn, "x-telegram-bot-api-secret-token") {
                    tg_wbslot[5] = 1;
                    if tg_wb_sec_eq(buf+v, le - v, tg_wb_secret) tg_wbslot[6] = 1;
                }
            }
        }
        ls = le + 2;   // следующая строка — после CR
    }

    // тело: без Content-Length — пустое (слоты уже 0)
    if tg_wbslot[9] == 1 {
        n = len - hend;
        if n > tg_wbslot[2] n = tg_wbslot[2];
        tg_wbslot[4] = n;
        tg_wbslot[3] = buf + hend;
        if n < tg_wbslot[2] tg_wbslot[7] = 1;
    }
    &tg_wbslot;
}

// tg_wb_resp(code): статусная строка HTTP/1.1 с CRLF (нет \r в литералах)
tg_wb_resp(code) {
    if code == 200 return "HTTP/1.1 200 OK\x0d\nContent-Length: 2\x0d\nConnection: close\x0d\n\x0d\nok";
    if code == 400 return "HTTP/1.1 400 Bad Request\x0d\nContent-Length: 0\x0d\nConnection: close\x0d\n\x0d\n";
    if code == 403 return "HTTP/1.1 403 Forbidden\x0d\nContent-Length: 0\x0d\nConnection: close\x0d\n\x0d\n";
    "HTTP/1.1 404 Not Found\x0d\nContent-Length: 0\x0d\nConnection: close\x0d\n\x0d\n";
}

// tg_wb_reply(cfd, code): отправить ответ целиком (счёт, MSG_NOSIGNAL)
tg_wb_reply(cfd, code) {
    auto s;
    auto n;
    auto off;
    auto r;
    s = tg_wb_resp(code);
    n = strlen(s);
    off = 0;
    while off < n {
        r = send(cfd, s + off, n - off, 16384);   // 16384 = MSG_NOSIGNAL
        if r > 4000000000 off = n;
        else if r == 0 off = n;
        else off = off + r;
    }
    1;
}

// tg_wb_wait(fd, sec, usec): select-ожидание чтения fd → 1 готово /
// 0 таймаут или ошибка сокета (закрытый fd → 0, не виснем)
tg_wb_wait(fd, sec, usec) {
    auto r;
    auto w;
    auto b;
    auto i;
    if fd > 1023 return 0;
    i = 0;
    while i < 16 {
        tg_wb_fds[i] = 0;
        i = i + 1;
    }
    w = fd >> 6;
    b = fd - (w << 6);
    tg_wb_fds[w] = 1 << b;
    tg_wb_tv[0] = sec;
    tg_wb_tv[1] = usec;
    r = select(fd + 1, &tg_wb_fds, 0, 0, &tg_wb_tv);
    if r > 4000000000 r = 0;
    if r > 0 r = 1;
    r;
}

// tg_wb_open(bot, port, secret*|0): listen-сокет 0.0.0.0:port.
// Успех → fd; иначе on_error(bot, "webhook_open", 1 сокет / 2 bind /
// 3 listen, desc) и 0. SO_REUSEADDR — чтобы тест мог перезапускать.
tg_wb_open(bot, port, secret) {
    auto sfd;
    auto r;
    auto oe;
    auto i;
    auto p;
    tg_wb_secret = secret;
    sfd = socket(2, 1, 0);
    if sfd > 4000000000 {
        oe = bot[7];
        oe(bot, "webhook_open", 1, "socket() failed: no network");
        return 0;
    }
    tg_wb_optv[0] = 1;
    setsockopt(sfd, 1, 2, &tg_wb_optv, 4);   // SOL_SOCKET/SO_REUSEADDR
    i = 0;
    p = &tg_wb_sa;
    while i < 16 {
        *p !8 0;
        p = p + 1;
        i = i + 1;
    }
    p = &tg_wb_sa;
    *p !8 2;                     // AF_INET
    *(p+2) !8 (port >> 8);       // port в network order (побайтово)
    *(p+3) !8 (port & 255);      // адреса нет → INADDR_ANY (0.0.0.0)
    r = bind(sfd, &tg_wb_sa, 16);
    if r > 4000000000 {
        oe = bot[7];
        oe(bot, "webhook_open", 2, "bind failed: port busy or forbidden");
        close(sfd);
        return 0;
    }
    r = listen(sfd, 8);
    if r > 4000000000 {
        oe = bot[7];
        oe(bot, "webhook_open", 3, "listen failed");
        close(sfd);
        return 0;
    }
    sfd;
}

// tg_wb_step(bot, sfd, secret*|0): ОДНА итерация сервера.
// select(sfd, 1с) → нет соединения или сокет закрыт → 0 (таймаут — цикл
// его не прерывает). Дальше: accept → чтение до \r\n\r\n (лимит 8 КБ) →
// Content-Length → дочитка тела (лимит 1 МБ) → tg_wb_parse → ответ
// 200/403/400/404 СРАЗУ, при 200 — диспетчер tg_handle_update (та же
// точка, что в tg_polling). Возврат: 1 — соединение обработано,
// 0 — таймаут/нет соединения.
tg_wb_step(bot, sfd, secret) {
    auto cfd;
    auto buf;
    auto p;
    auto n;
    auto got;
    auto hend;
    auto cl;
    auto want;
    auto resp;
    auto done;
    auto ok;

    tg_wb_secret = secret;
    if tg_wb_wait(sfd, 1, 0) == 0 return 0;
    cfd = accept(sfd, 0, 0);
    if cfd > 4000000000 return 0;
    buf = malloc(1056776);   // 8 КБ заголовок + 1 МБ тело + NUL
    got = 0;
    hend = 0;
    done = 0;

    // фаза 1: прочитать до \r\n\r\n (лимит 8192)
    while done == 0 {
        if hend > 0 done = 1;
        else {
            if got >= 8192 done = 1;
            else {
                if tg_wb_wait(cfd, 5, 0) == 1 {
                    n = recv(cfd, buf + got, 8192 - got, 0);
                    if n > 4000000000 done = 1;
                    else if n == 0 done = 1;
                    else {
                        got = got + n;
                        hend = tg_wb_find_hdr(buf, got);
                    }
                } else done = 1;
            }
        }
    }

    if hend == 0 {
        // заголовок не собран (обрыв или лимит 8 КБ) → 400
        tg_wb_reply(cfd, 400);
        shutdown(cfd, 2);
        close(cfd);
        free(buf);
        return 1;
    }

    // фаза 2: Content-Length из собранного заголовка
    tg_wb_parse(buf, got);
    cl = tg_wbslot[2];
    if tg_wbslot[9] == 0 cl = 0;   // нет Content-Length → пустое тело
    resp = 0;
    if cl > 1048576 resp = 400;    // тело больше лимита 1 МБ → без чтения

    // фаза 3: дочитать тело до hend+cl (обрыв → incomplete в финальном
    // разборе, таймаут клиента → тоже)
    done = 0;
    while done == 0 {
        if resp == 400 done = 1;
        else if got >= hend + cl done = 1;
        else {
            if tg_wb_wait(cfd, 5, 0) == 1 {
                want = hend + cl - got;
                if want > 65536 want = 65536;
                n = recv(cfd, buf + got, want, 0);
                if n > 4000000000 done = 1;
                else if n == 0 done = 1;
                else got = got + n;
            } else done = 1;
        }
    }

    p = buf + got;
    *p !8 0;   // NUL — тело для диспетчера (JSON обязан быть без \0)

    if resp == 0 {
        tg_wb_parse(buf, got);
        // метод → 404; секрет → 403; тело неполное/пустое → 400; иначе 200
        resp = 400;
        if tg_wbslot[0] == 1 {
            if tg_wbslot[1] != 1 resp = 404;
            else {
                ok = 1;
                if tg_wb_secret != 0 {
                    if tg_wbslot[5] == 0 ok = 0;
                    else if tg_wbslot[6] == 0 ok = 0;
                }
                if ok == 0 resp = 403;
                else {
                    if tg_wbslot[7] == 1 resp = 400;
                    else if tg_wbslot[4] == 0 resp = 400;
                    else resp = 200;
                }
            }
        }
    }

    // ответ СРАЗУ — Telegram требует быстрый 200 до обработки
    tg_wb_reply(cfd, resp);
    if resp == 200 {
        tg_handle_update(bot, tg_wbslot[3]);
    }
    shutdown(cfd, 2);
    close(cfd);
    free(buf);
    1;
}

// tg_webhook_serve(bot, port, secret*|0): открыть сокет (bind-ошибка —
// on_error внутри tg_wb_open и возврат 0) и крутить шаги, пока
// polling_flag bot[88]==1 (ставится здесь; остановка — tg_stop(bot)).
// Штатный таймаут шага (0) цикл НЕ прерывает.
tg_webhook_serve(bot, port, secret) {
    auto sfd;
    sfd = tg_wb_open(bot, port, secret);
    if sfd == 0 return 0;
    *(bot + 88) = 1;
    while *(bot + 88) == 1 {
        tg_wb_step(bot, sfd, secret);
    }
    close(sfd);
    1;
}
