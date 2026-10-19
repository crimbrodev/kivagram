// t_v2_pay.k — платежи (lib/tg_pay.k): sendInvoice / createInvoiceLink /
// refundStarPayment / getMyStarBalance / getStarTransactions /
// editUserStarSubscription — композиция URL+тела в dry-режиме (без сети).
// prices — JSON-массив LabeledPrice через tg_param_json (БЕЗ кавычек).
extern printf
extern exit
extern strcmp
extern strstr

fails[1];

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

global main
main() {
    auto bot;
    auto r;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // 1. tg_send_invoice(bot, chat_id, title, payload, currency, prices_json)
    //    (description пожертвован лимитом 6 аргументов — через tg_call)
    r = tg_send_invoice(bot, 55, "Т", "p", "XTR", "[{\"label\":\"x\",\"amount\":100}]");
    chk(r == 1, "send_invoice: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendInvoice|") != 0, "send_invoice: URL /sendInvoice");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"title\":\"Т\",\"payload\":\"p\",\"currency\":\"XTR\",\"prices\":[{\"label\":\"x\",\"amount\":100}]}") != 0,
        "send_invoice: тело {chat_id,title,payload,currency,prices}");
    chk(strstr(&tg_composed, "description") == 0,
        "send_invoice: description отсутствует");

    // 2. tg_invoice_link(bot, title, description, payload, currency, prices_json)
    r = tg_invoice_link(bot, "Т", "Д", "p", "XTR", "[{\"label\":\"x\",\"amount\":100}]");
    chk(r == 1, "invoice_link: dry-возврат 1");
    chk(strstr(&tg_composed, "/createInvoiceLink|") != 0, "invoice_link: URL /createInvoiceLink");
    chk(strstr(&tg_composed, "{\"title\":\"Т\",\"description\":\"Д\",\"payload\":\"p\",\"currency\":\"XTR\",\"prices\":[{\"label\":\"x\",\"amount\":100}]}") != 0,
        "invoice_link: тело {title,description,payload,currency,prices}");

    // 3. tg_refund(bot, user_id, charge_id) — refundStarPayment
    r = tg_refund(bot, 9, "ch1");
    chk(r == 1, "refund: dry-возврат 1");
    chk(strstr(&tg_composed, "/refundStarPayment|") != 0, "refund: URL /refundStarPayment");
    chk(strstr(&tg_composed, "{\"user_id\":9,\"telegram_payment_charge_id\":\"ch1\"}") != 0,
        "refund: тело {user_id,telegram_payment_charge_id}");

    // 4. tg_star_balance(bot) — getMyStarBalance, параметров нет
    r = tg_star_balance(bot);
    chk(r == 1, "star_balance: dry-возврат 1");
    chk(strstr(&tg_composed, "/getMyStarBalance|") != 0, "star_balance: URL /getMyStarBalance");

    // 5. tg_star_transactions(bot, limit) — limit=0 → параметр не передаётся
    r = tg_star_transactions(bot, 10);
    chk(r == 1, "star_tx: dry-возврат 1");
    chk(strstr(&tg_composed, "/getStarTransactions|") != 0, "star_tx: URL /getStarTransactions");
    chk(strstr(&tg_composed, "{\"limit\":10}") != 0, "star_tx: limit=10 в теле");
    tg_star_transactions(bot, 0);
    chk(strstr(&tg_composed, "/getStarTransactions|{}") != 0,
        "star_tx: limit=0 → пустое тело {}");

    // 6. tg_edit_star_sub(bot, user_id, charge_id, is_canceled) — bool → raw true/false
    r = tg_edit_star_sub(bot, 9, "ch1", 1);
    chk(r == 1, "edit_star_sub: dry-возврат 1");
    chk(strstr(&tg_composed, "/editUserStarSubscription|") != 0, "edit_star_sub: URL /editUserStarSubscription");
    chk(strstr(&tg_composed, "{\"user_id\":9,\"telegram_payment_charge_id\":\"ch1\",\"is_canceled\":true}") != 0,
        "edit_star_sub: is_canceled=true (без кавычек)");
    tg_edit_star_sub(bot, 9, "ch1", 0);
    chk(strstr(&tg_composed, "{\"user_id\":9,\"telegram_payment_charge_id\":\"ch1\",\"is_canceled\":false}") != 0,
        "edit_star_sub: is_canceled=false (без кавычек)");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
