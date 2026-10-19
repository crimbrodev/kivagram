// t_dispatch.k — реестр хендлеров и диспетчер kivagram (без сети)
extern printf
extern exit
extern strcmp
extern sprintf

fails[1];
logb[3];   // Buf-слот журнала срабатываний
u6[1];     // /cmd@ourbot a b c
u7[1];     // /cmd@otherbot a b c
u8[1];     // callback_query с вложенным message
u9[1];     // /привет — кириллица, entities UTF-16

// --- хендлеры: текстово ДО main (правило порядка определений) ---

h_upd(ctx) { tg_buf_add(&logb, "upd;"); 1; }
h_cmd(ctx) { tg_buf_add(&logb, "cmd;"); 1; }
h_help(ctx) { tg_buf_add(&logb, "help;"); 1; }
h_text(ctx) { tg_buf_add(&logb, "text;"); 1; }
h_cb(ctx) { tg_buf_add(&logb, "cb;"); 1; }
h_msg(ctx) { tg_buf_add(&logb, "msg;"); 1; }
h_stop(ctx) { tg_buf_add(&logb, "stop;"); 0; }
h_a(ctx) { tg_buf_add(&logb, "a;"); 1; }
h_b(ctx) { tg_buf_add(&logb, "b;"); 1; }
h_first(ctx) { tg_buf_add(&logb, "first;"); 1; }
h_first2(ctx) { tg_buf_add(&logb, "first2;"); 1; }
h_second(ctx) { tg_buf_add(&logb, "second;"); 1; }

// --- хендлеры Task 6: чтение полей ctx ---
h_ctx(ctx) {
    auto s;
    auto t;
    t = tg_text(ctx);
    s = tg_from_name(ctx);
    tg_buf_add(&logb, "txt:");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, "|");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, "|");
    s = tg_scratch();
    sprintf(s, "zz%d", 777);   // затереть scratch между чтениями
    tg_buf_add(&logb, t);      // поле ctx должно быть стабильно
    tg_buf_add(&logb, "|");
    t = tg_command(ctx);
    if t == 0 {
        tg_buf_add(&logb, "-");
    } else {
        tg_buf_add(&logb, t);
    }
    tg_buf_add(&logb, "|");
    if tg_exclusive(ctx) == 1 {
        tg_buf_add(&logb, "E1");
    } else {
        tg_buf_add(&logb, "E0");
    }
    tg_buf_add(&logb, ";");
    1;
}
h_cmdctx(ctx) {
    auto s;
    auto a;
    s = tg_command(ctx);
    tg_buf_add(&logb, "cmd:");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, "|");
    s = tg_target_bot(ctx);
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, "|");
    if tg_mine(ctx) == 1 {
        tg_buf_add(&logb, "1");
    } else {
        tg_buf_add(&logb, "0");
    }
    tg_buf_add(&logb, "|");
    a = tg_arg(ctx, 0);
    tg_buf_add(&logb, a);
    tg_buf_add(&logb, "|");
    if tg_exclusive(ctx) == 1 {
        tg_buf_add(&logb, "E1");
    } else {
        tg_buf_add(&logb, "E0");
    }
    tg_buf_add(&logb, ";");
    1;
}
h_cbctx(ctx) {
    auto s;
    auto n;
    s = tg_cbq_id(ctx);
    tg_buf_add(&logb, "cb:");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, "|");
    s = tg_data(ctx);
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, "|");
    n = tg_chat_id(ctx);
    tg_buf_addnum(&logb, n);
    tg_buf_add(&logb, "|");
    n = tg_msg_id(ctx);
    tg_buf_addnum(&logb, n);
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

global main
main() {
    auto bot;
    auto bot2;
    auto bot3;
    auto bot4;
    auto u1;
    auto u2;
    auto u3;
    auto u4;
    auto u5;

    fails[0] = 0;
    tg_buf_init(&logb);

    // (1) message с /start a b + entities bot_command
    u1 = "{\"update_id\":100, \"message\": {\"message_id\":7, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"text\": \"/start a b\", \"entities\": [{\"offset\":0, \"length\": 6, \"type\": \"bot_command\"}]}}";
    // (2) простое текстовое
    u2 = "{\"update_id\":101, \"message\": {\"message_id\":8, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"text\": \"просто текст\"}}";
    // (3) callback_query с data
    u3 = "{\"update_id\":102, \"callback_query\": {\"id\": \"cq1\", \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"data\": \"press\", \"chat_instance\": \"ci\"}}";
    // (4) message-фото (без text)
    u4 = "{\"update_id\":103, \"message\": {\"message_id\":9, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"photo\": [{\"file_id\": \"f1\", \"width\": 90, \"height\": 90}]}}";
    // (5) команда с другим именем — фильтр имени должен отсечь
    u5 = "{\"update_id\":104, \"message\": {\"message_id\":10, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9}, \"text\": \"/help me\", \"entities\": [{\"offset\":0, \"length\": 5, \"type\": \"bot_command\"}]}}";

    // ===== Фаза A: набор и порядок срабатываний =====
    bot = tg_bot("123:fake");
    tg_bot_set_username(bot, "ourbot");

    tg_on_update(bot, "upd", &h_upd);
    tg_on_command(bot, "start", &h_cmd);
    tg_on_text(bot, "text", &h_text);
    tg_on_callback(bot, "cb", &h_cb);
    tg_on_message(bot, "msg", &h_msg);
    tg_on_command(bot, "help", &h_help);

    tg_handle_update(bot, u1);
    tg_handle_update(bot, u2);
    tg_handle_update(bot, u3);
    tg_handle_update(bot, u4);
    chk(strcmp(logb[0], "upd;cmd;upd;text;upd;cb;upd;msg;") == 0,
        "dispatch: набор и порядок на 4 апдейтах");

    tg_handle_update(bot, u5);
    chk(strcmp(logb[0], "upd;cmd;upd;text;upd;cb;upd;msg;upd;help;") == 0,
        "cmd: имя команды фильтрует (start не сработал на /help)");

    // ===== Фаза B: return 0 прерывает цепочку =====
    tg_buf_reset(&logb);
    bot2 = tg_bot("123:fake");
    tg_on_update(bot2, "a", &h_a);
    tg_on_text(bot2, "stop", &h_stop);
    tg_on_update(bot2, "b", &h_b);
    tg_handle_update(bot2, u2);
    chk(strcmp(logb[0], "a;stop;") == 0,
        "return 0: цепочка прервана, b не вызван");

    // ===== Фаза C: перерегистрация по имени заменяет, позиция сохранена =====
    tg_buf_reset(&logb);
    bot3 = tg_bot("123:fake");
    tg_on_text(bot3, "first", &h_first);
    tg_on_text(bot3, "second", &h_second);
    tg_on_text(bot3, "first", &h_first2);
    tg_handle_update(bot3, u2);
    chk(strcmp(logb[0], "first2;second;") == 0,
        "re-register: замена по имени, старый не зовётся, порядок сохранён");

    // ===== Фаза D (Task 6): поля ctx, команда/цель/mine/args, callback, UTF-16-гард =====
    u6 = "{\"update_id\":200, \"message\": {\"message_id\":30, \"chat\": {\"id\":66, \"type\": \"private\"}, \"from\": {\"id\":77, \"first_name\": \"Юля\"}, \"text\": \"/cmd@ourbot a b c\", \"entities\": [{\"offset\":0, \"length\": 11, \"type\": \"bot_command\"}]}}";
    u7 = "{\"update_id\":201, \"message\": {\"message_id\":31, \"chat\": {\"id\":66, \"type\": \"private\"}, \"from\": {\"id\":77, \"first_name\": \"Юля\"}, \"text\": \"/cmd@otherbot a b c\", \"entities\": [{\"offset\":0, \"length\": 12, \"type\": \"bot_command\"}]}}";
    u8 = "{\"update_id\":202, \"callback_query\": {\"id\": \"cbid1\", \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"chat_instance\": \"ci\", \"data\": \"press\", \"message\": {\"message_id\": 42, \"chat\": {\"id\":55, \"type\": \"private\"}, \"text\": \"press\"}}}";
    u9 = "{\"update_id\":203, \"message\": {\"message_id\":32, \"chat\": {\"id\":66, \"type\": \"private\"}, \"from\": {\"id\":77, \"first_name\": \"Юля\"}, \"text\": \"/привет\", \"entities\": [{\"offset\":0, \"length\": 7, \"type\": \"bot_command\"}]}}";

    bot4 = tg_bot("123:fake");
    tg_bot_set_username(bot4, "ourbot");
    tg_on_command(bot4, "cmd", &h_cmdctx);
    tg_on_text(bot4, "ctxtext", &h_ctx);
    tg_on_callback(bot4, "ctxcb", &h_cbctx);

    tg_buf_reset(&logb);
    tg_handle_update(bot4, u6);
    chk(strcmp(logb[0], "cmd:cmd|ourbot|1|a|E1;") == 0,
        "ctx: /cmd@ourbot — command/target/mine/args/exclusive");
    tg_handle_update(bot4, u7);
    chk(strcmp(logb[0], "cmd:cmd|ourbot|1|a|E1;cmd:cmd|otherbot|0|a|E0;") == 0,
        "ctx: /cmd@otherbot — mine=0, exclusive=0");
    tg_handle_update(bot4, u8);
    chk(strcmp(logb[0], "cmd:cmd|ourbot|1|a|E1;cmd:cmd|otherbot|0|a|E0;cb:cbid1|press|55|42;") == 0,
        "ctx: callback — cbq_id/data + chat_id/msg_id из вложенного message");
    tg_handle_update(bot4, u9);
    chk(strcmp(logb[0], "cmd:cmd|ourbot|1|a|E1;cmd:cmd|otherbot|0|a|E0;cb:cbid1|press|55|42;txt:Юля|/привет|/привет|-|E1;") == 0,
        "ctx: UTF-16-гард (kind=1, command=0) + стабильность строк после scratch");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
