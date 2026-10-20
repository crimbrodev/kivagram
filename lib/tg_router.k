// lib/tg_router.k — V4-C: роутер/фильтры/middleware поверх lib/tg.k
// (карта aiogram router/filter/middlewares).
//
// Контракт (опирается на ядро V4: слот 18 state*, слот 19 cb_answered,
// хук tg_router_hook в tg_handle_update):
//   tg_router_new(name)            → роутер (указатель) или 0 (лимит 8)
//   tg_router_root(r)              → root-роутер глобально + включает хук
//                                    tg_router_hook = &tg_router_feed;
//                                    r=0 — снять root и хук (фолбэк tg_on_*)
//   tg_r_on(r, kind, filter, fn)   → регистрация хендлера fn(ctx): неноль =
//                                    handled (стоп), 0 — следующий хендлер.
//                                    kind 0-27 (см. tg_upd_kind), filter=0 —
//                                    без фильтра. Лимиты: ≤32 хендлера на
//                                    kind, ≤128 на роутер, kind >27 → 0.
//   tg_r_msg / tg_r_cb / tg_r_inline(r, filter, fn) — алиасы kind 1 (message
//     с текстом) / 3 (callback_query) / 8 (inline_query) по tg_upd_kind.
//   tg_mw(r, fn)                   → middleware fn(ctx): 0 = СТОП всего
//     роутера (feed → 0 → фолбэк на tg_on_* в ядре), неноль = продолжить.
//     Вызываются ПО ПОРЯДКУ регистрации ПЕРЕД хендлерами kind. ≤8 на роутер.
//   tg_router_feed(upd, ctx)       → 1 если handled; порядок: mw-цепочка →
//     хендлеры своего kind по порядку → первый вернувший неноль стоппит.
//     Вызывается ЯДРОМ из tg_handle_update через tg_router_hook (вызов
//     указателя с 2 аргументами — как у хендлеров-указателей ядра, обёртка
//     не нужна), либо вручную (симуляция диспатча).
//   tg_router_autoanswer(on)       → глобальный флаг: при handled kind 3
//     (callback_query) и слоте 19 ctx == 0 — tg_answer(ctx, "") (пустой
//     answerCallbackQuery); слот 19 ставит tg_answer.
//
// Фильтры (объект = структура 6 слов в статик-пуле ≤64, возврат — указатель):
//   tg_f_cmd(name)          — tg_text(ctx): "/name" или "/name@bot" (первое
//     слово, case-insensitive); при срабатывании аргументы (всё после имени,
//     пробелы trimmed) копируются в статик-буфер; tg_cmd_args(ctx) → строка
//     аргументов или 0 (последний сработавший разбор).
//   tg_f_state(s)           — tg_state(ctx) (слот 18) побайтово == s
//   tg_f_state_any()        — всегда истинен (any-state)
//   tg_f_text_eq/start/contains(s) — по tg_text(ctx)
//   tg_f_from(user_id)      — tg_from_id(ctx) == user_id
//   tg_f_chat_type(t)       — chat.type ("private"/"group"/"supergroup"/
//     "channel") из сырого апдейта по префиксу kind (см. tg_r_prefix)
//   tg_f_and(a,b) / tg_f_or(a,b) / tg_f_not(a) — комбинаторы (новые объекты)
//   Магия: tg_ff_path("text"|"caption"|"data"|"chat_id"|"from_id") и шорт-hands
//     tg_ff_text()/tg_ff_caption()/tg_ff_data()/tg_ff_chat_id()/tg_ff_from_id();
//     затем цепочкой tg_ff_eq(v) / tg_ff_start(p) / tg_ff_contains(s) /
//     tg_ff_in(json_array) / tg_ff_len(n) — КАЖДЫЙ возвращает ТОТ ЖЕ объект.
//     Одна цепочка = одно условие (последний вызов условия перезаписывает).
//     Для chat_id/from_id (числовые пути) eq/in сравнивают ЧЕРЕЗ %ld-строку —
//     "055" != "55" не бывает: число форматируется и сравнивается побайтово.
//     caption/chat.type берутся из tg_raw(ctx) по префиксу kind.
//
// Отклонения/примечания:
//  - kind callback_query в tg_upd_kind = 3 (не 5: 5 — channel_post), поэтому
//    tg_r_cb и авто-ответ работают с kind 3.
//  - tg_answer_cb (lib/tg_ext.k) НЕ ставит слот 19 — файл чужой волны;
//    авто-ответ может продублировать answerCallbackQuery, если хендлер
//    ответил именно им (tg_answer ядра слот ставит).

extern strcmp
extern strlen
extern strtoull
extern sprintf

// ===== Реестры (статика) =====
tg_rr_cnt;             // число роутеров (лимит 8)
tg_rr_root;            // root-роутер (0 — нет)
tg_rr_auto;            // авто-ответ на callback_query (0/1)
tg_rr_pool[64];        // 8 роутеров × 8 слов: 0 idx, 1 name*, 2 hlen, 3 mlen
tg_rh[4096];           // 8 × 128 хендлеров × 4 слова (запись 32 байта)
tg_rm[64];             // 8 × 8 middleware (запись 8 байт)
tg_fp[384];            // 64 фильтра × 6 слов (объект 48 байт)
tg_fp_cnt;             // использовано фильтров
tg_cmd_argsbuf[512];   // 4 КБ — аргументы последней сработавшей tg_f_cmd
tg_cmd_args_ok;        // 1 — в буфере есть валидные args
tg_r_pathbuf[64];      // 512 байт — dot-path "<pre>.caption"/"<pre>.chat.type"
tg_r_numbuf[32];       // 256 байт — "%ld" числового пути для string-условий

// ===== Строковые помощники =====

// tg_streq(a, b): побайтовое равенство двух ненулевых C-строк
tg_streq(a, b) {
    auto ok;
    auto i;
    auto c;
    ok = 0;
    if a != 0 {
        if b != 0 {
            ok = 1;
            i = 0;
            while 1 {
                c = @8 *(a+i);
                if c != @8 *(b+i) ok = 0;
                if c == 0 break;
                i = i + 1;
            }
        }
    }
    ok;
}

// tg_str_start(s, p): s начинается с префикса p
tg_str_start(s, p) {
    auto ok;
    auto i;
    auto c;
    ok = 1;
    if s == 0 ok = 0;
    if p == 0 ok = 0;
    i = 0;
    while ok != 0 {
        c = @8 *(p+i);
        if c == 0 break;
        if @8 *(s+i) != c ok = 0;
        i = i + 1;
    }
    ok;
}

// tg_str_has(s, sub): sub содержится в s
tg_str_has(s, sub) {
    auto ok;
    auto i;
    auto j;
    auto c;
    ok = 0;
    if s != 0 {
        if sub != 0 {
            i = 0;
            while ok == 0 {
                c = @8 *(s+i);
                if c == 0 break;
                j = 0;
                while 1 {
                    if @8 *(sub+j) == 0 {
                        ok = 1;
                        break;
                    }
                    if @8 *(s+i+j) != @8 *(sub+j) break;
                    j = j + 1;
                }
                i = i + 1;
            }
        }
    }
    ok;
}

// tg_r_prefix(ctx): префикс payload-путей апдейта по kind (как pre в
// tg_ctx_build; kind 3 — callback_query с вложенными message.*)
tg_r_prefix(ctx) {
    auto kind;
    auto pre;
    kind = tg_kind(ctx);
    pre = "message";
    if kind == 3 pre = "callback_query.message";
    if kind == 4 pre = "edited_message";
    if kind == 5 {
        pre = "channel_post";
        if tg_get(tg_raw(ctx), "channel_post") == 0 pre = "edited_channel_post";
    }
    if kind == 6 pre = "my_chat_member";
    if kind == 7 pre = "chat_join_request";
    if kind == 8 pre = "inline_query";
    if kind == 9 pre = "pre_checkout_query";
    if kind == 10 pre = "shipping_query";
    if kind == 11 pre = "business_message";
    if kind == 12 pre = "edited_business_message";
    if kind == 13 pre = "business_connection";
    if kind == 14 pre = "deleted_business_messages";
    if kind == 15 pre = "guest_message";
    if kind == 16 pre = "message_reaction";
    if kind == 17 pre = "message_reaction_count";
    if kind == 18 pre = "chosen_inline_result";
    if kind == 19 pre = "purchased_paid_media";
    if kind == 20 pre = "poll";
    if kind == 21 pre = "poll_answer";
    if kind == 22 pre = "chat_member";
    if kind == 23 pre = "chat_boost";
    if kind == 24 pre = "removed_chat_boost";
    if kind == 25 pre = "managed_bot";
    if kind == 26 pre = "subscription";
    if kind == 27 pre = "stopped_message_generation";
    pre;
}

// ===== Пул фильтров =====
// Объект (6 слов): 0 type, 1 a, 2 b, 3 c, 4-5 резерв.
// Типы: 1 cmd(имя*), 2 state(str*), 3 state_any, 4 text_eq(s*),
// 5 text_start(p*), 6 text_contains(s*), 7 magic(pathid, cond, val*|n),
// 8 and(f1*, f2*), 9 or(f1*, f2*), 10 not(f1*), 11 from(uid),
// 12 chat_type(str*).
// magic cond: 1 eq, 2 start, 3 contains, 4 in(json_array*), 5 len(n).
// magic pathid: 1 text, 2 caption, 3 data, 4 chat_id, 5 from_id.

// tg_f_new(): нулевой объект из пула или 0 (лимит 64)
tg_f_new() {
    auto p;
    p = 0;
    if tg_fp_cnt < 64 {
        p = &tg_fp + tg_fp_cnt * 48;
        p[0] = 0;
        p[1] = 0;
        p[2] = 0;
        p[3] = 0;
        p[4] = 0;
        p[5] = 0;
        tg_fp_cnt = tg_fp_cnt + 1;
    }
    p;
}

// ===== Конструкторы фильтров =====

tg_f_cmd(name) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 1;
        p[1] = name;
    }
    p;
}

tg_f_state(state) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 2;
        p[1] = state;
    }
    p;
}

tg_f_state_any() {
    auto p;
    p = tg_f_new();
    if p != 0 p[0] = 3;
    p;
}

tg_f_text_eq(s) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 4;
        p[1] = s;
    }
    p;
}

tg_f_text_start(s) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 5;
        p[1] = s;
    }
    p;
}

tg_f_text_contains(s) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 6;
        p[1] = s;
    }
    p;
}

tg_f_and(a, b) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 8;
        p[1] = a;
        p[2] = b;
    }
    p;
}

tg_f_or(a, b) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 9;
        p[1] = a;
        p[2] = b;
    }
    p;
}

tg_f_not(a) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 10;
        p[1] = a;
    }
    p;
}

tg_f_from(user_id) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 11;
        p[1] = user_id;
    }
    p;
}

tg_f_chat_type(t) {
    auto p;
    p = tg_f_new();
    if p != 0 {
        p[0] = 12;
        p[1] = t;
    }
    p;
}

// tg_ff_path(name): магический путь "text"|"caption"|"data"|"chat_id"|
// "from_id" → объект; неизвестное имя → pathid 0 (фильтр никогда не пройдёт)
tg_ff_path(name) {
    auto p;
    auto id;
    id = 0;
    if strcmp(name, "text") == 0 id = 1;
    if strcmp(name, "caption") == 0 id = 2;
    if strcmp(name, "data") == 0 id = 3;
    if strcmp(name, "chat_id") == 0 id = 4;
    if strcmp(name, "from_id") == 0 id = 5;
    p = tg_f_new();
    if p != 0 {
        p[0] = 7;
        p[1] = id;
    }
    p;
}

tg_ff_text() { tg_ff_path("text"); }
tg_ff_caption() { tg_ff_path("caption"); }
tg_ff_data() { tg_ff_path("data"); }
tg_ff_chat_id() { tg_ff_path("chat_id"); }
tg_ff_from_id() { tg_ff_path("from_id"); }

// tg_ff_eq/start/contains/in/len(f, ...): условие в объект f, возврат — f
// (цепочка: tg_ff_eq(tg_ff_text(), "hi"))
tg_ff_eq(f, v) {
    if f != 0 {
        f[2] = 1;
        f[3] = v;
    }
    f;
}

tg_ff_start(f, p) {
    if f != 0 {
        f[2] = 2;
        f[3] = p;
    }
    f;
}

tg_ff_contains(f, s) {
    if f != 0 {
        f[2] = 3;
        f[3] = s;
    }
    f;
}

tg_ff_in(f, arr) {
    if f != 0 {
        f[2] = 4;
        f[3] = arr;
    }
    f;
}

tg_ff_len(f, n) {
    if f != 0 {
        f[2] = 5;
        f[3] = n;
    }
    f;
}

// ===== Эвалюция фильтров =====

// tg_r_path_str(ctx, pathid): строковое значение магического пути или 0
// (caption — из tg_raw по префиксу kind, в scratch; использовать сразу)
tg_r_path_str(ctx, pathid) {
    auto r;
    r = 0;
    if pathid == 1 r = tg_text(ctx);
    if pathid == 2 {
        sprintf(&tg_r_pathbuf, "%s.caption", tg_r_prefix(ctx));
        r = tg_get_str(tg_raw(ctx), &tg_r_pathbuf);
    }
    if pathid == 3 r = tg_data(ctx);
    r;
}

// tg_r_elem_eq(elem, s, isnum, num): элемент сырого JSON-МАССИВА == значению:
// строковый элемент — побайтово до закрывающей кавычки; числовой (isnum) —
// через strtoull против num; иначе — сырые байты до разделителя против s
tg_r_elem_eq(elem, s, isnum, num) {
    auto ok;
    auto c;
    auto i;
    ok = 0;
    if elem != 0 {
        if @8 *elem == 34 {
            i = 1;
            ok = 1;
            while 1 {
                c = @8 *(elem+i);
                if c == 34 {
                    if @8 *(s+i-1) != 0 ok = 0;
                    break;
                }
                if c == 0 {
                    ok = 0;
                    break;
                }
                if c != @8 *(s+i-1) ok = 0;
                i = i + 1;
            }
        } else {
            if isnum != 0 {
                if strtoull(elem, 0, 10) == num ok = 1;
            } else {
                i = 0;
                ok = 1;
                while 1 {
                    c = @8 *(elem+i);
                    if c == 44 break;
                    if c == 93 break;
                    if c == 0 break;
                    if c != @8 *(s+i) ok = 0;
                    i = i + 1;
                }
                if @8 *(s+i) != 0 ok = 0;
            }
        }
    }
    ok;
}

// tg_ff_eval(f, ctx): магический фильтр (type 7)
tg_ff_eval(f, ctx) {
    auto pathid;
    auto cond;
    auto val;
    auto ok;
    auto v;
    auto n;
    auto i;
    auto num;
    auto elem;
    ok = 0;
    pathid = f[1];
    cond = f[2];
    val = f[3];
    num = 0;
    if pathid == 4 num = tg_chat_id(ctx);
    if pathid == 5 num = tg_from_id(ctx);
    if pathid >= 4 {
        sprintf(&tg_r_numbuf, "%ld", num);
        v = &tg_r_numbuf;
    } else {
        v = tg_r_path_str(ctx, pathid);
    }
    if v != 0 {
        if cond == 1 ok = tg_streq(v, val);
        if cond == 2 ok = tg_str_start(v, val);
        if cond == 3 ok = tg_str_has(v, val);
        if cond == 4 {
            i = 0;
            while 1 {
                elem = tg_arrelt(val, i);
                if elem == 0 break;
                if tg_r_elem_eq(elem, v, pathid >= 4, num) ok = 1;
                i = i + 1;
            }
        }
        if cond == 5 {
            n = strlen(v);
            if n == val ok = 1;
        }
    }
    ok;
}

// tg_r_cmd_ok(f, ctx): фильтр команды — первое слово tg_text == "/name"
// или "/name@bot" (ASCII-case-insensitive); при срабатывании аргументы
// (всё после имени, пробелы trimmed) — в tg_cmd_argsbuf
tg_r_cmd_ok(f, ctx) {
    auto s;
    auto name;
    auto i;
    auto j;
    auto c;
    auto n;
    auto ok;
    auto done;
    auto p;
    s = tg_text(ctx);
    ok = 0;
    if s != 0 {
        if @8 *s == 47 {
            name = f[1];
            i = 0;
            ok = 1;
            done = 0;
            while done == 0 {
                n = @8 *(name+i);
                c = @8 *(s+1+i);
                if n > 64 {
                    if n < 91 n = n + 32;
                }
                if c > 64 {
                    if c < 91 c = c + 32;
                }
                if n == 0 {
                    // имя кончилось — c обязан быть разделителем
                    // (0 конец / 32 пробел / 64 @bot), иначе это другое слово
                    done = 1;
                    if c != 0 {
                        if c != 32 {
                            if c != 64 ok = 0;
                        }
                    }
                } else {
                    if c != n ok = 0;
                    i = i + 1;
                }
                if c == 0 done = 1;
            }
            if ok != 0 {
                // c — разделитель: 0 (конец), 32 (пробел), 64 (@bot);
                // пропуск "@botusername" и пробелов перед аргументами
                p = s + 1 + i;
                done = 0;
                while done == 0 {
                    if @8 *p == 32 done = 1;
                    else if @8 *p == 0 done = 1;
                    else p = p + 1;
                }
                while @8 *p == 32 p = p + 1;
                j = 0;
                while j < 511 {
                    c = @8 *p;
                    if c == 0 break;
                    *(&tg_cmd_argsbuf + j) !8 c;
                    j = j + 1;
                    p = p + 1;
                }
                done = 0;
                while done == 0 {
                    if j == 0 done = 1;
                    else if @8 *(&tg_cmd_argsbuf + j - 1) != 32 done = 1;
                    else j = j - 1;
                }
                *(&tg_cmd_argsbuf + j) !8 0;
                tg_cmd_args_ok = 1;
            }
        }
    }
    ok;
}

// tg_cmd_args(ctx): аргументы последней сработавшей tg_f_cmd или 0
tg_cmd_args(ctx) {
    auto r;
    r = 0;
    if tg_cmd_args_ok != 0 r = &tg_cmd_argsbuf;
    r;
}

// tg_f_eval(f, ctx): 1 — фильтр прошёл (комбинаторы рекурсивны)
tg_f_eval(f, ctx) {
    auto t;
    auto ok;
    auto a;
    auto b;
    ok = 0;
    a = 0;
    b = 0;
    if f != 0 {
        t = f[0];
        if t == 1 ok = tg_r_cmd_ok(f, ctx);
        if t == 2 {
            a = f[1];
            if a != 0 ok = tg_streq(tg_state(ctx), a);
        }
        if t == 3 ok = 1;
        if t == 4 ok = tg_streq(tg_text(ctx), f[1]);
        if t == 5 ok = tg_str_start(tg_text(ctx), f[1]);
        if t == 6 ok = tg_str_has(tg_text(ctx), f[1]);
        if t == 7 ok = tg_ff_eval(f, ctx);
        if t == 8 {
            a = tg_f_eval(f[1], ctx);
            if a != 0 b = tg_f_eval(f[2], ctx);
            if b != 0 ok = 1;
        }
        if t == 9 {
            a = tg_f_eval(f[1], ctx);
            if a == 0 b = tg_f_eval(f[2], ctx);
            if a != 0 ok = 1;
            if b != 0 ok = 1;
        }
        if t == 10 {
            a = tg_f_eval(f[1], ctx);
            if a == 0 ok = 1;
        }
        if t == 11 ok = tg_from_id(ctx) == f[1];
        if t == 12 {
            sprintf(&tg_r_pathbuf, "%s.chat.type", tg_r_prefix(ctx));
            ok = tg_streq(tg_get_str(tg_raw(ctx), &tg_r_pathbuf), f[1]);
        }
    }
    ok;
}

// ===== Реестр роутеров =====

// tg_router_new(name): новый роутер или 0 (лимит 8)
tg_router_new(name) {
    auto r;
    auto i;
    r = 0;
    if tg_rr_cnt < 8 {
        i = tg_rr_cnt;
        r = &tg_rr_pool + i * 64;
        *r = i;
        r[1] = name;
        r[2] = 0;
        r[3] = 0;
        tg_rr_cnt = tg_rr_cnt + 1;
    }
    r;
}

// tg_r_on(r, kind, filter, fn): хендлер fn(ctx) на kind; неноль-возврат fn =
// handled (стоп). 1 — ок, 0 — отклонено (лимиты/неверный kind/r=0)
tg_r_on(r, kind, filter, fn) {
    auto idx;
    auto hlen;
    auto e;
    auto i;
    auto cnt;
    auto ok;
    ok = 0;
    if r != 0 {
        if kind < 28 {
            idx = *r;
            hlen = r[2];
            if hlen < 128 {
                cnt = 0;
                i = 0;
                while i < hlen {
                    e = &tg_rh + idx * 4096 + i * 32;
                    if e[0] == kind cnt = cnt + 1;
                    i = i + 1;
                }
                if cnt < 32 {
                    e = &tg_rh + idx * 4096 + hlen * 32;
                    e[0] = kind;
                    e[1] = filter;
                    e[2] = fn;
                    r[2] = hlen + 1;
                    ok = 1;
                }
            }
        }
    }
    ok;
}

// алиасы (kind по tg_upd_kind): 1 = message.text, 3 = callback_query,
// 8 = inline_query
tg_r_msg(r, filter, fn) { tg_r_on(r, 1, filter, fn); }
tg_r_cb(r, filter, fn) { tg_r_on(r, 3, filter, fn); }
tg_r_inline(r, filter, fn) { tg_r_on(r, 8, filter, fn); }

// tg_mw(r, fn): middleware fn(ctx) — 0 = стоп роутера (feed → 0)
tg_mw(r, fn) {
    auto idx;
    auto n;
    auto ok;
    ok = 0;
    if r != 0 {
        n = r[3];
        if n < 8 {
            idx = *r;
            *(&tg_rm + idx * 64 + n * 8) = fn;
            r[3] = n + 1;
            ok = 1;
        }
    }
    ok;
}

// ===== Feed =====

// tg_router_feed(upd, ctx): mw-цепочка → хендлеры kind → авто-ответ;
// 1 = handled, 0 = идти в tg_on_* (ядро) / ничего (ручной вызов)
tg_router_feed(upd, ctx) {
    auto r;
    auto idx;
    auto kind;
    auto i;
    auto n;
    auto e;
    auto fp;
    auto rr;
    auto stop;
    auto res;
    auto ok;
    auto filt;
    res = 0;
    r = tg_rr_root;
    if r != 0 {
        idx = *r;
        kind = tg_kind(ctx);
        stop = 0;
        n = r[3];
        i = 0;
        while i < n {
            if stop == 0 {
                fp = *(&tg_rm + idx * 64 + i * 8);
                if fp != 0 {
                    rr = fp(ctx);
                    if rr == 0 stop = 1;
                }
            }
            i = i + 1;
        }
        if stop == 0 {
            n = r[2];
            i = 0;
            while i < n {
                if res == 0 {
                    e = &tg_rh + idx * 4096 + i * 32;
                    if e[0] == kind {
                        ok = 1;
                        filt = e[1];
                        if filt != 0 ok = tg_f_eval(filt, ctx);
                        if ok != 0 {
                            fp = e[2];
                            rr = fp(ctx);
                            if rr != 0 res = 1;
                        }
                    }
                }
                i = i + 1;
            }
        }
        if res == 1 {
            if tg_rr_auto != 0 {
                if kind == 3 {
                    if tg_cb_answered(ctx) == 0 tg_answer(ctx, "");
                }
            }
        }
    }
    res;
}

// tg_router_root(r): root-роутер глобально + хук ядра; r=0 — снять
tg_router_root(r) {
    tg_rr_root = r;
    if r == 0 {
        tg_router_hook = 0;
    } else {
        tg_router_hook = &tg_router_feed;
    }
    tg_rr_root;
}

// tg_router_autoanswer(on): флаг авто-ответа на callback_query
tg_router_autoanswer(on) {
    tg_rr_auto = 0;
    if on != 0 tg_rr_auto = 1;
    tg_rr_auto;
}
