// t_methods.k — обёртки методов API: композиция URL+тела в dry-режиме (без сети)
extern printf
extern exit
extern strcmp
extern strstr

fails[1];
u_msg[1];
u_cb[1];

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
    auto ctx1;
    auto ctx2;
    auto r;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    u_msg = "{\"update_id\":1, \"message\": {\"message_id\": 42, \"chat\": {\"id\": 55, \"type\": \"private\"}, \"from\": {\"id\": 9, \"first_name\": \"Ю\"}, \"text\": \"hi\"}}";
    u_cb = "{\"update_id\":2, \"callback_query\": {\"id\": \"cb1\", \"from\": {\"id\":9}, \"data\": \"x\"}}";
    ctx1 = tg_ctx_build(bot, u_msg);
    ctx2 = tg_ctx_build(bot, u_cb);
    tg_dry_run = 1;

    // 1. tg_send_text(ctx, text) — chat_id из ctx
    r = tg_send_text(ctx1, "hi");
    chk(r == 1, "send_text: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendMessage|") != 0, "send_text: URL /sendMessage");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"text\":\"hi\"}") != 0,
        "send_text: тело {chat_id,text}");

    // 2. tg_send_to(bot, chat_id, text) — вне контекста
    tg_send_to(bot, 77, "yo");
    chk(strstr(&tg_composed, "/sendMessage|") != 0, "send_to: URL /sendMessage");
    chk(strstr(&tg_composed, "{\"chat_id\":77,\"text\":\"yo\"}") != 0,
        "send_to: тело с явным chat_id");

    // 3. tg_answer(ctx, text) — callback_query_id из ctx
    tg_answer(ctx2, "ok");
    chk(strstr(&tg_composed, "/answerCallbackQuery|") != 0, "answer: URL");
    chk(strstr(&tg_composed, "{\"callback_query_id\":\"cb1\",\"text\":\"ok\"}") != 0,
        "answer: тело {callback_query_id,text}");

    // 4. tg_action(ctx, action)
    tg_action(ctx1, "typing");
    chk(strstr(&tg_composed, "/sendChatAction|") != 0, "action: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"action\":\"typing\"}") != 0,
        "action: тело {chat_id,action}");

    // 5. tg_edit_text(bot, chat_id, msg_id, text)
    tg_edit_text(bot, 55, 42, "new");
    chk(strstr(&tg_composed, "/editMessageText|") != 0, "edit_text: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"text\":\"new\"}") != 0,
        "edit_text: тело {chat_id,message_id,text}");

    // 6. tg_edit_inline(bot, inline_msg_id, text) — БЕЗ chat_id
    tg_edit_inline(bot, "il1", "new");
    chk(strstr(&tg_composed, "/editMessageText|") != 0, "edit_inline: URL");
    chk(strstr(&tg_composed, "{\"inline_message_id\":\"il1\",\"text\":\"new\"}") != 0,
        "edit_inline: тело {inline_message_id,text}");
    chk(strstr(&tg_composed, "chat_id") == 0,
        "edit_inline: chat_id отсутствует");

    // 7. tg_delete(bot, chat_id, msg_id)
    tg_delete(bot, 55, 42);
    chk(strstr(&tg_composed, "/deleteMessage|") != 0, "delete: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "delete: тело {chat_id,message_id}");

    // 8. tg_send_photo_url(bot, chat_id, url)
    tg_send_photo_url(bot, 55, "http://x/p.jpg");
    chk(strstr(&tg_composed, "/sendPhoto|") != 0, "send_photo: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"photo\":\"http://x/p.jpg\"}") != 0,
        "send_photo: тело {chat_id,photo}");

    tg_dry_run = 0;
    tg_ctx_free(ctx1);
    tg_ctx_free(ctx2);

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
