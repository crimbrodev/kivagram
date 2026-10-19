// t_v2_config.k — конфиг бота и меню команд (B9): композиция URL+тела в dry-режиме
// Покрытие: 13 обёрток lib/tg_config.k + спецкейс commands-массив через
// tg_param_json входит в тело БЕЗ кавычек.
extern printf
extern exit
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

    // 1. tg_set_commands(bot, commands_json) — setMyCommands
    //    СПЕЦКЕЙС: commands-массив через tg_param_json входит в тело БЕЗ кавычек
    r = tg_set_commands(bot, "[{\"command\":\"start\",\"description\":\"Привет\"}]");
    chk(r == 1, "set_commands: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMyCommands|") != 0, "set_commands: URL /setMyCommands");
    chk(strstr(&tg_composed,
        "{\"commands\":[{\"command\":\"start\",\"description\":\"Привет\"}]}") != 0,
        "set_commands: тело — массив commands без кавычек");
    chk(strstr(&tg_composed, "\"commands\":\"[") == 0,
        "set_commands: массив НЕ обёрнут в кавычки");

    // 2. tg_get_commands(bot) — getMyCommands (scope/language_code — через tg_call)
    r = tg_get_commands(bot);
    chk(r == 1, "get_commands: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyCommands|") != 0, "get_commands: URL /getMyCommands");
    chk(strstr(&tg_composed, "|{}") != 0, "get_commands: пустое тело {}");

    // 3. tg_del_commands(bot) — deleteMyCommands
    r = tg_del_commands(bot);
    chk(r == 1, "del_commands: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteMyCommands|") != 0, "del_commands: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "del_commands: пустое тело {}");

    // 4. tg_set_name(bot, name) — setMyName (name обязателен по контракту)
    r = tg_set_name(bot, "Кива");
    chk(r == 1, "set_name: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMyName|") != 0, "set_name: URL");
    chk(strstr(&tg_composed, "{\"name\":\"Кива\"}") != 0, "set_name: тело {name}");

    // 5. tg_get_name(bot) — getMyName
    r = tg_get_name(bot);
    chk(r == 1, "get_name: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyName|") != 0, "get_name: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "get_name: пустое тело {}");

    // 6. tg_set_bot_description(bot, desc) — setMyDescription
    r = tg_set_bot_description(bot, "Описание бота");
    chk(r == 1, "set_desc: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMyDescription|") != 0, "set_desc: URL");
    chk(strstr(&tg_composed, "{\"description\":\"Описание бота\"}") != 0,
        "set_desc: тело {description}");

    // 7. tg_get_bot_description(bot) — getMyDescription
    r = tg_get_bot_description(bot);
    chk(r == 1, "get_desc: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyDescription|") != 0, "get_desc: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "get_desc: пустое тело {}");

    // 8. tg_set_short_description(bot, sdesc) — setMyShortDescription
    r = tg_set_short_description(bot, "Коротко");
    chk(r == 1, "set_sdesc: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMyShortDescription|") != 0, "set_sdesc: URL");
    chk(strstr(&tg_composed, "{\"short_description\":\"Коротко\"}") != 0,
        "set_sdesc: тело {short_description}");

    // 9. tg_get_short_description(bot) — getMyShortDescription
    r = tg_get_short_description(bot);
    chk(r == 1, "get_sdesc: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyShortDescription|") != 0, "get_sdesc: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "get_sdesc: пустое тело {}");

    // 10. tg_set_menu_button(bot, chat_id, button_json) — setChatMenuButton
    //     chat_id=0 → не передавать (дефолтная кнопка бота);
    //     button_json=0 → не передавать (сброс к MenuButtonDefault)
    r = tg_set_menu_button(bot, 0, "{\"type\":\"commands\"}");
    chk(r == 1, "set_menu: dry-возврат 1");
    chk(strstr(&tg_composed, "/setChatMenuButton|") != 0, "set_menu: URL");
    chk(strstr(&tg_composed, "{\"menu_button\":{\"type\":\"commands\"}}") != 0,
        "set_menu: тело {menu_button} без chat_id");
    chk(strstr(&tg_composed, "chat_id") == 0, "set_menu: chat_id=0 отсутствует");
    tg_set_menu_button(bot, 55, "{\"type\":\"commands\"}");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"menu_button\":{\"type\":\"commands\"}}") != 0,
        "set_menu(chat_id): тело {chat_id,menu_button}");
    tg_set_menu_button(bot, 55, 0);
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "set_menu(button=0): тело {chat_id} без menu_button");
    chk(strstr(&tg_composed, "menu_button") == 0,
        "set_menu(button=0): menu_button отсутствует");

    // 11. tg_get_menu_button(bot, chat_id) — getChatMenuButton
    r = tg_get_menu_button(bot, 0);
    chk(r == 1, "get_menu: dry-возврат 1");
    chk(strstr(&tg_composed, "/getChatMenuButton|") != 0, "get_menu: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "get_menu(chat_id=0): пустое тело {}");
    tg_get_menu_button(bot, 55);
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "get_menu(chat_id): тело {chat_id}");

    // 12. tg_set_admin_rights(bot, rights_json, for_channels) — setMyDefaultAdministratorRights
    //     rights_json=0 → не передавать (права очищаются);
    //     for_channels — bool-флаг 0/1 всегда через tg_param_raw (true/false)
    r = tg_set_admin_rights(bot,
        "{\"can_manage_chat\":true,\"can_post_messages\":false}", 1);
    chk(r == 1, "set_admrights: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMyDefaultAdministratorRights|") != 0,
        "set_admrights: URL");
    chk(strstr(&tg_composed,
        "{\"rights\":{\"can_manage_chat\":true,\"can_post_messages\":false},\"for_channels\":true}") != 0,
        "set_admrights: тело {rights-объект без кавычек,for_channels:true}");
    tg_set_admin_rights(bot, 0, 0);
    chk(strstr(&tg_composed, "/setMyDefaultAdministratorRights|") != 0,
        "set_admrights(0): URL");
    chk(strstr(&tg_composed, "{\"for_channels\":false}") != 0,
        "set_admrights(0): тело {for_channels:false} без rights");
    chk(strstr(&tg_composed, "\"rights\"") == 0,
        "set_admrights(0): rights отсутствует");

    // 13. tg_get_admin_rights(bot, for_channels) — getMyDefaultAdministratorRights
    r = tg_get_admin_rights(bot, 1);
    chk(r == 1, "get_admrights: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyDefaultAdministratorRights|") != 0,
        "get_admrights: URL");
    chk(strstr(&tg_composed, "{\"for_channels\":true}") != 0,
        "get_admrights: тело {for_channels:true}");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
