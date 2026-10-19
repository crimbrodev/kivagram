// tg_tail.k — хвост API v2 (W3-6): верификация (5), managed bot (4),
// boosts (getUserChatBoosts), черновики/сейв (2), чеклисты (2),
// профиля-фильтры (3) + removeMyProfilePhoto. 18 обёрток.
// Эталон: /tmp/opencode/ref/api/methods/*.md — параметры именованные,
// многие опциональны.
//
// Контракт: обязательные параметры — аргументы (вызов ≤6); ходовые
// опциональные — 0-арг «не передавать» (if x != 0 tg_param_*(...));
// экзотические — extras (tg_ex_str/tg_ex_raw/tg_ex_json), съедаются в
// tg_params_done автоматически (детали — в шапках обёрток). tg_call
// напрямую extras НЕ читает.
//
// chat_id — числовой (конвенция всей библиотеки v1); строковый "@username"
// — через tg_call(bot, "метод", params) напрямую.
//
// МЕТОДА getChatBoosts НЕТ: план «boosts 2» — в Bot API существует только
// getUserChatBoosts (эталон: methods/getuserchatboosts.md; GAP-док строка
// «getuserchatboosts»; core.telegram.org/bots/api — метода getChatBoosts в
// перечне нет). getChatBoosts есть только в TDLib (client API, не Bot API)
// — НЕ реализован. Не дублируется: tg_get_topic_icons (tg_forum.k),
// business gifts (tg_business.k).
//
// Расхождения сигнатур плана с эталоном .md (победил .md, «сверять .md»):
//  - tg_passport_errors: + user_id (обязателен в setPassportDataErrors);
//  - tg_set_managed_access: user_id + is_access_restricted обязательны,
//    added_user_ids опционален — было «(bot, json)»;
//  - tg_save_inline_message(bot, user_id, result_json): allow_user/bot/group/
//    channel_chats опциональны — через extras (было «(bot, button, content)»);
//  - tg_save_keyboard_button(bot, user_id, button_json): user_id обязателен;
//  - tg_send_checklist: business_connection_id + chat_id + checklist
//    (title/tasks входят в InputChecklist, это не аргументы);
//  - tg_edit_checklist: метод называется editMessageChecklist, обязателен
//    business_connection_id;
//  - фильтры getUserGifts/getChatGifts — плоские именованные параметры API:
//    filters_json входит срезом внешних скобок (паттерн tg_promote).

// tg_tail_obj(b, json): влить JSON-объект {"k":v,...} в тело как есть,
// срезав внешние скобки (сплайс в scratch — паттерн tg_promote из
// tg_admin.k). json=0 → ничего не добавлять (контракт «0 = не передавать»).
// Валидность JSON — вызывающий (как tg_param_raw).
tg_tail_obj(b, json) {
    auto s;
    auto n;
    if json != 0 {
        s = tg_scratch();
        strcpy(s, json);
        n = strlen(s);
        if n > 1 {
            // срез скобок: [1, n-1) — внутренность объекта
            *(s + n - 1) !8 0;
            tg_buf_add(b, s + 1);
        }
    }
    1;
}

// ===== Верификация (5) =====

// tg_verify_user(bot, user_id, custom_description*|0) — verifyUser
tg_verify_user(bot, user_id, custom_description) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if custom_description != 0 tg_param_str(&tg_paramslot, "custom_description", custom_description);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "verifyUser", body);
}

// tg_verify_chat(bot, chat_id, custom_description*|0) — verifyChat
tg_verify_chat(bot, chat_id, custom_description) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if custom_description != 0 tg_param_str(&tg_paramslot, "custom_description", custom_description);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "verifyChat", body);
}

// tg_unverify_user(bot, user_id) — removeUserVerification
tg_unverify_user(bot, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "removeUserVerification", body);
}

// tg_unverify_chat(bot, chat_id) — removeChatVerification
tg_unverify_chat(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "removeChatVerification", body);
}

// tg_passport_errors(bot, user_id, errors_json) — setPassportDataErrors;
// errors — JSON-массив PassportElementError (обязательный, как user_id)
tg_passport_errors(bot, user_id, errors_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_json(&tg_paramslot, "errors", errors_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setPassportDataErrors", body);
}

// ===== Managed bot (4) =====

// tg_get_managed_token(bot, user_id) — getManagedBotToken
tg_get_managed_token(bot, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getManagedBotToken", body);
}

// tg_replace_managed_token(bot, user_id) — replaceManagedBotToken
tg_replace_managed_token(bot, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "replaceManagedBotToken", body);
}

// tg_get_managed_access(bot, user_id) — getManagedBotAccessSettings
tg_get_managed_access(bot, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getManagedBotAccessSettings", body);
}

// tg_set_managed_access(bot, user_id, is_access_restricted,
// added_user_ids_json*|0) — setManagedBotAccessSettings;
// is_access_restricted 0/1 → raw-литерал "false"/"true" (bool JSON без
// кавычек), added_user_ids — JSON-массив Integer, 0 → не передавать
tg_set_managed_access(bot, user_id, is_access_restricted, added_user_ids) {
    auto body;
    auto v;
    v = "false";
    if is_access_restricted != 0 v = "true";
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_raw(&tg_paramslot, "is_access_restricted", v);
    if added_user_ids != 0 tg_param_json(&tg_paramslot, "added_user_ids", added_user_ids);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setManagedBotAccessSettings", body);
}

// ===== Boosts (1 из 2 плана — см. шапку: getChatBoosts в Bot API нет) =====

// tg_get_user_boosts(bot, chat_id, user_id) — getUserChatBoosts
tg_get_user_boosts(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getUserChatBoosts", body);
}

// ===== Черновики/сейв (2) =====

// tg_save_inline_message(bot, user_id, result_json) —
// savePreparedInlineMessage; result — InlineQueryResult как есть;
// allow_user_chats / allow_bot_chats / allow_group_chats /
// allow_channel_chats (Boolean, опциональны) — через extras:
//   tg_ex_raw("allow_user_chats", "true"); tg_save_inline_message(...)
tg_save_inline_message(bot, user_id, result_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_json(&tg_paramslot, "result", result_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "savePreparedInlineMessage", body);
}

// tg_save_keyboard_button(bot, user_id, button_json) —
// savePreparedKeyboardButton; button — KeyboardButton (request_users /
// request_chat / request_managed_bot) как есть. Опциональных нет.
tg_save_keyboard_button(bot, user_id, button_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_json(&tg_paramslot, "button", button_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "savePreparedKeyboardButton", body);
}

// ===== Чеклисты (2) =====

// tg_send_checklist(bot, business_connection_id, chat_id, checklist_json) —
// sendChecklist; checklist — InputChecklist (title, tasks — внутри него).
// Опциональные — extras: disable_notification / protect_content (tg_ex_raw
// "true"), message_effect_id (tg_ex_str), reply_parameters / reply_markup
// (tg_ex_json).
tg_send_checklist(bot, business_connection_id, chat_id, checklist_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", business_connection_id);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_json(&tg_paramslot, "checklist", checklist_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendChecklist", body);
}

// tg_edit_checklist(bot, business_connection_id, chat_id, message_id,
// checklist_json) — editMessageChecklist (НЕ editChecklist!); новый
// checklist обязателен; reply_markup — через tg_ex_json.
tg_edit_checklist(bot, business_connection_id, chat_id, message_id, checklist_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", business_connection_id);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", message_id);
    tg_param_json(&tg_paramslot, "checklist", checklist_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageChecklist", body);
}

// ===== Профиля-фильтры (3) + removeMyProfilePhoto =====

// tg_get_user_personal_messages(bot, user_id, limit) —
// getUserPersonalChatMessages; limit обязателен (1-20)
tg_get_user_personal_messages(bot, user_id, limit) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_num(&tg_paramslot, "limit", limit);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getUserPersonalChatMessages", body);
}

// tg_get_user_gifts(bot, user_id, filters_json*|0) — getUserGifts;
// filters_json — плоский объект фильтров API
// ({"exclude_unique":true,"limit":10,...}), сливается срезом скобок;
// 0 → не передавать (все фильтры опциональны)
tg_get_user_gifts(bot, user_id, filters_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_tail_obj(&tg_paramslot, filters_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getUserGifts", body);
}

// tg_get_chat_gifts(bot, chat_id, filters_json*|0) — getChatGifts;
// filters_json — плоский объект фильтров API ({"exclude_saved":true,...}),
// сливается срезом скобок; 0 → не передавать
tg_get_chat_gifts(bot, chat_id, filters_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_tail_obj(&tg_paramslot, filters_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChatGifts", body);
}

// tg_remove_profile_photo(bot) — removeMyProfilePhoto, без параметров
tg_remove_profile_photo(bot) {
    tg_call(bot, "removeMyProfilePhoto", 0);
}
