// t_v2_ext.k — расширенные send/edit/answer (B13): tg_sendx, tg_editx,
// tg_photox, tg_answer_cb, tg_actionx — композиция URL+тела в dry-режиме
// (без сети). Параметры — эталон /tmp/opencode/ref/api/methods/*.md.

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
    auto p;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    u_msg = "{\"update_id\":1, \"message\": {\"message_id\": 42, \"chat\": {\"id\": 55, \"type\": \"private\"}, \"from\": {\"id\": 9, \"first_name\": \"Ю\"}, \"text\": \"hi\"}}";
    u_cb = "{\"update_id\":2, \"callback_query\": {\"id\": \"cb1\", \"from\": {\"id\":9}, \"data\": \"x\"}}";
    ctx1 = tg_ctx_build(bot, u_msg);
    ctx2 = tg_ctx_build(bot, u_cb);
    tg_dry_run = 1;

    // 1. tg_sendx — все параметры (parse_mode строка, reply_markup сырой JSON)
    r = tg_sendx(bot, 55, "привет", "HTML", "{\"inline_keyboard\":[]}", 0);
    chk(r == 1, "sendx: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendMessage|") != 0, "sendx: URL /sendMessage");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"text\":\"привет\",\"parse_mode\":\"HTML\",\"reply_markup\":{\"inline_keyboard\":[]}}") != 0,
        "sendx: тело {chat_id,text,parse_mode,reply_markup}");

    // 2. tg_sendx — reply_to=42 → reply_parameters {"message_id":42}
    r = tg_sendx(bot, 55, "hi", 0, 0, 42);
    chk(r == 1, "sendx/reply: dry-возврат 1");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"text\":\"hi\",\"reply_parameters\":{\"message_id\":42}}") != 0,
        "sendx/reply: тело {chat_id,text,reply_parameters}");

    // 3. tg_sendx — опциональные по нулям → только обязательные
    tg_sendx(bot, 55, "t", 0, 0, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"text\":\"t\"}") != 0,
        "sendx/min: тело только {chat_id,text}");
    chk(strstr(&tg_composed, "parse_mode") == 0, "sendx/min: parse_mode отсутствует");
    chk(strstr(&tg_composed, "reply_") == 0, "sendx/min: reply_* отсутствуют");

    // 4. tg_editx — все параметры
    r = tg_editx(bot, 55, 42, "new", "HTML", "{\"inline_keyboard\":[[{}]]}");
    chk(r == 1, "editx: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageText|") != 0, "editx: URL /editMessageText");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"text\":\"new\",\"parse_mode\":\"HTML\",\"reply_markup\":{\"inline_keyboard\":[[{}]]}}") != 0,
        "editx: тело {chat_id,message_id,text,parse_mode,reply_markup}");

    // 5. tg_editx — опциональные по нулям
    tg_editx(bot, 55, 42, "new2", 0, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"text\":\"new2\"}") != 0,
        "editx/min: тело без опциональных");

    // 6. tg_photox — caption + parse_mode
    r = tg_photox(bot, 55, "file-1", "подпись", "HTML", 0);
    chk(r == 1, "photox: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendPhoto|") != 0, "photox: URL /sendPhoto");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"photo\":\"file-1\",\"caption\":\"подпись\",\"parse_mode\":\"HTML\"}") != 0,
        "photox: тело {chat_id,photo,caption,parse_mode}");

    // 7. tg_photox — caption=0 → поля нет, reply_markup проброшен
    tg_photox(bot, 55, "file-1", 0, 0, "{\"inline_keyboard\":[]}");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"photo\":\"file-1\",\"reply_markup\":{\"inline_keyboard\":[]}}") != 0,
        "photox/markup: тело {chat_id,photo,reply_markup}");
    chk(strstr(&tg_composed, "caption") == 0, "photox/markup: caption отсутствует");

    // 8. tg_answer_cb(ctx,0,0) → тело ТОЛЬКО {"callback_query_id":"cb1"}
    r = tg_answer_cb(ctx2, 0, 0);
    chk(r == 1, "answer_cb: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerCallbackQuery|") != 0, "answer_cb: URL");
    chk(strstr(&tg_composed, "|{\"callback_query_id\":\"cb1\"}") != 0,
        "answer_cb/id-only: тело только {callback_query_id}");
    chk(strstr(&tg_composed, "show_alert") == 0, "answer_cb/id-only: show_alert отсутствует");

    // 9. tg_answer_cb — text
    tg_answer_cb(ctx2, "ok", 0);
    chk(strstr(&tg_composed, "{\"callback_query_id\":\"cb1\",\"text\":\"ok\"}") != 0,
        "answer_cb/text: тело {callback_query_id,text}");

    // 10. tg_answer_cb — show_alert=1 → raw true (без кавычек)
    tg_answer_cb(ctx2, 0, 1);
    chk(strstr(&tg_composed, "{\"callback_query_id\":\"cb1\",\"show_alert\":true}") != 0,
        "answer_cb/alert: тело {callback_query_id,show_alert:true}");

    // 11. tg_answer_cb на ctx без callback_query (слот 13 = 0) → вызова нет
    p = &tg_composed;
    *p !8 0;   // очистить композицию предыдущего вызова (вызова не было → пусто)
    r = tg_answer_cb(ctx1, "x", 0);
    chk(r == 0, "answer_cb/no-cbq: возврат 0");
    chk(strstr(&tg_composed, "answerCallbackQuery") == 0,
        "answer_cb/no-cbq: вызов не отправлен");

    // 12. tg_actionx — без топика
    r = tg_actionx(bot, 55, "typing", 0);
    chk(r == 1, "actionx: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendChatAction|") != 0, "actionx: URL /sendChatAction");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"action\":\"typing\"}") != 0,
        "actionx: тело {chat_id,action}");

    // 13. tg_actionx — thread_id=7 → message_thread_id
    tg_actionx(bot, 55, "upload_photo", 7);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_thread_id\":7,\"action\":\"upload_photo\"}") != 0,
        "actionx/thread: тело {chat_id,message_thread_id,action}");

    tg_dry_run = 0;
    tg_ctx_free(ctx1);
    tg_ctx_free(ctx2);

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
