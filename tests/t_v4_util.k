// t_v4_util.k — lib/tg_util.k: keyboard-builder (tg_kbu_*), HTML-форматтеры
// (tg_fmt_*), sha256 + deep-linking, backoff/action-tick, media-group
// (сухой режим: tg_dry_run=1, без сети; time()/sleep — реальные).
extern printf
extern exit
extern strcmp
extern strstr
extern strlen

fails[1];
u_mg1[1];    // фото-сообщение внутри медиагруппы (caption)
u_mg2[1];    // второе фото той же группы (без caption)
u_txt[1];    // обычный текст — НЕ медиагруппа

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

// count_sub(s, sub): сколько раз sub встречается в s
count_sub(s, sub) {
    auto n;
    auto p;
    n = 0;
    p = strstr(s, sub);
    while p != 0 {
        n = n + 1;
        p = strstr(p + 1, sub);
    }
    n;
}

// inrange(v, lo, hi): 1 если lo <= v <= hi (тестовые значения малые > 0)
inrange(v, lo, hi) {
    if v < lo {
        0;
    } else if v > hi {
        0;
    } else {
        1;
    }
}

global main
main() {
    auto kb;
    auto kb2;
    auto s;
    auto r;
    auto bot;
    auto ctx;
    auto ctx2;

    fails[0] = 0;
    tg_dry_run = 1;
    bot = tg_bot("123:fake");

    // ===== 1. Keyboard builder: inline, ряды =====
    kb = tg_kbu_new();
    chk(kb != 0, "kbu_new: слот выдан");
    tg_kbu_inline(kb, "A", "a");
    tg_kbu_inline(kb, "B", "b");
    tg_kbu_row(kb);
    tg_kbu_inline(kb, "C", "c");
    s = tg_kbu_inline_json(kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"A\",\"callback_data\":\"a\"},{\"text\":\"B\",\"callback_data\":\"b\"}],[{\"text\":\"C\",\"callback_data\":\"c\"}]]}") == 0,
        "kbu_inline_json: 2 ряда из 3 кнопок");
    chk(count_sub(s, "}],[{") == 1, "kbu_row: ровно один стык рядов");

    // ===== 1а. adjust(2) из 5 кнопок → 3 ряда =====
    tg_kbu_reset(kb);
    tg_kbu_inline(kb, "1", "1");
    tg_kbu_inline(kb, "2", "2");
    tg_kbu_inline(kb, "3", "3");
    tg_kbu_inline(kb, "4", "4");
    tg_kbu_inline(kb, "5", "5");
    tg_kbu_adjust(kb, 2);
    s = tg_kbu_inline_json(kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"1\",\"callback_data\":\"1\"},{\"text\":\"2\",\"callback_data\":\"2\"}],[{\"text\":\"3\",\"callback_data\":\"3\"},{\"text\":\"4\",\"callback_data\":\"4\"}],[{\"text\":\"5\",\"callback_data\":\"5\"}]]}") == 0,
        "kbu_adjust(2): 5 кнопок → JSON с рядами по 2");
    chk(count_sub(s, "}],[{") == 2, "kbu_adjust(2): ровно 3 ряда");

    // ===== 1б. url / webapp-кнопки =====
    tg_kbu_reset(kb);
    tg_kbu_url(kb, "Go", "https://x.example");
    tg_kbu_webapp(kb, "App", "https://app.example");
    s = tg_kbu_inline_json(kb);
    chk(strstr(s, "{\"text\":\"Go\",\"url\":\"https://x.example\"}") != 0,
        "kbu_url: {text,url}");
    chk(strstr(s, "{\"text\":\"App\",\"web_app\":{\"url\":\"https://app.example\"}}") != 0,
        "kbu_webapp: {text,web_app:{url}}");

    // ===== 1в. reply-клавиатура (отдельный JSON) =====
    kb2 = tg_kbu_new();
    chk(kb2 != 0, "kbu_new: второй слот выдан");
    tg_kbu_reply(kb2, "Меню");
    tg_kbu_reply(kb2, "Ок");
    s = tg_kbu_reply_json(kb2);
    chk(strcmp(s, "{\"keyboard\":[[\"Меню\",\"Ок\"]],\"resize_keyboard\":true}") == 0,
        "kbu_reply_json: {keyboard,resize_keyboard:true}");
    chk(strstr(s, "\"resize_keyboard\":true") != 0,
        "kbu_reply_json: resize_keyboard:true присутствует");
    // reply-кнопки НЕ попадают в inline-JSON
    chk(tg_kbu_inline_json(kb2) == 0, "kbu_inline_json: только reply-кнопки → 0");

    // ===== 1г. JSON-эскейп: кавычки + кириллица как есть =====
    tg_kbu_reset(kb);
    tg_kbu_inline(kb, "Привет \"мир\"", "d");
    s = tg_kbu_inline_json(kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"Привет \\\"мир\\\"\",\"callback_data\":\"d\"}]]}") == 0,
        "kbu: кавычки в тексте → \\\" в JSON");
    chk(strstr(s, "Привет") != 0, "kbu: кириллица без изменений");

    // ===== 1д. пустой builder → 0 =====
    tg_kbu_reset(kb);
    chk(tg_kbu_inline_json(kb) == 0, "kbu_inline_json: пустой builder → 0");
    tg_kbu_reset(kb2);
    chk(tg_kbu_reply_json(kb2) == 0, "kbu_reply_json: пустой builder → 0");

    // ===== 2. HTML-форматтеры =====
    s = tg_fmt_bold("<>");
    chk(strcmp(s, "<b>&lt;&gt;</b>") == 0, "fmt_bold: экранирование <>");
    s = tg_fmt_bold("hi");
    chk(strcmp(s, "<b>hi</b>") == 0, "fmt_bold: простой текст");
    s = tg_fmt_italic("x");
    chk(strcmp(s, "<i>x</i>") == 0, "fmt_italic: <i>..</i>");
    s = tg_fmt_italic("a&b");
    chk(strcmp(s, "<i>a&amp;b</i>") == 0, "fmt_italic: экранирование &");
    s = tg_fmt_underline("y");
    chk(strcmp(s, "<u>y</u>") == 0, "fmt_underline: <u>..</u>");
    s = tg_fmt_strike("z");
    chk(strcmp(s, "<s>z</s>") == 0, "fmt_strike: <s>..</s>");
    s = tg_fmt_spoiler("w");
    chk(strcmp(s, "<tg-spoiler>w</tg-spoiler>") == 0, "fmt_spoiler: <tg-spoiler>..");
    s = tg_fmt_code("a&b");
    chk(strcmp(s, "<code>a&amp;b</code>") == 0, "fmt_code: экранирует содержимое");
    s = tg_fmt_pre("x < y");
    chk(strcmp(s, "<pre>x &lt; y</pre>") == 0, "fmt_pre: <pre>..</pre> с экранированием");
    s = tg_fmt_link("https://ya.ru", "Я");
    chk(strcmp(s, "<a href=\"https://ya.ru\">Я</a>") == 0, "fmt_link: простая ссылка");
    s = tg_fmt_link("https://a.ru/?a=1&b=2", "В<A>");
    chk(strcmp(s, "<a href=\"https://a.ru/?a=1&amp;b=2\">В&lt;A&gt;</a>") == 0,
        "fmt_link: URL и текст экранированы");
    s = tg_fmt_cat("abc", "def");
    chk(strcmp(s, "abcdef") == 0, "fmt_cat: конкатенация кусков");
    s = tg_fmt_cat(tg_fmt_bold("A"), tg_fmt_italic("B"));
    chk(strcmp(s, "<b>A</b><i>B</i>") == 0, "fmt_cat: два fmt-результата (ротация буферов)");

    // ===== 3. SHA-256: NIST-векторы =====
    s = tg_sha256_hex("");
    chk(strcmp(s, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0,
        "sha256: пустая строка (NIST)");
    s = tg_sha256_hex("abc");
    chk(strcmp(s, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0,
        "sha256: \"abc\" (NIST)");
    s = tg_sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    chk(strcmp(s, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") == 0,
        "sha256: 448-битный вектор (NIST)");
    chk(strlen(s) == 64, "sha256: hex-строка ровно 64 символа");

    // ===== 4. Deep linking =====
    s = tg_deep_create("mybot", "payload");
    chk(strcmp(s, "https://t.me/mybot?start=payload") == 0,
        "deep_create: ссылка https://t.me/<bot>?start=<payload>");
    s = tg_deep_create("mybot", "Привет мир");
    chk(strcmp(s, "https://t.me/mybot?start=Привет мир") == 0,
        "deep_create: payload как есть (кириллица/пробелы)");
    s = tg_deep_sign("payload");
    chk(strcmp(s, "I59Z7VXnN8dxR89VrQwbAw") == 0,
        "deep_sign: base64url(sha256[0:16]) без = (контрольное значение)");
    chk(strlen(s) == 22, "deep_sign: 22 символа, без паддинга");
    chk(tg_deep_verify("payload", "I59Z7VXnN8dxR89VrQwbAw") == 1,
        "deep_verify: верная подпись → 1");
    chk(tg_deep_verify("payload", "AAAAAAAAAAAAAAAAAAAAAA") == 0,
        "deep_verify: чужая подпись → 0");
    chk(tg_deep_verify("payloaX", "I59Z7VXnN8dxR89VrQwbAw") == 0,
        "deep_verify: другой payload → 0");
    s = tg_deep_create_signed("mybot", "payload");
    chk(strcmp(s, "https://t.me/mybot?start=payload-I59Z7VXnN8dxR89VrQwbAw") == 0,
        "deep_create_signed: payload-<sign> в ссылке");
    s = tg_deep_extract("https://t.me/bot?start=abc&x=1");
    chk(strcmp(s, "abc") == 0, "deep_extract: ?start= до &");
    s = tg_deep_extract("https://t.me/bot?start=abc");
    chk(strcmp(s, "abc") == 0, "deep_extract: ?start= до конца");
    s = tg_deep_extract("https://t.me/bot?x=1&start=q");
    chk(strcmp(s, "q") == 0, "deep_extract: &start= после другого параметра");
    chk(tg_deep_extract("https://t.me/bot") == 0, "deep_extract: нет параметра → 0");

    // ===== 5. Backoff =====
    r = tg_backoff_delay(1);
    chk(inrange(r, 1, 2), "backoff: попытка 1 → 1..2 c");
    r = tg_backoff_delay(6);
    chk(inrange(r, 32, 63), "backoff: попытка 6 → 32..63 c");
    r = tg_backoff_delay(7);
    chk(inrange(r, 60, 119), "backoff: cap 60 + jitter");
    r = tg_backoff_delay(99);
    chk(inrange(r, 60, 119), "backoff: большая попытка не переполняет exp");

    // ===== 5а. sleep =====
    r = tg_sleep_sec(0);
    chk(r == 1, "sleep_sec(0): мгновенно, статус 1");

    // ===== 6. Chat-action тикер (dry-run) =====
    r = tg_action_tick(bot, 55, "typing");
    chk(r == 1, "action_tick: первый вызов отправлен");
    chk(strstr(&tg_composed, "/sendChatAction|") != 0,
        "action_tick: композиция sendChatAction");
    chk(strstr(&tg_composed, "\"chat_id\":55,\"action\":\"typing\"") != 0,
        "action_tick: тело {chat_id,action}");
    r = tg_action_tick(bot, 55, "typing");
    chk(r == 0, "action_tick: повтор в пределах 4с пропущен");
    r = tg_action_tick(bot, 66, "upload_photo");
    chk(r == 1, "action_tick: другой чат отправляется");
    tg_action_reset(55);
    r = tg_action_tick(bot, 55, "typing");
    chk(r == 1, "action_reset: запись стёрта → снова отправка");

    // ===== 7. Media-group агрегатор =====
    u_mg1 = "{\"update_id\":10,\"message\":{\"message_id\":1,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9},\"media_group_id\":\"mg-1\",\"photo\":[{\"file_id\":\"small1\",\"width\":10,\"height\":10},{\"file_id\":\"big1\",\"width\":900,\"height\":900}],\"caption\":\"Подпись\"}}";
    u_mg2 = "{\"update_id\":11,\"message\":{\"message_id\":2,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9},\"media_group_id\":\"mg-1\",\"photo\":[{\"file_id\":\"big2\",\"width\":900,\"height\":900}]}}";
    u_txt = "{\"update_id\":12,\"message\":{\"message_id\":3,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9},\"text\":\"просто текст\"}}";

    tg_mg_reset();
    ctx = tg_ctx_build(bot, u_mg1);
    ctx2 = tg_ctx_build(bot, u_txt);
    chk(tg_mg_add(ctx2) == 0, "mg_add: сообщение без media_group_id → 0");
    chk(tg_mg_count() == 0, "mg_add: счётчик не вырос");
    chk(tg_mg_add(ctx) == 1, "mg_add: фото из группы принято");
    chk(tg_mg_count() == 1, "mg_add: счётчик 1");
    tg_ctx_free(ctx2);
    ctx2 = tg_ctx_build(bot, u_mg2);
    chk(tg_mg_add(ctx2) == 1, "mg_add: второе фото принято");
    chk(tg_mg_count() == 2, "mg_add: счётчик 2");
    chk(tg_mg_ready() == 0, "mg_ready: хвост группы ещё не дождался 1с");
    sleep(1);
    chk(tg_mg_ready() == 1, "mg_ready: прошла ≥1с → пора отправлять");
    r = tg_mg_send(bot, 55);
    chk(r == 1, "mg_send: dry-успех");
    chk(strstr(&tg_composed, "/sendMediaGroup|") != 0, "mg_send: URL sendMediaGroup");
    chk(strstr(&tg_composed, "\"chat_id\":55,\"media\":[{\"type\":\"photo\",\"media\":\"big1\",\"caption\":\"Подпись\"},{\"type\":\"photo\",\"media\":\"big2\"}]") != 0,
        "mg_send: media-массив (последнее фото, caption)");
    chk(tg_mg_count() == 0, "mg_send: сброс после успеха");

    // raw-версия агрегатора
    tg_mg_reset();
    tg_mg_add_raw("{\"type\":\"document\",\"media\":\"fid1\"}", 77, "grp2");
    chk(tg_mg_count() == 1, "mg_add_raw: элемент принят");
    tg_mg_add_raw("{\"type\":\"video\",\"media\":\"fid2\"}", 77, "grp2");
    chk(tg_mg_count() == 2, "mg_add_raw: второй элемент");
    r = tg_mg_send(bot, 77);
    chk(r == 1, "mg_add_raw: dry-отправка");
    chk(strstr(&tg_composed, "\"chat_id\":77,\"media\":[{\"type\":\"document\",\"media\":\"fid1\"},{\"type\":\"video\",\"media\":\"fid2\"}]") != 0,
        "mg_add_raw: тело sendMediaGroup");
    tg_mg_reset();
    chk(tg_mg_count() == 0, "mg_reset: очистка");
    tg_ctx_free(ctx);
    tg_ctx_free(ctx2);

    tg_dry_run = 0;
    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
