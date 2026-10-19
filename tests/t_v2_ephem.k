// t_v2_ephem.k — эфемерные сообщения, suggested posts, черновики, rich,
// join-request WebApp, subscription invite, emoji status.
// Композиция URL+тела в dry-режиме (без сети). Спецкейсы: markup=0 →
// "reply_markup":null; duration=0 → поле отсутствует; кириллица в text/caption.
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

    // 1. tg_del_ephemeral(bot, chat_id, receiver_user_id, ephemeral_message_id)
    r = tg_del_ephemeral(bot, 55, 9, 7);
    chk(r == 1, "del_ephemeral: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteEphemeralMessage|") != 0, "del_ephemeral: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7}") != 0,
        "del_ephemeral: тело {chat_id,receiver_user_id,ephemeral_message_id}");

    // 2. tg_edit_ephemeral_text — кириллица в text
    r = tg_edit_ephemeral_text(bot, 55, 9, 7, "Новый текст");
    chk(r == 1, "edit_ephemeral_text: dry-возврат 1");
    chk(strstr(&tg_composed, "/editEphemeralMessageText|") != 0, "edit_ephemeral_text: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7,\"text\":\"Новый текст\"}") != 0,
        "edit_ephemeral_text: тело с кириллицей");

    // 3. tg_edit_ephemeral_caption — кириллица в caption
    r = tg_edit_ephemeral_caption(bot, 55, 9, 7, "Подпись");
    chk(r == 1, "edit_ephemeral_caption: dry-возврат 1");
    chk(strstr(&tg_composed, "/editEphemeralMessageCaption|") != 0, "edit_ephemeral_caption: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7,\"caption\":\"Подпись\"}") != 0,
        "edit_ephemeral_caption: тело с кириллицей");

    // 4. tg_edit_ephemeral_media — media сырой JSON
    r = tg_edit_ephemeral_media(bot, 55, 9, 7, "{\"type\":\"photo\",\"media\":\"http://x/p.jpg\"}");
    chk(r == 1, "edit_ephemeral_media: dry-возврат 1");
    chk(strstr(&tg_composed, "/editEphemeralMessageMedia|") != 0, "edit_ephemeral_media: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7,\"media\":{\"type\":\"photo\",\"media\":\"http://x/p.jpg\"}}") != 0,
        "edit_ephemeral_media: тело с raw media");

    // 5. tg_edit_ephemeral_markup — markup_json
    r = tg_edit_ephemeral_markup(bot, 55, 9, 7, "{\"inline_keyboard\":[[]]}");
    chk(r == 1, "edit_ephemeral_markup: dry-возврат 1");
    chk(strstr(&tg_composed, "/editEphemeralMessageReplyMarkup|") != 0, "edit_ephemeral_markup: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7,\"reply_markup\":{\"inline_keyboard\":[[]]}}") != 0,
        "edit_ephemeral_markup: тело с reply_markup");

    // 5b. markup=0 → "reply_markup":null (снять клавиатуру)
    r = tg_edit_ephemeral_markup(bot, 55, 9, 7, 0);
    chk(strstr(&tg_composed, "/editEphemeralMessageReplyMarkup|") != 0, "edit_ephemeral_markup null: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"receiver_user_id\":9,\"ephemeral_message_id\":7,\"reply_markup\":null}") != 0,
        "edit_ephemeral_markup null: reply_markup null");

    // 6. tg_approve_suggested(bot, chat_id, message_id, send_date*|0)
    r = tg_approve_suggested(bot, 55, 42, 1760000000);
    chk(r == 1, "approve_suggested: dry-возврат 1");
    chk(strstr(&tg_composed, "/approveSuggestedPost|") != 0, "approve_suggested: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"send_date\":1760000000}") != 0,
        "approve_suggested: тело с send_date");

    // 6b. send_date=0 → поле не передаётся
    r = tg_approve_suggested(bot, 55, 42, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "approve_suggested без даты: тело {chat_id,message_id}");
    chk(strstr(&tg_composed, "send_date") == 0, "approve_suggested без даты: send_date отсутствует");

    // 7. tg_decline_suggested(bot, chat_id, message_id, comment*|0)
    r = tg_decline_suggested(bot, 55, 42, "нет спасибо");
    chk(r == 1, "decline_suggested: dry-возврат 1");
    chk(strstr(&tg_composed, "/declineSuggestedPost|") != 0, "decline_suggested: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"comment\":\"нет спасибо\"}") != 0,
        "decline_suggested: тело с comment");

    // 7b. comment=0 → поле не передаётся
    r = tg_decline_suggested(bot, 55, 42, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "decline_suggested без коммента: тело {chat_id,message_id}");

    // 8. tg_message_draft(bot, chat_id, draft_id, text*|0) — sendMessageDraft
    r = tg_message_draft(bot, 55, 3, "Текст черновика");
    chk(r == 1, "message_draft: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendMessageDraft|") != 0, "message_draft: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"draft_id\":3,\"text\":\"Текст черновика\"}") != 0,
        "message_draft: тело {chat_id,draft_id,text}");

    // 8b. text=0 → поле не передаётся
    r = tg_message_draft(bot, 55, 3, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"draft_id\":3}") != 0,
        "message_draft без текста: тело {chat_id,draft_id}");

    // 9. tg_rich_message(bot, chat_id, rich_json) — sendRichMessage
    r = tg_rich_message(bot, 55, "{\"blocks\":[]}");
    chk(r == 1, "rich_message: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendRichMessage|") != 0, "rich_message: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"rich_message\":{\"blocks\":[]}}") != 0,
        "rich_message: тело {chat_id,rich_message}");

    // 10. tg_rich_draft(bot, chat_id, draft_id, rich_json) — sendRichMessageDraft
    r = tg_rich_draft(bot, 55, 3, "{\"blocks\":[]}");
    chk(r == 1, "rich_draft: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendRichMessageDraft|") != 0, "rich_draft: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"draft_id\":3,\"rich_message\":{\"blocks\":[]}}") != 0,
        "rich_draft: тело {chat_id,draft_id,rich_message}");

    // 11. tg_join_request_webapp(bot, query_id, web_app_url) — sendChatJoinRequestWebApp
    // NB: по .md метод принимает chat_join_request_query_id, а НЕ chat_id
    r = tg_join_request_webapp(bot, "q1", "https://x.app");
    chk(r == 1, "join_request_webapp: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendChatJoinRequestWebApp|") != 0, "join_request_webapp: URL");
    chk(strstr(&tg_composed, "{\"chat_join_request_query_id\":\"q1\",\"web_app_url\":\"https://x.app\"}") != 0,
        "join_request_webapp: тело {chat_join_request_query_id,web_app_url}");

    // 12. tg_edit_subscription_invite(bot, chat_id, invite_link, name*|0)
    r = tg_edit_subscription_invite(bot, 55, "https://t.me/+abc", "имя");
    chk(r == 1, "edit_subscription_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/editChatSubscriptionInviteLink|") != 0, "edit_subscription_invite: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"invite_link\":\"https://t.me/+abc\",\"name\":\"имя\"}") != 0,
        "edit_subscription_invite: тело с name");

    // 12b. name=0 → поле не передаётся
    r = tg_edit_subscription_invite(bot, 55, "https://t.me/+abc", 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"invite_link\":\"https://t.me/+abc\"}") != 0,
        "edit_subscription_invite без имени: тело {chat_id,invite_link}");

    // 13. tg_user_emoji_status(bot, user_id, custom_emoji_id, duration*|0)
    r = tg_user_emoji_status(bot, 9, "5368324170671202286", 1760000000);
    chk(r == 1, "user_emoji_status: dry-возврат 1");
    chk(strstr(&tg_composed, "/setUserEmojiStatus|") != 0, "user_emoji_status: URL");
    chk(strstr(&tg_composed, "{\"user_id\":9,\"emoji_status_custom_emoji_id\":\"5368324170671202286\",\"emoji_status_expiration_date\":1760000000}") != 0,
        "user_emoji_status: тело с expiration_date");

    // 13b. duration=0 → поле отсутствует
    r = tg_user_emoji_status(bot, 9, "5368324170671202286", 0);
    chk(strstr(&tg_composed, "{\"user_id\":9,\"emoji_status_custom_emoji_id\":\"5368324170671202286\"}") != 0,
        "user_emoji_status без duration: тело {user_id,emoji_status_custom_emoji_id}");
    chk(strstr(&tg_composed, "emoji_status_expiration_date") == 0,
        "user_emoji_status без duration: expiration_date отсутствует");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
