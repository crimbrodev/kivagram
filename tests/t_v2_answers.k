// t_v2_answers.k — B5: обёртки ответов Bot API (без сети, dry-run):
// answerInlineQuery / answerPreCheckoutQuery / answerShippingQuery /
// answerWebAppQuery / answerGuestQuery / answerChatJoinRequestQuery
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

    // 1. tg_answer_inline(bot, query_id, results_json)
    r = tg_answer_inline(bot, "q1",
        "[{\"type\":\"photo\",\"photo_url\":\"http://x/p.jpg\"}]");
    chk(r == 1, "inline: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerInlineQuery|") != 0, "inline: URL");
    chk(strstr(&tg_composed,
        "{\"inline_query_id\":\"q1\",\"results\":[{\"type\":\"photo\",\"photo_url\":\"http://x/p.jpg\"}]}")
        != 0, "inline: тело {inline_query_id,results}");

    // 2. tg_answer_pre_checkout(bot, pcq_id, ok, error_msg) — ok=true, без ошибки
    r = tg_answer_pre_checkout(bot, "p1", 1, 0);
    chk(r == 1, "pre_checkout: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerPreCheckoutQuery|") != 0, "pre_checkout: URL");
    chk(strstr(&tg_composed, "{\"pre_checkout_query_id\":\"p1\",\"ok\":true}") != 0,
        "pre_checkout: тело {id,ok:true}");
    chk(strstr(&tg_composed, "error_message") == 0,
        "pre_checkout: error_message отсутствует при ok=1");

    // 3. tg_answer_pre_checkout(bot, pcq_id, ok, error_msg) — ok=false + причина
    tg_answer_pre_checkout(bot, "p2", 0, "нет товара");
    chk(strstr(&tg_composed,
        "{\"pre_checkout_query_id\":\"p2\",\"ok\":false,\"error_message\":\"нет товара\"}")
        != 0, "pre_checkout: тело {id,ok:false,error_message}");

    // 4. tg_answer_shipping(bot, ship_id, ok, options_json, error_msg) — ok=true
    r = tg_answer_shipping(bot, "s1", 1,
        "[{\"id\":\"o1\",\"title\":\"Почта\",\"price\":100}]", 0);
    chk(r == 1, "shipping: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerShippingQuery|") != 0, "shipping: URL");
    chk(strstr(&tg_composed,
        "{\"shipping_query_id\":\"s1\",\"ok\":true,\"shipping_options\":[{\"id\":\"o1\",\"title\":\"Почта\",\"price\":100}]}")
        != 0, "shipping: тело {id,ok:true,shipping_options}");
    chk(strstr(&tg_composed, "error_message") == 0,
        "shipping: error_message отсутствует при ok=1");

    // 5. tg_answer_shipping — ok=false, options=0 → не передаётся
    tg_answer_shipping(bot, "s2", 0, 0, "доставки нет");
    chk(strstr(&tg_composed,
        "{\"shipping_query_id\":\"s2\",\"ok\":false,\"error_message\":\"доставки нет\"}")
        != 0, "shipping: тело {id,ok:false,error_message}");
    chk(strstr(&tg_composed, "shipping_options") == 0,
        "shipping: shipping_options отсутствует при ok=0");

    // 6. tg_answer_webapp(bot, webapp_query_id, result_json)
    r = tg_answer_webapp(bot, "w1",
        "{\"type\":\"photo\",\"photo_url\":\"http://x/w.jpg\"}");
    chk(r == 1, "webapp: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerWebAppQuery|") != 0, "webapp: URL");
    chk(strstr(&tg_composed,
        "{\"web_app_query_id\":\"w1\",\"result\":{\"type\":\"photo\",\"photo_url\":\"http://x/w.jpg\"}}")
        != 0, "webapp: тело {web_app_query_id,result}");

    // 7. tg_answer_guest(bot, guest_query_id, result_json)
    r = tg_answer_guest(bot, "g1",
        "{\"type\":\"photo\",\"photo_url\":\"http://x/g.jpg\"}");
    chk(r == 1, "guest: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerGuestQuery|") != 0, "guest: URL");
    chk(strstr(&tg_composed,
        "{\"guest_query_id\":\"g1\",\"result\":{\"type\":\"photo\",\"photo_url\":\"http://x/g.jpg\"}}")
        != 0, "guest: тело {guest_query_id,result}");

    // 8. tg_answer_join_request(bot, query_id, approve=1) → result "approve"
    r = tg_answer_join_request(bot, "j1", 1);
    chk(r == 1, "join: dry-возврат 1");
    chk(strstr(&tg_composed, "/answerChatJoinRequestQuery|") != 0, "join: URL");
    chk(strstr(&tg_composed,
        "{\"chat_join_request_query_id\":\"j1\",\"result\":\"approve\"}")
        != 0, "join: тело approve");

    // 9. tg_answer_join_request(bot, query_id, approve=0) → result "decline"
    tg_answer_join_request(bot, "j2", 0);
    chk(strstr(&tg_composed,
        "{\"chat_join_request_query_id\":\"j2\",\"result\":\"decline\"}")
        != 0, "join: тело decline");
    chk(strstr(&tg_composed, "user_id") == 0, "join: user_id отсутствует (query_id)");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
