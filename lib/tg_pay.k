// lib/tg_pay.k — платежи Bot API: sendInvoice, createInvoiceLink,
// refundStarPayment, getMyStarBalance, getStarTransactions,
// editUserStarSubscription.
//
// Лимит ≤6 аргументов: у sendInvoice Required-величин 7 (chat_id, title,
// description, payload, currency, prices) + bot = 8 → пожертван description
// (редкий текстовый): НЕ входит в аргументы обёртки — для него передавайте
// тело через tg_call(bot, "sendInvoice", ...) с tg_param_str(...,"description",...).
// Редкие опциональные (provider_token, message_thread_id, photo_url, need_*,
// max_tip_amount, reply_markup, business_connection_id, subscription_period,
// offset у getStarTransactions и т.д.) — тоже через tg_call.
// prices — JSON-массив LabeledPrice через tg_param_json (БЕЗ кавычек).

// tg_send_invoice(bot, chat_id, title, payload, currency, prices_json) —
// sendInvoice. prices_json — '[{"label":"...","amount":N},...]'.
// description (Required по .md) пожертван лимитом 6 аргументов — через tg_call.
tg_send_invoice(bot, chat_id, title, payload, currency, prices_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "title", title);
    tg_param_str(&tg_paramslot, "payload", payload);
    tg_param_str(&tg_paramslot, "currency", currency);
    tg_param_json(&tg_paramslot, "prices", prices_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendInvoice", body);
}

// tg_invoice_link(bot, title, description, payload, currency, prices_json) —
// createInvoiceLink (ровно 6 арг). business_connection_id/subscription_period —
// через tg_call.
tg_invoice_link(bot, title, description, payload, currency, prices_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "title", title);
    tg_param_str(&tg_paramslot, "description", description);
    tg_param_str(&tg_paramslot, "payload", payload);
    tg_param_str(&tg_paramslot, "currency", currency);
    tg_param_json(&tg_paramslot, "prices", prices_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "createInvoiceLink", body);
}

// tg_refund(bot, user_id, charge_id) — refundStarPayment(user_id,
// telegram_payment_charge_id)
tg_refund(bot, user_id, charge_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "telegram_payment_charge_id", charge_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "refundStarPayment", body);
}

// tg_star_balance(bot) — getMyStarBalance, параметров нет; ответ — в tg_http_body()
tg_star_balance(bot) {
    tg_call(bot, "getMyStarBalance", 0);
}

// tg_star_transactions(bot, limit) — getStarTransactions; limit=0 → параметр не
// передаётся (дефолт API 100). offset — через tg_call.
tg_star_transactions(bot, limit) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if limit != 0 tg_param_num(&tg_paramslot, "limit", limit);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getStarTransactions", body);
}

// tg_edit_star_sub(bot, user_id, charge_id, is_canceled) —
// editUserStarSubscription; is_canceled 0/1 → raw-литерал "false"/"true"
// (bool JSON — tg_param_raw, без кавычек)
tg_edit_star_sub(bot, user_id, charge_id, is_canceled) {
    auto body;
    auto v;
    v = "false";
    if is_canceled != 0 v = "true";
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "telegram_payment_charge_id", charge_id);
    tg_param_raw(&tg_paramslot, "is_canceled", v);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editUserStarSubscription", body);
}
