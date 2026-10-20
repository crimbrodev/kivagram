// t_v4_router.k — V4-C: роутер/фильтры/middleware (lib/tg_router.k) + правки
// ядра (слоты 18/19 Context, хук tg_router_hook, tg_fsm_fill в dispatch).
// Канон tests/t_dispatch.k: синтетический апдейт, лог-слот хендлера, chk,
// PASS/exit0. Сеть не используется (tg_dry_run=1).
// NB: лимит роутеров — 8, кейсы 1/9 и 4/5/10 делят роутеры (разные kind).
extern printf
extern exit
extern strcmp
extern strstr

fails[1];
logb[3];   // Buf-слот журнала срабатываний

// --- апдейты ---
u_txt[1];    // текст "hi" (kind 1)
u_cmd[1];    // /start arg1 arg2 + entities bot_command (kind 2)
u_startx[1]; // /startx + entities (kind 2) — фильтр должен отсечь
u_cb[1];     // callback_query (kind 3)

// --- хендлеры роутера (текстово ДО main — правило порядка определений) ---
h_r1(ctx) { tg_buf_add(&logb, "r1;"); 1; }
h_r2(ctx) { tg_buf_add(&logb, "r2;"); 1; }
h_b1(ctx) { tg_buf_add(&logb, "b1;"); 0; }
h_b2(ctx) { tg_buf_add(&logb, "b2;"); 1; }
h_c1(ctx) { tg_buf_add(&logb, "c1;"); 1; }
h_c2(ctx) { tg_buf_add(&logb, "c2;"); 1; }
h_d(ctx) { tg_buf_add(&logb, "d;"); 1; }
h_e(ctx) { tg_buf_add(&logb, "e;"); 1; }
h_e2(ctx) { tg_buf_add(&logb, "e2;"); 1; }
h_f(ctx) { tg_buf_add(&logb, "f;"); 1; }
h_g(ctx) { tg_buf_add(&logb, "g;"); 1; }
h_h(ctx) { tg_buf_add(&logb, "h;"); 1; }
h_cb(ctx) { tg_buf_add(&logb, "cb;"); 1; }
h_legacy(ctx) { tg_buf_add(&logb, "legacy;"); 1; }
mw_stop(ctx) { tg_buf_add(&logb, "mw;"); 0; }

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
    auto r1p;
    auto r4p;
    auto ctx;
    auto res;
    auto p;

    fails[0] = 0;
    tg_buf_init(&logb);
    tg_dry_run = 1;

    u_txt = "{\"update_id\":300, \"message\": {\"message_id\":40, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"text\": \"hi\"}}";
    u_cmd = "{\"update_id\":301, \"message\": {\"message_id\":41, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"text\": \"/start arg1 arg2\", \"entities\": [{\"offset\":0, \"length\": 6, \"type\": \"bot_command\"}]}}";
    u_startx = "{\"update_id\":302, \"message\": {\"message_id\":42, \"chat\": {\"id\":55, \"type\": \"private\"}, \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"text\": \"/startx\", \"entities\": [{\"offset\":0, \"length\": 7, \"type\": \"bot_command\"}]}}";
    u_cb = "{\"update_id\":303, \"callback_query\": {\"id\": \"cq1\", \"from\": {\"id\":9, \"first_name\": \"Ю\"}, \"data\": \"x\", \"chat_instance\": \"ci\"}}";

    bot = tg_bot("123:fake");
    tg_bot_set_username(bot, "ourbot");
    // регрессионный legacy-хендлер (проверка фолбэка и пропуска при хуке)
    tg_on_text(bot, "legacy", &h_legacy);

    // ===== (1) два хендлера на kind: первый вернул 1 → второй не вызван =====
    r1p = tg_router_new("c1");
    chk(r1p != 0, "router_new: ненулевой указатель");
    r = r1p;
    tg_r_on(r, 1, 0, &h_r1);
    tg_r_on(r, 1, 0, &h_r2);
    tg_router_root(r);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "propagation: feed вернул 1 (handled)");
    chk(strcmp(logb[0], "r1;") == 0,
        "propagation: первый вернул 1 — второй не вызван");
    tg_ctx_free(ctx);

    // ===== (2) первый вернул 0 → второй вызван =====
    tg_buf_reset(&logb);
    r = tg_router_new("c2");
    tg_r_on(r, 1, 0, &h_b1);
    tg_r_on(r, 1, 0, &h_b2);
    tg_router_root(r);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "chain: 0 → продолжение, feed=1");
    chk(strcmp(logb[0], "b1;b2;") == 0, "chain: b1(0) затем b2");
    tg_ctx_free(ctx);

    // ===== (3) фильтр не прошёл → хендлер не вызван, следующий с другим — вызван =====
    tg_buf_reset(&logb);
    r = tg_router_new("c3");
    tg_r_on(r, 1, tg_f_text_eq("nope"), &h_c1);
    tg_r_on(r, 1, tg_f_text_eq("hi"), &h_c2);
    tg_router_root(r);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "filter: сработал второй хендлер");
    chk(strcmp(logb[0], "c2;") == 0,
        "filter: несовпавший фильтр пропустил c1, c2 вызван");
    tg_ctx_free(ctx);

    // ===== роутер кейсов (4) (5) (10): kind 2 / kind 1 / kind 3 =====
    r4p = tg_router_new("c4");
    r = r4p;
    tg_r_on(r, 2, tg_f_cmd("start"), &h_d);
    tg_r_on(r, 1, tg_f_state("G:A"), &h_e);
    tg_r_cb(r, 0, &h_cb);
    tg_router_root(r);

    // ===== (4) tg_f_cmd("start"): "/start arg1 arg2" — сработал + args; "/startx" — нет =====
    tg_buf_reset(&logb);
    ctx = tg_ctx_build(bot, u_cmd);
    res = tg_router_feed(u_cmd, ctx);
    chk(res == 1, "cmd: /start arg1 arg2 сработал");
    chk(strcmp(logb[0], "d;") == 0, "cmd: хендлер вызван");
    p = tg_cmd_args(ctx);
    chk(p != 0, "cmd: tg_cmd_args ненулевой");
    if p != 0 {
        chk(strcmp(p, "arg1 arg2") == 0, "cmd: args == 'arg1 arg2'");
    }
    tg_ctx_free(ctx);

    tg_buf_reset(&logb);
    ctx = tg_ctx_build(bot, u_startx);
    res = tg_router_feed(u_startx, ctx);
    chk(res == 0, "cmd: /startx не сработал (feed=0)");
    chk(logb[1] == 0, "cmd: /startx — хендлер не вызван");
    tg_ctx_free(ctx);

    // ===== (5) tg_f_state("G:A") при слоте 18 = "G:A" =====
    tg_buf_reset(&logb);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 0, "state: слот 18 пуст — не сработал");
    chk(logb[1] == 0, "state: без состояния хендлер не вызван");
    ctx[18] = "G:A";
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "state: слот 18 = G:A — сработал");
    chk(strcmp(logb[0], "e;") == 0, "state: хендлер вызван при state G:A");
    tg_ctx_free(ctx);

    // ===== роутер кейсов (5b) (6): state из dispatch + магия =====
    r = tg_router_new("c5");
    tg_r_on(r, 1, tg_f_state("D2"), &h_e2);
    tg_r_on(r, 1, tg_ff_eq(tg_ff_text(), "hi"), &h_f);
    tg_router_root(r);

    // ===== (5b) dispatch заполняет слот 18 через tg_fsm_fill (KV memory) =====
    tg_buf_reset(&logb);
    chk(tg_kv_open(0) == 1, "fsm-fill: kv open(0)");
    tg_fsm_set(55, 9, "D2");
    tg_handle_update(bot, u_txt);   // хук: роутер вместо tg_on_*
    chk(strcmp(logb[0], "e2;") == 0,
        "fsm-fill: dispatch налил слот 18, state-фильтр прошёл, legacy не вызван");
    tg_kv_close();

    // ===== (6) магия tg_ff_eq(tg_ff_text(), "hi") =====
    tg_buf_reset(&logb);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "ff: eq(text,'hi') на тексте 'hi' сработал");
    chk(strcmp(logb[0], "f;") == 0, "ff: хендлер вызван");
    tg_ctx_free(ctx);

    // ===== (7) комбинаторы tg_f_and / tg_f_not =====
    tg_buf_reset(&logb);
    r = tg_router_new("c7");
    tg_r_on(r, 1, tg_f_and(tg_f_text_eq("hi"), tg_f_not(tg_f_from(100))),
        &h_g);
    tg_router_root(r);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "and/not: (text==hi && !(from==100)) сработал");
    chk(strcmp(logb[0], "g;") == 0, "and/not: хендлер вызван");
    tg_ctx_free(ctx);

    // ===== (8) middleware вернул 0 → хендлер не вызван, feed вернул 0 =====
    tg_buf_reset(&logb);
    r = tg_router_new("c8");
    tg_mw(r, &mw_stop);
    tg_r_on(r, 1, 0, &h_h);
    tg_router_root(r);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 0, "mw: стоп middleware → feed=0 (фолбэк на tg_on_*)");
    chk(strcmp(logb[0], "mw;") == 0, "mw: хендлер не вызван");
    tg_ctx_free(ctx);

    // ===== (9) root установлен → tg_upd_kind + хук через tg_handle_update =====
    tg_buf_reset(&logb);
    tg_router_root(r1p);   // роутер кейса (1): h_r1/h_r2 на kind 1
    chk(tg_router_hook != 0, "root: tg_router_hook установлен");
    tg_handle_update(bot, u_txt);
    chk(strcmp(logb[0], "r1;") == 0,
        "hook: роутер обработал (handled), tg_on_text не вызван");
    // прямая симуляция диспатча
    tg_buf_reset(&logb);
    ctx = tg_ctx_build(bot, u_txt);
    res = tg_router_feed(u_txt, ctx);
    chk(res == 1, "feed: прямой вызов — handled=1");
    tg_ctx_free(ctx);

    // ===== (10) авто-ответ: kind 3 + autoanswer(1) → answerCallbackQuery, слот 19 = 1 =====
    tg_buf_reset(&logb);
    tg_router_root(r4p);   // там же зарегистрирован h_cb на kind 3 (tg_r_cb)
    tg_router_autoanswer(1);
    tg_dry_run = 1;
    ctx = tg_ctx_build(bot, u_cb);
    chk(tg_cb_answered(ctx) == 0, "auto: до обработки слот 19 == 0");
    res = tg_router_feed(u_cb, ctx);
    chk(res == 1, "auto: callback обработан");
    chk(strcmp(logb[0], "cb;") == 0, "auto: хендлер вызван (не отвечал сам)");
    chk(strstr(&tg_composed, "/answerCallbackQuery|") != 0,
        "auto: композиция answerCallbackQuery видна (dry-run)");
    chk(strstr(&tg_composed, "cq1") != 0, "auto: в теле callback_query_id=cq1");
    chk(tg_cb_answered(ctx) == 1, "auto: слот 19 стал 1");
    tg_router_autoanswer(0);
    tg_ctx_free(ctx);

    // слот 19 ставит и tg_answer ядра
    ctx = tg_ctx_build(bot, u_cb);
    tg_answer(ctx, "ok");
    chk(tg_cb_answered(ctx) == 1, "tg_answer: слот 19 = 1 после вызова API");
    tg_ctx_free(ctx);

    // ===== (11) регрессия: hook=0 → tg_on_*-хендлер по-прежнему вызывается =====
    tg_buf_reset(&logb);
    tg_router_hook = 0;
    tg_handle_update(bot, u_txt);
    chk(strcmp(logb[0], "legacy;") == 0,
        "regression: без роутера (hook=0) tg_on_text вызван");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
