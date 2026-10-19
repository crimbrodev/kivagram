// t_v2_chat.k — управление чатом (B8): композиция URL+тела в dry-режиме
// Покрытие: 16 обёрток lib/tg_chat.k + спецкейсы:
//   tg_unpin(bot,55,0) → тело только {"chat_id":55};
//   tg_set_description(bot,55,0) / tg_create_invite(bot,55,0) → опциональный
//   параметр не передаётся.
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

    // 1. tg_pin(bot, chat_id, msg_id) — pinChatMessage
    r = tg_pin(bot, 55, 42);
    chk(r == 1, "pin: dry-возврат 1");
    chk(strstr(&tg_composed, "/pinChatMessage|") != 0, "pin: URL /pinChatMessage");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "pin: тело {chat_id,message_id}");

    // 2. tg_unpin(bot, chat_id, msg_id) — unpinChatMessage
    r = tg_unpin(bot, 55, 42);
    chk(r == 1, "unpin: dry-возврат 1");
    chk(strstr(&tg_composed, "/unpinChatMessage|") != 0, "unpin: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "unpin: тело {chat_id,message_id}");

    // 2b. СПЕЦКЕЙС: tg_unpin(bot,55,0) → тело только {"chat_id":55}
    r = tg_unpin(bot, 55, 0);
    chk(r == 1, "unpin(0): dry-возврат 1");
    chk(strstr(&tg_composed, "/unpinChatMessage|") != 0, "unpin(0): URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "unpin(0): тело только {chat_id}");
    chk(strstr(&tg_composed, "message_id") == 0,
        "unpin(0): message_id отсутствует");

    // 3. tg_unpin_all(bot, chat_id) — unpinAllChatMessages
    r = tg_unpin_all(bot, 55);
    chk(r == 1, "unpin_all: dry-возврат 1");
    chk(strstr(&tg_composed, "/unpinAllChatMessages|") != 0, "unpin_all: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "unpin_all: тело {chat_id}");

    // 4. tg_set_title(bot, chat_id, title) — setChatTitle
    r = tg_set_title(bot, 55, "Название");
    chk(r == 1, "set_title: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatTitle|") != 0, "set_title: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"title\":\"Название\"}") != 0,
        "set_title: тело {chat_id,title}");

    // 5. tg_set_description(bot, chat_id, desc) — setChatDescription
    r = tg_set_description(bot, 55, "Описание");
    chk(r == 1, "set_desc: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatDescription|") != 0, "set_desc: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"description\":\"Описание\"}") != 0,
        "set_desc: тело {chat_id,description}");

    // 5b. desc=0 → не передавать
    r = tg_set_description(bot, 55, 0);
    chk(r == 1, "set_desc(0): dry-возврат 1");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "set_desc(0): тело {chat_id}");
    chk(strstr(&tg_composed, "description") == 0,
        "set_desc(0): description отсутствует");

    // 6. tg_set_chat_photo(bot, chat_id, file_id) — setChatPhoto
    r = tg_set_chat_photo(bot, 55, "f-1");
    chk(r == 1, "set_photo: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatPhoto|") != 0, "set_photo: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"photo\":\"f-1\"}") != 0,
        "set_photo: тело {chat_id,photo}");

    // 7. tg_del_chat_photo(bot, chat_id) — deleteChatPhoto
    r = tg_del_chat_photo(bot, 55);
    chk(r == 1, "del_photo: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteChatPhoto|") != 0, "del_photo: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "del_photo: тело {chat_id}");

    // 8. tg_set_chat_sticker_set(bot, chat_id, set_name) — setChatStickerSet
    r = tg_set_chat_sticker_set(bot, 55, "Stickers");
    chk(r == 1, "set_stickers: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatStickerSet|") != 0, "set_stickers: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"sticker_set_name\":\"Stickers\"}") != 0,
        "set_stickers: тело {chat_id,sticker_set_name}");

    // 9. tg_leave(bot, chat_id) — leaveChat
    r = tg_leave(bot, 55);
    chk(r == 1, "leave: dry-возврат 1");
    chk(strstr(&tg_composed, "/leaveChat|") != 0, "leave: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "leave: тело {chat_id}");

    // 10. tg_export_invite(bot, chat_id) — exportChatInviteLink
    r = tg_export_invite(bot, 55);
    chk(r == 1, "export_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/exportChatInviteLink|") != 0, "export_invite: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "export_invite: тело {chat_id}");

    // 11. tg_create_invite(bot, chat_id, name) — createChatInviteLink
    r = tg_create_invite(bot, 55, "имя");
    chk(r == 1, "create_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/createChatInviteLink|") != 0, "create_invite: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"name\":\"имя\"}") != 0,
        "create_invite: тело {chat_id,name}");

    // 11b. name=0 → не передавать
    r = tg_create_invite(bot, 55, 0);
    chk(r == 1, "create_invite(0): dry-возврат 1");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "create_invite(0): тело {chat_id}");
    chk(strstr(&tg_composed, "name") == 0,
        "create_invite(0): name отсутствует");

    // 12. tg_edit_invite(bot, chat_id, link, name) — editChatInviteLink
    r = tg_edit_invite(bot, 55, "https://t.me/+abc", "имя");
    chk(r == 1, "edit_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/editChatInviteLink|") != 0, "edit_invite: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"invite_link\":\"https://t.me/+abc\",\"name\":\"имя\"}") != 0,
        "edit_invite: тело {chat_id,invite_link,name}");

    // 12b. name=0 → не передавать
    r = tg_edit_invite(bot, 55, "https://t.me/+abc", 0);
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"invite_link\":\"https://t.me/+abc\"}") != 0,
        "edit_invite(0): тело без name");
    chk(strstr(&tg_composed, ",\"name\"") == 0,
        "edit_invite(0): name отсутствует");

    // 13. tg_revoke_invite(bot, chat_id, link) — revokeChatInviteLink
    r = tg_revoke_invite(bot, 55, "https://t.me/+abc");
    chk(r == 1, "revoke_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/revokeChatInviteLink|") != 0, "revoke_invite: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"invite_link\":\"https://t.me/+abc\"}") != 0,
        "revoke_invite: тело {chat_id,invite_link}");

    // 14. tg_approve_join(bot, chat_id, user_id) — approveChatJoinRequest
    r = tg_approve_join(bot, 55, 9);
    chk(r == 1, "approve_join: dry-возврат 1");
    chk(strstr(&tg_composed, "/approveChatJoinRequest|") != 0, "approve_join: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "approve_join: тело {chat_id,user_id}");

    // 15. tg_decline_join(bot, chat_id, user_id) — declineChatJoinRequest
    r = tg_decline_join(bot, 55, 9);
    chk(r == 1, "decline_join: dry-возврат 1");
    chk(strstr(&tg_composed, "/declineChatJoinRequest|") != 0, "decline_join: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "decline_join: тело {chat_id,user_id}");

    // 16. tg_create_subscription_invite(bot, chat_id, period, price)
    //     — createChatSubscriptionInviteLink (name — через tg_call)
    r = tg_create_subscription_invite(bot, 55, 2592000, 100);
    chk(r == 1, "sub_invite: dry-возврат 1");
    chk(strstr(&tg_composed, "/createChatSubscriptionInviteLink|") != 0,
        "sub_invite: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"subscription_period\":2592000,\"subscription_price\":100}") != 0,
        "sub_invite: тело {chat_id,subscription_period,subscription_price}");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
