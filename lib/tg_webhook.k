// tg_webhook.k — webhook-обёртки (kivagram v2, волна W3-2).
// Методы: setWebhook, deleteWebhook. Всё через tg_call (dry-режим композирует
// URL+тело в tg_composed, HTTP пропускается).
// tg_get_webhook_info(bot) — по контракту W3-2 входит в этот набор, но уже
// определена волной 1 в lib/tg_react.k (тело "{}" — идентично спецификации);
// дубликат сломал бы линковку всей матрицы, поэтому здесь НЕ повторяется —
// покрывается тестом tests/t_v3_webhook.k (кейс 8) через общую сборку.
//
// Опциональные параметры setWebhook — через extras-слот ядра (lib/tg.k).
// Контракт: tg_ex_* ВЫЗЫВАЮТСЯ ДО вызова обёртки и съедаются автоматически
// внутри tg_params_done (следующей обёрткой). Если накопленное не должно
// уйти в вызов — сделайте tg_ex_reset() сами (в тестах это делается явно).
// Пример:
//
//   tg_ex_raw("drop_pending_updates", "true");
//   tg_set_webhook(bot, "https://example.com/hook", 0);
//   // → {"url":"https://example.com/hook","drop_pending_updates":true}
//
// Ключи опциональных параметров setWebhook:
//   ip_address          — tg_ex_str("ip_address", "1.2.3.4")
//   max_connections     — tg_ex_num("max_connections", 40)   (1-100, дефолт 40)
//   allowed_updates     — tg_ex_json("allowed_updates", "[\"message\"]")
//                         (готовый JSON-массив, валидность — на вызывающем)
//   drop_pending_updates— tg_ex_raw("drop_pending_updates", "true")
//   и любые другие ключи — tg_ex_str / tg_ex_num / tg_ex_json / tg_ex_raw.
//
// certificate (InputFile, self-signed) — multipart: файлы не передаются в
// JSON-теле, нужен tg_call_mp. extras в multipart-путь НЕ льётся (слитие
// делает только tg_params_done для JSON-тела) — поля набираются в tg_mpslot:
//
//   tg_mp_reset();
//   tg_mf_str("url", "https://example.com/hook");
//   tg_mf_str("secret_token", "sk");          // если секрет нужен
//   tg_mf_file("certificate", "/path/cert.pem");
//   tg_call_mp(bot, "setWebhook");
//
// Возврат всех обёрток — 1 в dry-режиме, иначе 1 при ok:true (см. tg_call).

// tg_set_webhook(bot, url, secret) — setWebhook.
// url обязателен: HTTPS-URL приёма апдейтов (порты 443, 80, 88, 8443);
// пустая строка снимает интеграцию. secret=0 → secret_token не передаётся;
// иначе — 1-256 символов [A-Za-z0-9_-] (шапка X-Telegram-Bot-Api-Secret-Token).
tg_set_webhook(bot, url, secret) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "url", url);
    if secret != 0 tg_param_str(&tg_paramslot, "secret_token", secret);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setWebhook", body);
}

// tg_delete_webhook(bot, drop_pending) — deleteWebhook.
// drop_pending 1 → "drop_pending_updates":true (сбросить отложенные апдейты),
// 0 → параметр не передаётся. Экспортируемая замена внутреннему вызову в
// tg_polling (его не трогаем).
tg_delete_webhook(bot, drop_pending) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if drop_pending != 0 tg_ex_raw("drop_pending_updates", "true");
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteWebhook", body);
}

