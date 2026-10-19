// tg_ephem.k — эфемерные сообщения, suggested posts, черновики (drafts),
// rich-сообщения, join-request WebApp, subscription invite, emoji status.
// 13 обёрток Bot API (сверено по ref/api/methods/*.md):
//  Ephemeral (5): deleteEphemeralMessage / editEphemeralMessageText /
//    editEphemeralMessageCaption / editEphemeralMessageMedia /
//    editEphemeralMessageReplyMarkup;
//  Suggested (2): approveSuggestedPost / declineSuggestedPost;
//  Разное (6): sendMessageDraft / sendRichMessage / sendRichMessageDraft /
//    sendChatJoinRequestWebApp / editChatSubscriptionInviteLink /
//    setUserEmojiStatus.
// Контракт 0: необязательный аргумент 0 → поле не передаётся. Исключение —
// markup у edit-ephemeral-reply-markup: 0 → "reply_markup":null (снять
// клавиатуру). Готовые JSON-фрагменты (media/rich_message) вставляются через
// tg_param_json БЕЗ кавычек; остальные опциональные параметры метода — через
// extras (tg_ex_str/num/json/raw), применяются к следующему вызову.

// ===== Ephemeral =====

// tg_del_ephemeral(bot, chat_id, receiver_user_id, ephemeral_message_id) —
// deleteEphemeralMessage: удалить эфемерное сообщение.
tg_del_ephemeral(bot, chat_id, receiver_user_id, ephemeral_message_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "receiver_user_id", receiver_user_id);
    tg_param_num(&tg_paramslot, "ephemeral_message_id", ephemeral_message_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteEphemeralMessage", body);
}

// tg_edit_ephemeral_text(bot, chat_id, receiver_user_id, ephemeral_message_id,
// text*|0) — editEphemeralMessageText: новый текст эфемерного сообщения.
// text=0 → не передаётся (rich_message — через extras tg_ex_json("rich_message",...)).
// parse_mode/entities/link_preview_options/reply_markup — через extras.
tg_edit_ephemeral_text(bot, chat_id, receiver_user_id, ephemeral_message_id, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "receiver_user_id", receiver_user_id);
    tg_param_num(&tg_paramslot, "ephemeral_message_id", ephemeral_message_id);
    if text != 0 tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editEphemeralMessageText", body);
}

// tg_edit_ephemeral_caption(bot, chat_id, receiver_user_id,
// ephemeral_message_id, caption*|0) — editEphemeralMessageCaption.
// caption=0 → не передаётся; parse_mode/caption_entities/
// show_caption_above_media — через extras.
tg_edit_ephemeral_caption(bot, chat_id, receiver_user_id, ephemeral_message_id, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "receiver_user_id", receiver_user_id);
    tg_param_num(&tg_paramslot, "ephemeral_message_id", ephemeral_message_id);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editEphemeralMessageCaption", body);
}

// tg_edit_ephemeral_media(bot, chat_id, receiver_user_id,
// ephemeral_message_id, media_json) — editEphemeralMessageMedia: media
// ОБЯЗАТЕЛЕН — сырой JSON-объект InputMedia через tg_param_json (без кавычек);
// reply_markup — через extras.
tg_edit_ephemeral_media(bot, chat_id, receiver_user_id, ephemeral_message_id, media_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "receiver_user_id", receiver_user_id);
    tg_param_num(&tg_paramslot, "ephemeral_message_id", ephemeral_message_id);
    tg_param_json(&tg_paramslot, "media", media_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editEphemeralMessageMedia", body);
}

// tg_edit_ephemeral_markup(bot, chat_id, receiver_user_id,
// ephemeral_message_id, markup_json*|0) — editEphemeralMessageReplyMarkup.
// markup_json — сырой JSON InlineKeyboardMarkup. 0 → "reply_markup":null
// (явно снять клавиатуру) через tg_param_raw.
tg_edit_ephemeral_markup(bot, chat_id, receiver_user_id, ephemeral_message_id, markup_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "receiver_user_id", receiver_user_id);
    tg_param_num(&tg_paramslot, "ephemeral_message_id", ephemeral_message_id);
    if markup_json == 0 {
        tg_param_raw(&tg_paramslot, "reply_markup", "null");
    } else {
        tg_param_json(&tg_paramslot, "reply_markup", markup_json);
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editEphemeralMessageReplyMarkup", body);
}

// ===== Suggested posts =====

// tg_approve_suggested(bot, chat_id, message_id, send_date*|0) —
// approveSuggestedPost: одобрить suggested post в direct-messages чате.
// send_date — Unix timestamp публикации; 0 → не передаётся.
tg_approve_suggested(bot, chat_id, message_id, send_date) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", message_id);
    if send_date != 0 tg_param_num(&tg_paramslot, "send_date", send_date);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "approveSuggestedPost", body);
}

// tg_decline_suggested(bot, chat_id, message_id, comment*|0) —
// declineSuggestedPost: отклонить suggested post. comment (0-128 символов) —
// комментарий автору; 0 → не передаётся.
tg_decline_suggested(bot, chat_id, message_id, comment) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", message_id);
    if comment != 0 tg_param_str(&tg_paramslot, "comment", comment);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "declineSuggestedPost", body);
}

// ===== Разное =====

// tg_message_draft(bot, chat_id, draft_id, text*|0) — sendMessageDraft:
// стриминг частичного текста пользователю (30-секундный превью-черновик).
// draft_id ОБЯЗАТЕЛЕН (ненулевой). text=0 → не передаётся. message_thread_id/
// parse_mode/entities/can_stop/keep_on_stop — через extras.
tg_message_draft(bot, chat_id, draft_id, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "draft_id", draft_id);
    if text != 0 tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendMessageDraft", body);
}

// tg_rich_message(bot, chat_id, rich_json) — sendRichMessage: отправить
// rich-сообщение. rich_json — сырой JSON InputRichMessage через tg_param_json
// (без кавычек). Остальное (business_connection_id/message_thread_id/
// disable_notification/protect_content/reply_markup и т.д.) — через extras.
tg_rich_message(bot, chat_id, rich_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_json(&tg_paramslot, "rich_message", rich_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendRichMessage", body);
}

// tg_rich_draft(bot, chat_id, draft_id, rich_json) — sendRichMessageDraft:
// стриминг частичного rich-сообщения. draft_id ОБЯЗАТЕЛЕН (ненулевой).
// rich_json — сырой JSON InputRichMessage. can_stop/keep_on_stop/
// message_thread_id — через extras.
tg_rich_draft(bot, chat_id, draft_id, rich_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "draft_id", draft_id);
    tg_param_json(&tg_paramslot, "rich_message", rich_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendRichMessageDraft", body);
}

// tg_join_request_webapp(bot, query_id, web_app_url) —
// sendChatJoinRequestWebApp: показать Mini App пользователю перед решением
// по chat join request. NB: по .md принимает chat_join_request_query_id
// (String), а НЕ chat_id. query_id и web_app_url — обязательные строки.
tg_join_request_webapp(bot, query_id, web_app_url) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "chat_join_request_query_id", query_id);
    tg_param_str(&tg_paramslot, "web_app_url", web_app_url);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendChatJoinRequestWebApp", body);
}

// tg_edit_subscription_invite(bot, chat_id, invite_link, name*|0) —
// editChatSubscriptionInviteLink: изменить subscription invite link.
// name (0-32 символа) — новое имя ссылки; 0 → не передаётся. Иные
// необязательные параметры метода — через extras (tg_ex_*).
tg_edit_subscription_invite(bot, chat_id, invite_link, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "invite_link", invite_link);
    if name != 0 tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editChatSubscriptionInviteLink", body);
}

// tg_user_emoji_status(bot, user_id, custom_emoji_id, duration*|0) —
// setUserEmojiStatus: сменить emoji status пользователя (нужно разрешение
// боту через requestEmojiStatusAccess). custom_emoji_id — id кастомного
// эмодзи (пустая строка — снять статус). duration — срок действия в секундах
// (→ emoji_status_expiration_date); 0 → не передаётся.
tg_user_emoji_status(bot, user_id, custom_emoji_id, duration) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "emoji_status_custom_emoji_id", custom_emoji_id);
    if duration != 0 tg_param_num(&tg_paramslot, "emoji_status_expiration_date", duration);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setUserEmojiStatus", body);
}
