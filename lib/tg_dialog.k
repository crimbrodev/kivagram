// lib/tg_dialog.k — V5-B: диалоги поверх FSM (карта aiogram_dialogs Tishka17).
// НЕ трогает ядро/FSM/KV/роутер — только читает их контракт:
//   tg_fsm_state/set/data/set_data (состояние "Group:state", data — JSON),
//   tg_json-парсер ядра (tg_find/tg_get_str/tg_skipval/tg_find_key/...),
//   tg_send_to/tg_edit_text/tg_answer + extras (tg_ex_json → reply_markup),
//   tg_router: регистрация tg_r_msg/tg_r_cb пользователем, tg_text/tg_data/
//   tg_chat_id/tg_from_id — аксессоры ctx.
//
// ИДЕЯ (как aiogram-диалог с DEFAULT_STACK): диалог = FSM-группа + окна + стек
// в tg_fsm data. Один стек на user+chat:
//   {"stack":[{"i":<intent>,"s":"Group:state","d":{start_data},
//              "dd":{dialog_data}}, ...], "mid":<last_message_id>}
//   i    — intent последнего показа (клик со старым intent гасится);
//   s    — состояние FSM текущего окна;
//   d    — данные старта диалога ({start.<k>} в тексте окна);
//   dd   — dialog_data окна ({dialog_data.<k>}), merge через tg_dlg_update;
//   mid  — последнее сообщение окна: есть → editMessageText, нет → sendMessage.
// Стек читается ядерным tg_json-парсером; запись/мутации — своя сборка строк
// через аккумулятор (побайтовая копия сырых элементов JSON).
//
// Публичный API (реестр ≤8 диалогов, ≤16 окон на диалог, стек ≤10; ≤6 арг):
// Регистрация:
//   tg_dialog_new(group)            → диалог-указатель или 0 (лимит 8);
//                                     group — имя FSM-группы ("OrderSG").
//   tg_dg_window(dlg, tail, text, kbd) — окно: tail — хвост состояния
//                                     ("first" → "OrderSG:first"); text —
//                                     шаблон с {dialog_data.<k>}/{start.<k>}/
//                                     {getter.<k>}; kbd — сырой JSON
//                                     reply_markup (0 — без клавиатуры);
//                                     дубликат (dlg, tail) перезаписывается.
//   tg_dg_on_start(dlg, fn)        — fn(dlg_ctx) при tg_dlg_start.
//   tg_dg_on_close(dlg, fn)        — fn(dlg_ctx) при tg_dlg_done (result —
//                                     слот 9 dlg_ctx).
//   tg_dg_getter(dlg, fn)          — fn(dlg_ctx) → JSON-строка сквозных
//                                     данных рендера ({getter.<k>}).
//   tg_dg_button(dlg, tail, btn_id, text)     — кнопка-событие (текущий ряд).
//   tg_dg_button_go(dlg, tail, btn_id, text, go_tail) — кнопка-переход.
//   tg_dg_on_click(dlg, tail, btn_id, fn)     — custom-обработчик кнопки
//                                     (найдена → замена, нет → создание).
//   tg_dg_on_text(dlg, tail, fn)   — текстовый ввод состояния: fn(dlg_ctx)
//                                     (tg_text(ctx) — через слот 6 text_ctx);
//                                     1 = показать окно заново.
//   tg_dg_kbd_row(dlg)             — завершить текущий ряд кнопок.
// Менеджмент (работают с вершиной стека):
//   tg_dlg_start(chat, user, group, tail, start_json|0) — push стека +
//       tg_fsm_set + on_start; tail=0 → первое окно диалога. Показ — сам
//       вызывающий (tg_dlg_show): у start нет bot-аргумента.
//   tg_dlg_switch(chat, user, tail) — смена окна текущего диалога + show.
//   tg_dlg_next(chat, user) / tg_dlg_back(chat, user) — следующее/предыдущее
//       окно диалога по порядку регистрации + show. 0 — граница/нет стека.
//   tg_dlg_done(chat, user, result_json|0) — on_close + pop + показ
//       родительского окна (стек пуст → tg_fsm_set(0)).
//   tg_dlg_update(chat, user, dd_json) — shallow-merge в dialog_data + show.
//   tg_dlg_show(bot, chat, user)    — рендер текущего окна: {плейсхолдеры} →
//       текст, кнопки состояния → inline-клавиатура с префиксом
//       "<intent>|", edit (mid) или send; mid запоминается из ответа API
//       (кроме dry-режима).
//   tg_dlg_click(bot, ctx)          — callback: (1) разбор "<intent>|btn_id";
//       (2) intent ≠ стек вершины → tg_answer(ctx,"") и 0; (3) действие
//       кнопки (go → switch, custom fn); (4) show; 1 = handled.
//   tg_dlg_input(bot, ctx)          — текст в состоянии диалога с on_text →
//       вызов fn + show; 1 = handled, иначе 0.
//
// dlg_ctx (статик-слот, 10 слов): 0 chat_id, 1 user_id, 2 intent,
//   3 state* (копия в tg_dg_cstate), 4 dd* (сырой JSON), 5 start* (сырой
//   JSON), 6 text_ctx* (ядро-ctx для on_text), 7 bot*, 8 dlg*, 9 result*
//   (on_close). Валиден до ближайшей tg_dlg_*-мутации стека.
//
// Показ/next/back/done/update используют tg_dg_lastbot — bot последнего
// tg_dlg_show/tg_dlg_click (у стека bot-аргумента нет); lastbot=0 → только
// FSM-переключение без отправки.
//
// Отклонения/примечания:
//  - intent — глобальный счётчик (старт 100, без рандомизации 0-поколения),
//    при каждом show пересоздаётся и пишется в элемент стека "i";
//  - лимит стека формально ≤10 не ограничивается принудительно (JSON
//    упирается в буфер 16 КБ, мутации при переполнении усекают запись);
//  - dialog_data/start — вложенные JSON-объекты; плейсхолдеры читаются
//    только у строковых значений.

extern strcmp
extern strcpy
extern strlen
extern sprintf
extern strtoull

// ===== Пулы =====
tg_dg_dcnt;          // диалогов (лимит 8)
tg_dg_dlgs[64];      // 8 диалогов × 8 слов: 0 idx, 1 group*, 2 on_start*,
                     // 3 on_close*, 4 getter*, 5-7 резерв
tg_dg_wcnt;          // окон (лимит 128 всего)
tg_dg_wins[640];     // 128 окон × 5 слов: 0 dlg_id, 1 tail*, 2 text*,
                     // 3 on_text*, 4 kbd*
tg_dg_bcnt;          // кнопок (лимит 256 всего)
tg_dg_btns[1792];    // 256 кнопок × 7 слов: 0 dlg_id, 1 tail*, 2 btn_id*,
                     // 3 text*, 4 kind (0 on_click, 1 go, 2 пусто),
                     // 5 act* (fn|go_tail), 6 row
tg_dg_currow;        // текущий ряд кнопок (сброс в tg_dg_window)

// ===== Состояние =====
tg_dg_intent;        // глобальный счётчик intent (старт 100)
tg_dg_lastbot;       // bot последнего show/click (для switch/next/back/done)
tg_dg_newmid;        // отложенное mid для tg_dg_setmid
tg_dg_midflag;       // 1 — заменить mid при следующем rebuild

// ===== Буферы =====
tg_dg_data[2048];    // 16 КБ — копия FSM-data (стек) вне KV-слота
tg_dg_acc[2048];     // 16 КБ — аккумулятор сборки JSON стека
tg_dg_accpos;        // позиция в аккумуляторе
tg_dg_first;         // первая запись dd-merge дописана (флаг запятой)
tg_dg_ddbuf[1024];   // 8 КБ — результат merge dialog_data
tg_dg_rbuf[512];     // 4 КБ — копия строки getter
tg_dg_out[2048];     // 16 КБ — рендер текста окна
tg_dg_opos;          // позиция в tg_dg_out
tg_dg_kbuf[1024];    // 8 КБ — собранная клавиатура
tg_dg_kpos;          // позиция в tg_dg_kbuf
tg_dg_ctx[12];       // dlg_ctx (см. шапку)
tg_dg_gbuf[32];      // 256 байт — группа FSM из состояния
tg_dg_tbuf[32];      // 256 байт — хвост состояния
tg_dg_statebuf[96];  // 768 байт — рабочее полное состояние "Group:tail"
tg_dg_oldstate[96];  // 768 байт — копия прежнего состояния внутри rebuild
tg_dg_cstate[96];    // 768 байт — состояние для dlg_ctx[3]
tg_dg_ktmp[64];      // 512 байт — имя плейсхолдера
tg_dg_tmp[64];       // 512 байт — "%ld" и callback_data
tg_dg_path[64];      // 512 байт — dot-path "stack.N.field"

// ===== Примитивы аккумулятора/буферов =====

// tg_dg_ab(c): байт в аккумулятор (отсечка ~16 КБ)
tg_dg_ab(c) {
    if tg_dg_accpos < 16300 {
        *(&tg_dg_acc + tg_dg_accpos) !8 c;
        tg_dg_accpos = tg_dg_accpos + 1;
    }
    1;
}

// tg_dg_as(s): C-строка в аккумулятор
tg_dg_as(s) {
    auto i;
    i = 0;
    while @8 *(s+i) {
        tg_dg_ab(@8 *(s+i));
        i = i + 1;
    }
    1;
}

// tg_dg_araw(p, e): сырой диапазон [p,e) в аккумулятор
tg_dg_araw(p, e) {
    while p != e {
        tg_dg_ab(@8 *p);
        p = p + 1;
    }
    1;
}

// tg_dg_anum(n): число в аккумулятор (%ld в tg_dg_tmp)
tg_dg_anum(n) {
    sprintf(&tg_dg_tmp, "%ld", n);
    tg_dg_as(&tg_dg_tmp);
}

// tg_dg_afin(): NUL-терминатор аккумулятора → тело
tg_dg_afin() {
    *(&tg_dg_acc + tg_dg_accpos) !8 0;
    &tg_dg_acc;
}

// tg_dg_ob(c): байт в буфер рендера (отсечка ~16 КБ)
tg_dg_ob(c) {
    if tg_dg_opos < 16300 {
        *(&tg_dg_out + tg_dg_opos) !8 c;
        tg_dg_opos = tg_dg_opos + 1;
    }
    1;
}

// tg_dg_kb(s): C-строка в буфер клавиатуры (отсечка ~8 КБ)
tg_dg_kb(s) {
    auto i;
    auto c;
    auto done;
    i = 0;
    done = 0;
    while done == 0 {
        c = @8 *(s+i);
        if c == 0 done = 1;
        else {
            if tg_dg_kpos < 8100 {
                *(&tg_dg_kbuf + tg_dg_kpos) !8 c;
                tg_dg_kpos = tg_dg_kpos + 1;
            } else {
                done = 1;
            }
            i = i + 1;
        }
    }
    1;
}

// ===== Строковые помощники =====

// tg_dg_streq(a, b): побайтовое равенство двух C-строк (0 в любом → нет)
tg_dg_streq(a, b) {
    auto ok;
    auto i;
    auto c;
    ok = 1;
    if a == 0 ok = 0;
    if b == 0 ok = 0;
    i = 0;
    while ok != 0 {
        c = @8 *(a+i);
        if c != @8 *(b+i) ok = 0;
        if c == 0 break;
        i = i + 1;
    }
    ok;
}

// tg_dg_eqn(s, m, pre, pm): s[0,m) начинается с pre[0,pm)
tg_dg_eqn(s, m, pre, pm) {
    auto ok;
    auto i;
    ok = 0;
    if m >= pm {
        ok = 1;
        i = 0;
        while i < pm {
            if @8 *(s+i) != @8 *(pre+i) ok = 0;
            i = i + 1;
        }
    }
    ok;
}

// ===== Стек: load/save =====

// tg_dg_load(chat, user): копия FSM-data в tg_dg_data; 1 — данные есть
tg_dg_load(chat, user) {
    auto p;
    auto n;
    auto c;
    auto ok;
    ok = 0;
    p = tg_fsm_data(chat, user);
    if p != 0 {
        n = 0;
        c = 1;
        while c != 0 {
            if n >= 16300 {
                c = 0;
            } else {
                c = @8 *(p + n);
                *(&tg_dg_data + n) !8 c;
                n = n + 1;
            }
        }
        if n >= 16300 {
            *(&tg_dg_data + 16299) !8 0;
        }
        ok = 1;
    }
    ok;
}

// tg_dg_slen(): число элементов stack в tg_dg_data
tg_dg_slen() {
    auto n;
    n = tg_count(&tg_dg_data, "stack");
    n;
}

// tg_dg_el(i): сырой JSON-объект элемента i (внутри tg_dg_data) или 0
tg_dg_el(i) {
    auto p;
    sprintf(&tg_dg_path, "stack.%ld", i);
    p = tg_find(&tg_dg_data, &tg_dg_path);
    p;
}

// tg_dg_save(chat, user): аккумулятор → tg_fsm data
tg_dg_save(chat, user) {
    tg_dg_afin();
    tg_fsm_set_data(chat, user, &tg_dg_acc);
}

// ===== Стек: мутации (своя сборка JSON) =====

// tg_dg_push(chat, user, intent, state, start_json, dd_json): append
// элемента в stack (mid копируется из прежнего data)
tg_dg_push(chat, user, intent, state, start_json, dd_json) {
    auto has;
    auto len;
    auto i;
    auto el;
    auto e2;
    auto mid;
    mid = 0;
    has = tg_dg_load(chat, user);
    tg_dg_accpos = 0;
    tg_dg_as("{\"stack\":[");
    if has != 0 {
        len = tg_dg_slen();
        mid = tg_get_num(&tg_dg_data, "mid");
        i = 0;
        while i < len {
            if i > 0 tg_dg_ab(44);
            el = tg_dg_el(i);
            e2 = tg_skipval(el);
            tg_dg_araw(el, e2);
            i = i + 1;
        }
        if len > 0 tg_dg_ab(44);
    }
    tg_dg_as("{\"i\":");
    tg_dg_anum(intent);
    tg_dg_as(",\"s\":\"");
    tg_dg_as(state);
    tg_dg_as("\",\"d\":");
    if start_json == 0 {
        tg_dg_as("{}");
    } else {
        tg_dg_as(start_json);
    }
    tg_dg_as(",\"dd\":");
    if dd_json == 0 {
        tg_dg_as("{}");
    } else {
        tg_dg_as(dd_json);
    }
    tg_dg_ab(125);
    tg_dg_as("],\"mid\":");
    tg_dg_anum(mid);
    tg_dg_ab(125);
    tg_dg_save(chat, user);
    1;
}

// tg_dg_pop(chat, user): снять последний элемент стека; 0 — пусто/нет data
tg_dg_pop(chat, user) {
    auto has;
    auto len;
    auto i;
    auto el;
    auto e2;
    auto mid;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            mid = tg_get_num(&tg_dg_data, "mid");
            tg_dg_accpos = 0;
            tg_dg_as("{\"stack\":[");
            i = 0;
            while i < len - 1 {
                if i > 0 tg_dg_ab(44);
                el = tg_dg_el(i);
                e2 = tg_skipval(el);
                tg_dg_araw(el, e2);
                i = i + 1;
            }
            tg_dg_as("],\"mid\":");
            tg_dg_anum(mid);
            tg_dg_ab(125);
            tg_dg_save(chat, user);
            ok = 1;
        }
    }
    ok;
}

// tg_dg_rebuild(chat, user, intent, state, d_raw, dd_raw): пересборка стека с
// заменой последнего элемента; 0 в intent/state/d_raw/dd_raw = копировать
// прежние значения; mid заменяется, если выставлен tg_dg_midflag.
tg_dg_rebuild(chat, user, intent, state, d_raw, dd_raw) {
    auto has;
    auto len;
    auto i;
    auto el;
    auto e2;
    auto cd;
    auto cdd;
    auto ci;
    auto sp;
    auto mid;
    auto ni;
    auto ns;
    auto nd;
    auto ndd;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            el = tg_dg_el(len - 1);
            ci = tg_get_num(el, "i");
            sp = tg_get_str(el, "s");
            *(&tg_dg_oldstate) !8 0;
            if sp != 0 strcpy(&tg_dg_oldstate, sp);
            cd = tg_find(el, "d");
            cdd = tg_find(el, "dd");
            mid = tg_get_num(&tg_dg_data, "mid");
            if tg_dg_midflag != 0 mid = tg_dg_newmid;
            ni = intent;
            if ni == 0 ni = ci;
            ns = state;
            if ns == 0 ns = &tg_dg_oldstate;
            nd = d_raw;
            if nd == 0 nd = cd;
            ndd = dd_raw;
            if ndd == 0 ndd = cdd;
            tg_dg_accpos = 0;
            tg_dg_as("{\"stack\":[");
            i = 0;
            while i < len - 1 {
                if i > 0 tg_dg_ab(44);
                el = tg_dg_el(i);
                e2 = tg_skipval(el);
                tg_dg_araw(el, e2);
                i = i + 1;
            }
            if len > 1 tg_dg_ab(44);
            tg_dg_as("{\"i\":");
            tg_dg_anum(ni);
            tg_dg_as(",\"s\":\"");
            tg_dg_as(ns);
            tg_dg_as("\",\"d\":");
            if nd == 0 {
                tg_dg_as("{}");
            } else {
                e2 = tg_skipval(nd);
                tg_dg_araw(nd, e2);
            }
            tg_dg_as(",\"dd\":");
            if ndd == 0 {
                tg_dg_as("{}");
            } else {
                e2 = tg_skipval(ndd);
                tg_dg_araw(ndd, e2);
            }
            tg_dg_ab(125);
            tg_dg_as("],\"mid\":");
            tg_dg_anum(mid);
            tg_dg_ab(125);
            tg_dg_midflag = 0;
            tg_dg_save(chat, user);
            ok = 1;
        }
    }
    ok;
}

// tg_dg_mobj(obj, other, onlymiss): записи obj (на '{') сырым текстом в
// аккумулятор; onlymiss=1 → только чьих ключей нет в other (shallow-merge)
tg_dg_mobj(obj, other, onlymiss) {
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
            e = tg_skipstr(p);
            m = e - p - 2;
            v = tg_skipspace(e);
            if @8 *v == 58 {
                v = tg_skipspace(v + 1);
                ve = tg_skipval(v);
                emit = 1;
                if onlymiss != 0 {
                    if tg_find_key(other, p + 1, m) != 0 emit = 0;
                }
                if emit == 1 {
                    if tg_dg_first == 0 tg_dg_ab(44);
                    tg_dg_first = 0;
                    while p != ve {
                        tg_dg_ab(@8 *p);
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

// tg_dg_ddmerge(dst, src): shallow-merge объектов → tg_dg_ddbuf (старые
// ключи без перезаписи + все ключи src); dst/src=0 → "{}"
tg_dg_ddmerge(dst, src) {
    auto i;
    auto c;
    if dst == 0 {
        dst = "{}";
    }
    if src == 0 {
        src = "{}";
    }
    tg_dg_accpos = 0;
    tg_dg_first = 1;
    tg_dg_ab(123);
    tg_dg_mobj(dst, src, 1);
    tg_dg_mobj(src, dst, 0);
    tg_dg_ab(125);
    *(&tg_dg_acc + tg_dg_accpos) !8 0;
    i = 0;
    c = 1;
    while c != 0 {
        if i >= 8100 {
            c = 0;
        } else {
            c = @8 *(&tg_dg_acc + i);
            *(&tg_dg_ddbuf + i) !8 c;
            i = i + 1;
        }
    }
    if i >= 8100 {
        *(&tg_dg_ddbuf + 8099) !8 0;
    }
    &tg_dg_ddbuf;
}

// tg_dg_setmid(chat, user, mid): замена поля mid стека
tg_dg_setmid(chat, user, mid) {
    tg_dg_newmid = mid;
    tg_dg_midflag = 1;
    tg_dg_rebuild(chat, user, 0, 0, 0, 0);
}

// ===== Реестр диалогов/окон/кнопок =====

// tg_dialog_new(group): новый диалог или 0 (лимит 8)
tg_dialog_new(group) {
    auto d;
    d = 0;
    if tg_dg_dcnt < 8 {
        d = &tg_dg_dlgs + tg_dg_dcnt * 64;
        *d = tg_dg_dcnt;
        d[1] = group;
        d[2] = 0;
        d[3] = 0;
        d[4] = 0;
        tg_dg_dcnt = tg_dg_dcnt + 1;
    }
    d;
}

// tg_dg_find(group): диалог по имени FSM-группы или 0
tg_dg_find(group) {
    auto i;
    auto d;
    auto r;
    r = 0;
    i = 0;
    while i < tg_dg_dcnt {
        d = &tg_dg_dlgs + i * 64;
        if tg_dg_streq(d[1], group) != 0 r = d;
        i = i + 1;
    }
    r;
}

// tg_dg_win_find(id, tail): окно диалога id с хвостом tail или 0
tg_dg_win_find(id, tail) {
    auto i;
    auto w;
    auto r;
    r = 0;
    i = 0;
    while i < tg_dg_wcnt {
        w = &tg_dg_wins + i * 40;
        if w[0] == id {
            if tg_dg_streq(w[1], tail) != 0 r = w;
        }
        i = i + 1;
    }
    r;
}

// tg_dg_win_first(id): первое зарегистрированное окно диалога или 0
tg_dg_win_first(id) {
    auto i;
    auto w;
    auto r;
    r = 0;
    i = 0;
    while i < tg_dg_wcnt {
        w = &tg_dg_wins + i * 40;
        if r == 0 {
            if w[0] == id r = w;
        }
        i = i + 1;
    }
    r;
}

// tg_dg_btn_find(id, tail, btn_id): кнопка состояния или 0
tg_dg_btn_find(id, tail, btn_id) {
    auto i;
    auto b;
    auto r;
    r = 0;
    i = 0;
    while i < tg_dg_bcnt {
        b = &tg_dg_btns + i * 56;
        if b[0] == id {
            if tg_dg_streq(b[1], tail) != 0 {
                if tg_dg_streq(b[2], btn_id) != 0 r = b;
            }
        }
        i = i + 1;
    }
    r;
}

// tg_dg_btn_add(id, tail, btn_id, text, kind, act): новая кнопка в текущий
// ряд (лимит 256); 1 — ок, 0 — отклонено
tg_dg_btn_add(id, tail, btn_id, text, kind, act) {
    auto b;
    auto ok;
    ok = 0;
    if tg_dg_bcnt < 256 {
        b = &tg_dg_btns + tg_dg_bcnt * 56;
        b[0] = id;
        b[1] = tail;
        b[2] = btn_id;
        b[3] = text;
        b[4] = kind;
        b[5] = act;
        b[6] = tg_dg_currow;
        tg_dg_bcnt = tg_dg_bcnt + 1;
        ok = 1;
    }
    ok;
}

// tg_dg_window(dlg, tail, text, kbd): окно; дубликат перезаписывает text/kbd
tg_dg_window(dlg, tail, text, kbd) {
    auto id;
    auto w;
    auto ok;
    ok = 0;
    if dlg != 0 {
        id = *dlg;
        w = tg_dg_win_find(id, tail);
        if w != 0 {
            w[2] = text;
            w[4] = kbd;
            ok = 1;
        } else {
            if tg_dg_wcnt < 128 {
                w = &tg_dg_wins + tg_dg_wcnt * 40;
                w[0] = id;
                w[1] = tail;
                w[2] = text;
                w[3] = 0;
                w[4] = kbd;
                tg_dg_wcnt = tg_dg_wcnt + 1;
                tg_dg_currow = 0;
                ok = 1;
            }
        }
    }
    ok;
}

tg_dg_on_start(dlg, fn) {
    if dlg != 0 dlg[2] = fn;
    1;
}

tg_dg_on_close(dlg, fn) {
    if dlg != 0 dlg[3] = fn;
    1;
}

tg_dg_getter(dlg, fn) {
    if dlg != 0 dlg[4] = fn;
    1;
}

// tg_dg_button(dlg, tail, btn_id, text): кнопка-событие в текущий ряд
tg_dg_button(dlg, tail, btn_id, text) {
    auto ok;
    ok = 0;
    if dlg != 0 ok = tg_dg_btn_add(*dlg, tail, btn_id, text, 2, 0);
    ok;
}

// tg_dg_button_go(dlg, tail, btn_id, text, go_tail): кнопка-переход
tg_dg_button_go(dlg, tail, btn_id, text, go_tail) {
    auto ok;
    ok = 0;
    if dlg != 0 ok = tg_dg_btn_add(*dlg, tail, btn_id, text, 1, go_tail);
    ok;
}

// tg_dg_on_click(dlg, tail, btn_id, fn): custom-обработчик кнопки
// (найдена → замена действия, нет → создание)
tg_dg_on_click(dlg, tail, btn_id, fn) {
    auto b;
    auto ok;
    ok = 0;
    if dlg != 0 {
        b = tg_dg_btn_find(*dlg, tail, btn_id);
        if b != 0 {
            b[4] = 0;
            b[5] = fn;
            ok = 1;
        } else {
            ok = tg_dg_btn_add(*dlg, tail, btn_id, btn_id, 0, fn);
        }
    }
    ok;
}

// tg_dg_on_text(dlg, tail, fn): текстовый ввод состояния (окно должно быть
// зарегистрировано)
tg_dg_on_text(dlg, tail, fn) {
    auto w;
    auto ok;
    ok = 0;
    if dlg != 0 {
        w = tg_dg_win_find(*dlg, tail);
        if w != 0 {
            w[3] = fn;
            ok = 1;
        }
    }
    ok;
}

// tg_dg_kbd_row(dlg): завершить текущий ряд кнопок
tg_dg_kbd_row(dlg) {
    tg_dg_currow = tg_dg_currow + 1;
    tg_dg_currow;
}

// ===== Группа/хвост состояния =====

// tg_dg_group(state): группа до ':' → tg_dg_gbuf (копия)
tg_dg_group(state) {
    auto i;
    auto c;
    auto done;
    i = 0;
    done = 0;
    while done == 0 {
        c = @8 *(state+i);
        if c == 0 done = 1;
        else if c == 58 done = 2;
        else {
            *(&tg_dg_gbuf + i) !8 c;
            i = i + 1;
        }
    }
    *(&tg_dg_gbuf + i) !8 0;
    &tg_dg_gbuf;
}

// tg_dg_tail(state): хвост после первого ':' → tg_dg_tbuf (копия)
tg_dg_tail(state) {
    auto i;
    auto c;
    auto done;
    auto pos;
    pos = 0;
    done = 0;
    while done == 0 {
        c = @8 *(state + pos);
        if c == 0 done = 1;
        else if c == 58 done = 2;
        else pos = pos + 1;
    }
    if done == 2 pos = pos + 1;
    i = 0;
    done = 0;
    while done == 0 {
        c = @8 *(state + pos + i);
        if c == 0 done = 1;
        else {
            *(&tg_dg_tbuf + i) !8 c;
            i = i + 1;
        }
    }
    *(&tg_dg_tbuf + i) !8 0;
    &tg_dg_tbuf;
}

// ===== dlg_ctx =====

// tg_dg_mkctx(chat, user, bot): статик-слот текущего диалога (см. шапку)
tg_dg_mkctx(chat, user, bot) {
    auto has;
    auto len;
    auto el;
    auto sp;
    tg_dg_ctx[0] = chat;
    tg_dg_ctx[1] = user;
    tg_dg_ctx[2] = 0;
    tg_dg_ctx[3] = 0;
    tg_dg_ctx[4] = 0;
    tg_dg_ctx[5] = 0;
    tg_dg_ctx[6] = 0;
    tg_dg_ctx[7] = bot;
    tg_dg_ctx[8] = 0;
    tg_dg_ctx[9] = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            el = tg_dg_el(len - 1);
            tg_dg_ctx[2] = tg_get_num(el, "i");
            sp = tg_get_str(el, "s");
            *(&tg_dg_cstate) !8 0;
            if sp != 0 strcpy(&tg_dg_cstate, sp);
            tg_dg_ctx[3] = &tg_dg_cstate;
            tg_dg_ctx[4] = tg_find(el, "dd");
            tg_dg_ctx[5] = tg_find(el, "d");
        }
    }
    &tg_dg_ctx;
}

// ===== Рендер =====

// tg_dg_render(text, dd, sd, gr): замена {dialog_data.<k>}/{start.<k>}/
// {getter.<k>} → tg_dg_out (строковые значения; неизвестный ключ → пусто)
tg_dg_render(text, dd, sd, gr) {
    auto p;
    auto q;
    auto c;
    auto cc;
    auto klen;
    auto endk;
    auto v;
    auto done;
    tg_dg_opos = 0;
    p = text;
    done = 0;
    while done == 0 {
        c = @8 *p;
        if c == 0 done = 1;
        else {
            if c == 123 {
                q = p + 1;
                klen = 0;
                endk = 0;
                while endk == 0 {
                    cc = @8 *q;
                    if cc == 0 endk = 1;
                    else if cc == 125 endk = 2;
                    else {
                        if klen < 63 {
                            *(&tg_dg_ktmp + klen) !8 cc;
                            klen = klen + 1;
                        }
                        q = q + 1;
                    }
                }
                if endk == 2 {
                    *(&tg_dg_ktmp + klen) !8 0;
                    v = 0;
                    if tg_dg_eqn(&tg_dg_ktmp, klen, "dialog_data.", 12) != 0 {
                        if dd != 0 v = tg_get_str(dd, &tg_dg_ktmp + 12);
                    } else {
                        if tg_dg_eqn(&tg_dg_ktmp, klen, "start.", 6) != 0 {
                            if sd != 0 v = tg_get_str(sd, &tg_dg_ktmp + 6);
                        } else {
                            if tg_dg_eqn(&tg_dg_ktmp, klen, "getter.", 7) != 0 {
                                if gr != 0 v = tg_get_str(gr, &tg_dg_ktmp + 7);
                            }
                        }
                    }
                    if v != 0 {
                        while @8 *v {
                            tg_dg_ob(@8 *v);
                            v = v + 1;
                        }
                    }
                    p = q + 1;
                } else {
                    tg_dg_ob(123);
                    done = 1;
                }
            } else {
                tg_dg_ob(c);
                p = p + 1;
            }
        }
    }
    *(&tg_dg_out + tg_dg_opos) !8 0;
    &tg_dg_out;
}

// tg_dg_kbd_json(id, tail, intent): inline-клавиатура кнопок состояния с
// callback_data "<intent>|<btn_id>", ряды по tg_dg_currow; 0 — кнопок нет
tg_dg_kbd_json(id, tail, intent) {
    auto i;
    auto b;
    auto currow;
    auto firstrow;
    tg_dg_kpos = 0;
    firstrow = 1;
    currow = 0;
    i = 0;
    while i < tg_dg_bcnt {
        b = &tg_dg_btns + i * 56;
        if b[0] == id {
            if tg_dg_streq(b[1], tail) != 0 {
                if firstrow == 1 {
                    tg_dg_kb("{\"inline_keyboard\":[[");
                    firstrow = 0;
                } else {
                    if b[6] != currow {
                        tg_dg_kb("],[");
                    } else {
                        tg_dg_kb(",");
                    }
                }
                tg_dg_kb("{\"text\":\"");
                tg_dg_kb(tg_json_escape(b[3]));
                tg_dg_kb("\",\"callback_data\":\"");
                sprintf(&tg_dg_tmp, "%ld|%s", intent, b[2]);
                tg_dg_kb(tg_json_escape(&tg_dg_tmp));
                tg_dg_kb("\"}");
                currow = b[6];
            }
        }
        i = i + 1;
    }
    if firstrow == 1 {
        0;
    } else {
        tg_dg_kb("]]}");
        *(&tg_dg_kbuf + tg_dg_kpos) !8 0;
        &tg_dg_kbuf;
    }
}

// ===== Показ =====

// tg_dlg_show(bot, chat, user): рендер текущего окна стека; edit при mid,
// иначе send; reply_markup — через extras ядра; 1 — ок, 0 — нечего показать
tg_dlg_show(bot, chat, user) {
    auto has;
    auto len;
    auto el;
    auto sp;
    auto dlg;
    auto win;
    auto sd;
    auto dd;
    auto gr;
    auto fp;
    auto text;
    auto kbd;
    auto mid;
    auto mid2;
    auto r;
    tg_dg_lastbot = bot;
    r = 0;
    has = tg_dg_load(chat, user);
    if has == 0 {
        r = 0;
    } else {
        len = tg_dg_slen();
        if len == 0 {
            r = 0;
        } else {
            el = tg_dg_el(len - 1);
            sp = tg_get_str(el, "s");
            if sp != 0 {
                strcpy(&tg_dg_statebuf, sp);
                tg_dg_group(&tg_dg_statebuf);
                tg_dg_tail(&tg_dg_statebuf);
                dlg = tg_dg_find(&tg_dg_gbuf);
                if dlg == 0 {
                    r = 0;
                } else {
                    win = tg_dg_win_find(*dlg, &tg_dg_tbuf);
                    if win == 0 {
                        r = 0;
                    } else {
                        // getter → tg_dg_rbuf (mkctx перечитывает data)
                        gr = 0;
                        fp = dlg[4];
                        if fp != 0 {
                            tg_dg_mkctx(chat, user, bot);
                            gr = fp(&tg_dg_ctx);
                            if gr != 0 {
                                strcpy(&tg_dg_rbuf, gr);
                                gr = &tg_dg_rbuf;
                            }
                        }
                        // новый intent + запись в элемент стека
                        tg_dg_intent = tg_dg_intent + 1;
                        tg_dg_rebuild(chat, user, tg_dg_intent, 0, 0, 0);
                        el = tg_dg_el(len - 1);
                        sd = tg_find(el, "d");
                        dd = tg_find(el, "dd");
                        text = tg_dg_render(win[2], dd, sd, gr);
                        kbd = tg_dg_kbd_json(*dlg, &tg_dg_tbuf, tg_dg_intent);
                        mid = tg_get_num(&tg_dg_data, "mid");
                        if kbd != 0 {
                            tg_ex_reset();
                            tg_ex_json("reply_markup", kbd);
                        }
                        if mid != 0 {
                            r = tg_edit_text(bot, chat, mid, text);
                        } else {
                            r = tg_send_to(bot, chat, text);
                        }
                        if tg_dry_run == 0 {
                            if r != 0 {
                                mid2 = tg_get_num(tg_http_body(), "result.message_id");
                                if mid2 > 0 tg_dg_setmid(chat, user, mid2);
                            }
                        }
                    }
                }
            }
        }
    }
    r;
}

// ===== Менеджмент =====

// tg_dlg_start(chat, user, group, tail, start_json|0): push стека + FSM-state
// + on_start; tail=0 → первое окно диалога; показ — tg_dlg_show вручную
tg_dlg_start(chat, user, group, tail, start_json) {
    auto dlg;
    auto w;
    auto t;
    auto fp;
    auto ok;
    ok = 0;
    dlg = tg_dg_find(group);
    if dlg != 0 {
        t = tail;
        if t == 0 {
            w = tg_dg_win_first(*dlg);
            if w != 0 t = w[1];
        }
        if t != 0 {
            tg_dg_intent = tg_dg_intent + 1;
            sprintf(&tg_dg_statebuf, "%s:%s", group, t);
            tg_dg_push(chat, user, tg_dg_intent, &tg_dg_statebuf, start_json, 0);
            tg_fsm_set(chat, user, &tg_dg_statebuf);
            tg_dg_mkctx(chat, user, tg_dg_lastbot);
            fp = dlg[2];
            if fp != 0 fp(&tg_dg_ctx);
            ok = 1;
        }
    }
    ok;
}

// tg_dlg_switch(chat, user, tail): смена состояния текущего окна + show
tg_dlg_switch(chat, user, tail) {
    auto has;
    auto len;
    auto sp;
    auto dlg;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            sp = tg_fsm_state(chat, user);
            if sp != 0 {
                strcpy(&tg_dg_statebuf, sp);
                tg_dg_group(&tg_dg_statebuf);
                dlg = tg_dg_find(&tg_dg_gbuf);
                if dlg != 0 {
                    sprintf(&tg_dg_statebuf, "%s:%s", &tg_dg_gbuf, tail);
                    tg_dg_rebuild(chat, user, 0, &tg_dg_statebuf, 0, 0);
                    tg_fsm_set(chat, user, &tg_dg_statebuf);
                    if tg_dg_lastbot != 0 tg_dlg_show(tg_dg_lastbot, chat, user);
                    ok = 1;
                }
            }
        }
    }
    ok;
}

// tg_dg_move(chat, user, dir): следующее (dir=1) / предыдущее (dir=0) окно
// диалога по порядку регистрации + show; 0 — граница/нет стека
tg_dg_move(chat, user, dir) {
    auto has;
    auto len;
    auto sp;
    auto dlg;
    auto best;
    auto i;
    auto w;
    auto curi;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            sp = tg_fsm_state(chat, user);
            if sp != 0 {
                strcpy(&tg_dg_statebuf, sp);
                tg_dg_group(&tg_dg_statebuf);
                tg_dg_tail(&tg_dg_statebuf);
                dlg = tg_dg_find(&tg_dg_gbuf);
                if dlg != 0 {
                    // индекс текущего окна в реестре
                    curi = 0;
                    i = 0;
                    while i < tg_dg_wcnt {
                        w = &tg_dg_wins + i * 40;
                        if w[0] == *dlg {
                            if tg_dg_streq(w[1], &tg_dg_tbuf) != 0 curi = i;
                        }
                        i = i + 1;
                    }
                    // ближайшее окно диалога после/до текущего
                    best = 0;
                    if dir != 0 {
                        i = curi + 1;
                        while i < tg_dg_wcnt {
                            w = &tg_dg_wins + i * 40;
                            if best == 0 {
                                if w[0] == *dlg best = w;
                            }
                            i = i + 1;
                        }
                    } else {
                        if curi > 0 {
                            i = curi - 1;
                            while 1 {
                                w = &tg_dg_wins + i * 40;
                                if best == 0 {
                                    if w[0] == *dlg best = w;
                                }
                                if i == 0 break;
                                i = i - 1;
                            }
                        }
                    }
                    if best != 0 {
                        sprintf(&tg_dg_statebuf, "%s:%s", &tg_dg_gbuf, best[1]);
                        tg_dg_rebuild(chat, user, 0, &tg_dg_statebuf, 0, 0);
                        tg_fsm_set(chat, user, &tg_dg_statebuf);
                        if tg_dg_lastbot != 0 tg_dlg_show(tg_dg_lastbot, chat, user);
                        ok = 1;
                    }
                }
            }
        }
    }
    ok;
}

tg_dlg_next(chat, user) { tg_dg_move(chat, user, 1); }
tg_dlg_back(chat, user) { tg_dg_move(chat, user, 0); }

// tg_dlg_update(chat, user, dd_json): shallow-merge в dialog_data + show
tg_dlg_update(chat, user, dd_json) {
    auto has;
    auto len;
    auto el;
    auto dd;
    auto m;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            el = tg_dg_el(len - 1);
            dd = tg_find(el, "dd");
            m = tg_dg_ddmerge(dd, dd_json);
            tg_dg_rebuild(chat, user, 0, 0, 0, m);
            if tg_dg_lastbot != 0 tg_dlg_show(tg_dg_lastbot, chat, user);
            ok = 1;
        }
    }
    ok;
}

// tg_dlg_done(chat, user, result_json|0): on_close + pop + показ родителя
// (стек пуст → tg_fsm_clear: состояние и data стираются)
tg_dlg_done(chat, user, result_json) {
    auto has;
    auto len;
    auto el;
    auto sp;
    auto dlg;
    auto fp;
    auto ok;
    ok = 0;
    has = tg_dg_load(chat, user);
    if has != 0 {
        len = tg_dg_slen();
        if len > 0 {
            el = tg_dg_el(len - 1);
            sp = tg_get_str(el, "s");
            *(&tg_dg_statebuf) !8 0;
            if sp != 0 strcpy(&tg_dg_statebuf, sp);
            tg_dg_mkctx(chat, user, tg_dg_lastbot);
            tg_dg_ctx[9] = result_json;
            tg_dg_group(&tg_dg_statebuf);
            dlg = tg_dg_find(&tg_dg_gbuf);
            if dlg != 0 {
                fp = dlg[3];
                if fp != 0 fp(&tg_dg_ctx);
            }
            tg_dg_pop(chat, user);
            has = tg_dg_load(chat, user);
            len = 0;
            if has != 0 len = tg_dg_slen();
            if len == 0 {
                tg_fsm_clear(chat, user);
            } else {
                el = tg_dg_el(len - 1);
                sp = tg_get_str(el, "s");
                *(&tg_dg_statebuf) !8 0;
                if sp != 0 strcpy(&tg_dg_statebuf, sp);
                tg_fsm_set(chat, user, &tg_dg_statebuf);
            }
            if tg_dg_lastbot != 0 tg_dlg_show(tg_dg_lastbot, chat, user);
            ok = 1;
        }
    }
    ok;
}

// ===== Клик / ввод =====

// tg_dlg_click(bot, ctx): callback "<intent>|<btn_id>"; устаревший intent →
// tg_answer(ctx,"") и 0; действие кнопки + show; 1 = handled
tg_dlg_click(bot, ctx) {
    auto chat;
    auto user;
    auto d;
    auto i;
    auto c;
    auto done;
    auto intent;
    auto bid;
    auto has;
    auto len;
    auto top;
    auto sp;
    auto dlg;
    auto btn;
    auto fp;
    auto r;
    r = 0;
    chat = tg_chat_id(ctx);
    user = tg_from_id(ctx);
    d = tg_data(ctx);
    if d != 0 {
        i = 0;
        done = 0;
        while done == 0 {
            c = @8 *(d + i);
            if c == 0 done = 1;
            else if c == 124 done = 2;
            else i = i + 1;
        }
        if done == 2 {
            intent = strtoull(d, 0, 10);
            bid = d + i + 1;
            has = tg_dg_load(chat, user);
            if has != 0 {
                len = tg_dg_slen();
                if len > 0 {
                    sprintf(&tg_dg_path, "stack.%ld.i", len - 1);
                    top = tg_get_num(&tg_dg_data, &tg_dg_path);
                    if top == intent {
                        sp = tg_fsm_state(chat, user);
                        if sp != 0 {
                            strcpy(&tg_dg_statebuf, sp);
                            tg_dg_group(&tg_dg_statebuf);
                            dlg = tg_dg_find(&tg_dg_gbuf);
                            if dlg != 0 {
                                tg_dg_tail(&tg_dg_statebuf);
                                btn = tg_dg_btn_find(*dlg, &tg_dg_tbuf, bid);
                                if btn != 0 {
                                    if btn[4] == 1 {
                                        sprintf(&tg_dg_statebuf, "%s:%s", &tg_dg_gbuf, btn[5]);
                                        tg_dg_rebuild(chat, user, 0, &tg_dg_statebuf, 0, 0);
                                        tg_fsm_set(chat, user, &tg_dg_statebuf);
                                    }
                                    if btn[4] == 0 {
                                        tg_dg_mkctx(chat, user, bot);
                                        fp = btn[5];
                                        if fp != 0 fp(&tg_dg_ctx);
                                    }
                                    tg_dlg_show(bot, chat, user);
                                    r = 1;
                                } else {
                                    tg_answer(ctx, "");
                                }
                            } else {
                                tg_answer(ctx, "");
                            }
                        }
                    } else {
                        tg_answer(ctx, "");
                    }
                }
            }
        }
    }
    r;
}

// tg_dlg_input(bot, ctx): текст в состоянии диалога с on_text-хендлером;
// fn(dlg_ctx) (текст — слот 6 text_ctx) → показ; 1 = handled, иначе 0
tg_dlg_input(bot, ctx) {
    auto sp;
    auto dlg;
    auto win;
    auto fp;
    auto rr;
    auto r;
    r = 0;
    sp = tg_fsm_state(tg_chat_id(ctx), tg_from_id(ctx));
    if sp != 0 {
        strcpy(&tg_dg_statebuf, sp);
        tg_dg_group(&tg_dg_statebuf);
        dlg = tg_dg_find(&tg_dg_gbuf);
        if dlg != 0 {
            tg_dg_tail(&tg_dg_statebuf);
            win = tg_dg_win_find(*dlg, &tg_dg_tbuf);
            if win != 0 {
                fp = win[3];
                if fp != 0 {
                    tg_dg_mkctx(tg_chat_id(ctx), tg_from_id(ctx), bot);
                    tg_dg_ctx[6] = ctx;
                    rr = fp(&tg_dg_ctx);
                    if rr != 0 {
                        tg_dlg_show(bot, tg_chat_id(ctx), tg_from_id(ctx));
                        r = 1;
                    }
                }
            }
        }
    }
    r;
}
