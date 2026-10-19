// t_v2_admin.k — модерация и участники (B7): композиция URL+тела в dry-режиме
// Покрытие: 13 обёрток lib/tg_admin.k + спецкейс permissions как JSON-объект
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

    // 1. tg_ban(bot, chat_id, user_id) — banChatMember
    r = tg_ban(bot, 55, 9);
    chk(r == 1, "ban: dry-возврат 1");
    chk(strstr(&tg_composed, "/banChatMember|") != 0, "ban: URL /banChatMember");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "ban: тело {chat_id,user_id}");

    // 2. tg_unban(bot, chat_id, user_id) — unbanChatMember
    r = tg_unban(bot, 55, 9);
    chk(r == 1, "unban: dry-возврат 1");
    chk(strstr(&tg_composed, "/unbanChatMember|") != 0, "unban: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "unban: тело {chat_id,user_id}");

    // 3. tg_restrict(bot, chat_id, user_id, perms_json) — restrictChatMember
    //    СПЕЦКЕЙС: permissions через tg_param_json входит в тело БЕЗ кавычек
    r = tg_restrict(bot, 55, 9, "{\"can_send_messages\":false}");
    chk(r == 1, "restrict: dry-возврат 1");
    chk(strstr(&tg_composed, "/restrictChatMember|") != 0, "restrict: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"user_id\":9,\"permissions\":{\"can_send_messages\":false}}") != 0,
        "restrict: тело {chat_id,user_id,permissions-объект без кавычек}");

    // 4. tg_promote(bot, chat_id, user_id, rights_json) — promoteChatMember
    //    rights=0 → не передавать
    r = tg_promote(bot, 55, 9, "{\"can_delete_messages\":true}");
    chk(r == 1, "promote: dry-возврат 1");
    chk(strstr(&tg_composed, "/promoteChatMember|") != 0, "promote: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"user_id\":9,\"can_delete_messages\":true}") != 0,
        "promote: тело {chat_id,user_id,rights-объект}");
    tg_promote(bot, 55, 9, 0);
    chk(strstr(&tg_composed, "/promoteChatMember|") != 0, "promote(0): URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "promote(0): тело без прав");
    chk(strstr(&tg_composed, "can_delete_messages") == 0,
        "promote(0): права отсутствуют");

    // 5. tg_ban_sender_chat(bot, chat_id, sender_chat_id) — banChatSenderChat
    r = tg_ban_sender_chat(bot, 55, -100123);
    chk(r == 1, "ban_sender: dry-возврат 1");
    chk(strstr(&tg_composed, "/banChatSenderChat|") != 0, "ban_sender: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"sender_chat_id\":-100123}") != 0,
        "ban_sender: тело {chat_id,sender_chat_id}");

    // 6. tg_unban_sender_chat(bot, chat_id, sender_chat_id) — unbanChatSenderChat
    r = tg_unban_sender_chat(bot, 55, -100123);
    chk(r == 1, "unban_sender: dry-возврат 1");
    chk(strstr(&tg_composed, "/unbanChatSenderChat|") != 0, "unban_sender: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"sender_chat_id\":-100123}") != 0,
        "unban_sender: тело {chat_id,sender_chat_id}");

    // 7. tg_get_chat_member(bot, chat_id, user_id) — getChatMember
    r = tg_get_chat_member(bot, 55, 9);
    chk(r == 1, "get_member: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChatMember|") != 0, "get_member: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "get_member: тело {chat_id,user_id}");

    // 8. tg_get_member_count(bot, chat_id) — getChatMemberCount
    r = tg_get_member_count(bot, 55);
    chk(r == 1, "member_count: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChatMemberCount|") != 0, "member_count: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "member_count: тело {chat_id}");

    // 9. tg_get_chat(bot, chat_id) — getChat
    r = tg_get_chat(bot, 55);
    chk(r == 1, "get_chat: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChat|") != 0, "get_chat: URL /getChat|");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "get_chat: тело {chat_id}");

    // 10. tg_get_admins(bot, chat_id) — getChatAdministrators
    r = tg_get_admins(bot, 55);
    chk(r == 1, "admins: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChatAdministrators|") != 0, "admins: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "admins: тело {chat_id}");

    // 11. tg_set_permissions(bot, chat_id, perms_json) — setChatPermissions
    r = tg_set_permissions(bot, 55, "{\"can_send_messages\":false}");
    chk(r == 1, "set_perms: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatPermissions|") != 0, "set_perms: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"permissions\":{\"can_send_messages\":false}}") != 0,
        "set_perms: тело {chat_id,permissions-объект без кавычек}");

    // 12. tg_set_member_tag(bot, chat_id, user_id, tag) — setChatMemberTag
    //     tag опционален: 0 → не передавать (снять тег)
    r = tg_set_member_tag(bot, 55, 9, "VIP");
    chk(r == 1, "set_tag: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatMemberTag|") != 0, "set_tag: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9,\"tag\":\"VIP\"}") != 0,
        "set_tag: тело {chat_id,user_id,tag}");
    tg_set_member_tag(bot, 55, 9, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":9}") != 0,
        "set_tag(0): тело без tag");
    chk(strstr(&tg_composed, "tag") == 0, "set_tag(0): tag отсутствует");

    // 13. tg_set_admin_title(bot, chat_id, user_id, title) — setChatAdministratorCustomTitle
    r = tg_set_admin_title(bot, 55, 9, "Boss");
    chk(r == 1, "admin_title: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatAdministratorCustomTitle|") != 0, "admin_title: URL");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"user_id\":9,\"custom_title\":\"Boss\"}") != 0,
        "admin_title: тело {chat_id,user_id,custom_title}");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
