// t_v5_i18n.k — V5-A: i18n lib/tg_i18n.k по карте aiogram-i18n (волна v5).
// Каталоги: locales/<locale>.json (простые ключи — строки с {0}/{1},
// plural-ключи — объекты one/few/many/other). Контракт:
//   - статик-буфер tg_i18n_get/get_l/fmt/nget живёт до СЛЕДУЮЩЕГО вызова
//     tg_i18n_* (слот-кэш, как tg_kv_get) — для двух переводов копируй;
//   - ключ не найден → возвращается сам key (aiogram: KeyError → message);
//   - default_locale — фолбэк-локаль при отсутствии ключа в текущей.
// Только локальные файлы, БЕЗ сети. Временный каталог удаляется в конце.
extern printf
extern exit
extern strcmp
extern strlen
extern fopen
extern fclose
extern fwrite
extern remove
extern rmdir
extern mkdir

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

// wrfile(path, content): записать файл каталога локалей; 1 — ок
wrfile(path, content) {
    auto f;
    auto n;
    f = fopen(path, "w");
    if f == 0 {
        printf("FAIL: open %s\n", path);
        fails[0] = fails[0] + 1;
        0;
    } else {
        n = strlen(content);
        fwrite(content, 1, n, f);
        fclose(f);
        1;
    }
}

global main
main() {
    auto p;
    auto q;
    auto r;
    auto bot;
    auto ctx;
    auto upd;

    fails[0] = 0;

    // ===== setup: временный каталог каталогов локалей =====
    mkdir("/tmp/v5a_locales", 493);
    wrfile("/tmp/v5a_locales/ru.json",
        "{\"hello\":\"Привет, {0}!\",\"profile-title\":\"Профиль\",\"welcome\":\"Добро пожаловать, {0}! Ты — {1}.\",\"apples\":{\"one\":\"Яблоко\",\"few\":\"Яблока\",\"many\":\"Яблок\",\"other\":\"Яблока\"},\"emoji\":\"Ёлка \xF0\x9F\x8E\x84\",\"note\":\"Кавычки \\\" и\\nперенос\"}");
    wrfile("/tmp/v5a_locales/en.json",
        "{\"hello\":\"Hello, {0}!\",\"profile-title\":\"Profile\",\"welcome\":\"Welcome, {0}! You are {1}.\",\"apples\":{\"one\":\"Apple\",\"other\":\"Apples\"},\"emoji\":\"Tree \xF0\x9F\x8E\x84\",\"note\":\"Quotes \\\" and\\nnewline\"}");

    // ===== 0. несуществующий каталог =====
    r = tg_i18n_load("/tmp/v5a_missing", "en");
    chk(r == 0, "load: нет каталога -> 0");
    r = tg_i18n_count();
    chk(r == 0, "load: count после ошибки -> 0");

    // ===== 1. загрузка двух локалей =====
    r = tg_i18n_load("/tmp/v5a_locales", "en");
    chk(r == 1, "load: два файла -> 1");
    r = tg_i18n_count();
    chk(r == 2, "count: 2 локали");
    p = tg_i18n_available(0);
    q = tg_i18n_available(1);
    chk(p != 0, "available(0) -> имя");
    chk(q != 0, "available(1) -> имя");
    r = 0;
    if p != 0 {
        if strcmp(p, "ru") == 0 r = r + 1;
    }
    if p != 0 {
        if strcmp(p, "en") == 0 r = r + 1;
    }
    if q != 0 {
        if strcmp(q, "ru") == 0 r = r + 1;
    }
    if q != 0 {
        if strcmp(q, "en") == 0 r = r + 1;
    }
    chk(r == 2, "available: имена ru/en без дублей");
    p = tg_i18n_available(2);
    chk(p == 0, "available(2) -> 0");

    // ===== 2. set_locale + get =====
    r = tg_i18n_set_locale("ru");
    chk(r == 1, "set_locale(ru) -> 1");
    p = tg_i18n_get("profile-title");
    chk(p != 0, "get: указатель");
    if p != 0 chk(strcmp(p, "Профиль") == 0, "get: Профиль");

    // ===== 3. fmt: {0}, {0}+{1}, a1=0 =====
    p = tg_i18n_fmt("hello", "Мир", 0);
    chk(p != 0, "fmt: указатель");
    if p != 0 chk(strcmp(p, "Привет, Мир!") == 0, "fmt: {0} -> Мир");
    p = tg_i18n_fmt("welcome", "Аня", "гость");
    if p != 0 chk(strcmp(p, "Добро пожаловать, Аня! Ты — гость.") == 0,
        "fmt: два плейсхолдера");
    p = tg_i18n_fmt("welcome", "Аня", 0);
    if p != 0 chk(strcmp(p, "Добро пожаловать, Аня! Ты — .") == 0,
        "fmt: a1=0 -> пусто");

    // ===== 4. nget ru: правила русского языка =====
    p = tg_i18n_nget("apples", 1);
    chk(p != 0, "nget ru 1: указатель");
    if p != 0 chk(strcmp(p, "Яблоко") == 0, "nget ru: 1 -> Яблоко");
    p = tg_i18n_nget("apples", 3);
    if p != 0 chk(strcmp(p, "Яблока") == 0, "nget ru: 3 -> Яблока");
    p = tg_i18n_nget("apples", 5);
    if p != 0 chk(strcmp(p, "Яблок") == 0, "nget ru: 5 -> Яблок");
    p = tg_i18n_nget("apples", 11);
    if p != 0 chk(strcmp(p, "Яблок") == 0, "nget ru: 11 -> Яблок");
    p = tg_i18n_nget("apples", 21);
    if p != 0 chk(strcmp(p, "Яблоко") == 0, "nget ru: 21 -> Яблоко");

    // ===== 5. en: ветка other =====
    r = tg_i18n_set_locale("en");
    chk(r == 1, "set_locale(en) -> 1");
    p = tg_i18n_nget("apples", 1);
    chk(p != 0, "nget en 1: указатель");
    if p != 0 chk(strcmp(p, "Apple") == 0, "nget en: 1 -> Apple");
    p = tg_i18n_nget("apples", 3);
    if p != 0 chk(strcmp(p, "Apples") == 0, "nget en: 3 -> Apples");
    p = tg_i18n_locale();
    chk(p != 0, "locale: указатель");
    if p != 0 chk(strcmp(p, "en") == 0, "locale -> en");

    // ===== 6. отсутствующий ключ -> сам key =====
    p = tg_i18n_get("no-such-key");
    chk(p != 0, "get miss: указатель");
    if p != 0 chk(strcmp(p, "no-such-key") == 0, "get miss -> сам key");

    // ===== 7. from_user: менеджер локалей =====
    p = tg_i18n_from_user("ru-RU");
    chk(p != 0, "from_user ru-RU: указатель");
    if p != 0 chk(strcmp(p, "ru") == 0, "from_user(ru-RU) -> ru");
    p = tg_i18n_from_user("de");
    chk(p != 0, "from_user de: указатель");
    if p != 0 chk(strcmp(p, "en") == 0, "from_user(de) -> default en");

    // ===== 8. get_l: явная локаль =====
    p = tg_i18n_get_l("profile-title", "en");
    chk(p != 0, "get_l: указатель");
    if p != 0 chk(strcmp(p, "Profile") == 0, "get_l(en) -> Profile");

    // ===== 9. кириллица/эмодзи и JSON-эскейпы каталога (локаль ru) =====
    r = tg_i18n_set_locale("ru");
    chk(r == 1, "set_locale(ru) перед emoji/note -> 1");
    p = tg_i18n_get("emoji");
    chk(p != 0, "emoji: указатель");
    if p != 0 chk(strcmp(p, "Ёлка \xF0\x9F\x8E\x84") == 0, "emoji: кириллица+эмодзи");
    p = tg_i18n_get("note");
    chk(p != 0, "note: указатель");
    if p != 0 chk(strcmp(p, "Кавычки \" и\nперенос") == 0, "note: \\\" и \\n раскрыты");

    // ===== 10. bind_ctx: language_code из сырого апдейта =====
    bot = tg_bot("123:fake");
    upd = "{\"update_id\":1, \"message\": {\"message_id\": 42, \"chat\": {\"id\": 55, \"type\": \"private\"}, \"from\": {\"id\": 9, \"first_name\": \"A\", \"language_code\": \"ru-RU\"}, \"text\": \"hi\"}}";
    ctx = tg_ctx_build(bot, upd);
    p = tg_i18n_bind_ctx(ctx);
    chk(p != 0, "bind_ctx: указатель");
    if p != 0 chk(strcmp(p, "ru") == 0, "bind_ctx: language_code ru-RU -> ru");
    tg_ctx_free(ctx);

    // ===== cleanup =====
    remove("/tmp/v5a_locales/ru.json");
    remove("/tmp/v5a_locales/en.json");
    rmdir("/tmp/v5a_locales");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
