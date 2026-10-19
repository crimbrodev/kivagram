// t_v3_webhook.k — W3-2: webhook-обёртки (setWebhook / deleteWebhook /
// getWebhookInfo) в dry-режиме, без сети. Кейсы: URL+тело (secret 0→skip),
// extras-кейс (drop_pending_updates через tg_ex_raw → в тело через
// tg_params_done), опциональные через extras (ip_address/max_connections/
// allowed_updates), multipart-кейс certificate (-F 'certificate=@path'),
// НЕГАТИВНЫЙ: tg_ex_reset() в конце кейса — extras не протекает в следующие
// проверки (контракт ядра: слот съедается автоматически, но в тесте сбрасываем
// явно ради чистоты).
extern printf
extern exit
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
    tg_ex_reset();

    // ===== 1. tg_set_webhook(bot, url, secret): url + secret_token =====
    r = tg_set_webhook(bot, "https://example.com/hook", "s3cret_1");
    chk(r == 1, "set_webhook: dry-возврат 1");
    chk(strstr(&tg_composed, "/setWebhook|") != 0, "set_webhook: URL /setWebhook");
    chk(strstr(&tg_composed,
        "{\"url\":\"https://example.com/hook\",\"secret_token\":\"s3cret_1\"}") != 0,
        "set_webhook: тело {url,secret_token}");

    // ===== 2. secret=0 → secret_token не передаётся =====
    tg_set_webhook(bot, "https://example.com/hook", 0);
    chk(strstr(&tg_composed, "{\"url\":\"https://example.com/hook\"}") != 0,
        "set_webhook: secret=0 → тело только {url}");
    chk(strstr(&tg_composed, "secret_token") == 0,
        "set_webhook: secret=0 → secret_token пропущен");

    // ===== 3. extras-кейс: drop_pending_updates через tg_ex_raw ДО вызова =====
    tg_ex_reset();
    tg_ex_raw("drop_pending_updates", "true");
    r = tg_set_webhook(bot, "https://example.com/hook", "sk");
    chk(r == 1, "extras: dry-возврат 1");
    chk(strstr(&tg_composed,
        "{\"url\":\"https://example.com/hook\",\"secret_token\":\"sk\",\"drop_pending_updates\":true}") != 0,
        "extras: drop_pending_updates:true слито в тело перед }");
    chk(tg_extraslot[1] == 0, "extras: слот съеден после обёртки");
    tg_ex_reset();  // негативный кейс: явный сброс ради чистоты

    // ===== 4. негативный: после tg_ex_reset() extras не течёт дальше =====
    tg_set_webhook(bot, "https://example.com/hook", 0);
    chk(strstr(&tg_composed, "drop_pending_updates") == 0,
        "негатив: после tg_ex_reset extras не протекает в следующий вызов");
    chk(strstr(&tg_composed, "{\"url\":\"https://example.com/hook\"}") != 0,
        "негатив: тело только {url}");

    // ===== 5. опциональные через extras: ip_address/max_connections/allowed_updates =====
    tg_ex_str("ip_address", "1.2.3.4");
    tg_ex_num("max_connections", 40);
    tg_ex_json("allowed_updates", "[\"message\",\"callback_query\"]");
    tg_set_webhook(bot, "https://example.com/hook", 0);
    chk(strstr(&tg_composed, "\"ip_address\":\"1.2.3.4\"") != 0,
        "extras: ip_address через tg_ex_str");
    chk(strstr(&tg_composed, "\"max_connections\":40") != 0,
        "extras: max_connections через tg_ex_num (без кавычек)");
    chk(strstr(&tg_composed, "\"allowed_updates\":[\"message\",\"callback_query\"]") != 0,
        "extras: allowed_updates через tg_ex_json (сырой массив)");
    tg_ex_reset();

    // ===== 6. certificate — multipart: tg_mf_file + tg_call_mp =====
    tg_mp_reset();
    tg_mf_str("url", "https://example.com/hook");
    tg_mf_file("certificate", "/tmp/cert.pem");
    r = tg_call_mp(bot, "setWebhook");
    chk(r == 1, "certificate: dry-возврат 1");
    chk(strstr(&tg_composed, "/setWebhook|MP ") != 0,
        "certificate: URL /setWebhook|MP");
    chk(strstr(&tg_composed, "-F 'url=https://example.com/hook'") != 0,
        "certificate: url уходит mp-полем");
    chk(strstr(&tg_composed, "-F 'certificate=@/tmp/cert.pem'") != 0,
        "certificate: -F 'certificate=@path'");

    // ===== 7. tg_delete_webhook(bot, drop_pending) =====
    r = tg_delete_webhook(bot, 1);
    chk(r == 1, "delete_webhook: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteWebhook|") != 0,
        "delete_webhook: URL /deleteWebhook");
    chk(strstr(&tg_composed, "{\"drop_pending_updates\":true}") != 0,
        "delete_webhook: drop_pending=1 → {\"drop_pending_updates\":true}");

    tg_delete_webhook(bot, 0);
    chk(strstr(&tg_composed, "/deleteWebhook|{}") != 0,
        "delete_webhook: drop_pending=0 → тело {}");
    chk(strstr(&tg_composed, "drop_pending_updates") == 0,
        "delete_webhook: drop_pending=0 → параметр не передан");

    // ===== 8. tg_get_webhook_info(bot): без параметров, тело {} =====
    r = tg_get_webhook_info(bot);
    chk(r == 1, "get_webhook_info: dry-возврат 1");
    chk(strstr(&tg_composed, "/getWebhookInfo|{}") != 0,
        "get_webhook_info: URL + тело {}");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
