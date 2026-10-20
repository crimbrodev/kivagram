// tg_ext.k — расширенные send/edit/answer (B13), вариант с 6 аргументами.
//
// Покрывает ходовые опциональные параметры sendMessage / editMessageText /
// sendPhoto / answerCallbackQuery / sendChatAction:
//  - parse_mode — строка "HTML"|"MarkdownV2"|... → tg_param_str;
//  - reply_markup — ГОТОВЫЙ JSON (объект с кнопками) → tg_param_json
//    (вставляется в тело БЕЗ кавычек);
//  - reply_to (int) → {"message_id":N}: sprintf в ЛОКАЛЬНЫЙ буфер модуля,
//    затем tg_param_json отдельным шагом — вложенный sprintf в аргументе
//    tg_param_json НЕ допустим (ловушка языка);
//  - show_alert (tg_answer_cb): 1 → tg_param_raw(..., "true") — литерал
//    без кавычек; 0 → поле не передаётся;
//  - thread_id → message_thread_id (топик форума); 0 → не передаётся.
// Контракт: каждый опциональный аргумент 0 → поле не передаётся.
//
// Не вошли в v1 (через tg_call(bot, "method", params)): business_connection_id,
// entities/caption_entities/link_preview_options, disable_notification,
// protect_content, allow_paid_broadcast, message_effect_id, has_spoiler,
// show_caption_above_media, url/cache_time (answerCallbackQuery).

extern sprintf

// Локальный буфер под reply_parameters {"message_id":N} — 64 байта
// (как tg_numbuf: массив-слот вне scratch, значение копируется в params
// сразу при tg_param_json).
tg_rpbuf[8];

// tg_sendx(bot, chat_id, text, parse_mode, reply_markup, reply_to) —
// sendMessage с форматированием, клавиатурой и ответом на сообщение.
tg_sendx(bot, chat_id, text, parse_mode, reply_markup, reply_to) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "text", text);
    if parse_mode != 0 tg_param_str(&tg_paramslot, "parse_mode", parse_mode);
    if reply_to != 0 {
        sprintf(&tg_rpbuf, "{\"message_id\":%ld}", reply_to);
        tg_param_json(&tg_paramslot, "reply_parameters", &tg_rpbuf);
    }
    if reply_markup != 0 tg_param_json(&tg_paramslot, "reply_markup", reply_markup);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendMessage", body);
}

// tg_editx(bot, chat_id, msg_id, text, parse_mode, reply_markup) —
// editMessageText с форматированием и клавиатурой (оба 0 → не передаются).
tg_editx(bot, chat_id, msg_id, text, parse_mode, reply_markup) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_str(&tg_paramslot, "text", text);
    if parse_mode != 0 tg_param_str(&tg_paramslot, "parse_mode", parse_mode);
    if reply_markup != 0 tg_param_json(&tg_paramslot, "reply_markup", reply_markup);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageText", body);
}

// tg_photox(bot, chat_id, photo, caption, parse_mode, reply_markup) —
// sendPhoto: caption/parse_mode/reply_markup — 0 → не передаются.
tg_photox(bot, chat_id, photo, caption, parse_mode, reply_markup) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "photo", photo);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    if parse_mode != 0 tg_param_str(&tg_paramslot, "parse_mode", parse_mode);
    if reply_markup != 0 tg_param_json(&tg_paramslot, "reply_markup", reply_markup);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendPhoto", body);
}

// tg_answer_cb(ctx, text, show_alert) — answerCallbackQuery из ctx
// (callback_query_id = слот 13, как в tg_answer). text=0 → поле не
// передаётся (снять спиннер без уведомления); show_alert=1 → "true" raw,
// 0 → не передаётся. Слот 13 = 0 (ctx без callback_query) → вызова нет,
// возврат 0.
tg_answer_cb(ctx, text, show_alert) {
    auto bot;
    auto body;
    auto id;
    auto ok;
    ok = 0;
    bot = ctx[0];
    id = ctx[13];
    if id != 0 {
        ctx[19] = 1;
        tg_params_reset(&tg_paramslot);
        tg_param_str(&tg_paramslot, "callback_query_id", id);
        if text != 0 tg_param_str(&tg_paramslot, "text", text);
        if show_alert == 1 tg_param_raw(&tg_paramslot, "show_alert", "true");
        body = tg_params_done(&tg_paramslot);
        ok = tg_call(bot, "answerCallbackQuery", body);
    }
    ok;
}

// tg_actionx(bot, chat_id, action, thread_id) — sendChatAction с
// message_thread_id (топик форума); thread_id=0 → не передаётся.
tg_actionx(bot, chat_id, action, thread_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if thread_id != 0 tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    tg_param_str(&tg_paramslot, "action", action);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendChatAction", body);
}
