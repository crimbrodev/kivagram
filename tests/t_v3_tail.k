// t_v3_tail.k — хвост API v2 (W3-6): dry-композиция URL+тела по каждому
// методу lib/tg_tail.k. Верификация (5), managed bot (4), boosts (getUserChatBoosts),
// черновики/сейв (2), чеклисты (2), профиля-фильтры (3) + removeMyProfilePhoto.
// 0-кейсы: 0 → параметр не передаётся. Extras-слияние в тело. Только dry-run,
// без сети.
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
    tg_ex_reset();

    // ===== 1. verifyUser: URL + тело =====
    r = tg_verify_user(bot, 777, "ok");
    chk(r == 1, "verify_user: dry-возврат 1");
    chk(strstr(&tg_composed, "/verifyUser|") != 0, "verify_user: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777,\"custom_description\":\"ok\"}") != 0,
        "verify_user: тело {user_id,custom_description}");

    // 1b. 0-кейс: custom_description=0 → не передаётся
    tg_verify_user(bot, 777, 0);
    chk(strstr(&tg_composed, "{\"user_id\":777}") != 0,
        "verify_user(0): тело без custom_description");

    // ===== 2. verifyChat: URL + тело + 0-кейс =====
    r = tg_verify_chat(bot, 55, "d");
    chk(r == 1, "verify_chat: dry-возврат 1");
    chk(strstr(&tg_composed, "/verifyChat|") != 0, "verify_chat: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"custom_description\":\"d\"}") != 0,
        "verify_chat: тело {chat_id,custom_description}");

    tg_verify_chat(bot, 55, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "verify_chat(0): тело без custom_description");

    // ===== 3. removeUserVerification =====
    r = tg_unverify_user(bot, 777);
    chk(r == 1, "unverify_user: dry-возврат 1");
    chk(strstr(&tg_composed, "/removeUserVerification|") != 0, "unverify_user: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777}") != 0, "unverify_user: тело {user_id}");

    // ===== 4. removeChatVerification =====
    r = tg_unverify_chat(bot, 55);
    chk(r == 1, "unverify_chat: dry-возврат 1");
    chk(strstr(&tg_composed, "/removeChatVerification|") != 0, "unverify_chat: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "unverify_chat: тело {chat_id}");

    // ===== 5. setPassportDataErrors: user_id + errors (JSON-массив) =====
    r = tg_passport_errors(bot, 9, "[{\"type\":\"email\",\"message\":\"bad\"}]");
    chk(r == 1, "passport_errors: dry-возврат 1");
    chk(strstr(&tg_composed, "/setPassportDataErrors|") != 0, "passport_errors: URL");
    chk(strstr(&tg_composed,
        "{\"user_id\":9,\"errors\":[{\"type\":\"email\",\"message\":\"bad\"}]}") != 0,
        "passport_errors: тело {user_id,errors[]}");

    // ===== 6. getManagedBotToken =====
    r = tg_get_managed_token(bot, 900);
    chk(r == 1, "get_managed_token: dry-возврат 1");
    chk(strstr(&tg_composed, "/getManagedBotToken|") != 0, "get_managed_token: URL");
    chk(strstr(&tg_composed, "{\"user_id\":900}") != 0, "get_managed_token: тело {user_id}");

    // ===== 7. replaceManagedBotToken =====
    r = tg_replace_managed_token(bot, 900);
    chk(r == 1, "replace_managed_token: dry-возврат 1");
    chk(strstr(&tg_composed, "/replaceManagedBotToken|") != 0, "replace_managed_token: URL");
    chk(strstr(&tg_composed, "{\"user_id\":900}") != 0, "replace_managed_token: тело {user_id}");

    // ===== 8. getManagedBotAccessSettings =====
    r = tg_get_managed_access(bot, 900);
    chk(r == 1, "get_managed_access: dry-возврат 1");
    chk(strstr(&tg_composed, "/getManagedBotAccessSettings|") != 0, "get_managed_access: URL");
    chk(strstr(&tg_composed, "{\"user_id\":900}") != 0, "get_managed_access: тело {user_id}");

    // ===== 9. setManagedBotAccessSettings: bool-литерал + added_user_ids =====
    r = tg_set_managed_access(bot, 900, 1, "[11,22]");
    chk(r == 1, "set_managed_access: dry-возврат 1");
    chk(strstr(&tg_composed, "/setManagedBotAccessSettings|") != 0, "set_managed_access: URL");
    chk(strstr(&tg_composed,
        "{\"user_id\":900,\"is_access_restricted\":true,\"added_user_ids\":[11,22]}") != 0,
        "set_managed_access: тело {user_id,is_access_restricted:true,added_user_ids}");

    // 9b. 0-кейс: added_user_ids=0 → не передаётся, restricted=false
    tg_set_managed_access(bot, 900, 0, 0);
    chk(strstr(&tg_composed,
        "{\"user_id\":900,\"is_access_restricted\":false}") != 0,
        "set_managed_access(added=0): тело без added_user_ids, false");

    // ===== 10. getUserChatBoosts (точное имя метода из эталона) =====
    r = tg_get_user_boosts(bot, 55, 777);
    chk(r == 1, "get_user_boosts: dry-возврат 1");
    chk(strstr(&tg_composed, "/getUserChatBoosts|") != 0, "get_user_boosts: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"user_id\":777}") != 0,
        "get_user_boosts: тело {chat_id,user_id}");

    // ===== 11. savePreparedInlineMessage: user_id + result =====
    r = tg_save_inline_message(bot, 777, "{\"type\":\"article\"}");
    chk(r == 1, "save_inline_message: dry-возврат 1");
    chk(strstr(&tg_composed, "/savePreparedInlineMessage|") != 0, "save_inline_message: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777,\"result\":{\"type\":\"article\"}}") != 0,
        "save_inline_message: тело {user_id,result}");

    // 11b. allow_* — через extras (съедаются автоматически)
    tg_ex_raw("allow_user_chats", "true");
    tg_save_inline_message(bot, 777, "{\"type\":\"article\"}");
    chk(strstr(&tg_composed,
        "{\"user_id\":777,\"result\":{\"type\":\"article\"},\"allow_user_chats\":true}") != 0,
        "save_inline_message: extras allow_user_chats в теле");
    chk(tg_extraslot[1] == 0, "save_inline_message: extras слот съеден");

    // ===== 12. savePreparedKeyboardButton: user_id + button =====
    r = tg_save_keyboard_button(bot, 777, "{\"type\":\"request_users\"}");
    chk(r == 1, "save_keyboard_button: dry-возврат 1");
    chk(strstr(&tg_composed, "/savePreparedKeyboardButton|") != 0, "save_keyboard_button: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777,\"button\":{\"type\":\"request_users\"}}") != 0,
        "save_keyboard_button: тело {user_id,button}");
    // extras предыдущего кейса не течёт
    chk(strstr(&tg_composed, "allow_user_chats") == 0,
        "save_keyboard_button: extras не течёт в следующий вызов");

    // ===== 13. sendChecklist: business_connection_id + chat_id + checklist =====
    r = tg_send_checklist(bot, "bc1", 55, "{\"title\":\"t\",\"tasks\":[]}");
    chk(r == 1, "send_checklist: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendChecklist|") != 0, "send_checklist: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"chat_id\":55,\"checklist\":{\"title\":\"t\",\"tasks\":[]}}") != 0,
        "send_checklist: тело {business_connection_id,chat_id,checklist}");

    // 13b. disable_notification — через extras
    tg_ex_raw("disable_notification", "true");
    tg_send_checklist(bot, "bc1", 55, "{\"title\":\"t\",\"tasks\":[]}");
    chk(strstr(&tg_composed, "\"disable_notification\":true}") != 0,
        "send_checklist: extras disable_notification перед }");
    chk(tg_extraslot[1] == 0, "send_checklist: extras слот съеден");

    // ===== 14. editMessageChecklist (не editChecklist!) =====
    r = tg_edit_checklist(bot, "bc1", 55, 60, "{\"title\":\"t2\",\"tasks\":[]}");
    chk(r == 1, "edit_checklist: dry-возврат 1");
    chk(strstr(&tg_composed, "/editMessageChecklist|") != 0, "edit_checklist: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"chat_id\":55,\"message_id\":60,\"checklist\":{\"title\":\"t2\",\"tasks\":[]}}") != 0,
        "edit_checklist: тело {bc,chat_id,message_id,checklist}");

    // ===== 15. getUserPersonalChatMessages: user_id + limit (обязательный) =====
    r = tg_get_user_personal_messages(bot, 777, 20);
    chk(r == 1, "get_user_personal_messages: dry-возврат 1");
    chk(strstr(&tg_composed, "/getUserPersonalChatMessages|") != 0,
        "get_user_personal_messages: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777,\"limit\":20}") != 0,
        "get_user_personal_messages: тело {user_id,limit}");

    // ===== 16. getUserGifts: фильтры — плоский объект, срез скобок =====
    r = tg_get_user_gifts(bot, 777, 0);
    chk(r == 1, "get_user_gifts: dry-возврат 1");
    chk(strstr(&tg_composed, "/getUserGifts|") != 0, "get_user_gifts: URL");
    chk(strstr(&tg_composed, "{\"user_id\":777}") != 0,
        "get_user_gifts(0): тело без фильтров");

    tg_get_user_gifts(bot, 777, "{\"exclude_unique\":true,\"limit\":10}");
    chk(strstr(&tg_composed,
        "{\"user_id\":777,\"exclude_unique\":true,\"limit\":10}") != 0,
        "get_user_gifts: тело со срезом скобок filters_json");

    // ===== 17. getChatGifts =====
    r = tg_get_chat_gifts(bot, 55, 0);
    chk(r == 1, "get_chat_gifts: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChatGifts|") != 0, "get_chat_gifts: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "get_chat_gifts(0): тело без фильтров");

    tg_get_chat_gifts(bot, 55, "{\"exclude_saved\":true}");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"exclude_saved\":true}") != 0,
        "get_chat_gifts: тело со срезом скобок filters_json");

    // ===== 18. removeMyProfilePhoto: без параметров (tg_call(...,0), как
    // tg_topic_icons) — композиция "<url>|" с пустым телом =====
    r = tg_remove_profile_photo(bot);
    chk(r == 1, "remove_profile_photo: dry-возврат 1");
    chk(strcmp(&tg_composed,
        "https://api.telegram.org/bot123:fake/removeMyProfilePhoto|") == 0,
        "remove_profile_photo: URL и пустое тело");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
