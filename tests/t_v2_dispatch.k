// t_v2_dispatch.k — диспетчер v2: kind 4-10, аксессоры payload-апдейтов,
// расширенный Ctx (слот 17 business_connection_id), allowed_updates.
// Без сети: только tg_upd_kind / tg_handle_update / tg_poll_params.
extern printf
extern exit
extern strcmp
extern strstr

fails[1];
logb[3];   // Buf-слот журнала срабатываний

// синтетические апдейты (слоты-глобалы: в позиции значения = word0 = ptr)
ued[1];    // update_id:7  edited_message            → kind 4
ucp[1];    // channel_post                           → kind 5
uecp[1];   // edited_channel_post                    → kind 5
umm[1];    // my_chat_member                         → kind 6
ujr[1];    // update_id:8  chat_join_request         → kind 7
uiq[1];    // update_id:9  inline_query              → kind 8
upc[1];    // pre_checkout_query                     → kind 9
ush[1];    // shipping_query                         → kind 10
utx[1];    // message с текстом                      → kind 1 (регресс)
ucm[1];    // message /start + entities              → kind 2 (регресс)
ucb[1];    // callback_query                         → kind 3 (регресс)
ubc[1];    // message + business_connection_id       → ctx-слот 17

// --- хендлеры: текстово ДО main (правило порядка определений) ---

h_text(ctx) { tg_buf_add(&logb, "text;"); 1; }
h_cmd(ctx) { tg_buf_add(&logb, "cmd;"); 1; }
h_cb(ctx) { tg_buf_add(&logb, "cb;"); 1; }

// kind 4: ctx из edited_message.* — копия текста + chat_id + msg_id
h_edit(ctx) {
    auto t;
    auto n;
    auto m;
    t = tg_text(ctx);
    n = tg_chat_id(ctx);
    m = tg_msg_id(ctx);
    tg_buf_add(&logb, "edit:");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, "|");
    tg_buf_addnum(&logb, n);
    tg_buf_add(&logb, "|");
    tg_buf_addnum(&logb, m);
    tg_buf_add(&logb, ";");
    1;
}

h_chan(ctx) { tg_buf_add(&logb, "chan;"); 1; }
h_member(ctx) { tg_buf_add(&logb, "member;"); 1; }

// kind 7: chat_id / user_id из chat_join_request
h_join(ctx) {
    auto c;
    auto u;
    c = tg_join_chat_id(ctx);
    u = tg_join_user_id(ctx);
    tg_buf_add(&logb, "join:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, u);
    tg_buf_add(&logb, ";");
    1;
}

// kind 8: query из inline_query
h_inline(ctx) {
    auto q;
    q = tg_inline_query(ctx);
    tg_buf_add(&logb, "inline:");
    tg_buf_add(&logb, q);
    tg_buf_add(&logb, ";");
    1;
}

// kind 9: id из pre_checkout_query
h_pcq(ctx) {
    auto id;
    id = tg_pcq_id(ctx);
    tg_buf_add(&logb, "pcq:");
    tg_buf_add(&logb, id);
    tg_buf_add(&logb, ";");
    1;
}

// kind 10: id из shipping_query
h_ship(ctx) {
    auto id;
    id = tg_ship_id(ctx);
    tg_buf_add(&logb, "ship:");
    tg_buf_add(&logb, id);
    tg_buf_add(&logb, ";");
    1;
}

// ctx-слот 17: business_connection_id верхнего уровня
h_bc(ctx) {
    auto b;
    b = tg_business_conn(ctx);
    tg_buf_add(&logb, "bc:");
    tg_buf_add(&logb, b);
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
    auto body;

    fails[0] = 0;
    tg_buf_init(&logb);

    // --- синтетические апдейты ---
    ued = "{\"update_id\":7,\"edited_message\":{\"message_id\":50,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"правка\"}}";
    ucp = "{\"update_id\":10,\"channel_post\":{\"message_id\":60,\"chat\":{\"id\":55,\"type\":\"channel\"},\"text\":\"пост\"}}";
    uecp = "{\"update_id\":11,\"edited_channel_post\":{\"message_id\":61,\"chat\":{\"id\":55,\"type\":\"channel\"},\"text\":\"пост2\"}}";
    umm = "{\"update_id\":12,\"my_chat_member\":{\"chat\":{\"id\":70,\"type\":\"supergroup\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"date\":1,\"old_chat_member\":{\"status\":\"member\"},\"new_chat_member\":{\"status\":\"administrator\"}}}";
    ujr = "{\"update_id\":8,\"chat_join_request\":{\"chat\":{\"id\":66,\"type\":\"group\"},\"from\":{\"id\":77,\"first_name\":\"Юля\"},\"date\":1,\"join_request\":{\"date\":2}}}";
    uiq = "{\"update_id\":9,\"inline_query\":{\"id\":\"iq1\",\"from\":{\"id\":88,\"first_name\":\"Ин\"},\"query\":\"поиск\",\"offset\":\"\"}}";
    upc = "{\"update_id\":13,\"pre_checkout_query\":{\"id\":\"pcq1\",\"from\":{\"id\":88,\"first_name\":\"Ин\"},\"currency\":\"XTR\",\"total_amount\":100,\"invoice_payload\":\"p\"}}";
    ush = "{\"update_id\":14,\"shipping_query\":{\"id\":\"sq1\",\"from\":{\"id\":88,\"first_name\":\"Ин\"},\"invoice_payload\":\"p\"}}";
    utx = "{\"update_id\":100,\"message\":{\"message_id\":8,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"просто текст\"}}";
    ucm = "{\"update_id\":101,\"message\":{\"message_id\":7,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"/start a b\",\"entities\":[{\"offset\":0,\"length\":6,\"type\":\"bot_command\"}]}}";
    ucb = "{\"update_id\":102,\"callback_query\":{\"id\":\"cq1\",\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"data\":\"press\",\"chat_instance\":\"ci\"}}";
    ubc = "{\"update_id\":103,\"business_connection_id\":\"bc9\",\"message\":{\"message_id\":70,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"с бизнесом\"}}";

    // ===== 1. kind-классификация =====
    chk(tg_upd_kind(ued) == 4, "kind: edited_message == 4");
    chk(tg_upd_kind(ucp) == 5, "kind: channel_post == 5");
    chk(tg_upd_kind(uecp) == 5, "kind: edited_channel_post == 5");
    chk(tg_upd_kind(umm) == 6, "kind: my_chat_member == 6");
    chk(tg_upd_kind(ujr) == 7, "kind: chat_join_request == 7");
    chk(tg_upd_kind(uiq) == 8, "kind: inline_query == 8");
    chk(tg_upd_kind(upc) == 9, "kind: pre_checkout_query == 9");
    chk(tg_upd_kind(ush) == 10, "kind: shipping_query == 10");

    // регресс: существующие kind 1/2/3 не сломаны
    chk(tg_upd_kind(utx) == 1, "regress: kind 1 текст");
    chk(tg_upd_kind(ucm) == 2, "regress: kind 2 команда");
    chk(tg_upd_kind(ucb) == 3, "regress: kind 3 callback");

    // ===== 2. регистрация + диспетчеризация =====
    bot = tg_bot("123:fake");
    tg_bot_set_username(bot, "ourbot");
    tg_on_text(bot, "text", &h_text);
    tg_on_command(bot, "start", &h_cmd);
    tg_on_callback(bot, "cb", &h_cb);
    tg_on_edited(bot, "ed", &h_edit);
    tg_on_channel(bot, "chan", &h_chan);
    tg_on_membership(bot, "member", &h_member);
    tg_on_join_request(bot, "jr", &h_join);
    tg_on_inline(bot, "iq", &h_inline);
    tg_on_payment(bot, "pcq", &h_pcq);
    tg_on_shipping(bot, "sq", &h_ship);

    // kind 4: хендлер вызван, ctx построен из edited_message.*
    tg_buf_reset(&logb);
    tg_handle_update(bot, ued);
    chk(strcmp(logb[0], "edit:правка|55|50;") == 0,
        "ctx: edited_message — text/chat_id/msg_id из префикса");

    // kind 5: channel_post и edited_channel_post — один хендлер
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucp);
    tg_handle_update(bot, uecp);
    chk(strcmp(logb[0], "chan;chan;") == 0,
        "dispatch: channel_post + edited_channel_post → tg_on_channel");

    // kind 6
    tg_buf_reset(&logb);
    tg_handle_update(bot, umm);
    chk(strcmp(logb[0], "member;") == 0, "dispatch: my_chat_member → tg_on_membership");

    // kind 7: аксессоры chat_id / user_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ujr);
    chk(strcmp(logb[0], "join:66,77;") == 0,
        "ctx: chat_join_request — tg_join_chat_id/tg_join_user_id");

    // kind 8: аксессор query
    tg_buf_reset(&logb);
    tg_handle_update(bot, uiq);
    chk(strcmp(logb[0], "inline:поиск;") == 0,
        "ctx: inline_query — tg_inline_query == query");

    // kind 9: аксессор pre_checkout id
    tg_buf_reset(&logb);
    tg_handle_update(bot, upc);
    chk(strcmp(logb[0], "pcq:pcq1;") == 0,
        "ctx: pre_checkout_query — tg_pcq_id == id");

    // kind 10: аксессор shipping id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ush);
    chk(strcmp(logb[0], "ship:sq1;") == 0,
        "ctx: shipping_query — tg_ship_id == id");

    // регресс: kind 1/2/3 — набор и порядок срабатываний
    tg_buf_reset(&logb);
    tg_handle_update(bot, utx);
    chk(strcmp(logb[0], "text;") == 0, "regress: kind 1 — только хендлер текста");
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucm);
    chk(strcmp(logb[0], "cmd;") == 0, "regress: kind 2 — только хендлер команды");
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucb);
    chk(strcmp(logb[0], "cb;") == 0, "regress: kind 3 — только хендлер callback");

    // ===== 3. ctx-слот 17: business_connection_id =====
    bot2 = tg_bot("123:fake");
    tg_on_text(bot2, "bc", &h_bc);
    tg_buf_reset(&logb);
    tg_handle_update(bot2, ubc);
    chk(strcmp(logb[0], "bc:bc9;") == 0,
        "ctx: tg_business_conn — слот 17 из business_connection_id");

    // ===== 4. allowed_updates =====
    // по умолчанию НЕ передаётся (поведение v1 сохраняется)
    body = tg_poll_params(0);
    chk(strstr(body, "allowed_updates") == 0,
        "allowed: по умолчанию тело без allowed_updates");
    chk(strstr(body, "\"timeout\":30,\"offset\":0") != 0,
        "allowed: timeout/offset как раньше");

    tg_allow_updates_add("message");
    tg_allow_updates_add("callback_query");
    body = tg_poll_params(0);
    chk(strstr(body, "\"allowed_updates\":[\"message\",\"callback_query\"]") != 0,
        "allowed: массив добавляется в тело getUpdates");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
