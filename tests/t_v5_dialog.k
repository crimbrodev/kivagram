// t_v5_dialog.k — V5-B: диалоги lib/tg_dialog.k (карта aiogram_dialogs):
// стек в FSM-data, окна, кнопки с intent, рендер плейсхолдеров, ввод текста.
// Канон t_methods.k/t_dispatch.k: синтетический ctx, tg_dry_run=1, без сети.
extern printf
extern exit
extern strcmp
extern strstr
extern sprintf

fails[1];
logb[3];     // Buf-слот журнала жизненного цикла
ucb[512];    // 4 КБ — сборка callback-апдейта под intent

// --- хендлеры диалогов (до main — правило порядка определений) ---

h_dstart(dlg) { tg_buf_add(&logb, "start;"); 1; }
h_dclose(dlg) { tg_buf_add(&logb, "close;"); 1; }
h_dclick(dlg) { tg_buf_add(&logb, "click;"); 1; }
h_dtext(dlg) {
    tg_buf_add(&logb, "text;");
    tg_dlg_update(dlg[0], dlg[1], "{\"name\":\"Ввод\"}");
    1;
}
h_dgetter(dlg) { "{\"title\":\"Корзина\"}"; }

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
    auto d1;
    auto d2;
    auto p;
    auto data;
    auto bot;
    auto ctx;
    auto intent;
    auto upd;

    fails[0] = 0;
    tg_buf_init(&logb);

    tg_kv_open(0);
    tg_fsm_strategy(0);
    tg_dry_run = 1;
    bot = tg_bot("123:fake");

    // ===== Реестр диалога: 2 окна, хендлеры, кнопки (2 ряда) =====
    d1 = tg_dialog_new("OrderSG");
    chk(d1 != 0, "reg: диалог создан");
    tg_dg_window(d1, "first", "Привет, {start.name}! Вы: {dialog_data.name}! Т:{getter.title}", 0);
    tg_dg_window(d1, "second", "Второй шаг", 0);
    tg_dg_on_start(d1, &h_dstart);
    tg_dg_on_close(d1, &h_dclose);
    tg_dg_getter(d1, &h_dgetter);
    tg_dg_button_go(d1, "first", "btn1", "Далее", "second");
    tg_dg_button(d1, "first", "btnX", "Кастом");
    tg_dg_on_click(d1, "first", "btnX", &h_dclick);
    tg_dg_kbd_row(d1);
    tg_dg_button(d1, "first", "btn2", "Ещё");
    tg_dg_on_text(d1, "second", &h_dtext);

    // ===== (1) start: state == OrderSG:first, стек length 1, on_start =====
    tg_dlg_start(55, 9, "OrderSG", 0, "{\"name\":\"Миша\"}");
    p = tg_fsm_state(55, 9);
    chk(p != 0, "start: state есть");
    if p != 0 chk(strcmp(p, "OrderSG:first") == 0, "start: state == OrderSG:first");
    data = tg_fsm_data(55, 9);
    chk(data != 0, "start: data стека есть");
    if data != 0 chk(tg_count(data, "stack") == 1, "start: стек length 1");
    chk(strstr(logb[0], "start;") != 0, "start: on_start вызван");

    // ===== (7)+(9) рендер: плейсхолдеры start/dialog_data/getter =====
    tg_dlg_show(bot, 55, 9);
    chk(strstr(&tg_composed, "/sendMessage|") != 0, "show: первый показ — sendMessage");
    chk(strstr(&tg_composed, "Привет, Миша!") != 0, "render: {start.name} подставлен");
    chk(strstr(&tg_composed, "Вы: !") != 0, "render: пустой {dialog_data.name}");
    chk(strstr(&tg_composed, "Корзина") != 0, "getter: {getter.title} подставлен");

    // ===== (3) next/back по порядку окон =====
    tg_dlg_next(55, 9);
    p = tg_fsm_state(55, 9);
    chk(p != 0, "next: state есть");
    if p != 0 chk(strcmp(p, "OrderSG:second") == 0, "next: -> second");
    tg_dlg_back(55, 9);
    p = tg_fsm_state(55, 9);
    if p != 0 chk(strcmp(p, "OrderSG:first") == 0, "back: -> first");

    // ===== (4) кнопка_go с intent: рендер клавиатуры + click =====
    tg_dlg_show(bot, 55, 9);   // второй show — intent пересоздан
    chk(strstr(&tg_composed, "btn1") != 0, "kbd: btn1 в композиции");
    chk(strstr(&tg_composed, "btnX") != 0, "kbd: btnX в композиции");
    chk(strstr(&tg_composed, "btn2") != 0, "kbd: btn2 (второй ряд)");
    chk(strstr(&tg_composed, "callback_data") != 0, "kbd: callback_data есть");
    data = tg_fsm_data(55, 9);
    intent = tg_get_num(data, "stack.0.i");
    chk(intent > 0, "intent: в элементе стека");
    sprintf(&ucb, "{\"update_id\":90, \"callback_query\": {\"id\": \"cq9\", \"from\": {\"id\": 9}, \"data\": \"%ld|btn1\"}}", intent);
    ctx = tg_ctx_build(bot, &ucb);
    chk(tg_dlg_click(bot, ctx) == 1, "click: кнопка_go обработана");
    p = tg_fsm_state(55, 9);
    if p != 0 chk(strcmp(p, "OrderSG:second") == 0, "click: state -> second");
    tg_ctx_free(ctx);

    // ===== (5) устаревший intent -> click 0, state не меняется =====
    ctx = tg_ctx_build(bot, &ucb);
    chk(tg_dlg_click(bot, ctx) == 0, "click: устаревший intent -> 0");
    p = tg_fsm_state(55, 9);
    if p != 0 chk(strcmp(p, "OrderSG:second") == 0, "click: state не изменился");
    tg_ctx_free(ctx);

    // ===== (7) update dialog_data -> {dialog_data.name} в рендере =====
    tg_dlg_back(55, 9);   // вернуться на first для показа
    tg_dg_setmid(55, 9, 42);   // сымитировать mid от Telegram (dry-run ставит 0)
    tg_dlg_update(55, 9, "{\"name\":\"Иван\"}");
    chk(strstr(&tg_composed, "Вы: Иван!") != 0, "update: {dialog_data.name} подставлен");
    chk(strstr(&tg_composed, "/editMessageText|") != 0, "update: второй показ — editMessageText");

    // ===== (8) tg_dlg_input: on_text в состоянии вызывается =====
    tg_dlg_switch(55, 9, "second");
    upd = "{\"update_id\":91, \"message\": {\"message_id\": 50, \"chat\": {\"id\": 55, \"type\": \"private\"}, \"from\": {\"id\": 9}, \"text\": \"hi\"}}";
    ctx = tg_ctx_build(bot, upd);
    chk(tg_dlg_input(bot, ctx) == 1, "input: on_text обработал");
    chk(strstr(logb[0], "text;") != 0, "input: on_text вызван");
    tg_ctx_free(ctx);

    // ===== (6) done: pop, state -> родитель, затем пустой стек =====
    tg_dlg_done(55, 9, 0);   // закрыть текущий диалог (стек -> 0)
    data = tg_fsm_data(55, 9);
    chk(data == 0, "done: закрытие до вложенных — стек пуст");
    tg_dlg_start(55, 9, "OrderSG", 0, 0);
    d2 = tg_dialog_new("PaySG");
    chk(d2 != 0, "reg: второй диалог создан");
    tg_dg_window(d2, "form", "Оплата", 0);
    tg_dlg_start(55, 9, "PaySG", 0, 0);
    data = tg_fsm_data(55, 9);
    if data != 0 chk(tg_count(data, "stack") == 2, "nested: стек length 2");
    p = tg_fsm_state(55, 9);
    if p != 0 chk(strcmp(p, "PaySG:form") == 0, "nested: state == PaySG:form");
    tg_dlg_done(55, 9, "{\"ok\":1}");
    chk(strstr(logb[0], "close;") != 0, "done: on_close вызван");
    data = tg_fsm_data(55, 9);
    if data != 0 chk(tg_count(data, "stack") == 1, "done: pop -> стек 1");
    p = tg_fsm_state(55, 9);
    if p != 0 chk(strcmp(p, "OrderSG:first") == 0, "done: state -> родитель");
    tg_dlg_done(55, 9, 0);
    data = tg_fsm_data(55, 9);
    chk(data == 0, "done: стек пуст -> data стёрта");
    chk(tg_fsm_state(55, 9) == 0, "done: state стёрт");

    tg_dry_run = 0;
    tg_kv_close();

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
