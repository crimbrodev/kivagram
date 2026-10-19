// tg_chat.k — управление чатом (B8): пины, заголовок/описание, фото,
// стикер-сет, выход из чата, инвайт-ссылки, заявки на вступление. 16 обёрток.
//
// Контракт: обязательные параметры — аргументы (≤6), ходовые опциональные —
// 0-арг «не передавать». tg_get_admins НЕ здесь — он в lib/tg_admin.k (B7).
//
// Не входят в v1 (через tg_call(bot, "метод", params) напрямую):
//   pinChatMessage:                 business_connection_id, disable_notification
//   unpinChatMessage:               business_connection_id
//   createChatInviteLink:           expire_date, member_limit, creates_join_request
//   editChatInviteLink:             expire_date, member_limit, creates_join_request
//   createChatSubscriptionInviteLink: name
//   setChatPhoto:                   multipart-загрузка файла (InputFile)

// tg_pin(bot, chat_id, msg_id) — pinChatMessage
tg_pin(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "pinChatMessage", body);
}

// tg_unpin(bot, chat_id, msg_id) — unpinChatMessage
// msg_id=0 → не передавать: отпинивается последний закреплённый
// (спецкейс: тело только {"chat_id":55})
tg_unpin(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if msg_id != 0 tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unpinChatMessage", body);
}

// tg_unpin_all(bot, chat_id) — unpinAllChatMessages
tg_unpin_all(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unpinAllChatMessages", body);
}

// tg_set_title(bot, chat_id, title) — setChatTitle
tg_set_title(bot, chat_id, title) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "title", title);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatTitle", body);
}

// tg_set_description(bot, chat_id, desc) — setChatDescription
// desc=0 → не передавать (описание снимается)
tg_set_description(bot, chat_id, desc) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if desc != 0 tg_param_str(&tg_paramslot, "description", desc);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatDescription", body);
}

// tg_set_chat_photo(bot, chat_id, file_id) — setChatPhoto
// photo: file_id или attach://-имя; multipart-загрузка — через tg_call
tg_set_chat_photo(bot, chat_id, file_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "photo", file_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatPhoto", body);
}

// tg_del_chat_photo(bot, chat_id) — deleteChatPhoto
tg_del_chat_photo(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteChatPhoto", body);
}

// tg_set_chat_sticker_set(bot, chat_id, set_name) — setChatStickerSet
tg_set_chat_sticker_set(bot, chat_id, set_name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "sticker_set_name", set_name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setChatStickerSet", body);
}

// tg_leave(bot, chat_id) — leaveChat
tg_leave(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "leaveChat", body);
}

// tg_export_invite(bot, chat_id) — exportChatInviteLink
tg_export_invite(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "exportChatInviteLink", body);
}

// tg_create_invite(bot, chat_id, name) — createChatInviteLink
// name=0 → не передавать (остальные опциональные — через tg_call)
tg_create_invite(bot, chat_id, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if name != 0 tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "createChatInviteLink", body);
}

// tg_edit_invite(bot, chat_id, link, name) — editChatInviteLink
// name=0 → не передавать (expire_date/member_limit/creates_join_request —
// через tg_call)
tg_edit_invite(bot, chat_id, link, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "invite_link", link);
    if name != 0 tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editChatInviteLink", body);
}

// tg_revoke_invite(bot, chat_id, link) — revokeChatInviteLink
tg_revoke_invite(bot, chat_id, link) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "invite_link", link);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "revokeChatInviteLink", body);
}

// tg_approve_join(bot, chat_id, user_id) — approveChatJoinRequest
tg_approve_join(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "approveChatJoinRequest", body);
}

// tg_decline_join(bot, chat_id, user_id) — declineChatJoinRequest
tg_decline_join(bot, chat_id, user_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "declineChatJoinRequest", body);
}

// tg_create_subscription_invite(bot, chat_id, period, price)
// — createChatSubscriptionInviteLink
// period: subscription_period, секунды (сейчас всегда 2592000 = 30 дней);
// price: subscription_price, Stars 1-10000. name — опционален, через tg_call.
tg_create_subscription_invite(bot, chat_id, period, price) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "subscription_period", period);
    tg_param_num(&tg_paramslot, "subscription_price", price);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "createChatSubscriptionInviteLink", body);
}
