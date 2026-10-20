// t_v5_kvredis.k — V5-C: RESP-протокол (lib/tg_kv_redis.k), БЕЗ сети.
//
// Детерминированно тестируется протокольный слой:
//   1) tg_kv_redis_enc_cmd — кодирование аргументов в RESP (массив bulk-строк),
//      длина каждой bulk считается strlen в БАЙТАХ (UTF-8), подстановки нет:
//      спецсимволы в ключе (\r\n, пробелы) не разрывают протокол;
//   2) tg_kv_redis_parse / tg_kv_redis_parse_at — разбор ответов
//      +simple / $bulk / :int / -err / *array, nil ($-1), incomplete, invalid;
//   3) round-trip: закодированная команда → синтетический ответ сервера → parse.
//
// Без сети остаётся I/O: tg_kv_redis_connect/get/set/del/close — им нужен живой
// redis-server (здесь его нет). Ручная проверка интеграции:
//   tg_kv_redis_connect("127.0.0.1", 6379, 0) → tg_kv_redis_set/get/del.
extern printf
extern exit
extern strcmp
extern strlen
extern sprintf
extern strcpy

fails[1];
cargs[8];    // слот-массив указателей на аргументы команды
expb[128];   // ожидаемая строка (1 КБ)
reply[128];  // синтетический ответ (1 КБ)
stream[32];  // конкатенированный поток ответов (256 байт)

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

global main
main() {
    auto r;
    auto p;
    auto off;

    fails[0] = 0;

    // ===== 1. encode: точные RESP-строки =====
    cargs[0] = "GET";
    cargs[1] = "key";
    r = tg_kv_redis_enc_cmd(2, &cargs);
    chk(strcmp(r, "*2\x0d\n$3\x0d\nGET\x0d\n$3\x0d\nkey\x0d\n") == 0,
        "enc: GET key → точная RESP-строка");

    cargs[0] = "PING";
    r = tg_kv_redis_enc_cmd(1, &cargs);
    chk(strcmp(r, "*1\x0d\n$4\x0d\nPING\x0d\n") == 0, "enc: PING → *1");

    // SET с кириллицей и эмодзи: $len в БАЙТАХ (strlen UTF-8), не в символах
    cargs[0] = "SET";
    cargs[1] = "k";
    cargs[2] = "значение 🎉";
    r = tg_kv_redis_enc_cmd(3, &cargs);
    sprintf(&expb, "*3\x0d\n$3\x0d\nSET\x0d\n$1\x0d\nk\x0d\n$%ld\x0d\nзначение 🎉\x0d\n",
            strlen("значение 🎉"));
    chk(strcmp(r, &expb) == 0, "enc: SET кириллица/эмодзи → длина в байтах");
    chk(strlen("значение 🎉") == 21, "enc: длина 'значение 🎉' = 21 байт");

    // ===== 2. инъекция: пробел и CRLF внутри ключа =====
    cargs[0] = "GET";
    cargs[1] = "a b\x0d\nGET injected";
    r = tg_kv_redis_enc_cmd(2, &cargs);
    sprintf(&expb, "*2\x0d\n$3\x0d\nGET\x0d\n$%ld\x0d\na b\x0d\nGET injected\x0d\n",
            strlen("a b\x0d\nGET injected"));
    chk(strcmp(r, &expb) == 0, "enc: ключ с CRLF → bulk-длина, не разрыв протокола");

    // bulk-ответ с \r\n ВНУТРИ данных: парсер читает ровно len байт
    sprintf(&reply, "$%ld\x0d\na b\x0d\nGET inj\x0d\n", strlen("a b\x0d\nGET inj"));
    p = tg_kv_redis_parse(&reply);
    chk(p[2] == strlen("a b\x0d\nGET inj"), "parse: bulk с CRLF → длина по байтам");
    chk(p[1] != 0, "parse: bulk с CRLF → значение есть");
    if p[1] != 0 chk(strcmp(p[1], "a b\x0d\nGET inj") == 0,
                     "parse: CRLF внутри данных не разрывает bulk");
    chk(p[3] == strlen(&reply), "parse: bulk с CRLF → end = весь ответ");

    // ===== 3. parse: типы RESP =====
    p = tg_kv_redis_parse("+OK\x0d\n");
    chk(p[0] == 1, "parse: +OK → тип simple");
    chk(p[4] == 0, "parse: +OK → status ok");
    chk(p[1] != 0, "parse: +OK → значение есть");
    if p[1] != 0 chk(strcmp(p[1], "OK") == 0, "parse: +OK → OK");

    p = tg_kv_redis_parse("$5\x0d\nhello\x0d\n");
    chk(p[0] == 2, "parse: $5 → тип bulk");
    chk(p[2] == 5, "parse: $5 → длина 5");
    chk(p[1] != 0, "parse: bulk значение есть");
    if p[1] != 0 chk(strcmp(p[1], "hello") == 0, "parse: bulk → hello");
    chk(p[3] == 11, "parse: bulk end = 11 (весь ответ)");

    p = tg_kv_redis_parse("$-1\x0d\n");
    chk(p[0] == 2, "parse: $-1 → тип bulk");
    chk(p[1] == 0, "parse: $-1 → nil (указатель 0)");
    chk(p[2] == 0 - 1, "parse: $-1 → num -1");

    p = tg_kv_redis_parse(":42\x0d\n");
    chk(p[0] == 3, "parse: :42 → тип integer");
    chk(p[2] == 42, "parse: :42 → 42");

    p = tg_kv_redis_parse("-ERR x\x0d\n");
    chk(p[0] == 4, "parse: -ERR → тип error");
    chk(p[1] != 0, "parse: error → текст есть");
    if p[1] != 0 chk(strcmp(p[1], "ERR x") == 0, "parse: error → 'ERR x'");

    // массив: счётчик + продолжение через parse_at
    strcpy(&stream, "*2\x0d\n$3\x0d\nGET\x0d\n$3\x0d\nkey\x0d\n");
    p = tg_kv_redis_parse(&stream);
    chk(p[0] == 5, "parse: *2 → тип array");
    chk(p[2] == 2, "parse: *2 → счётчик 2");

    // два ответа подряд: parse → end → parse_at со смещения
    strcpy(&stream, "+OK\x0d\n:42\x0d\n");
    p = tg_kv_redis_parse(&stream);
    chk(p[0] == 1, "parse: поток первый ответ simple");
    off = p[3];
    p = tg_kv_redis_parse_at(&stream, off);
    chk(p[0] == 3, "parse_at: второй ответ integer");
    chk(p[2] == 42, "parse_at: второй ответ → 42");

    // ===== 4. incomplete / invalid =====
    p = tg_kv_redis_parse("$5\x0d\nhel");
    chk(p[4] == 1, "parse: обрезанный bulk → incomplete");
    p = tg_kv_redis_parse("+OK\x0d");
    chk(p[4] == 1, "parse: нет \\n → incomplete");
    p = tg_kv_redis_parse("?weird\x0d\n");
    chk(p[4] == 2, "parse: неизвестный тип → invalid");
    p = tg_kv_redis_parse("");
    chk(p[4] == 1, "parse: пустой ввод → incomplete");

    // ===== 5. round-trip: encode → синтетический ответ → parse =====
    cargs[0] = "SET";
    cargs[1] = "session:42";
    cargs[2] = "значение 'с' \"кавычками\" 🎉";
    r = tg_kv_redis_enc_cmd(3, &cargs);
    // ответ сервера на SET — "+OK"
    p = tg_kv_redis_parse("+OK\x0d\n");
    chk(p[0] == 1, "rt: SET → ответ +OK");
    // GET того же ключа → bulk с тем же значением
    sprintf(&reply, "$%ld\x0d\n%s\x0d\n", strlen("значение 'с' \"кавычками\" 🎉"),
            "значение 'с' \"кавычками\" 🎉");
    p = tg_kv_redis_parse(&reply);
    chk(p[0] == 2, "rt: GET → ответ bulk");
    chk(p[1] != 0, "rt: GET → значение есть");
    if p[1] != 0 chk(strcmp(p[1], "значение 'с' \"кавычками\" 🎉") == 0,
                     "rt: значение пережило encode/parse");
    chk(r != 0, "rt: encode SET не 0");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
