// t_v2_msg.k — B4: пересылка/копирование/правки/массовое удаление (dry-run, без сети)
extern printf
extern exit
extern strcmp
extern strstr

fails[1];

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
    auto r;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // 1. tg_forward(bot, chat_id, from_chat_id, msg_id)
    r = tg_forward(bot, 55, 66, 42);
    chk(r == 1, "forward: dry-возврат 1");
    chk(strstr(&tg_composed, "/forwardMessage|") != 0, "forward: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"from_chat_id\":66,\"message_id\":42}") != 0,
        "forward: тело {chat_id,from_chat_id,message_id}");

    // 2. tg_forward_many(bot, chat_id, from_chat_id, ids_json)
    r = tg_forward_many(bot, 55, 66, "[41,42]");
    chk(r == 1, "forward_many: dry-возврат 1");
    chk(strstr(&tg_composed, "/forwardMessages|") != 0, "forward_many: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"from_chat_id\":66,\"message_ids\":[41,42]}") != 0,
        "forward_many: тело с message_ids-массивом без кавычек");

    // 3. tg_copy(bot, chat_id, from_chat_id, msg_id, caption)
    r = tg_copy(bot, 55, 66, 42, "привет");
    chk(r == 1, "copy: dry-возврат 1");
    chk(strstr(&tg_composed, "/copyMessage|") != 0, "copy: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"from_chat_id\":66,\"message_id\":42,\"caption\":\"привет\"}") != 0,
        "copy: тело с caption");

    // 3b. caption=0 → caption не передаётся
    tg_copy(bot, 55, 66, 42, 0);
    chk(strstr(&tg_composed, "/copyMessage|") != 0, "copy nocap: URL");
    chk(strstr(&tg_composed, "\"caption\"") == 0, "copy nocap: caption отсутствует");

    // 4. tg_copy_many(bot, chat_id, from_chat_id, ids_json)
    r = tg_copy_many(bot, 55, 66, "[41,42]");
    chk(r == 1, "copy_many: dry-возврат 1");
    chk(strstr(&tg_composed, "/copyMessages|") != 0, "copy_many: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"from_chat_id\":66,\"message_ids\":[41,42]}") != 0,
        "copy_many: тело с message_ids-массивом");

    // 5. tg_edit_caption(bot, chat_id, msg_id, caption)
    r = tg_edit_caption(bot, 55, 42, "новая");
    chk(r == 1, "edit_caption: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageCaption|") != 0, "edit_caption: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"caption\":\"новая\"}") != 0,
        "edit_caption: тело {chat_id,message_id,caption}");

    // 6. tg_edit_markup(bot, chat_id, msg_id, markup_json)
    r = tg_edit_markup(bot, 55, 42, "{\"inline_keyboard\":[]}");
    chk(r == 1, "edit_markup: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageReplyMarkup|") != 0, "edit_markup: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"reply_markup\":{\"inline_keyboard\":[]}}") != 0,
        "edit_markup: тело с reply_markup-объектом");

    // 6b. markup=0 → снять кнопки: "reply_markup":null (tg_param_raw)
    tg_edit_markup(bot, 55, 42, 0);
    chk(strstr(&tg_composed, "/editMessageReplyMarkup|") != 0, "edit_markup null: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"reply_markup\":null}") != 0,
        "edit_markup null: тело reply_markup=null");

    // 7. tg_edit_media(bot, chat_id, msg_id, media_json)
    r = tg_edit_media(bot, 55, 42, "{\"type\":\"photo\",\"media\":\"f1\"}");
    chk(r == 1, "edit_media: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageMedia|") != 0, "edit_media: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"media\":{\"type\":\"photo\",\"media\":\"f1\"}}") != 0,
        "edit_media: тело с media-объектом без кавычек");

    // 8. tg_edit_live_loc(bot, chat_id, msg_id, lat, lng) — дроби через raw
    r = tg_edit_live_loc(bot, 55, 42, "55.75", "37.62");
    chk(r == 1, "edit_live_loc: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageLiveLocation|") != 0, "edit_live_loc: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"latitude\":55.75,\"longitude\":37.62}") != 0,
        "edit_live_loc: дроби без кавычек");

    // 9. tg_stop_live_loc(bot, chat_id, msg_id)
    r = tg_stop_live_loc(bot, 55, 42);
    chk(r == 1, "stop_live_loc: dry-возврат 1");
    chk(strstr(&tg_composed, "/stopMessageLiveLocation|") != 0, "stop_live_loc: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "stop_live_loc: тело {chat_id,message_id}");

    // 10. tg_delete_many(bot, chat_id, ids_json)
    r = tg_delete_many(bot, 55, "[41,42]");
    chk(r == 1, "delete_many: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteMessages|") != 0, "delete_many: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_ids\":[41,42]}") != 0,
        "delete_many: тело с message_ids-массивом");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
