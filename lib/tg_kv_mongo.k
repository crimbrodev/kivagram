// lib/tg_kv_mongo.k — V5-C: MongoDB wire-протокол (BSON + OP_MSG) для KV.
//
// Изоляция I/O: кодировщик BSON и сборка фрейма OP_MSG работают БЕЗ сети и
// покрыты тестом tests/t_v5_kvmongo.k; сокетный слой (tg_mongo_connect/
// tg_mongo_call/tg_kv_mongo_*) требует живого mongod — локально его нет,
// тестом не покрывается (ручная проверка: mongod на 127.0.0.1:27017).
//
// Контракт KV (как у lib/tg_kv.k, см. также табличку функций ниже):
//   tg_kv_mongo_connect(host, port, db) → 1/0 — socket+connect, db запоминается
//     (0 → "tgkv"); host — ТОЛЬКО IPv4-литерал (резолв имён не входит в спайк
//     линковки). Аутентификации SCRAM НЕТ: работает только mongod без auth.
//   tg_kv_mongo_get(key)  → строка в общем буфере либо 0 (нет ключа/ошибки);
//     указатель живёт до следующего get/set/del/close (слот-кэш как в tg_kv).
//   tg_kv_mongo_set(key, val) → 1/0 — UPSERT РЕАЛИЗОВАН КАК delete+insert
//     (два round-trip'а, не атомарно): сначала delete по {k:key}, затем
//     insert {k:key, v:val}. Замена на replaceOne/findAndModify отложена —
//     это тот же результат при меньшем числе кода, гонки при конкурентной
//     записи одного ключа допустимы по контракту KV.
//   tg_kv_mongo_del(key) → 1 — ключ удалён (ответ n>0), 0 — иначе.
//   tg_kv_mongo_close()  → закрыть сокет.
//   Документ хранения: {k:<key>, v:<val>} (оба строки) в коллекции "kv"
//     (глобальная tg_mg_coll, можно переопределить до вызова).
//
// BSON (все числа little-endian): документ = int32 total_len + поля + 0x00;
// поле = тип(1 байт) + ключ(cstring) + значение.
//   Поддерживаемые типы кодировщиком: 0x02 string, 0x10 int32, 0x12 int64.
//   Поддерживаемые декодером (пропуск/чтение): 0x01 double (пропуск 8,
//   читается как число в get_i64), 0x02 string, 0x03 embedded doc, 0x04 array
//   (как doc), 0x05 binary (4+1+len), 0x07 ObjectId (12), 0x08 bool (1),
//   0x09 date (8), 0x0A null (0), 0x10 int32, 0x11 timestamp (8), 0x12 int64,
//   0x13 decimal128 (16). ЛЮБОЙ ДРУГОЙ ТИП — обход прекращается (get → 0),
//   сканер помнит позицию поля и не выходит за total_len.
//
// OP_MSG (opcode 2013): int32 message_length, int32 request_id=0,
//   int32 response_to=0, int32 opCode=2013, uint32 flagBits=0,
//   uint8 sectionKind=0, затем BSON-документ. message_length = 21 + len(bson).
//   Ответ читается так: первые 4 байта (LE int32) = длина всего фрейма →
//   дочитать ровно столько (см. tg_mg_recvn).
//
// Публичные функции:
//   tg_mongo_bson_put_str/put_i32/put_i64/put_doc/put_doc_begin
//   tg_mongo_bson_wrap_begin/wrap_end/len/doclen
//   tg_mongo_bson_get_str/get_i64/get_doc
//   tg_mongo_opmsg(bson) → Buf-слот фрейма ([0] data, [1] len)
//   tg_mongo_query/insert/delete/ismaster → собирают команду в tg_mg_out
//   tg_mongo_connect(host, port) / tg_mongo_call(fb) / tg_mongo_reply_doc()
//     / tg_mongo_close()
//
// Языковые ловушки Kiva: сравнения БЕЗЗНАКОВЫЕ (проверки длины идут двумя
// порогами: < 10485760 ловит и -1, и мусор), литералов с \r нет (нет —
// впрочем, BSON \r не требует), <=6 аргументов, побайтовая работа через
// `*p !8 байт` / `@8 *p`.

extern strlen
extern strcmp
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

tg_mg_out[4];       // Buf: последний собранный OP_MSG-фрейм (результат builders)
tg_mg_cmd[4];       // Buf: BSON-документ команды (внутри builders)
tg_mg_tbuf[4];      // Buf: фильтр/документ KV-операции (вне builders!)
tg_mg_in[4];        // Buf: сырой ответ сервера (NUL за фреймом)
tg_mg_vbuf[4];      // Buf: копия строкового значения поля ответа
tgm_recvbuf[1024];  // 8 КБ: приёмный чанк recv (имя вне префикса tg_mg_ —
                    // там в lib/tg_util.k живёт медиа-Buf tg_mg_tmp)
tg_mg_stack[16];    // стек позиций wrap_begin (слоты = смещения в Buf)
tg_mg_depth;        // глубина вложенных документов
tg_mg_ftype;        // тип последнего найденного поля (0x02/0x03/...)
tg_mg_fd;           // дескриптор сокета
tg_mg_on;           // 1 — соединение установлено
tg_mg_sa[2];        // sockaddr_in (16 байт)
tg_mg_optv[1];      // int для setsockopt
tg_mg_dbname;       // имя БД для $db (0 → "tgkv")
tg_mg_coll;         // имя коллекции KV (0 → "kv")

// ===== Низкоуровневые байтовые помощники =====

// tg_mg_need(b, n): ёмкость >= len+n+1 (NUL); 0 — malloc не удался
tg_mg_need(b, n) {
    auto need;
    auto np;
    need = b[1] + n + 1;
    if need > b[2] {
        np = malloc(need + need);
        if np == 0 return 0;
        if b[0] memcpy(np, b[0], b[1]);
        if b[0] free(b[0]);
        b[0] = np;
        b[2] = need + need;
    }
    1;
}

// tg_mg_byte(b, c): дописать один байт
tg_mg_byte(b, c) {
    if tg_mg_need(b, 1) == 0 return 0;
    *(b[0] + b[1]) !8 c;
    b[1] = b[1] + 1;
    *(b[0] + b[1]) !8 0;
    1;
}

// tg_mg_raw(b, src, n): дописать ровно n байт (без NUL в них)
tg_mg_raw(b, src, n) {
    if n <= 0 return 1;
    if tg_mg_need(b, n) == 0 return 0;
    memcpy(b[0] + b[1], src, n);
    b[1] = b[1] + n;
    *(b[0] + b[1]) !8 0;
    1;
}

// tg_mg_cstr(b, s): дописать строку + NUL (ключ BSON)
tg_mg_cstr(b, s) {
    if tg_mg_raw(b, s, strlen(s)) == 0 return 0;
    tg_mg_byte(b, 0);
}

// tg_mg_i32(b, v) / tg_mg_i64(b, v): little-endian запись числа
tg_mg_i32(b, v) {
    tg_mg_byte(b, v & 255);
    tg_mg_byte(b, (v >> 8) & 255);
    tg_mg_byte(b, (v >> 16) & 255);
    tg_mg_byte(b, (v >> 24) & 255);
    1;
}

tg_mg_i64(b, v) {
    tg_mg_byte(b, v & 255);
    tg_mg_byte(b, (v >> 8) & 255);
    tg_mg_byte(b, (v >> 16) & 255);
    tg_mg_byte(b, (v >> 24) & 255);
    tg_mg_byte(b, (v >> 32) & 255);
    tg_mg_byte(b, (v >> 40) & 255);
    tg_mg_byte(b, (v >> 48) & 255);
    tg_mg_byte(b, (v >> 56) & 255);
    1;
}

// tg_mg_rd_i32(p) / tg_mg_rd_i64(p): little-endian чтение со знаком
tg_mg_rd_i32(p) {
    auto v;
    v = @8 *p;
    v = v + ((@8 *(p + 1)) << 8);
    v = v + ((@8 *(p + 2)) << 16);
    v = v + ((@8 *(p + 3)) << 24);
    if @8 *(p + 3) > 127 v = v - 4294967296;
    v;
}

tg_mg_rd_i64(p) {
    auto v;
    v = @8 *p;
    v = v + ((@8 *(p + 1)) << 8);
    v = v + ((@8 *(p + 2)) << 16);
    v = v + ((@8 *(p + 3)) << 24);
    v = v + ((@8 *(p + 4)) << 32);
    v = v + ((@8 *(p + 5)) << 40);
    v = v + ((@8 *(p + 6)) << 48);
    v = v + ((@8 *(p + 7)) << 56);
    v;
}

// tg_mg_rd_double(p): IEEE-754 (binary64) → целое (1.0 → 1, 2.5 → 2)
tg_mg_rd_double(p) {
    auto u;
    auto exp;
    auto frac;
    auto mant;
    auto v;
    u = tg_mg_rd_i64(p);
    exp = (u >> 52) & 2047;
    frac = u & 4503599627370495;      // 2^52 - 1
    if exp == 0 {
        v = frac >> 52;
    } else {
        mant = frac | 4503599627370496;   // 2^52
        if exp > 1075 v = mant << (exp - 1075);
        else v = mant >> (1075 - exp);
    }
    if (u >> 63) != 0 v = 0 - v;
    v;
}

// tg_mg_rd_double корректно для 1.0 / целых; дробные — вниз по модулю.

// tg_mg_patch32(b, off, v): перезаписать 4 байта LE по смещению
tg_mg_patch32(b, off, v) {
    auto p;
    p = b[0] + off;
    *p !8 (v & 255);
    *(p + 1) !8 ((v >> 8) & 255);
    *(p + 2) !8 ((v >> 16) & 255);
    *(p + 3) !8 ((v >> 24) & 255);
    1;
}

// tg_mg_vset(src, n): копия n байт + NUL в общий буфер значения ответа
tg_mg_vset(src, n) {
    auto b;
    auto need;
    auto np;
    b = &tg_mg_vbuf;
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

// ===== Кодировщик BSON =====

// tg_mongo_bson_doclen(p): int32 total_len в начале документа
tg_mongo_bson_doclen(p) {
    tg_mg_rd_i32(p);
}

// tg_mongo_bson_len(buf): длина BSON-документа в Buf-слоте
tg_mongo_bson_len(buf) {
    buf[1];
}

// tg_mongo_bson_wrap_begin(buf): начало документа (4 байта под total_len)
tg_mongo_bson_wrap_begin(buf) {
    if tg_mg_depth >= 16 {
        printf("kv: mongo: bson wrap too deep (16)\n");
        return 0;
    }
    tg_mg_stack[tg_mg_depth] = buf[1];
    tg_mg_depth = tg_mg_depth + 1;
    tg_mg_i32(buf, 0);
    1;
}

// tg_mongo_bson_wrap_end(buf): 0x00-терминатор + прошивка total_len → длина
tg_mongo_bson_wrap_end(buf) {
    auto pos;
    auto total;
    if tg_mg_depth <= 0 {
        printf("kv: mongo: bson wrap underflow\n");
        return 0;
    }
    tg_mg_depth = tg_mg_depth - 1;
    pos = tg_mg_stack[tg_mg_depth];
    tg_mg_byte(buf, 0);
    total = buf[1] - pos;
    tg_mg_patch32(buf, pos, total);
    total;
}

// tg_mongo_bson_put_str(buf, key, val): поле 0x02 (string с NUL)
tg_mongo_bson_put_str(buf, key, val) {
    tg_mg_byte(buf, 2);
    tg_mg_cstr(buf, key);
    tg_mg_i32(buf, strlen(val) + 1);
    tg_mg_raw(buf, val, strlen(val) + 1);
    1;
}

// tg_mongo_bson_put_i32(buf, key, val): поле 0x10 (int32)
tg_mongo_bson_put_i32(buf, key, val) {
    tg_mg_byte(buf, 16);
    tg_mg_cstr(buf, key);
    tg_mg_i32(buf, val);
    1;
}

// tg_mongo_bson_put_i64(buf, key, val): поле 0x12 (int64)
tg_mongo_bson_put_i64(buf, key, val) {
    tg_mg_byte(buf, 18);
    tg_mg_cstr(buf, key);
    tg_mg_i64(buf, val);
    1;
}

// tg_mongo_bson_put_doc(buf, key, sub): поле 0x03 — готовый под-документ sub
tg_mongo_bson_put_doc(buf, key, sub) {
    auto n;
    n = tg_mongo_bson_doclen(sub);
    if n > 10485760 return 0;    // отрицательная/мусорная длина (беззнаковые)
    if n < 5 return 0;
    tg_mg_byte(buf, 3);
    tg_mg_cstr(buf, key);
    tg_mg_raw(buf, sub, n);
    1;
}

// tg_mongo_bson_put_doc_begin(buf, key): начало ПОЛЯ-документа: тип+ключ и
// старт вложенного документа (закрывается wrap_end)
tg_mongo_bson_put_doc_begin(buf, key) {
    tg_mg_byte(buf, 3);
    tg_mg_cstr(buf, key);
    tg_mongo_bson_wrap_begin(buf);
}

// ===== Декодер BSON =====

// tg_mg_skip(t, p): размер значения типа t по адресу p; -1 — тип неизвестен
tg_mg_skip(t, p) {
    auto n;
    n = 0 - 1;
    if t == 1 n = 8;                       // double
    else if t == 2 n = tg_mg_rd_i32(p) + 4; // string
    else if t == 3 n = tg_mg_rd_i32(p);     // embedded doc
    else if t == 4 n = tg_mg_rd_i32(p);     // array (это тоже doc)
    else if t == 5 n = tg_mg_rd_i32(p) + 5; // binary: len + subtype
    else if t == 7 n = 12;                  // ObjectId
    else if t == 8 n = 1;                   // bool
    else if t == 9 n = 8;                   // UTC date
    else if t == 10 n = 0;                  // null
    else if t == 16 n = 4;                  // int32
    else if t == 17 n = 8;                  // timestamp
    else if t == 18 n = 8;                  // int64
    else if t == 19 n = 16;                 // decimal128
    n;
}

// tg_mg_find(doc, key): смещение ЗНАЧЕНИЯ поля либо 0 (нет/типы вне списка);
// тип кладётся в tg_mg_ftype. Вложенные документы пропускаются целиком.
tg_mg_find(doc, key) {
    auto total;
    auto off;
    auto t;
    auto r;
    auto kl;
    auto skip;
    auto stop;
    auto kdone;
    r = 0;
    stop = 0;
    total = tg_mg_rd_i32(doc);
    if total > 10485760 return 0;          // мусорная/отрицательная длина
    if total < 5 return 0;
    off = 4;
    while stop == 0 {
        if off >= total stop = 1;
        else {
            t = @8 *(doc + off);
            if t == 0 stop = 1;            // конец документа
            else {
                off = off + 1;
                kl = 0;
                kdone = 0;
                while kdone == 0 {
                    if off + kl >= total kdone = 1;
                    else if @8 *(doc + off + kl) == 0 kdone = 1;
                    else kl = kl + 1;
                }
                if off + kl >= total stop = 1;   // ключ без NUL — порча
                else {
                    if strcmp(doc + off, key) == 0 {
                        r = off + kl + 1;
                        tg_mg_ftype = t;
                        stop = 1;
                    } else {
                        skip = tg_mg_skip(t, doc + off + kl + 1);
                        if skip > 4000000000 stop = 1;   // неизвестный тип
                        else off = off + kl + 1 + skip;
                    }
                }
            }
        }
    }
    r;
}

// tg_mongo_bson_get_str(doc, key): копия строкового поля (слот-кэш значений,
// живёт до следующего get_*) либо 0 (нет ключа / поле не 0x02)
tg_mongo_bson_get_str(doc, key) {
    auto off;
    auto n;
    auto r;
    r = 0;
    off = tg_mg_find(doc, key);
    if off != 0 {
        if tg_mg_ftype == 2 {
            n = tg_mg_rd_i32(doc + off);
            if n > 0 {
                if n < 10485760 {
                    if tg_mg_vset(doc + off + 4, n - 1) != 0 r = tg_mg_vbuf[0];
                }
            }
        }
    }
    r;
}

// tg_mongo_bson_get_i64(doc, key): число поля 0x10/0x12/0x01; иначе 0
tg_mongo_bson_get_i64(doc, key) {
    auto off;
    auto r;
    auto t;
    r = 0;
    off = tg_mg_find(doc, key);
    if off != 0 {
        t = tg_mg_ftype;
        if t == 16 r = tg_mg_rd_i32(doc + off);
        else if t == 18 r = tg_mg_rd_i64(doc + off);
        else if t == 1 r = tg_mg_rd_double(doc + off);
    }
    r;
}

// tg_mongo_bson_get_doc(doc, key): указатель на под-документ/массив (0x03/0x04)
// или 0; указатель живёт внутри буфера-родителя
tg_mongo_bson_get_doc(doc, key) {
    auto off;
    auto r;
    r = 0;
    off = tg_mg_find(doc, key);
    if off != 0 {
        if tg_mg_ftype == 3 r = doc + off;
        else if tg_mg_ftype == 4 r = doc + off;
    }
    r;
}

// ===== OP_MSG и команды =====

// tg_mongo_opmsg(bson) → Buf-слот с полным фреймом ([0] data, [1] len)
tg_mongo_opmsg(bson) {
    auto b;
    auto n;
    n = tg_mongo_bson_doclen(bson);
    if n > 10485760 return 0;
    if n < 5 return 0;
    b = &tg_mg_out;
    tg_buf_reset(b);
    tg_mg_i32(b, 21 + n);      // messageLength
    tg_mg_i32(b, 0);           // request_id
    tg_mg_i32(b, 0);           // response_to
    tg_mg_i32(b, 2013);        // opCode = OP_MSG
    tg_mg_i32(b, 0);           // flagBits
    tg_mg_byte(b, 0);          // sectionKind = 0 (один BSON-документ)
    tg_mg_raw(b, bson, n);
    b;
}

// tg_mg_db(): имя БД для $db (0 → "tgkv")
tg_mg_db() {
    if tg_mg_dbname == 0 "tgkv";
    else tg_mg_dbname;
}

// tg_mg_collname(): имя коллекции KV (0 → "kv")
tg_mg_collname() {
    if tg_mg_coll == 0 "kv";
    else tg_mg_coll;
}

// tg_mongo_query(coll, filter): {find:coll, filter:<doc>, $db:<db>}
tg_mongo_query(coll, filter) {
    auto b;
    b = &tg_mg_cmd;
    tg_buf_reset(b);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_str(b, "find", coll);
    tg_mongo_bson_put_doc(b, "filter", filter);
    tg_mongo_bson_put_str(b, "$db", tg_mg_db());
    tg_mongo_bson_wrap_end(b);
    tg_mongo_opmsg(tg_mg_cmd[0]);
}

// tg_mongo_insert(coll, doc): {insert:coll, documents:[<doc>], $db:<db>}
tg_mongo_insert(coll, doc) {
    auto b;
    b = &tg_mg_cmd;
    tg_buf_reset(b);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_str(b, "insert", coll);
    tg_mg_byte(b, 4);                  // поле-массив documents
    tg_mg_cstr(b, "documents");
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_doc(b, "0", doc);
    tg_mongo_bson_wrap_end(b);
    tg_mongo_bson_put_str(b, "$db", tg_mg_db());
    tg_mongo_bson_wrap_end(b);
    tg_mongo_opmsg(tg_mg_cmd[0]);
}

// tg_mongo_delete(coll, filter): {delete:coll, deletes:[{q:<doc>,limit:0}], $db}
tg_mongo_delete(coll, filter) {
    auto b;
    b = &tg_mg_cmd;
    tg_buf_reset(b);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_str(b, "delete", coll);
    tg_mg_byte(b, 4);                  // поле-массив deletes
    tg_mg_cstr(b, "deletes");
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_doc_begin(b, "0");
    tg_mongo_bson_put_doc(b, "q", filter);
    tg_mongo_bson_put_i32(b, "limit", 0);
    tg_mongo_bson_wrap_end(b);         // элемент deletes[0]
    tg_mongo_bson_wrap_end(b);         // массив deletes
    tg_mongo_bson_put_str(b, "$db", tg_mg_db());
    tg_mongo_bson_wrap_end(b);
    tg_mongo_opmsg(tg_mg_cmd[0]);
}

// tg_mongo_ismaster(): {hello:1, $db:"admin"} — handshake-фрейм (диагностика).
// Выполнить: tg_mongo_call(tg_mongo_ismaster())
tg_mongo_ismaster() {
    auto b;
    b = &tg_mg_cmd;
    tg_buf_reset(b);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(b);
    tg_mongo_bson_put_i32(b, "hello", 1);
    tg_mongo_bson_put_str(b, "$db", "admin");
    tg_mongo_bson_wrap_end(b);
    tg_mongo_opmsg(tg_mg_cmd[0]);
}

// ===== Сетевой слой (требует живой mongod) =====

// tg_mg_ip4(host): IPv4-литерал → адрес (network order) либо 0 (ошибка/0.0.0.0)
tg_mg_ip4(host) {
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

// tg_mg_append(b, src, n): сырые n байт в Buf + NUL
tg_mg_append(b, src, n) {
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

// tg_mongo_connect(host, port) → 1/0
tg_mongo_connect(host, port) {
    auto fd;
    auto r;
    auto ip;
    auto p;
    auto i;
    tg_mongo_close();
    if host == 0 {
        printf("kv: mongo: no host\n");
        return 0;
    }
    ip = tg_mg_ip4(host);
    if ip == 0 {
        printf("kv: mongo: bad host '%s' (нужен IPv4-литерал)\n", host);
        return 0;
    }
    fd = socket(2, 1, 0);
    if fd > 4000000000 {
        printf("kv: mongo: socket() failed (no network?)\n");
        return 0;
    }
    p = &tg_mg_sa;
    i = 0;
    while i < 16 {
        *p !8 0;
        p = p + 1;
        i = i + 1;
    }
    p = &tg_mg_sa;
    *p !8 2;                        // AF_INET
    *(p + 2) !8 (port >> 8);
    *(p + 3) !8 (port & 255);
    *(p + 4) !8 (ip >> 24);
    *(p + 5) !8 ((ip >> 16) & 255);
    *(p + 6) !8 ((ip >> 8) & 255);
    *(p + 7) !8 (ip & 255);
    r = connect(fd, &tg_mg_sa, 16);
    if r > 4000000000 {
        printf("kv: mongo: connect %s:%ld failed\n", host, port);
        close(fd);
        return 0;
    }
    tg_mg_optv[0] = 10;             // SO_RCVTIMEO 10с — recv не зависнет
    setsockopt(fd, 1, 20, &tg_mg_optv, 4);
    tg_mg_fd = fd;
    tg_mg_on = 1;
    1;
}

// tg_mongo_close(): закрыть сокет (1)
tg_mongo_close() {
    if tg_mg_on != 0 close(tg_mg_fd);
    tg_mg_fd = 0;
    tg_mg_on = 0;
    1;
}

// tg_mg_recvn(want): прочитать ровно want байт в tg_mg_in → want или 0
tg_mg_recvn(want) {
    auto n;
    auto got;
    auto guard;
    auto chunk;
    got = 0;
    guard = 0;
    while got < want {
        if guard > 65536 return 0;
        guard = guard + 1;
        chunk = want - got;
        if chunk > 8192 chunk = 8192;
        n = recv(tg_mg_fd, &tgm_recvbuf, chunk, 0);
        if n > 4000000000 return 0;     // ошибка/таймаут
        if n == 0 return 0;             // сервер закрыл соединение
        if tg_mg_append(&tg_mg_in, &tgm_recvbuf, n) == 0 return 0;
        got = got + n;
    }
    got;
}

// tg_mongo_call(fb): отправить фрейм (fb[0]/fb[1] — Buf-слот, например
// результат tg_mongo_query/insert/delete) и прочитать ответ → сырой фрейм
// (NUL-терминирован после фрейма) либо 0 (транспорт/формат).
tg_mongo_call(fb) {
    auto s;
    auto len;
    auto n;
    auto off;
    if tg_mg_on == 0 {
        printf("kv: mongo: not connected (tg_kv_mongo_connect first)\n");
        return 0;
    }
    s = fb[0];
    len = fb[1];
    if len < 21 return 0;
    off = 0;
    while off < len {
        n = send(tg_mg_fd, s + off, len - off, 16384);   // MSG_NOSIGNAL
        if n > 4000000000 return 0;
        if n == 0 return 0;
        off = off + n;
    }
    tg_buf_reset(&tg_mg_in);
    if tg_mg_recvn(4) != 4 return 0;
    len = tg_mg_rd_i32(tg_mg_in[0]);   // длина ВСЕГО фрейма (LE int32)
    if len < 21 return 0;
    if len > 16777216 return 0;        // 16 МБ — защита от мусорной длины
    if tg_mg_recvn(len - 4) != len - 4 return 0;
    tg_mg_in[0];
}

// tg_mongo_reply_doc(): BSON-документ последнего ответа (секция kind 0)
// либо 0 (не OP_MSG / не kind 0 / ответа нет)
tg_mongo_reply_doc() {
    auto b;
    auto p;
    b = &tg_mg_in;
    if b[1] < 21 return 0;
    p = b[0];
    if tg_mg_rd_i32(p + 12) != 2013 return 0;
    if @8 *(p + 20) != 0 return 0;
    p + 21;
}

// tg_mg_reply_ok(): 1 — ответ получен и без errmsg (печатает errmsg сам)
tg_mg_reply_ok() {
    auto doc;
    auto r;
    r = 0;
    doc = tg_mongo_reply_doc();
    if doc != 0 {
        if tg_mongo_bson_get_str(doc, "errmsg") != 0 printf("kv: mongo: %s\n", tg_mg_vbuf[0]);
        else r = 1;
    }
    r;
}

// ===== KV поверх mongo =====

// tg_kv_mongo_connect(host, port, db|0) → 1/0 (db=0 → "tgkv")
tg_kv_mongo_connect(host, port, db) {
    if db == 0 tg_mg_dbname = 0;
    else tg_mg_dbname = db;
    tg_mongo_connect(host, port);
}

// tg_kv_mongo_close(): закрыть сокет (1)
tg_kv_mongo_close() {
    tg_mongo_close();
}

// tg_kv_mongo_get(key): find {k:key} → firstBatch[0].v (слот-кэш) либо 0
tg_kv_mongo_get(key) {
    auto r;
    auto f;
    auto doc;
    auto cur;
    auto batch;
    auto row;
    r = 0;
    tg_buf_reset(&tg_mg_tbuf);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(&tg_mg_tbuf);
    tg_mongo_bson_put_str(&tg_mg_tbuf, "k", key);
    tg_mongo_bson_wrap_end(&tg_mg_tbuf);
    f = tg_mongo_query(tg_mg_collname(), tg_mg_tbuf[0]);
    if f == 0 return 0;
    if tg_mongo_call(f) == 0 return 0;
    doc = tg_mongo_reply_doc();
    if doc == 0 return 0;
    if tg_mongo_bson_get_str(doc, "errmsg") != 0 {
        printf("kv: mongo: %s\n", tg_mg_vbuf[0]);
        return 0;
    }
    cur = tg_mongo_bson_get_doc(doc, "cursor");
    if cur == 0 return 0;
    batch = tg_mongo_bson_get_doc(cur, "firstBatch");
    if batch == 0 return 0;
    row = tg_mongo_bson_get_doc(batch, "0");
    if row == 0 return 0;                 // ключа нет — пустой firstBatch
    r = tg_mongo_bson_get_str(row, "v");
    r;
}

// tg_kv_mongo_set(key, val): delete {k:key} → insert {k,val}; 1/0
tg_kv_mongo_set(key, val) {
    auto r;
    auto f;
    r = 0;
    tg_buf_reset(&tg_mg_tbuf);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(&tg_mg_tbuf);
    tg_mongo_bson_put_str(&tg_mg_tbuf, "k", key);
    tg_mongo_bson_wrap_end(&tg_mg_tbuf);
    f = tg_mongo_delete(tg_mg_collname(), tg_mg_tbuf[0]);
    if f == 0 return 0;
    if tg_mongo_call(f) == 0 return 0;
    if tg_mg_reply_ok() == 0 return 0;
    tg_buf_reset(&tg_mg_tbuf);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(&tg_mg_tbuf);
    tg_mongo_bson_put_str(&tg_mg_tbuf, "k", key);
    tg_mongo_bson_put_str(&tg_mg_tbuf, "v", val);
    tg_mongo_bson_wrap_end(&tg_mg_tbuf);
    f = tg_mongo_insert(tg_mg_collname(), tg_mg_tbuf[0]);
    if f == 0 return 0;
    if tg_mongo_call(f) == 0 return 0;
    tg_mg_reply_ok();
}

// tg_kv_mongo_del(key): delete {k:key}; 1 — удалён (n>0)
tg_kv_mongo_del(key) {
    auto r;
    auto f;
    auto doc;
    auto n;
    r = 0;
    tg_buf_reset(&tg_mg_tbuf);
    tg_mg_depth = 0;
    tg_mongo_bson_wrap_begin(&tg_mg_tbuf);
    tg_mongo_bson_put_str(&tg_mg_tbuf, "k", key);
    tg_mongo_bson_wrap_end(&tg_mg_tbuf);
    f = tg_mongo_delete(tg_mg_collname(), tg_mg_tbuf[0]);
    if f == 0 return 0;
    if tg_mongo_call(f) == 0 return 0;
    doc = tg_mongo_reply_doc();
    if doc == 0 return 0;
    if tg_mongo_bson_get_str(doc, "errmsg") != 0 {
        printf("kv: mongo: %s\n", tg_mg_vbuf[0]);
        return 0;
    }
    n = tg_mongo_bson_get_i64(doc, "n");
    if n < 4000000000 {
        if n > 0 r = 1;
    }
    r;
}
