// tg_msg.k — B4: пересылка/копирование/правки/массовое удаление.
// 10 обёрток Bot API: forward*/copy*/edit*/deleteMessages.
// chat_id/from_chat_id — числа через tg_param_num (Kiva 64-бит, %ld).
// JSON-массивы/объекты (message_ids, media, reply_markup) — tg_param_json.
// Дробные lat/lng в editMessageLiveLocation — строки через tg_param_raw
// (без кавычек, литерал вида "55.75" от вызывающего).
// Остальные опциональные параметры (business_connection_id, parse_mode,
// message_thread_id, disable_notification и т.д.) — через tg_call напрямую.

// tg_forward(bot, chat_id, from_chat_id, msg_id) — forwardMessage
tg_forward(bot, chat_id, from_chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "from_chat_id", from_chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "forwardMessage", body);
}

// tg_forward_many(bot, chat_id, from_chat_id, ids_json) — forwardMessages
tg_forward_many(bot, chat_id, from_chat_id, ids_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "from_chat_id", from_chat_id);
    tg_param_json(&tg_paramslot, "message_ids", ids_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "forwardMessages", body);
}

// tg_copy(bot, chat_id, from_chat_id, msg_id, caption) — copyMessage;
// caption=0 → не передавать (оригинальный caption сохраняется)
tg_copy(bot, chat_id, from_chat_id, msg_id, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "from_chat_id", from_chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "copyMessage", body);
}

// tg_copy_many(bot, chat_id, from_chat_id, ids_json) — copyMessages
tg_copy_many(bot, chat_id, from_chat_id, ids_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "from_chat_id", from_chat_id);
    tg_param_json(&tg_paramslot, "message_ids", ids_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "copyMessages", body);
}

// tg_edit_caption(bot, chat_id, msg_id, caption) — editMessageCaption
tg_edit_caption(bot, chat_id, msg_id, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageCaption", body);
}

// tg_edit_markup(bot, chat_id, msg_id, markup_json) — editMessageReplyMarkup;
// markup=0 → СНЯТЬ кнопки: tg_param_raw("reply_markup","null") — литерал null
tg_edit_markup(bot, chat_id, msg_id, markup_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    if markup_json == 0 {
        tg_param_raw(&tg_paramslot, "reply_markup", "null");
    } else {
        tg_param_json(&tg_paramslot, "reply_markup", markup_json);
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageReplyMarkup", body);
}

// tg_edit_media(bot, chat_id, msg_id, media_json) — editMessageMedia;
// media — сырой JSON-объект InputMedia через tg_param_json
tg_edit_media(bot, chat_id, msg_id, media_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_json(&tg_paramslot, "media", media_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageMedia", body);
}

// tg_edit_live_loc(bot, chat_id, msg_id, lat, lng) — editMessageLiveLocation;
// lat/lng — СТРОКИ-ЛИТЕРАЛЫ дробей ("55.75") через tg_param_raw — без кавычек
tg_edit_live_loc(bot, chat_id, msg_id, lat, lng) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_raw(&tg_paramslot, "latitude", lat);
    tg_param_raw(&tg_paramslot, "longitude", lng);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageLiveLocation", body);
}

// tg_stop_live_loc(bot, chat_id, msg_id) — stopMessageLiveLocation
tg_stop_live_loc(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "stopMessageLiveLocation", body);
}

// tg_delete_many(bot, chat_id, ids_json) — deleteMessages (1-100 id)
tg_delete_many(bot, chat_id, ids_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_json(&tg_paramslot, "message_ids", ids_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteMessages", body);
}
