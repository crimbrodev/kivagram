// tg_admin.k — модерация и участники (B7): баны, restrict/promote, getters,
// права чата, теги и кастомные титулы. 13 обёрток.
//
// Контракт: обязательные параметры — аргументы (≤6), ходовые опциональные —
// 0-арг «не передавать». JSON-объекты (permissions) входят через
// tg_param_json — в тело БЕЗ кавычек, как есть.
//
// Не входят в v1 (через tg_call(bot, "метод", params) напрямую):
//   banChatMember:      until_date, revoke_messages
//   unbanChatMember:    only_if_banned
//   restrictChatMember: use_independent_chat_permissions, until_date
//   getChatAdministrators: return_bots
//   setChatPermissions: use_independent_chat_permissions

// tg_ban(bot, chat_id, user_id) — banChatMember
tg_ban(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "banChatMember", body);
}

// tg_unban(bot, chat_id, user_id) — unbanChatMember
tg_unban(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unbanChatMember", body);
}

// tg_restrict(bot, chat_id, user_id, perms_json) — restrictChatMember
// perms_json: объект ChatPermissions строкой, tg_param_json → без кавычек
tg_restrict(bot, chat_id, user_id, perms_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_json(&tg_paramslot, "permissions", perms_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "restrictChatMember", body);
}

// tg_promote(bot, chat_id, user_id, rights_json) — promoteChatMember
// В .md НЕТ параметра "rights": флаги (is_anonymous, can_*) — верхний уровень
// тела. rights_json = объект вида {"can_delete_messages":true} — снимаем у
// него внешние скобки и дописываем в тело как есть (сплайс в scratch).
// rights_json=0 → не передавать (все права опциональны).
tg_promote(bot, chat_id, user_id, rights_json) {
    auto body;
    auto s;
    auto n;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if rights_json != 0 {
        s = tg_scratch();
        strcpy(s, rights_json);
        n = strlen(s);
        if n > 1 {
            // срез скобок: [1, n-1) — внутренность объекта
            *(s + n - 1) !8 0;
            tg_buf_add(&tg_paramslot, s + 1);
        }
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "promoteChatMember", body);
}

// tg_ban_sender_chat(bot, chat_id, sender_chat_id) — banChatSenderChat
tg_ban_sender_chat(bot, chat_id, sender_chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "sender_chat_id", sender_chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "banChatSenderChat", body);
}

// tg_unban_sender_chat(bot, chat_id, sender_chat_id) — unbanChatSenderChat
tg_unban_sender_chat(bot, chat_id, sender_chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "sender_chat_id", sender_chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unbanChatSenderChat", body);
}

// tg_get_chat_member(bot, chat_id, user_id) — getChatMember
tg_get_chat_member(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChatMember", body);
}

// tg_get_member_count(bot, chat_id) — getChatMemberCount
tg_get_member_count(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChatMemberCount", body);
}

// tg_get_chat(bot, chat_id) — getChat
tg_get_chat(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChat", body);
}

// tg_get_admins(bot, chat_id) — getChatAdministrators
tg_get_admins(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getChatAdministrators", body);
}

// tg_set_permissions(bot, chat_id, perms_json) — setChatPermissions
// perms_json: объект ChatPermissions строкой → в тело без кавычек
tg_set_permissions(bot, chat_id, perms_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_json(&tg_paramslot, "permissions", perms_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatPermissions", body);
}

// tg_set_member_tag(bot, chat_id, user_id, tag) — setChatMemberTag
// tag опционален (0-16 символов): 0 → не передавать (тег снимается)
tg_set_member_tag(bot, chat_id, user_id, tag) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if tag != 0 tg_param_str(&tg_paramslot, "tag", tag);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatMemberTag", body);
}

// tg_set_admin_title(bot, chat_id, user_id, title) — setChatAdministratorCustomTitle
// custom_title обязателен (0-16 символов, без эмодзи)
tg_set_admin_title(bot, chat_id, user_id, title) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "custom_title", title);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatAdministratorCustomTitle", body);
}
