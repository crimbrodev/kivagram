// examples/bot.k — эхо-бот kivagram на чистой Kiva
// Сборка: ./build.sh examples/bot.k bot
// Токен: замените строку в main на свой (BotFather → /newbot).
//
// Демонстрирует: русские имена функций (UTF-8 идентификаторы),
// контракт хендлера (последнее выражение — 1), inline-кнопку через
// tg_param_json, форматирование в scratch, вызовы методов API.

extern sprintf
extern strcmp
extern printf

// слот билдера для ответа с inline-кнопкой
mykb[3];

// ===== Хендлеры: текстово ДО main (обязательный порядок определений) =====

// /start — приветствие с inline-кнопкой
приветствие(ctx) {
    auto bot;
    auto chat;
    auto body;
    bot = tg_bot_of(ctx);
    chat = tg_chat_id(ctx);
    tg_params_reset(&mykb);
    tg_param_num(&mykb, "chat_id", chat);
    tg_param_str(&mykb, "text", "Привет! Я эхо-бот на чистой Kive. Нажми кнопку или просто напиши что-нибудь.");
    tg_param_json(&mykb, "reply_markup", "{\"inline_keyboard\": [[{\"text\": \"Нажми меня\", \"callback_data\": \"greet\"}]]}");
    body = tg_params_done(&mykb);
    tg_call(bot, "sendMessage", body);
    1;
}

// /help — справка, отформатированная в scratch (sprintf)
подсказка(ctx) {
    auto bot;
    auto s;
    auto name;
    bot = tg_bot_of(ctx);
    s = tg_scratch();
    name = bot[3];
    sprintf(s, "Команды: /start — приветствие с кнопкой, /help — эта справка. Меня зовут %s.", name);
    tg_send_text(ctx, s);
    1;
}

// обычный текст — точное эхо
эхо(ctx) {
    auto t;
    t = tg_text(ctx);
    tg_send_text(ctx, t);
    1;
}

// нажатие кнопки — отвечаем и редактируем исходное сообщение
кнопка(ctx) {
    auto bot;
    auto d;
    auto mid;
    auto chat;
    bot = tg_bot_of(ctx);
    d = tg_data(ctx);
    tg_answer(ctx, "Нажатие принято");
    if d != 0 {
        if strcmp(d, "greet") == 0 {
            mid = tg_msg_id(ctx);
            if mid != 0 {
                chat = tg_chat_id(ctx);
                tg_edit_text(bot, chat, mid, "Ты нажал кнопку!");
            }
        }
    }
    1;
}

global main
main() {
    auto bot;
    bot = tg_bot("ВСТАВЬТЕ_ТОКЕН:000000000");
    tg_on_command(bot, "start", &приветствие);
    tg_on_command(bot, "help", &подсказка);
    tg_on_text(bot, "эхо", &эхо);
    tg_on_callback(bot, "кнопка", &кнопка);
    printf("kivagram echo bot: polling started\n");
    tg_polling(bot);
    printf("kivagram echo bot: stopped\n");
    0;
}
