// t_v3_wbserve.k — W3-3: HTTP-сервер приёма апдейтов (lib/tg_wbserve.k).
// Часть 1 — unit-парсер tg_wb_parse на сырых строках (БЕЗ сети).
// Часть 2 — живой localhost: tg_wb_open → tg_wb_step одной итерацией,
// клиент-сокет в ТОМ ЖЕ процессе (connect до accept через backlog):
// 200+диспетчер / 403 / 404 / 400. Порт 18081, при неудаче 18082.
// Конвенция t_http: сокеты недоступны → FAIL: no network.
extern printf
extern exit
extern strlen
extern strcmp
extern strstr
extern sprintf
extern socket
extern connect
extern send
extern recv
extern close
extern shutdown
extern setsockopt

fails[1];
errc[3];      // ловца on_error: 0 счётчик, 1 код, 2 был ли desc
logb[3];      // журнал хендлера (Buf)
csa[2];       // sockaddr_in клиента 127.0.0.1:<port>
optv[1];      // int для setsockopt
reqbuf[4096]; // собираемый запрос/ответ (32 КБ)
respbuf[512]; // ответ сервера (4 КБ)

// --- хендлеры и помощники: текстово ДО main (правило порядка определений) ---

myerr(b, method, code, desc) {
    errc[0] = errc[0] + 1;
    errc[1] = code;
    if strlen(desc) > 0 errc[2] = 1;
    1;
}

h_log(ctx) {
    tg_buf_add(&logb, "got:");
    tg_buf_add(&logb, tg_text(ctx));
    tg_buf_add(&logb, ";");
    1;
}

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

ishuge(x) {
    auto ok;
    ok = 0;
    if x > 4000000000 ok = 1;
    ok;
}

// mkclient(port): клиентский сокет на 127.0.0.1:port, connect до accept;
// SO_RCVTIMEO 2с — recv не зависнет, если сервер не ответил.
mkclient(port) {
    auto fd;
    auto r;
    auto p;
    auto i;
    fd = socket(2, 1, 0);
    if ishuge(fd) == 1 return 0;
    p = &csa;
    i = 0;
    while i < 16 {
        *p !8 0;
        p = p + 1;
        i = i + 1;
    }
    p = &csa;
    *p !8 2;                          // AF_INET
    *(p+2) !8 (port >> 8);            // port в network order (побайтово)
    *(p+3) !8 (port & 255);
    *(p+4) !8 127;                    // 127.0.0.1
    *(p+7) !8 1;
    r = connect(fd, &csa, 16);
    if ishuge(r) == 1 {
        close(fd);
        return 0;
    }
    optv[0] = 2;
    setsockopt(fd, 1, 20, &optv, 4);  // SO_RCVTIMEO
    fd;
}

// csend(fd): отправить reqbuf как есть
csend(fd) {
    auto n;
    n = send(fd, &reqbuf, strlen(&reqbuf), 16384);   // MSG_NOSIGNAL
    n;
}

// cread(): прочитать ответ сервера в respbuf (с NUL), вернуть длину
cread(fd) {
    auto n;
    auto p;
    n = recv(fd, &respbuf, 400, 0);
    if n > 400 n = 400;
    if ishuge(n) == 1 n = 0;
    p = &respbuf;
    p = p + n;
    *p !8 0;
    n;
}

global main
main() {
    auto bot;
    auto body;
    auto p;
    auto sfd;
    auto cfd;
    auto r;
    auto n;
    auto port;

    fails[0] = 0;
    errc[0] = 0;
    errc[1] = 0;
    errc[2] = 0;
    tg_buf_init(&logb);

    // ===== 1. unit-парсер: сырые строки запросов, без сети =====
    tg_wb_secret = "s3cr";
    body = "{\"update_id\":7,\"message\":{\"message_id\":5,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"A\"},\"text\":\"вебхук\"}}";

    // (а) валидный POST + секрет-матч
    sprintf(&reqbuf,
        "POST /bot123:fake/AAA HTTP/1.1\x0d\nHost: api.telegram.org\x0d\nContent-Type: application/json\x0d\nContent-Length: %ld\x0d\nX-Telegram-Bot-Api-Secret-Token: s3cr\x0d\n\x0d\n%s",
        strlen(body), body);
    tg_wb_parse(&reqbuf, strlen(&reqbuf));
    chk(tg_wbslot[0] == 1, "parse: валидный POST — valid==1");
    chk(tg_wbslot[1] == 1, "parse: метод POST==1");
    chk(tg_wbslot[9] == 1, "parse: cl_present==1");
    chk(tg_wbslot[2] == strlen(body), "parse: content-length==длине тела");
    chk(tg_wbslot[4] == strlen(body), "parse: body_len==длине тела");
    chk(strcmp(tg_wbslot[3], body) == 0, "parse: body_ptr указывает на тело");
    chk(tg_wbslot[5] == 1, "parse: secret_present==1");
    chk(tg_wbslot[6] == 1, "parse: secret_ok==1");
    chk(tg_wbslot[7] == 0, "parse: incomplete==0");

    // (б) секрет-мимо
    sprintf(&reqbuf,
        "POST /x HTTP/1.1\x0d\nContent-Length: %ld\x0d\nX-Telegram-Bot-Api-Secret-Token: bad\x0d\n\x0d\n%s",
        strlen(body), body);
    tg_wb_parse(&reqbuf, strlen(&reqbuf));
    chk(tg_wbslot[5] == 1, "parse: неверный секрет — present==1");
    chk(tg_wbslot[6] == 0, "parse: неверный секрет — ok==0");

    // (в) заголовка секрета нет
    sprintf(&reqbuf, "POST /x HTTP/1.1\x0d\nContent-Length: %ld\x0d\n\x0d\n%s",
        strlen(body), body);
    tg_wb_parse(&reqbuf, strlen(&reqbuf));
    chk(tg_wbslot[5] == 0, "parse: секрета нет — present==0");
    chk(tg_wbslot[6] == 0, "parse: секрета нет — ok==0");

    // (г) GET
    tg_wb_parse("GET /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\n", strlen("GET /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\n"));
    chk(tg_wbslot[0] == 1, "parse: GET структурно валиден");
    chk(tg_wbslot[1] == 2, "parse: метод GET==2");

    // (г2) прочий метод
    tg_wb_parse("PUT /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\n", strlen("PUT /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\n"));
    chk(tg_wbslot[1] == 3, "parse: прочий метод==3");

    // (д) нет Content-Length → пустое тело
    tg_wb_parse("POST /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\njunk", strlen("POST /x HTTP/1.1\x0d\nHost: h\x0d\n\x0d\njunk"));
    chk(tg_wbslot[9] == 0, "parse: без Content-Length — cl_present==0");
    chk(tg_wbslot[2] == 0, "parse: без Content-Length — пустое тело");
    chk(tg_wbslot[4] == 0, "parse: без Content-Length — body_len==0");
    chk(tg_wbslot[7] == 0, "parse: без Content-Length — incomplete==0");

    // (е) обрезанное тело: Content-Length 100, фактически 6 байт
    sprintf(&reqbuf, "POST /x HTTP/1.1\x0d\nContent-Length: 100\x0d\n\x0d\nshorty");
    tg_wb_parse(&reqbuf, strlen(&reqbuf));
    chk(tg_wbslot[0] == 1, "parse: обрезанное тело — valid==1");
    chk(tg_wbslot[7] == 1, "parse: обрезанное тело — incomplete==1");
    chk(tg_wbslot[4] == 6, "parse: обрезанное тело — body_len==6");

    // (ж) нет \r\n\r\n → невалиден
    tg_wb_parse("POST /x HTTP/1.1\x0d\nHost: h", strlen("POST /x HTTP/1.1\x0d\nHost: h"));
    chk(tg_wbslot[0] == 0, "parse: без \\r\\n\\r\\n — valid==0");

    // ===== 2. живой localhost-тест =====
    bot = tg_bot("123:fake");
    bot[7] = &myerr;
    tg_on_text(bot, "h", &h_log);

    port = 18081;
    sfd = tg_wb_open(bot, port, "s3cr");
    if sfd == 0 {
        port = 18082;
        sfd = tg_wb_open(bot, port, "s3cr");
    }
    if sfd == 0 {
        printf("FAIL: no network\n");
        exit(1);
    }

    // (а) EADDRINUSE: повторный open того же порта → 0 + on_error
    r = tg_wb_open(bot, port, "s3cr");
    chk(r == 0, "open: занятый порт → 0");
    chk(errc[0] == 1, "open: on_error вызван 1 раз");
    chk(errc[1] == 2, "open: on_error code==2 (bind)");

    // (б) без соединений: select-таймаут → 0 (~1с)
    r = tg_wb_step(bot, sfd, "s3cr");
    chk(r == 0, "step: таймаут accept → 0");

    // (в) валидный POST с секретом → 200 + диспетчер
    tg_buf_reset(&logb);
    cfd = mkclient(port);
    chk(cfd > 0, "live: клиент подключился");
    sprintf(&reqbuf,
        "POST /bot123:fake/AAA HTTP/1.1\x0d\nContent-Type: application/json\x0d\nContent-Length: %ld\x0d\nX-Telegram-Bot-Api-Secret-Token: s3cr\x0d\n\x0d\n%s",
        strlen(body), body);
    n = csend(cfd);
    chk(ishuge(n) == 0, "live: клиент отправил запрос");
    r = tg_wb_step(bot, sfd, "s3cr");
    chk(r == 1, "step: соединение обработано → 1");
    n = cread(cfd);
    chk(strstr(&respbuf, "HTTP/1.1 200 OK") != 0, "live: ответ 200 OK");
    chk(strstr(&respbuf, "\x0d\n\x0d\nok") != 0, "live: тело ответа ok");
    chk(logb[1] > 0, "live: диспетчер получил апдейт");
    chk(strcmp(logb[0], "got:вебхук;") == 0, "live: handler увидел текст вебхук");
    close(cfd);

    // (г) секрет-мимо → 403, диспетчер НЕ вызывается
    tg_buf_reset(&logb);
    cfd = mkclient(port);
    chk(cfd > 0, "live: клиент (403) подключился");
    sprintf(&reqbuf,
        "POST /x HTTP/1.1\x0d\nContent-Length: %ld\x0d\nX-Telegram-Bot-Api-Secret-Token: BAD\x0d\n\x0d\n%s",
        strlen(body), body);
    csend(cfd);
    r = tg_wb_step(bot, sfd, "s3cr");
    chk(r == 1, "step: 403-соединение обработано → 1");
    cread(cfd);
    chk(strstr(&respbuf, "403 Forbidden") != 0, "live: неверный секрет → 403");
    chk(logb[1] == 0, "live: 403 — диспетчер НЕ вызван");
    close(cfd);

    // (д) GET → 404
    tg_buf_reset(&logb);
    cfd = mkclient(port);
    chk(cfd > 0, "live: клиент (404) подключился");
    sprintf(&reqbuf, "GET / HTTP/1.1\x0d\nHost: h\x0d\n\x0d\n");
    csend(cfd);
    tg_wb_step(bot, sfd, "s3cr");
    cread(cfd);
    chk(strstr(&respbuf, "404 Not Found") != 0, "live: GET → 404");
    chk(logb[1] == 0, "live: 404 — диспетчер НЕ вызван");
    close(cfd);

    // (е) обрезанное тело: клиент дописал заголовок и полузакрылся (SHUT_WR)
    // → сервер видит обрыв тела → 400; ответ ещё читается (полузакрытие)
    tg_buf_reset(&logb);
    cfd = mkclient(port);
    chk(cfd > 0, "live: клиент (400) подключился");
    sprintf(&reqbuf, "POST /x HTTP/1.1\x0d\nContent-Length: 100\x0d\nX-Telegram-Bot-Api-Secret-Token: s3cr\x0d\n\x0d\nshort");
    csend(cfd);
    shutdown(cfd, 1);                // SHUT_WR: тело не дописано, чтение открыто
    tg_wb_step(bot, sfd, "s3cr");
    cread(cfd);
    chk(strstr(&respbuf, "400 Bad Request") != 0, "live: обрезанное тело → 400");
    chk(logb[1] == 0, "live: 400 — диспетчер НЕ вызван");
    close(cfd);

    // (ж) нет Content-Length → 400
    tg_buf_reset(&logb);
    cfd = mkclient(port);
    chk(cfd > 0, "live: клиент (no-cl) подключился");
    sprintf(&reqbuf, "POST /x HTTP/1.1\x0d\nX-Telegram-Bot-Api-Secret-Token: s3cr\x0d\nHost: h\x0d\n\x0d\n");
    csend(cfd);
    tg_wb_step(bot, sfd, "s3cr");
    cread(cfd);
    chk(strstr(&respbuf, "400 Bad Request") != 0, "live: без Content-Length → 400");
    chk(logb[1] == 0, "live: 400 — диспетчер НЕ вызван");
    close(cfd);

    // (з) step на закрытом сокете → 0
    close(sfd);
    r = tg_wb_step(bot, sfd, "s3cr");
    chk(r == 0, "step: закрытый сокет → 0");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
