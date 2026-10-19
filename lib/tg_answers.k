// lib/tg_answers.k — B5: ответы на запросы Bot API.
// Обёртки: answerInlineQuery, answerPreCheckoutQuery, answerShippingQuery,
// answerWebAppQuery, answerGuestQuery, answerChatJoinRequestQuery.
// Контракт плана: обязательные параметры — аргументы (≤6), ходовые
// опциональные — аргумент с контрактом «0 = не передавать».
// Редкие/экзотические опциональные НЕ входят в v1 — через tg_call:
//   answerInlineQuery: cache_time / is_personal / next_offset / button
//   answerChatJoinRequestQuery: result "queue" (решение за другими админами)

// tg_answer_inline(bot, query_id, results_json) — answerInlineQuery.
// .md: inline_query_id (String, Yes), results (Array, Yes) — JSON-массив
// через tg_param_json (без кавычек); cache_time/is_personal/next_offset/
// button — через tg_call(bot, "answerInlineQuery", params).
tg_answer_inline(bot, query_id, results_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "inline_query_id", query_id);
    tg_param_json(&tg_paramslot, "results", results_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerInlineQuery", body);
}

// tg_answer_pre_checkout(bot, pcq_id, ok, error_msg) — answerPreCheckoutQuery.
// .md: pre_checkout_query_id (String, Yes), ok (Boolean, Yes) — ВСЕГДА
// передаётся: 1 → true, 0 → false (bool-литерал через tg_param_raw);
// error_message (String, Optional, обязателен при ok=false) — 0 → skip.
tg_answer_pre_checkout(bot, pcq_id, ok, error_msg) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "pre_checkout_query_id", pcq_id);
    if ok != 0 {
        tg_param_raw(&tg_paramslot, "ok", "true");
    } else {
        tg_param_raw(&tg_paramslot, "ok", "false");
    }
    if error_msg != 0 tg_param_str(&tg_paramslot, "error_message", error_msg);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerPreCheckoutQuery", body);
}

// tg_answer_shipping(bot, ship_id, ok, options_json, error_msg) —
// answerShippingQuery.
// .md: shipping_query_id (String, Yes), ok (Boolean, Yes — всегда
// true/false через tg_param_raw), shipping_options (Array, Optional,
// обязателен при ok=true) — JSON-массив через tg_param_json, 0 → skip;
// error_message (String, Optional, обязателен при ok=false) — 0 → skip.
tg_answer_shipping(bot, ship_id, ok, options_json, error_msg) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "shipping_query_id", ship_id);
    if ok != 0 {
        tg_param_raw(&tg_paramslot, "ok", "true");
    } else {
        tg_param_raw(&tg_paramslot, "ok", "false");
    }
    if options_json != 0 tg_param_json(&tg_paramslot, "shipping_options", options_json);
    if error_msg != 0 tg_param_str(&tg_paramslot, "error_message", error_msg);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerShippingQuery", body);
}

// tg_answer_webapp(bot, webapp_query_id, result_json) — answerWebAppQuery.
// .md: web_app_query_id (String, Yes), result (InlineQueryResult-объект,
// Yes) — сырой JSON-объект через tg_param_json (без кавычек).
tg_answer_webapp(bot, webapp_query_id, result_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "web_app_query_id", webapp_query_id);
    tg_param_json(&tg_paramslot, "result", result_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerWebAppQuery", body);
}

// tg_answer_guest(bot, guest_query_id, result_json) — answerGuestQuery.
// .md: guest_query_id (String, Yes), result (InlineQueryResult-объект, Yes)
// — сырой JSON-объект через tg_param_json (без кавычек).
tg_answer_guest(bot, guest_query_id, result_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "guest_query_id", guest_query_id);
    tg_param_json(&tg_paramslot, "result", result_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerGuestQuery", body);
}

// tg_answer_join_request(bot, query_id, approve) — answerChatJoinRequestQuery.
// СВЕРЕНО С .md (answerchatjoinrequestquery.md): параметров РОВНО два —
// chat_join_request_query_id (String, Yes) и result (String, Yes), который
// обязан быть "approve" | "decline" | "queue". Никаких chat_id/user_id!
// approve: 1 → "approve", 0 → "decline". result — тип String по .md, поэтому
// tg_param_str (кавычки), а НЕ raw-безкавычный литерал. "queue" — через
// tg_call(bot, "answerChatJoinRequestQuery", params).
tg_answer_join_request(bot, query_id, approve) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "chat_join_request_query_id", query_id);
    if approve != 0 {
        tg_param_str(&tg_paramslot, "result", "approve");
    } else {
        tg_param_str(&tg_paramslot, "result", "decline");
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "answerChatJoinRequestQuery", body);
}
