// lib/tg_fsm.k — V4-A: машина состояний поверх lib/tg_kv.k (по карте aiogram fsm/).
// FSM НЕ трогает lib/tg.k — только читает контракт ядра.
//
// Ключи поверх KV (scope/стратегия):
//   global (ДЕФОЛТ, как aiogram FSMStrategy.GLOBAL):
//     state-ключ `fsm:<user_id>`, data — `fsm:<user_id>#data`.
//   isolated:
//     state-ключ `fsm:<chat_id>:<user_id>`, data — `...#data`.
//   Переключение: tg_fsm_strategy(isolated) — 1=isolated, 0=global; глобальный
//   флаг, можно ставить до/после открытия бота.
//
// Публичный API (контракт для ядра/роутера):
//   tg_fsm_strategy(isolated)               → новый флаг (1/0)
//   tg_fsm_state(chat_id, user_id)          → "Group:state" в общем KV-буфере
//                                              или 0 (нет состояния/бэкенда)
//   tg_fsm_set(chat_id, user_id, state)     → state=0 стирает состояние
//                                              (DATA остаётся, как set_state(None)
//                                              в aiogram), иначе upsert; 1/0
//   tg_fsm_data(chat_id, user_id)           → JSON-строка (KV-буфер) или 0
//   tg_fsm_set_data(chat_id, user_id, json) → json=0 стирает data; 1/0
//   tg_fsm_update_data(chat_id, user_id, json) — shallow-merge объектов:
//                                              существующий + новый, ключи
//                                              нового перезаписывают; json=0
//                                              стирает data; 1/0
//   tg_fsm_clear(chat_id, user_id)          → state+data, всегда 1 (идемпотентна)
//   tg_fsm_fill(ctx)                        → tg_fsm_state(tg_chat_id(ctx),
//                                              tg_from_id(ctx)) — хелпер для
//                                              роутера следующей волны (акcессоры
//                                              ctx — из ядра: tg_chat_id/tg_from_id)
//
// Жизнь указателей: state/data возвращают слот-кэш KV — указатель валиден
// только до следующего вызова tg_kv_get/set/del/close или любого tg_fsm_*,
// который читает KV. json для set_data/update_data — независимая строка (не
// указатель из tg_fsm_data/tg_kv_get): update_data сначала копирует json в
// свой буфер, но set_data передаёт его в bind напрямую.
//
// Лимиты: shallow-merge копирует вложения как есть (tg_skipval из ядра);
// результат merge ограничен буфером ~32 КБ (при переполнении — усечение).
// Вложенные функции ядра (tg_skipspace/tg_skipstr/tg_skipval/tg_find_key)
// переиспользуются, ничего не меняя.

extern sprintf

tg_fsm_iso;            // 0 = global (дефолт), 1 = isolated
tg_fsm_keybuf[64];     // 512 байт — рабочий ключ (state или data)
tg_fsm_acc[4096];      // 32 КБ — аккумулятор shallow-merge
tg_fsm_accpos;         // позиция в аккумуляторе (байт)
tg_fsm_first;          // уже дописана первая запись merge (запятая)
tg_fsm_js[4096];       // 32 КБ — копия json-аргументa update_data

// ===== Ключи scope =====

// tg_fsm_state_key(chat, user): "fsm:<user>" или "fsm:<chat>:<user>" → &keybuf
tg_fsm_state_key(chat, user) {
    if tg_fsm_iso != 0 {
        sprintf(&tg_fsm_keybuf, "fsm:%ld:%ld", chat, user);
    } else {
        sprintf(&tg_fsm_keybuf, "fsm:%ld", user);
    }
    &tg_fsm_keybuf;
}

// tg_fsm_data_key(chat, user): то же + "#data" → &keybuf
tg_fsm_data_key(chat, user) {
    if tg_fsm_iso != 0 {
        sprintf(&tg_fsm_keybuf, "fsm:%ld:%ld#data", chat, user);
    } else {
        sprintf(&tg_fsm_keybuf, "fsm:%ld#data", user);
    }
    &tg_fsm_keybuf;
}

// ===== Аккумулятор merge =====

// tg_fsm_ab(c): дописать байт в аккумулятор (отсечка на ~32 КБ)
tg_fsm_ab(c) {
    if tg_fsm_accpos < 32700 {
        *(&tg_fsm_acc + tg_fsm_accpos) !8 c;
        tg_fsm_accpos = tg_fsm_accpos + 1;
    }
    1;
}

// tg_fsm_as(s): дописать C-строку в аккумулятор
tg_fsm_as(s) {
    auto i;
    i = 0;
    while @8 *(s+i) {
        tg_fsm_ab(@8 *(s+i));
        i = i + 1;
    }
    1;
}

// tg_fsm_merge_obj(obj, other, onlymiss): obj/other — на '{'; дописать
// записи obj сырым текстом в аккумулятор; onlymiss=1 → только те, чьего
// ключа нет в other (shallow: новый объект забирает свои ключи).
tg_fsm_merge_obj(obj, other, onlymiss) {
    auto p;
    auto e;
    auto v;
    auto ve;
    auto m;
    auto stop;
    auto emit;
    p = tg_skipspace(obj + 1);
    stop = 0;
    while stop == 0 {
        if @8 *p == 34 {
            e = tg_skipstr(p);          // за закрывающей кавычкой ключа
            m = e - p - 2;              // длина ключа
            v = tg_skipspace(e);
            if @8 *v == 58 {
                v = tg_skipspace(v + 1);
                ve = tg_skipval(v);     // за значением (вложенные {} [] свои)
                emit = 1;
                if onlymiss != 0 {
                    if tg_find_key(other, p + 1, m) != 0 emit = 0;
                }
                if emit == 1 {
                    if tg_fsm_first == 0 tg_fsm_ab(44);
                    tg_fsm_first = 0;
                    while p != ve {
                        tg_fsm_ab(@8 *p);
                        p = p + 1;
                    }
                }
                p = tg_skipspace(ve);
                if @8 *p == 44 p = tg_skipspace(p + 1);
            } else {
                stop = 1;
            }
        } else {
            stop = 1;
        }
        if @8 *p == 0 stop = 1;
    }
    1;
}

// ===== Публичный API =====

// tg_fsm_strategy(isolated): 1 = isolated, 0 = global (дефолт)
tg_fsm_strategy(isolated) {
    tg_fsm_iso = 0;
    if isolated != 0 tg_fsm_iso = 1;
    tg_fsm_iso;
}

// tg_fsm_state(chat, user): "Group:state" (слот-кэш KV) или 0
tg_fsm_state(chat, user) {
    auto k;
    auto r;
    k = tg_fsm_state_key(chat, user);
    r = tg_kv_get(k);
    r;
}

// tg_fsm_set(chat, user, state): state=0 → стереть состояние (data остаётся)
tg_fsm_set(chat, user, state) {
    auto k;
    auto ok;
    k = tg_fsm_state_key(chat, user);
    if state == 0 {
        ok = tg_kv_del(k);
    } else {
        ok = tg_kv_set(k, state);
    }
    ok;
}

// tg_fsm_data(chat, user): JSON-строка (слот-кэш KV) или 0
tg_fsm_data(chat, user) {
    auto k;
    auto r;
    k = tg_fsm_data_key(chat, user);
    r = tg_kv_get(k);
    r;
}

// tg_fsm_set_data(chat, user, json): json=0 → стереть data
tg_fsm_set_data(chat, user, json) {
    auto k;
    auto ok;
    k = tg_fsm_data_key(chat, user);
    if json == 0 {
        ok = tg_kv_del(k);
    } else {
        ok = tg_kv_set(k, json);
    }
    ok;
}

// tg_fsm_update_data(chat, user, json): shallow-merge существующего объекта
// с новым (ключи нового перезаписывают, вложения копируются как есть).
// json=0 → стереть data. 1 — ок, 0 — ошибка KV.
tg_fsm_update_data(chat, user, json) {
    auto dk;
    auto ex;
    auto nj;
    auto ok;
    auto i;
    auto c;
    auto last;
    auto exs;
    auto njs;
    dk = tg_fsm_data_key(chat, user);
    if json == 0 {
        ok = tg_kv_del(dk);
    } else {
        // копия json ВНЕ KV-буфера (побайтово): ex = tg_kv_get ниже затирает
        // слот-кэш, а json может указывать туда же (вызвали tg_fsm_data
        // прямо перед merge)
        i = 0;
        c = 1;
        while c != 0 {
            if i >= 32700 {
                c = 0;
            } else {
                c = @8 *(json + i);
                *(&tg_fsm_js + i) !8 c;
                i = i + 1;
            }
        }
        if i >= 32700 {
            last = 32699;                // отсечка длинного json + NUL
            *(&tg_fsm_js + last) !8 0;
        }
        nj = &tg_fsm_js;
        ex = tg_kv_get(dk);
        if ex == 0 {
            ok = tg_kv_set(dk, nj);
        } else {
            exs = tg_skipspace(ex);
            njs = tg_skipspace(nj);
            if @8 *exs != 123 {
                ok = tg_kv_set(dk, nj);   // старое не объект — заменить
            } else if @8 *njs != 123 {
                ok = tg_kv_set(dk, nj);   // новый не объект — заменить
            } else {
                tg_fsm_accpos = 0;
                tg_fsm_first = 1;
                tg_fsm_ab(123);               // {
                tg_fsm_merge_obj(exs, njs, 1); // из старого — чьих ключей нет в новом
                tg_fsm_merge_obj(njs, exs, 0); // из нового — все
                tg_fsm_ab(125);               // }
                *(&tg_fsm_acc + tg_fsm_accpos) !8 0;   // NUL-терминатор
                ok = tg_kv_set(dk, &tg_fsm_acc);
            }
        }
    }
    ok;
}

// tg_fsm_clear(chat, user): state + data; всегда 1 (идемпотентна)
tg_fsm_clear(chat, user) {
    auto k;
    k = tg_fsm_state_key(chat, user);
    tg_kv_del(k);
    k = tg_fsm_data_key(chat, user);
    tg_kv_del(k);
    1;
}

// tg_fsm_fill(ctx): хелпер для роутера — состояние из ctx ядра
// (tg_chat_id/tg_from_id — аксессоры Context в lib/tg.k).
tg_fsm_fill(ctx) {
    auto r;
    r = tg_fsm_state(tg_chat_id(ctx), tg_from_id(ctx));
    r;
}
