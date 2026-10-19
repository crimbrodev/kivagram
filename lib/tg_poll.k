// tg_poll.k — B3 v2: альбомы, опросы, платные медиа.
// Методы: sendMediaGroup, sendPoll, stopPoll, sendPaidMedia.
// Контракт обёрток (волна v2): обязательные параметры — аргументы (≤6),
// ходовые опциональные — через tg_call напрямую.
// JSON-массивы (media, options) пробрасываются через tg_param_json:
// в теле запроса они входят БЕЗ кавычек, как есть (валидность JSON — на вызывающем).

// tg_send_media_group(bot, chat_id, media_json) — sendMediaGroup.
// media: JSON-массив 2-10 InputMedia{Audio,Document,LivePhoto,Photo,Video} (обязателен).
// Остальные опциональные (business_connection_id, message_thread_id,
// disable_notification, protect_content, message_effect_id, reply_parameters,
// reply_markup и т.д.) — через tg_call(bot, "sendMediaGroup", params).
tg_send_media_group(bot, chat_id, media_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_json(&tg_paramslot, "media", media_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendMediaGroup", body);
}

// tg_send_poll(bot, chat_id, question, options_json) — sendPoll.
// question: строка 1-300 символов; options: JSON-массив 1-12 InputPollOption
// (напр. "[\"а\",\"б\"]") — оба обязательны.
// is_anonymous / type / allows_multiple_answers и прочие опциональные
// (open_period, close_date, explanation, reply_markup...) — через
// tg_call(bot, "sendPoll", params): 0-флаги в эту обёртку v1 не входят.
tg_send_poll(bot, chat_id, question, options_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "question", question);
    tg_param_json(&tg_paramslot, "options", options_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendPoll", body);
}

// tg_stop_poll(bot, chat_id, msg_id) — stopPoll: остановить опрос в msg_id.
// reply_markup (inline-клавиатура) — опционально, через tg_call.
tg_stop_poll(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "stopPoll", body);
}

// tg_send_paid_media(bot, chat_id, star_count, media_json) — sendPaidMedia.
// star_count: 1-25000 (обязателен); media: JSON-массив до 10 InputPaidMedia
// (обязателен). payload/caption/parse_mode/disable_notification/
// reply_parameters/reply_markup — через tg_call(bot, "sendPaidMedia", params).
tg_send_paid_media(bot, chat_id, star_count, media_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "star_count", star_count);
    tg_param_json(&tg_paramslot, "media", media_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendPaidMedia", body);
}
