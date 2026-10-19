// examples/webhook_bot.k — kivagram в webhook-режиме (вместо polling).
// Сборка: ./build.sh examples/webhook_bot.k webhook_bot
// Токен и URL: замените строки в main (BotFather → /newbot; URL — куда
// стучится Telegram, например https://<домен>/tgk или http://IP:8443/).
//
// Демонстрирует: tg_set_webhook + tg_webhook_serve (приём апдейтов по
// HTTP-сокету, проверка секрета, мгновенный 200 + диспетчер) и extras
// (tg_ex_raw — «экзотический» параметр drop_pending_updates).

extern printf

// /start — приветствие
приветствие(ctx) {
    tg_send_text(ctx, "Webhook-бот работает! Ответы приходят мгновенно.");
    1;
}

// всё остальное — тихое подтверждение
эхо(ctx) {
    tg_send_text(ctx, tg_text(ctx));
    1;
}

global main
main() {
    auto bot;
    // замените на свой токен и публичный URL (http://IP:порт/ либо https://домен/...)
    bot = tg_bot("ВСТАВЬТЕ_ТОКЕН:000000000");
    tg_on_command(bot, "start", &приветствие);
    tg_on_text(bot, "эхо", &эхо);

    // extras-слот: применим «экзотический» параметр к следующему вызову
    // обёртки (съедается автоматически)
    tg_ex_raw("drop_pending_updates", "true");
    tg_set_webhook(bot, "http://127.0.0.1:8443/", 0);

    printf("kivagram webhook bot: serving on :8443 (secret disabled)\n");
    tg_webhook_serve(bot, 8443, 0);
    printf("kivagram webhook bot: stopped\n");
    0;
}
