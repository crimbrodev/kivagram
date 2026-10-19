// t_v2_dispatch2.k — диспетчер v3: kind 13-27, аксессоры payload-апдейтов.
// Без сети: tg_upd_kind / tg_handle_update на синтетических апдейтах.
extern printf
extern exit
extern strcmp

fails[1];
logb[3];   // Buf-слот журнала срабатываний

// синтетические апдейты kind 13-27
ubc13[1];  // business_connection                → kind 13
udel14[1]; // deleted_business_messages           → kind 14
ugst15[1]; // guest_message                       → kind 15
urct16[1]; // message_reaction                    → kind 16
urcc17[1]; // message_reaction_count              → kind 17
uchn18[1]; // chosen_inline_result                → kind 18
upmd19[1]; // purchased_paid_media                → kind 19
upol20[1]; // poll                                → kind 20
upan21[1]; // poll_answer                         → kind 21
ucmb22[1]; // chat_member                         → kind 22
ubst23[1]; // chat_boost                          → kind 23
ubrm24[1]; // removed_chat_boost                  → kind 24
uman25[1]; // managed_bot                         → kind 25
usub26[1]; // subscription                        → kind 26
ustp27[1]; // stopped_message_generation          → kind 27
utx1[1];   // message с текстом                   → kind 1 (регресс)
ucm2[1];   // message /start + entities           → kind 2 (регресс)
ucb3[1];   // callback_query                      → kind 3 (регресс)

// --- хендлеры: текстово ДО main (правило порядка определений) ---

h_text(ctx) { tg_buf_add(&logb, "text;"); 1; }
h_cmd(ctx) { tg_buf_add(&logb, "cmd;"); 1; }
h_cb(ctx) { tg_buf_add(&logb, "cb;"); 1; }

// kind 13: chat_id (user_chat_id), from_id (user.id), business_conn (id)
h_bconn(ctx) {
    auto n;
    auto m;
    auto s;
    n = tg_chat_id(ctx);
    m = tg_from_id(ctx);
    s = tg_business_conn(ctx);
    tg_buf_add(&logb, "bconn:");
    tg_buf_addnum(&logb, n);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, m);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 14: chat_id (chat.id), business_conn
h_delb(ctx) {
    auto n;
    auto s;
    n = tg_chat_id(ctx);
    s = tg_business_conn(ctx);
    tg_buf_add(&logb, "delb:");
    tg_buf_addnum(&logb, n);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 15: text из сообщения + guest_query_id
h_gst(ctx) {
    auto t;
    auto s;
    t = tg_text(ctx);
    s = tg_guest_query_id(ctx);
    tg_buf_add(&logb, "gst:");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 16: chat_id / msg_id в стандартных слотах + from_id (user)
h_rct(ctx) {
    auto c;
    auto m;
    auto f;
    c = tg_chat_id(ctx);
    m = tg_msg_id(ctx);
    f = tg_from_id(ctx);
    tg_buf_add(&logb, "rct:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, m);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ";");
    1;
}

// kind 17: chat_id / msg_id
h_rcc(ctx) {
    auto c;
    auto m;
    c = tg_chat_id(ctx);
    m = tg_msg_id(ctx);
    tg_buf_add(&logb, "rcc:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, m);
    tg_buf_add(&logb, ";");
    1;
}

// kind 18: from_id, text (query), inline_msg_id
h_chn(ctx) {
    auto f;
    auto t;
    auto m;
    f = tg_from_id(ctx);
    t = tg_text(ctx);
    m = tg_inline_msg_id(ctx);
    tg_buf_add(&logb, "chn:");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, m);
    tg_buf_add(&logb, ";");
    1;
}

// kind 19: from_id, paid_payload (paid_media_payload)
h_pmd(ctx) {
    auto f;
    auto s;
    f = tg_from_id(ctx);
    s = tg_paid_payload(ctx);
    tg_buf_add(&logb, "pmd:");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 20: text (poll.question)
h_pol(ctx) {
    auto t;
    t = tg_text(ctx);
    tg_buf_add(&logb, "pol:");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, ";");
    1;
}

// kind 21: poll_id, option_ids (сырой JSON-массив), from_id (user)
h_pan(ctx) {
    auto p;
    auto o;
    auto f;
    p = tg_poll_answer_poll_id(ctx);
    o = tg_poll_answer_ids(ctx);
    f = tg_from_id(ctx);
    tg_buf_add(&logb, "pan:");
    tg_buf_add(&logb, p);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, o);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ";");
    1;
}

// kind 22: chat_id / from_id из chat_member
h_cmb(ctx) {
    auto c;
    auto f;
    c = tg_chat_id(ctx);
    f = tg_from_id(ctx);
    tg_buf_add(&logb, "cmb:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ";");
    1;
}

// kind 23: boost_chat_id, boost_id, boost_source
h_bst(ctx) {
    auto c;
    auto i;
    auto s;
    c = tg_boost_chat_id(ctx);
    i = tg_boost_id(ctx);
    s = tg_boost_source(ctx);
    tg_buf_add(&logb, "bst:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, i);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 24: chat_id, boost_id, boost_source
h_brm(ctx) {
    auto c;
    auto i;
    auto s;
    c = tg_chat_id(ctx);
    i = tg_boost_id(ctx);
    s = tg_boost_source(ctx);
    tg_buf_add(&logb, "brm:");
    tg_buf_addnum(&logb, c);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, i);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 25: from_id (user — создатель), from_name
h_man(ctx) {
    auto f;
    auto s;
    f = tg_from_id(ctx);
    s = tg_from_name(ctx);
    tg_buf_add(&logb, "man:");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 26: from_id (user — подписчик), from_name
h_sub(ctx) {
    auto f;
    auto s;
    f = tg_from_id(ctx);
    s = tg_from_name(ctx);
    tg_buf_add(&logb, "sub:");
    tg_buf_addnum(&logb, f);
    tg_buf_add(&logb, ",");
    tg_buf_add(&logb, s);
    tg_buf_add(&logb, ";");
    1;
}

// kind 27: chat_id (chat.id)
h_stp(ctx) {
    auto c;
    c = tg_chat_id(ctx);
    tg_buf_add(&logb, "stp:");
    tg_buf_addnum(&logb, c);
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

    fails[0] = 0;
    tg_buf_init(&logb);

    // --- синтетические апдейты kind 13-27 ---
    ubc13 = "{\"update_id\":300,\"business_connection\":{\"id\":\"bc7\",\"user\":{\"id\":9,\"first_name\":\"Ю\"},\"user_chat_id\":55,\"date\":1,\"is_enabled\":true}}";
    udel14 = "{\"update_id\":301,\"deleted_business_messages\":{\"business_connection_id\":\"bc7\",\"chat\":{\"id\":55,\"type\":\"private\"},\"message_ids\":[7,8]}}";
    ugst15 = "{\"update_id\":302,\"guest_message\":{\"message_id\":71,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"гость\",\"guest_query_id\":\"gq1\"}}";
    urct16 = "{\"update_id\":303,\"message_reaction\":{\"chat\":{\"id\":55,\"type\":\"private\"},\"message_id\":72,\"user\":{\"id\":9,\"first_name\":\"Ю\"},\"date\":1,\"old_reaction\":[],\"new_reaction\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}}";
    urcc17 = "{\"update_id\":304,\"message_reaction_count\":{\"chat\":{\"id\":56,\"type\":\"channel\"},\"message_id\":73,\"date\":1,\"reactions\":[]}}";
    uchn18 = "{\"update_id\":305,\"chosen_inline_result\":{\"result_id\":\"r1\",\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"inline_message_id\":\"im1\",\"query\":\"поиск\"}}";
    upmd19 = "{\"update_id\":306,\"purchased_paid_media\":{\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"paid_media_payload\":\"pp1\"}}";
    upol20 = "{\"update_id\":307,\"poll\":{\"id\":\"p1\",\"question\":\"Вопрос?\",\"options\":[],\"total_voter_count\":0,\"is_closed\":false,\"is_anonymous\":true,\"type\":\"regular\",\"allows_multiple_answers\":false}}";
    upan21 = "{\"update_id\":308,\"poll_answer\":{\"poll_id\":\"p1\",\"user\":{\"id\":9,\"first_name\":\"Ю\"},\"option_ids\":[0,2]}}";
    ucmb22 = "{\"update_id\":309,\"chat_member\":{\"chat\":{\"id\":56,\"type\":\"supergroup\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"date\":1,\"old_chat_member\":{\"status\":\"member\"},\"new_chat_member\":{\"status\":\"administrator\"}}}";
    ubst23 = "{\"update_id\":310,\"chat_boost\":{\"chat\":{\"id\":56,\"type\":\"supergroup\"},\"boost\":{\"boost_id\":\"b1\",\"add_date\":1,\"expiration_date\":2,\"source\":{\"source\":\"premium\",\"user\":{\"id\":9,\"first_name\":\"Ю\"}}}}}";
    ubrm24 = "{\"update_id\":311,\"removed_chat_boost\":{\"chat\":{\"id\":56,\"type\":\"supergroup\"},\"boost_id\":\"b1\",\"remove_date\":2,\"source\":{\"source\":\"premium\",\"user\":{\"id\":9,\"first_name\":\"Ю\"}}}}";
    uman25 = "{\"update_id\":312,\"managed_bot\":{\"user\":{\"id\":9,\"first_name\":\"Ю\"},\"bot\":{\"id\":77,\"is_bot\":true,\"first_name\":\"Мой\",\"username\":\"mybot\"}}}";
    usub26 = "{\"update_id\":313,\"subscription\":{\"user\":{\"id\":9,\"first_name\":\"Ю\"},\"invoice_payload\":\"inv1\",\"state\":\"active\"}}";
    ustp27 = "{\"update_id\":314,\"stopped_message_generation\":{\"chat\":{\"id\":55,\"type\":\"private\"},\"message_thread_id\":1,\"draft_id\":42}}";
    // регресс: kind 1/2/3
    utx1 = "{\"update_id\":100,\"message\":{\"message_id\":8,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"просто текст\"}}";
    ucm2 = "{\"update_id\":101,\"message\":{\"message_id\":7,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"/start a b\",\"entities\":[{\"offset\":0,\"length\":6,\"type\":\"bot_command\"}]}}";
    ucb3 = "{\"update_id\":102,\"callback_query\":{\"id\":\"cq1\",\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"data\":\"press\",\"chat_instance\":\"ci\"}}";

    // ===== 1. kind-классификация kind 13-27 =====
    chk(tg_upd_kind(ubc13) == 13, "kind: business_connection == 13");
    chk(tg_upd_kind(udel14) == 14, "kind: deleted_business_messages == 14");
    chk(tg_upd_kind(ugst15) == 15, "kind: guest_message == 15");
    chk(tg_upd_kind(urct16) == 16, "kind: message_reaction == 16");
    chk(tg_upd_kind(urcc17) == 17, "kind: message_reaction_count == 17");
    chk(tg_upd_kind(uchn18) == 18, "kind: chosen_inline_result == 18");
    chk(tg_upd_kind(upmd19) == 19, "kind: purchased_paid_media == 19");
    chk(tg_upd_kind(upol20) == 20, "kind: poll == 20");
    chk(tg_upd_kind(upan21) == 21, "kind: poll_answer == 21");
    chk(tg_upd_kind(ucmb22) == 22, "kind: chat_member == 22");
    chk(tg_upd_kind(ubst23) == 23, "kind: chat_boost == 23");
    chk(tg_upd_kind(ubrm24) == 24, "kind: removed_chat_boost == 24");
    chk(tg_upd_kind(uman25) == 25, "kind: managed_bot == 25");
    chk(tg_upd_kind(usub26) == 26, "kind: subscription == 26");
    chk(tg_upd_kind(ustp27) == 27, "kind: stopped_message_generation == 27");

    // регресс: существующие kind 1/2/3 не сдвинулись
    chk(tg_upd_kind(utx1) == 1, "regress: kind 1 текст");
    chk(tg_upd_kind(ucm2) == 2, "regress: kind 2 команда");
    chk(tg_upd_kind(ucb3) == 3, "regress: kind 3 callback");

    // ===== 2. регистрация + диспетчеризация + аксессоры =====
    bot = tg_bot("123:fake");
    tg_bot_set_username(bot, "ourbot");
    tg_on_text(bot, "text", &h_text);
    tg_on_command(bot, "start", &h_cmd);
    tg_on_callback(bot, "cb", &h_cb);
    tg_on_business_connection(bot, "bconn", &h_bconn);
    tg_on_deleted_business_messages(bot, "delb", &h_delb);
    tg_on_guest(bot, "gst", &h_gst);
    tg_on_reaction(bot, "rct", &h_rct);
    tg_on_reaction_count(bot, "rcc", &h_rcc);
    tg_on_chosen_inline(bot, "chn", &h_chn);
    tg_on_paid_media(bot, "pmd", &h_pmd);
    tg_on_poll(bot, "pol", &h_pol);
    tg_on_poll_answer(bot, "pan", &h_pan);
    tg_on_chat_member(bot, "cmb", &h_cmb);
    tg_on_chat_boost(bot, "bst", &h_bst);
    tg_on_boost_removed(bot, "brm", &h_brm);
    tg_on_managed_bot(bot, "man", &h_man);
    tg_on_subscription(bot, "sub", &h_sub);
    tg_on_stopped_generation(bot, "stp", &h_stp);

    // kind 13: chat_id = user_chat_id, from_id = user.id, слот 17 = id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ubc13);
    chk(strcmp(logb[0], "bconn:55,9,bc7;") == 0,
        "ctx: business_connection — chat_id/from_id/tg_business_conn");

    // kind 14: chat_id + business_connection_id из payload
    tg_buf_reset(&logb);
    tg_handle_update(bot, udel14);
    chk(strcmp(logb[0], "delb:55,bc7;") == 0,
        "ctx: deleted_business_messages — chat_id/tg_business_conn");

    // kind 15: text из сообщения + guest_query_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ugst15);
    chk(strcmp(logb[0], "gst:гость,gq1;") == 0,
        "ctx: guest_message — text/tg_guest_query_id");

    // kind 16: chat_id/msg_id в стандартных слотах, from_id = user.id
    tg_buf_reset(&logb);
    tg_handle_update(bot, urct16);
    chk(strcmp(logb[0], "rct:55,72,9;") == 0,
        "ctx: message_reaction — tg_chat_id/tg_msg_id/from_id");

    // kind 17: chat_id/msg_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, urcc17);
    chk(strcmp(logb[0], "rcc:56,73;") == 0,
        "ctx: message_reaction_count — tg_chat_id/tg_msg_id");

    // kind 18: from_id, text=query, inline_msg_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, uchn18);
    chk(strcmp(logb[0], "chn:9,поиск,im1;") == 0,
        "ctx: chosen_inline_result — from_id/text/tg_inline_msg_id");

    // kind 19: from_id, paid_media_payload
    tg_buf_reset(&logb);
    tg_handle_update(bot, upmd19);
    chk(strcmp(logb[0], "pmd:9,pp1;") == 0,
        "ctx: purchased_paid_media — from_id/tg_paid_payload");

    // kind 20: text = poll.question
    tg_buf_reset(&logb);
    tg_handle_update(bot, upol20);
    chk(strcmp(logb[0], "pol:Вопрос?;") == 0,
        "ctx: poll — text == question");

    // kind 21: poll_id, option_ids (сырой массив), from_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, upan21);
    chk(strcmp(logb[0], "pan:p1,[0,2],9;") == 0,
        "ctx: poll_answer — tg_poll_answer_poll_id/tg_poll_answer_ids/from_id");

    // kind 22: chat_id/from_id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucmb22);
    chk(strcmp(logb[0], "cmb:56,9;") == 0,
        "ctx: chat_member — tg_chat_id/tg_from_id");

    // kind 23: boost_chat_id/boost_id/boost_source
    tg_buf_reset(&logb);
    tg_handle_update(bot, ubst23);
    chk(strcmp(logb[0], "bst:56,b1,premium;") == 0,
        "ctx: chat_boost — tg_boost_chat_id/tg_boost_id/tg_boost_source");

    // kind 24: chat_id/boost_id/boost_source
    tg_buf_reset(&logb);
    tg_handle_update(bot, ubrm24);
    chk(strcmp(logb[0], "brm:56,b1,premium;") == 0,
        "ctx: removed_chat_boost — tg_chat_id/tg_boost_id/tg_boost_source");

    // kind 25: from_id = user.id (создатель), from_name
    tg_buf_reset(&logb);
    tg_handle_update(bot, uman25);
    chk(strcmp(logb[0], "man:9,Ю;") == 0,
        "ctx: managed_bot — from_id/from_name из user");

    // kind 26: from_id = user.id (подписчик), from_name
    tg_buf_reset(&logb);
    tg_handle_update(bot, usub26);
    chk(strcmp(logb[0], "sub:9,Ю;") == 0,
        "ctx: subscription — from_id/from_name из user");

    // kind 27: chat_id = chat.id
    tg_buf_reset(&logb);
    tg_handle_update(bot, ustp27);
    chk(strcmp(logb[0], "stp:55;") == 0,
        "ctx: stopped_message_generation — tg_chat_id");

    // регресс: kind 1/2/3 — набор срабатываний
    tg_buf_reset(&logb);
    tg_handle_update(bot, utx1);
    chk(strcmp(logb[0], "text;") == 0, "regress: kind 1 — только хендлер текста");
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucm2);
    chk(strcmp(logb[0], "cmd;") == 0, "regress: kind 2 — только хендлер команды");
    tg_buf_reset(&logb);
    tg_handle_update(bot, ucb3);
    chk(strcmp(logb[0], "cb;") == 0, "regress: kind 3 — только хендлер callback");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
