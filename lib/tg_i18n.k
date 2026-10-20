// lib/tg_i18n.k — V5-A: i18n (каталоги локалей) поверх lib/tg.k, по карте
// aiogram-i18n. Ядро и роутер НЕ трогаются — только публичный контракт.
//
// Соответствие aiogram-i18n:
//   I18nContext.get / __call__     → tg_i18n_get, tg_i18n_get_l, tg_i18n_fmt
//   I18nContext.locale/set_locale  → tg_i18n_locale / tg_i18n_set_locale
//   BaseCore.startup (find_locales)→ tg_i18n_load (JSON-каталоги locales/*.json)
//   BaseCore.nget (plural)         → tg_i18n_nget (правила ru + ветка other)
//   MemoryManager/FSMManager       → tg_i18n_set_locale (глобальная локаль)
//   менеджер examples/sqlalchemy_manager (from update) → tg_i18n_from_user
//   I18nMiddleware (locale_getter на апдейт) → tg_i18n_bind_ctx
//   KeyError → message             → неизвестный ключ возвращается как сам key
//
// Формат каталога: JSON-файл dir/<locale>.json — объект на верхнем уровне:
//   {
//     "hello": "Привет, {0}!",
//     "profile-title": "Профиль",
//     "apples": {"one": "Яблоко", "few": "Яблока", "many": "Яблок",
//                "other": "Яблока"}
//   }
//   - простой ключ — строка, плейсхолдеры {0}, {1} (fmt) и {n} (nget);
//   - plural-ключ — объект one/few/many/other;
//   - ключи ищутся dot-path'ом ядра, поэтому ТОЧКУ в ключе не используй
//     (как key_separator="-" в aiogram); управляющие символы и кавычки —
//     обычные JSON-эскейпы (\n, \", \uXXXX), раскрываются при чтении.
//
// ПУБЛИЧНЫЙ API (все вызовы ≤6 аргументов):
//   tg_i18n_load(dir, default_locale) → 1/0. Читает ВСЕ dir/*.json (обход
//       через `ls`, пути с ' запрещены), ключи файлов одной локали сливаются
//       в пул: более поздний файл (алфавитный порядок ls) перекрывает ранний.
//       default_locale — фолбэк-локаль; если её нет среди загруженных —
//       предупреждение и фолбэк-цепочка сокращается до текущей локали.
//       Повторный вызов освобождает предыдущие каталоги. Лимиты: 8 локалей,
//       16 файлов (после предупреждения в stdout лишние пропускаются).
//   tg_i18n_count()                 → число загруженных локалей
//   tg_i18n_available(idx)          → имя idx-й локали или 0 (нет такой)
//   tg_i18n_set_locale(locale)      → 1 — локаль загружена и включена,
//                                      0 — нет (текущая не меняется)
//   tg_i18n_locale()                → текущая локаль или 0 (ничего не загружено)
//   tg_i18n_get(key)                → перевод ТЕКУЩЕЙ локали; цепочка
//                                      текущая → default → сам key. Статик-буфер.
//   tg_i18n_get_l(key, locale)      → перевод УКАЗАННОЙ локали (для проверок
//                                      и фильтров), без фолбэка: локаль не
//                                      загружена или ключа нет → сам key.
//   tg_i18n_fmt(key, a0, a1)        → перевод текущей локали с подстановкой
//                                      {0}=a0, {1}=a1. a0/a1 = 0 → пустая
//                                      строка (одноаргументный вызов —
//                                      tg_i18n_fmt(key, text, 0)). Больше
//                                      двух плейсхолдеров нет — лимит ≤6
//                                      аргументов API; {n} отдан nget.
//   tg_i18n_nget(key, n)            → plural-перевод по n: ru-семейство
//                                      (ru/uk/be) — one/few/many по правилам
//                                      русского, остальные — n==1 → one,
//                                      иначе other. Отсутствующая форма
//                                      падает на other → many → one → few;
//                                      ключа нет вообще → строка числа n.
//                                      {n} подставляется числом.
//   tg_i18n_from_user(lang_code)    → менеджер локалей: точное совпадение,
//                                      иначе усечение до языка ("ru-RU"→"ru"),
//                                      иначе default. Возвращает текущую локаль.
//   tg_i18n_bind_ctx(ctx)           → хук middleware: читает
//                                      user.language_code из сырого апдейта
//                                      (message/edited_message/channel_post/
//                                      callback_query/inline_query/
//                                      my_chat_member/chat_join_request) и
//                                      делает from_user. Возвращает локаль.
//                                      Ядро/роутер не правятся: в tg_on_*
//                                      хендлере достаточно вызвать её первой
//                                      строкой (это и есть контракт middleware).
//
// БУФЕРЫ (слот-кэш, как tg_kv_get): get/get_l/fmt/nget возвращают указатель
// на ОБЩИЙ статик-буфер, валидный только до следующего вызова tg_i18n_*.
// Нужны два перевода сразу — копируй первый (strcpy) перед вторым. Исключение:
// tg_i18n_available/tg_i18n_locale возвращают имя в статическом массиве имён —
// оно живёт до следующего tg_i18n_load. Неизвестный ключ возвращается как
// сам аргумент key (указатель на строку вызывающего).
//
// ПОБОЧНЫЕ ЭФФЕКТЫ: поиск использует tg_get/tg_get_str ядра, поэтому
// выставляет tg_last_err (как любой вызов JSON-сканера ядра).
// Чтение каталога — через popen("ls") + fopen/fgets (транспортный стиль
// ядра для curl), без сети.
//
// Пример:
//   tg_i18n_load("locales", "en");
//   tg_i18n_bind_ctx(ctx);                    // локаль из апдейта
//   tg_send_text(ctx, tg_i18n_fmt("hello", tg_from_name(ctx), 0));

extern printf
extern strcmp
extern strcpy
extern strlen
extern sprintf
extern popen
extern pclose
extern fgets
extern fopen
extern fclose

// ===== Глобальное состояние =====

tg_i18n_nloc;           // число загруженных локалей (≤8)
tg_i18n_ndocs;          // число файлов-документов (≤16)
tg_i18n_cur;            // индекс текущей локали
tg_i18n_defidx;         // индекс default-локали
tg_i18n_defok;          // 1 — default найден среди загруженных
tg_i18n_names[128];     // 8 имён × 16 байт (NUL-терминированные)
tg_i18n_docs[48];       // 16 Buf-слотов × 3 слова (сырой JSON файла)
tg_i18n_dloc[16];       // индекс локали каждого документа
tg_i18n_out[2048];      // 16 КБ — общий выходной буфер (слот-кэш)
tg_i18n_opos;           // позиция записи в out, байт
tg_i18n_doc;            // корень JSON, где найден ключ (для tg_get_str)
tg_i18n_cmd[64];        // 512 байт — команда ls
tg_i18n_rb[64];         // 512 байт — строка вывода ls
tg_i18n_rb2[64];        // 512 байт — приёмник чтения файла
tg_i18n_floc[16];       // имя локали, вырезанное из имени файла
tg_i18n_pbuf[64];       // 512 байт — рабочий путь "key.formname"
tg_i18n_num[16];        // 128 байт — "%ld" для nget
tg_i18n_empty[1];       // "" — заглушка пустой подстановки (слово = NUL)

// ===== Выходной буфер =====

// tg_i18n_ob(c): дописать байт в out; 1 — ок, 0 — отсечка (~16 КБ)
tg_i18n_ob(c) {
    if tg_i18n_opos > 16000 {
        0;
    } else {
        *(&tg_i18n_out + tg_i18n_opos) !8 c;
        tg_i18n_opos = tg_i18n_opos + 1;
        1;
    }
}

// tg_i18n_emit2(src, ph0, r0, ph1, r1): копия src в out с подстановкой
// {ph0} → r0 и {ph1} → r1. ph — байт-код символа в фигурных скобках
// (48='0', 49='1', 110='n'); ph=0 — подстановка выключена; r=0 — на месте
// плейсхолдера пустая строка. n — число плейсхолдеров не растёт: API ≤6
// аргументов.
tg_i18n_emit2(src, ph0, r0, ph1, r1) {
    auto c;
    auto d;
    auto done;
    auto hit;
    auto rs;
    auto k;
    auto c2;
    auto stop2;
    tg_i18n_opos = 0;
    done = 0;
    while done == 0 {
        c = @8 *src;
        if c == 0 {
            done = 1;
        } else if c == 123 {              // '{' — возможный плейсхолдер
            d = @8 *(src + 1);
            hit = 0;
            rs = 0;
            if ph0 != 0 {
                if d == ph0 {
                    hit = 1;
                    rs = r0;
                }
            }
            if ph1 != 0 {
                if d == ph1 {
                    hit = 1;
                    rs = r1;
                }
            }
            if hit != 0 {
                if @8 *(src + 2) == 125 {  // '}'
                    src = src + 3;
                    if rs != 0 {
                        k = 0;
                        stop2 = 0;
                        while stop2 == 0 {
                            c2 = @8 *(rs + k);
                            if c2 == 0 {
                                stop2 = 1;
                            } else {
                                if tg_i18n_ob(c2) == 0 stop2 = 1;
                                k = k + 1;
                            }
                        }
                    }
                } else {
                    if tg_i18n_ob(123) == 0 done = 1;
                    src = src + 1;
                }
            } else {
                if tg_i18n_ob(123) == 0 done = 1;
                src = src + 1;
            }
        } else {
            if tg_i18n_ob(c) == 0 done = 1;
            src = src + 1;
        }
    }
    *(&tg_i18n_out + tg_i18n_opos) !8 0;
    &tg_i18n_out;
}

// tg_i18n_putout(src): копия src в out без подстановок → &out
tg_i18n_putout(src) {
    auto r;
    r = tg_i18n_emit2(src, 0, 0, 0, 0);
    r;
}

// ===== Поиск локалей и ключей =====

// tg_i18n_find_loc(name): индекс загруженной локали или -1
tg_i18n_find_loc(name) {
    auto i;
    auto r;
    r = -1;
    i = 0;
    while i < tg_i18n_nloc {
        if strcmp(&tg_i18n_names + i * 16, name) == 0 r = i;
        i = i + 1;
    }
    r;
}

// tg_i18n_raw_at(key, loc): сырое значение ключа в локали loc или 0;
// tg_i18n_doc — корень документа, где найдено (для tg_get_str).
// Берётся ПОСЛЕДНИЙ файл локали (перекрытие: поздний файл важнее раннего).
tg_i18n_raw_at(key, loc) {
    auto i;
    auto j;
    auto r;
    r = 0;
    tg_i18n_doc = 0;
    i = tg_i18n_ndocs;
    while i > 0 {
        i = i - 1;
        if tg_i18n_dloc[i] == loc {
            j = tg_i18n_docs[i * 3];
            if j != 0 {
                r = tg_get(j, key);
                if r != 0 {
                    tg_i18n_doc = j;
                    i = 0;          // найдено — выйти из цикла
                }
            }
        }
    }
    r;
}

// tg_i18n_str_at(key, loc): перевод-строка в scratch ядра или 0
// (нет ключа / значение — объект или массив, т.е. не строка)
tg_i18n_str_at(key, loc) {
    auto s;
    auto r;
    r = 0;
    s = tg_i18n_raw_at(key, loc);
    if s != 0 {
        if @8 *s == 123 r = 0;
        else if @8 *s == 91 r = 0;
        else r = tg_get_str(tg_i18n_doc, key);
    }
    r;
}

// tg_i18n_src(key): цепочка текущая → default → 0 (указатель в scratch)
tg_i18n_src(key) {
    auto s;
    s = tg_i18n_str_at(key, tg_i18n_cur);
    if s == 0 {
        if tg_i18n_defok != 0 {
            if tg_i18n_defidx != tg_i18n_cur {
                s = tg_i18n_str_at(key, tg_i18n_defidx);
            }
        }
    }
    s;
}

// ===== Plural =====

// tg_i18n_slavic(name): 1 — ru/uk/be (правила вида one/few/many/other)
tg_i18n_slavic(name) {
    auto a;
    auto b;
    auto r;
    r = 0;
    a = @8 *name;
    b = @8 *(name + 1);
    if a == 114 {                       // ru
        if b == 117 r = 1;
    }
    if a == 117 {                       // uk
        if b == 107 r = 1;
    }
    if a == 98 {                        // be
        if b == 101 r = 1;
    }
    r;
}

// tg_i18n_formname(f): 0 one, 1 few, 2 many, 3 other → литерал
tg_i18n_formname(f) {
    auto r;
    r = "other";
    if f == 0 r = "one";
    if f == 1 r = "few";
    if f == 2 r = "many";
    r;
}

// tg_i18n_form(name, n): номер формы для локали name:
//   славянские: n%10==1 && n%100!=11 → one; n%10 в 2..4 && n%100 не в
//   12..14 → few; иначе many. Прочие (en и др.): n==1 → one, иначе other.
tg_i18n_form(name, n) {
    auto r;
    auto n10;
    auto n100;
    r = 3;
    if tg_i18n_slavic(name) != 0 {
        n10 = n % 10;
        n100 = n % 100;
        r = 2;
        if n10 == 1 {
            if n100 != 11 r = 0;
        }
        if r == 2 {
            if n10 >= 2 {
                if n10 <= 4 {
                    if n100 >= 12 {
                        if n100 <= 14 {
                            r = 2;
                        } else {
                            r = 1;
                        }
                    } else {
                        r = 1;
                    }
                }
            }
        }
    } else {
        if n == 1 r = 0;
    }
    r;
}

// tg_i18n_form_try(key, loc, f): форма f ключа-объекта в локали loc →
// строка в scratch ядра или 0
tg_i18n_form_try(key, loc, f) {
    auto s;
    auto fn;
    auto r;
    r = 0;
    s = tg_i18n_raw_at(key, loc);
    if s != 0 {
        if @8 *s == 123 {
            fn = tg_i18n_formname(f);           // вложенный вызов — в локальную
            sprintf(&tg_i18n_pbuf, "%s.%s", key, fn);
            r = tg_get_str(tg_i18n_doc, &tg_i18n_pbuf);
        }
    }
    r;
}

// tg_i18n_plural_str(key, loc, f): нужная форма, иначе запасные
// other → many → one → few; 0 — ключ-объект не найден вовсе
tg_i18n_plural_str(key, loc, f) {
    auto s;
    s = tg_i18n_form_try(key, loc, f);
    if s == 0 s = tg_i18n_form_try(key, loc, 3);
    if s == 0 s = tg_i18n_form_try(key, loc, 2);
    if s == 0 s = tg_i18n_form_try(key, loc, 0);
    if s == 0 s = tg_i18n_form_try(key, loc, 1);
    s;
}

// ===== Загрузка каталога =====

// tg_i18n_reset(): освободить документы, обнулить состояние (внутренняя)
tg_i18n_reset() {
    auto i;
    i = 0;
    while i < tg_i18n_ndocs {
        tg_buf_free(&tg_i18n_docs + i * 24);
        i = i + 1;
    }
    tg_i18n_ndocs = 0;
    tg_i18n_nloc = 0;
    tg_i18n_cur = 0;
    tg_i18n_defidx = 0;
    tg_i18n_defok = 0;
    1;
}

// tg_i18n_readfile(path, slot): содержимое файла в Buf-слот; 1 — файл открыт
tg_i18n_readfile(path, slot) {
    auto f;
    auto ok;
    ok = 0;
    f = fopen(path, "r");
    if f != 0 {
        tg_buf_reset(slot);
        while fgets(&tg_i18n_rb2, 512, f) tg_buf_add(slot, &tg_i18n_rb2);
        fclose(f);
        ok = 1;
    }
    ok;
}

// tg_i18n_add_locale(name): зарегистрировать локаль → индекс или -1 (лимит 8)
tg_i18n_add_locale(name) {
    auto i;
    i = -1;
    if tg_i18n_nloc < 8 {
        strcpy(&tg_i18n_names + tg_i18n_nloc * 16, name);
        i = tg_i18n_nloc;
        tg_i18n_nloc = tg_i18n_nloc + 1;
    } else {
        printf("i18n: too many locales (8 max), skipped: %s\n", name);
    }
    i;
}

// tg_i18n_take_line(line): одна строка вывода ls — путь к *.json;
// имя локали = базовое имя без ".json"; файл становится документом локали
tg_i18n_take_line(line) {
    auto i;
    auto j;
    auto st;
    auto m;
    auto idx;
    auto ok;
    auto c;
    auto slot;
    auto p;
    i = strlen(line);
    if i > 0 {
        if @8 *(line + i - 1) == 10 i = i - 1;      // \n
    }
    if i > 0 {
        if @8 *(line + i - 1) == 13 i = i - 1;      // \r
    }
    *(line + i) !8 0;                              // путь без перевода строки
    ok = 0;
    if i >= 5 {
        if @8 *(line + i - 5) == 46 {               // ".json"
            if @8 *(line + i - 4) == 106 {
                if @8 *(line + i - 3) == 115 {
                    if @8 *(line + i - 2) == 111 {
                        if @8 *(line + i - 1) == 110 ok = 1;
                    }
                }
            }
        }
    }
    if ok != 0 {
        st = 0;
        j = 0;
        while j < i {
            if @8 *(line + j) == 47 st = j + 1;     // после последнего '/'
            j = j + 1;
        }
        m = (i - 5) - st;                           // длина имени локали
        if m > 0 {
            if m < 16 {
                j = 0;
                while j < m {
                    c = @8 *(line + st + j);
                    *(&tg_i18n_floc + j) !8 c;
                    j = j + 1;
                }
                *(&tg_i18n_floc + m) !8 0;
                if tg_i18n_ndocs < 16 {
                    slot = &tg_i18n_docs + tg_i18n_ndocs * 24;
                    tg_buf_init(slot);
                    if tg_i18n_readfile(line, slot) != 0 {
                        p = slot[0];
                        ok = 0;
                        if p != 0 {
                            p = tg_skipspace(p);
                            if @8 *p == 123 ok = 1;    // объект на входе
                        }
                        if ok != 0 {
                            // локаль регистрируется ТОЛЬКО с валидным файлом
                            idx = tg_i18n_find_loc(&tg_i18n_floc);
                            if idx == -1 idx = tg_i18n_add_locale(&tg_i18n_floc);
                            if idx != -1 {
                                tg_i18n_dloc[tg_i18n_ndocs] = idx;
                                tg_i18n_ndocs = tg_i18n_ndocs + 1;
                            } else {
                                tg_buf_free(slot);
                            }
                        } else {
                            printf("i18n: not a JSON object, skipped: %s\n", line);
                            tg_buf_free(slot);
                        }
                    }
                } else {
                    printf("i18n: too many locale files (16 max): %s\n", line);
                }
            } else {
                printf("i18n: locale name too long, skipped: %s\n", line);
            }
        }
    }
    1;
}

// ===== Публичный API =====

// tg_i18n_load(dir, default_locale): прочитать dir/*.json и включить локали
tg_i18n_load(dir, default_locale) {
    auto f;
    auto n;
    auto i;
    auto q;
    auto ok;
    tg_i18n_reset();
    ok = 0;
    if dir != 0 {
        n = strlen(dir);
        if n < 400 {
            q = 0;
            i = 0;
            while i < n {                     // ' в пути — инъекция в shell
                if @8 *(dir + i) == 39 q = 1;
                i = i + 1;
            }
            if q == 0 {
                sprintf(&tg_i18n_cmd, "ls -1 '%s'/*.json 2>/dev/null", dir);
                f = popen(&tg_i18n_cmd, "r");
                if f != 0 {
                    while fgets(&tg_i18n_rb, 512, f) tg_i18n_take_line(&tg_i18n_rb);
                    pclose(f);
                    if tg_i18n_ndocs > 0 {        // локаль есть только с файлом
                        tg_i18n_defidx = 0;
                        tg_i18n_defok = 0;
                        if default_locale != 0 {
                            i = tg_i18n_find_loc(default_locale);
                            if i != -1 {
                                tg_i18n_defidx = i;
                                tg_i18n_defok = 1;
                            } else {
                                printf("i18n: default locale not loaded: %s\n", default_locale);
                            }
                        }
                        tg_i18n_cur = tg_i18n_defidx;
                        ok = 1;
                    } else {
                        printf("i18n: no readable <locale>.json in %s\n", dir);
                    }
                }
            } else {
                printf("i18n: dir with ' is not allowed: %s\n", dir);
            }
        }
    }
    ok;
}

// tg_i18n_count(): число загруженных локалей
tg_i18n_count() {
    tg_i18n_nloc;
}

// tg_i18n_available(idx): имя idx-й локали или 0 (предел/нет такой)
tg_i18n_available(idx) {
    auto r;
    r = 0;
    if idx < tg_i18n_nloc r = &tg_i18n_names + idx * 16;
    r;
}

// tg_i18n_locale(): текущая локаль или 0 (ничего не загружено)
tg_i18n_locale() {
    auto r;
    r = 0;
    if tg_i18n_nloc > 0 r = &tg_i18n_names + tg_i18n_cur * 16;
    r;
}

// tg_i18n_set_locale(locale): включить загруженную локаль → 1/0
tg_i18n_set_locale(locale) {
    auto i;
    auto ok;
    ok = 0;
    i = tg_i18n_find_loc(locale);
    if i != -1 {
        tg_i18n_cur = i;
        ok = 1;
    }
    ok;
}

// tg_i18n_get(key): перевод текущей локали (статик-буфер) или сам key
tg_i18n_get(key) {
    auto s;
    auto r;
    s = tg_i18n_src(key);
    if s == 0 {
        r = key;
    } else {
        r = tg_i18n_putout(s);
    }
    r;
}

// tg_i18n_get_l(key, locale): перевод указанной локали (статик-буфер);
// локаль не загружена или ключа нет → сам key
tg_i18n_get_l(key, locale) {
    auto i;
    auto s;
    auto r;
    r = key;
    i = tg_i18n_find_loc(locale);
    if i != -1 {
        s = tg_i18n_str_at(key, i);
        if s != 0 r = tg_i18n_putout(s);
    }
    r;
}

// tg_i18n_fmt(key, a0, a1): перевод + подстановка {0}/{1} (статик-буфер);
// a0=0 → пусто вместо {0}, a1=0 → пусто вместо {1}
tg_i18n_fmt(key, a0, a1) {
    auto s;
    auto s0;
    auto s1;
    auto r;
    s = tg_i18n_src(key);
    if s == 0 s = key;
    s0 = a0;
    if s0 == 0 s0 = &tg_i18n_empty;
    s1 = a1;
    if s1 == 0 s1 = &tg_i18n_empty;
    r = tg_i18n_emit2(s, 48, s0, 49, s1);
    r;
}

// tg_i18n_nget(key, n): plural-перевод + подстановка {n} (статик-буфер);
// ключа нет → строка числа n
tg_i18n_nget(key, n) {
    auto raw;
    auto loc;
    auto f;
    auto s;
    auto r;
    sprintf(&tg_i18n_num, "%ld", n);
    raw = tg_i18n_raw_at(key, tg_i18n_cur);
    loc = tg_i18n_cur;
    if raw == 0 {
        if tg_i18n_defok != 0 {
            if tg_i18n_defidx != tg_i18n_cur {
                raw = tg_i18n_raw_at(key, tg_i18n_defidx);
                if raw != 0 loc = tg_i18n_defidx;
            }
        }
    }
    if raw == 0 {
        r = tg_i18n_putout(&tg_i18n_num);
    } else {
        if @8 *raw == 123 {
            f = tg_i18n_form(&tg_i18n_names + loc * 16, n);
            s = tg_i18n_plural_str(key, loc, f);
        } else {
            s = tg_get_str(tg_i18n_doc, key);
        }
        if s == 0 {
            r = tg_i18n_putout(&tg_i18n_num);
        } else {
            r = tg_i18n_emit2(s, 110, &tg_i18n_num, 0, 0);
        }
    }
    r;
}

// tg_i18n_from_user(lang_code): менеджер локалей — точное имя, затем язык
// до '-', иначе default; возвращает текущую локаль
tg_i18n_from_user(lang_code) {
    auto i;
    auto j;
    auto c;
    auto done;
    auto r;
    if lang_code == 0 {
        if tg_i18n_defok != 0 tg_i18n_cur = tg_i18n_defidx;
    } else {
        i = tg_i18n_find_loc(lang_code);
        if i == -1 {
            j = 0;
            done = 0;
            while done == 0 {
                c = @8 *(lang_code + j);
                if c == 0 done = 1;
                else if c == 45 done = 1;         // '-'
                else if j >= 15 done = 1;
                else {
                    *(&tg_i18n_pbuf + j) !8 c;
                    j = j + 1;
                }
            }
            *(&tg_i18n_pbuf + j) !8 0;
            i = tg_i18n_find_loc(&tg_i18n_pbuf);
        }
        if i != -1 {
            tg_i18n_cur = i;
        } else {
            if tg_i18n_defok != 0 tg_i18n_cur = tg_i18n_defidx;
        }
    }
    r = tg_i18n_locale();
    r;
}

// tg_i18n_bind_ctx(ctx): хук middleware — language_code из сырого апдейта
// ctx → tg_i18n_from_user; возвращает текущую локаль. Ограничение: пути
// message/edited_message/channel_post/callback_query/inline_query/
// my_chat_member/chat_join_request; для остальных kind локаль ставится
// вручную через tg_i18n_set_locale/tg_i18n_from_user в хендлере.
tg_i18n_bind_ctx(ctx) {
    auto upd;
    auto lang;
    auto r;
    lang = 0;
    upd = tg_raw(ctx);
    if upd != 0 {
        lang = tg_get_str(upd, "message.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "edited_message.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "channel_post.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "callback_query.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "inline_query.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "my_chat_member.from.language_code");
        if lang == 0 lang = tg_get_str(upd, "chat_join_request.from.language_code");
    }
    r = tg_i18n_from_user(lang);
    r;
}
