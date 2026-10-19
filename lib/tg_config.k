// tg_config.k — конфиг бота и меню команд v1 (B9): setMyCommands/getMyCommands/
// deleteMyCommands, имена, описания, кнопка меню, дефолтные админ-права.
// 13 обёрток. Эталон параметров: /tmp/opencode/ref/api/methods/*.md
// (setmycommands, getmycommands, deletemycommands, setmyname, getmyname,
// setmydescription, getmydescription, setmyshortdescription, getmyshortdescription,
// setchatmenubutton, getchatmenubutton, setmydefaultadministratorrights,
// getmydefaultadministratorrights).
//
// Контракт обёрток: обязательные параметры — аргументы (вызов ≤6); ходовые
// опциональные — аргумент с контрактом «0 = не передавать»
// (if x != 0 tg_param_*(...)). Геттеры без параметров шлют пустое тело {}.
//
// Примечания (параметры, НЕ вошедшие в v1 — через tg_call(bot, "method", params)):
//  - scope (BotCommandScope) и language_code у setMyCommands/getMyCommands/
//    deleteMyCommands — через tg_call;
//  - language_code у setMyName/getMyName/setMyDescription/getMyDescription/
//    setMyShortDescription/getMyShortDescription — через tg_call.
//
// ВАЖНО: имя tg_set_bot_description/tg_get_bot_description — переименование
// относительно плана (Task 11: tg_set_description/tg_get_description): коллизия
// символов с lib/tg_chat.k (B8) — там tg_set_description(bot, chat_id, desc) =
// setChatDescription. Kiva не поддерживает перегрузку, сборка склеивает ВСЕ
// lib/tg_*.k, поэтому ботовский сеттер назван с префиксом bot (пара переименована
// целиком — для симметрии).

// tg_set_commands(bot, commands_json) — setMyCommands.
// commands — JSON-массив BotCommand, входит в тело через tg_param_json БЕЗ
// кавычек: {"commands":[{"command":...}]}. commands обязателен (0 не передавать
// нельзя — вызывающий обязан дать массив, иначе API 400).
tg_set_commands(bot, commands_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_json(&tg_paramslot, "commands", commands_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMyCommands", body);
}

// tg_get_commands(bot) — getMyCommands; scope/language_code — через tg_call
tg_get_commands(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getMyCommands", body);
}

// tg_del_commands(bot) — deleteMyCommands; scope/language_code — через tg_call
tg_del_commands(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteMyCommands", body);
}

// tg_set_name(bot, name) — setMyName.
// name в .md опционален, но по контракту обёртки обязателен (без имени метод
// бессмыслен): пустую строку для удаления имени передаёт вызывающий.
tg_set_name(bot, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMyName", body);
}

// tg_get_name(bot) — getMyName; language_code — через tg_call
tg_get_name(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getMyName", body);
}

// tg_set_bot_description(bot, desc) — setMyDescription (см. шапку файла:
// переименование из-за коллизии с tg_set_description из lib/tg_chat.k)
tg_set_bot_description(bot, desc) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "description", desc);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMyDescription", body);
}

// tg_get_bot_description(bot) — getMyDescription; language_code — через tg_call
tg_get_bot_description(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getMyDescription", body);
}

// tg_set_short_description(bot, sdesc) — setMyShortDescription
tg_set_short_description(bot, sdesc) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "short_description", sdesc);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMyShortDescription", body);
}

// tg_get_short_description(bot) — getMyShortDescription; language_code — через tg_call
tg_get_short_description(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getMyShortDescription", body);
}

// tg_set_menu_button(bot, chat_id, button_json) — setChatMenuButton.
// chat_id=0 → не передавать (меняется кнопка по умолчанию для всех чатов);
// button_json=0 → не передавать (API сбрасывает к MenuButtonDefault).
// button_json — JSON-объект MenuButton через tg_param_json (без кавычек).
tg_set_menu_button(bot, chat_id, button_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if chat_id != 0 tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if button_json != 0 tg_param_json(&tg_paramslot, "menu_button", button_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatMenuButton", body);
}

// tg_get_menu_button(bot, chat_id) — getChatMenuButton; chat_id=0 → дефолтная
tg_get_menu_button(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if chat_id != 0 tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChatMenuButton", body);
}

// tg_set_admin_rights(bot, rights_json, for_channels) — setMyDefaultAdministratorRights.
// rights_json=0 → не передавать (API очищает дефолтные права);
// for_channels — bool-флаг 0/1, ВСЕГДА передаётся как raw "false"/"true"
// (явный false = поведение по умолчанию для групп).
tg_set_admin_rights(bot, rights_json, for_channels) {
    auto body;
    auto chans;
    if for_channels == 0 {
        chans = "false";
    } else {
        chans = "true";
    }
    tg_params_reset(&tg_paramslot);
    if rights_json != 0 tg_param_json(&tg_paramslot, "rights", rights_json);
    tg_param_raw(&tg_paramslot, "for_channels", chans);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMyDefaultAdministratorRights", body);
}

// tg_get_admin_rights(bot, for_channels) — getMyDefaultAdministratorRights;
// for_channels — bool-флаг 0/1 → raw "false"/"true"
tg_get_admin_rights(bot, for_channels) {
    auto body;
    auto chans;
    if for_channels == 0 {
        chans = "false";
    } else {
        chans = "true";
    }
    tg_params_reset(&tg_paramslot);
    tg_param_raw(&tg_paramslot, "for_channels", chans);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getMyDefaultAdministratorRights", body);
}
