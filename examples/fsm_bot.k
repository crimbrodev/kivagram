// examples/fsm_bot.k — FSM-бот kivagram: анкета с состояниями в SQLite
// Сборка: ./build.sh examples/fsm_bot.k fsm_bot   (линкует libsqlite3)
// Токен: замените строку в main на свой (BotFather → /newbot).
//
// Демонстрирует волну v4: роутер с фильтрами (tg_r_msg, tg_f_cmd,
// tg_f_state), машину состояний (tg_fsm_*) поверх KV-хранилища SQLite
// (tg_kv_open), middleware и авто-ответ на callback-кнопки.
//
// Сценарий: /start → спрашивает имя → спрашивает возраст → итог.
// Состояние переживает перезапуск бота (SQLite). /cancel сбрасывает.

extern printf
extern strcmp
extern sprintf
extern exit

global main
// ===== Хендлеры (текстово ДО main — порядок определений) =====

// /start — начало анкеты: в состояние Form:name
начало(ctx) {
    auto chat;
    auto user;
    chat = tg_chat_id(ctx);
    user = tg_from_id(ctx);
    tg_fsm_set(chat, user, "Form:name");
    tg_send_text(ctx, "Начинаем анкету. Как тебя зовут?");
    1;
}

// /cancel — сброс состояния и данных
сброс(ctx) {
    auto chat;
    auto user;
    chat = tg_chat_id(ctx);
    user = tg_from_id(ctx);
    tg_fsm_clear(chat, user);
    tg_send_text(ctx, "Анкета отменена. /start чтобы начать заново.");
    1;
}

// шаг 1: имя → в состояние Form:age, имя кладём в data (JSON)
шаг_имя(ctx) {
    auto chat;
    auto user;
    auto name;
    auto json;
    chat = tg_chat_id(ctx);
    user = tg_from_id(ctx);
    name = tg_text(ctx);
    json = tg_scratch();
    sprintf(json, "{\"name\": \"%s\"}", name);
    tg_fsm_update_data(chat, user, json);
    tg_fsm_set(chat, user, "Form:age");
    tg_send_text(ctx, "Приятно познакомиться! Сколько тебе лет?");
    1;
}

// шаг 2: возраст → имя из data + итог
шаг_возраст(ctx) {
    auto chat;
    auto user;
    auto age;
    auto data;
    auto name;
    auto json;
    auto out;
    chat = tg_chat_id(ctx);
    user = tg_from_id(ctx);
    age = tg_text(ctx);
    json = tg_scratch();
    sprintf(json, "{\"age\": \"%s\"}", age);
    tg_fsm_update_data(chat, user, json);
    data = tg_fsm_data(chat, user);
    name = tg_get_str(data, "name");
    out = tg_scratch();
    if name != 0 {
        sprintf(out, "Готово, %s: %s лет. /start — повторить, /cancel — сброс.", name, age);
    } else {
        sprintf(out, "Готово: %s лет. /start — повторить.", age);
    }
    tg_send_text(ctx, out);
    tg_fsm_clear(chat, user);
    1;
}

// прочий текст без состояния — подсказка
без_состояния(ctx) {
    tg_send_text(ctx, "Напиши /start, чтобы заполнить анкету.");
    1;
}

// middleware: лог каждого апдейта (0 = стоп роутера, тут всегда 1)
лог(ctx) {
    printf("[router] chat=%ld from=%ld\n", tg_chat_id(ctx), tg_from_id(ctx));
    1;
}

main() {
    auto bot;
    auto r;
    auto fsm;
    fsm = tg_kv_open("fsm_bot.db"); // 1 = SQLite; 0 = memory
    bot = tg_bot("ВСТАВЬТЕ_ТОКЕН:000000000");
    r = tg_router_new("anketa");
    tg_router_root(r);
    tg_router_autoanswer(1); // пустой answerCallbackQuery на кнопки
    tg_mw(r, &лог);
    // команды — снаружи FSM (срабатывают в любом состоянии)
    tg_r_msg(r, tg_f_cmd("start"), &начало);
    tg_r_msg(r, tg_f_cmd("cancel"), &сброс);
    // шаги анкеты — только в своём состоянии
    tg_r_msg(r, tg_f_state("Form:name"), &шаг_имя);
    tg_r_msg(r, tg_f_state("Form:age"), &шаг_возраст);
    // всё остальное
    tg_r_msg(r, 0, &без_состояния);
    printf("fsm example bot: SQLite=%ld, polling started\n", fsm);
    tg_polling(bot);
    printf("fsm example bot: stopped\n");
    0;
}
