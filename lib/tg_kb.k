// lib/tg_kb.k — B6: билдеры клавиатур + reply/link-preview хелперы.
// Модуль работает с ПОЛЬЗОВАТЕЛЬСКИМ Buf-слотом (0 ptr*, 1 len, 2 cap),
// как tg_buf_*/tg_param_* из ядра: вызывающий объявляет слот `kb[3];`
// (глобально, т.к. слоты в Kiva — только на уровне файла) и передаёт &kb.
//
// Схема накопления (без глобальных флагов — состояние читается из последних
// байтов буфера):
//   prefix  = {"inline_keyboard":[   (или {"keyboard":[ у reply-клавиатуры)
//   begin   → b = prefix             lc='['  pc=':'   — ряд не открыт
//   btn     → lc='}'  → ','+кнопка (уже есть кнопки в ряду);
//             lc='[' + pc=':' → '['+кнопка (первый ряд);
//             lc='[' + pc=',' → ряд уже открыт после row (кнопка первая)
//   row     → lc='}' → "],[" (закрыть ряд с кнопками, открыть следующий);
//             lc='[' — пустой/не открытый ряд: повтор игнорируется
//   done    → lc='}' → "]" (ряд) + "]}"; lc='[' + pc=',' → срезать ",["
//             (висячий пустой ряд) + "]}"; lc='[' + pc=':' → "]}"; пусто → "]}"
// Жизнь результата tg_kb_done/tg_rkb_done — в слоте вызывающего до его
// следующего begin/другого билдера; tg_kb_force_reply/tg_reply_params — в
// собственных статических слотах модуля до следующего вызова той же функции.
//
// parse_mode / вебхуки / сеть — вне модуля (ядро, tg_ext).
// tg_kb_btn: data с префиксом http:// или https:// роутится в url-кнопку —
// точный контракт Task 8 плана; явное указание типа всегда через
// tg_kb_url_btn (tg://, любые прочие схемы).

// ===== Вспомогательные: последние байты Buf =====

// tg_kb_lc(b): последний байт буфера, 0 если буфер пуст
tg_kb_lc(b) {
    auto c;
    c = 0;
    if b[1] > 0 c = @8 *(b[0] + b[1] - 1);
    c;
}

// tg_kb_pc(b): предпоследний байт, 0 если байт меньше двух
tg_kb_pc(b) {
    auto c;
    c = 0;
    if b[1] > 1 c = @8 *(b[0] + b[1] - 2);
    c;
}

// tg_kb_is_url(s): 1 — строка начинается с http:// или https://
// (побайтово, без strncmp: чтение не выходит за NUL — каждый следующий байт
// проверяется только после совпадения предыдущих)
tg_kb_is_url(s) {
    auto ok;
    ok = 0;
    if s != 0 {
        if @8 *s == 104 {              // 'h'
            if @8 *(s+1) == 116 {      // 't'
                if @8 *(s+2) == 116 {  // 't'
                    if @8 *(s+3) == 112 {  // 'p'
                        if @8 *(s+4) == 58 {   // ':', http://
                            if @8 *(s+5) == 47 {
                                if @8 *(s+6) == 47 ok = 1;
                            }
                        } else if @8 *(s+4) == 115 {  // 's'
                            if @8 *(s+5) == 58 {
                                if @8 *(s+6) == 47 {
                                    if @8 *(s+7) == 47 ok = 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ok;
}

// ===== Inline-клавиатура: {"inline_keyboard":[[...]]} =====

// tg_kb_begin(b): сброс слота + opening prefix
tg_kb_begin(b) {
    tg_buf_reset(b);
    tg_buf_add(b, "{\"inline_keyboard\":[");
    1;
}

// tg_kb_open(b): подготовить место для следующей кнопки текущего ряда
// (первый ряд открывает '[', после tg_kb_row разделитель ',', пустой ряд —
// ничего). begin не вызывался — открывает за собой.
tg_kb_open(b) {
    auto lc;
    auto pc;
    if b[1] == 0 tg_kb_begin(b);
    lc = tg_kb_lc(b);
    pc = tg_kb_pc(b);
    if lc == 125 {
        tg_buf_add(b, ",");
    } else if lc == 91 {
        if pc == 58 tg_buf_add(b, "[");
    }
    1;
}

// tg_kb_push(b, text, key, val): сам объект кнопки {"text":..,"key":..}
// (оба значения через tg_json_escape; эскейп копируется в буфер сразу —
// tg_escbuf общий, следующий вызов его перезаписывает)
tg_kb_push(b, text, key, val) {
    auto e;
    tg_buf_add(b, "{\"text\":\"");
    e = tg_json_escape(text);
    tg_buf_add(b, e);
    tg_buf_add(b, "\",\"");
    tg_buf_add(b, key);
    tg_buf_add(b, "\":\"");
    e = tg_json_escape(val);
    tg_buf_add(b, e);
    tg_buf_add(b, "\"}");
    1;
}

// tg_kb_url_btn(b, text, url): кнопка {"text":..,"url":..}
tg_kb_url_btn(b, text, url) {
    tg_kb_open(b);
    tg_kb_push(b, text, "url", url);
    1;
}

// tg_kb_btn(b, text, data): кнопка {"text":..,"callback_data":..};
// data с http(s)-префиксом → url-кнопка (контракт Task 8)
tg_kb_btn(b, text, data) {
    auto u;
    u = tg_kb_is_url(data);
    if u == 1 {
        tg_kb_url_btn(b, text, data);
    } else {
        tg_kb_open(b);
        tg_kb_push(b, text, "callback_data", data);
    }
    1;
}

// tg_kb_row(b): закрыть текущий ряд, открыть следующий ("],[")
tg_kb_row(b) {
    auto lc;
    if b[1] > 0 {
        lc = tg_kb_lc(b);
        if lc == 125 tg_buf_add(b, "],[");
    }
    1;
}

// tg_kb_done(b): финализировать — возврат готовой строки JSON-объекта
tg_kb_done(b) {
    auto lc;
    auto pc;
    if b[1] == 0 tg_kb_begin(b);
    lc = tg_kb_lc(b);
    pc = tg_kb_pc(b);
    if lc == 125 {
        tg_buf_add(b, "]");
    } else if lc == 91 {
        if pc == 44 {
            b[1] = b[1] - 2;                 // срезать висячий хвост ",["
            *(b[0] + b[1]) !8 0;
        }
    }
    tg_buf_add(b, "]}");
    b[0];
}

// ===== Reply-клавиатура: {"keyboard":[[...]],"resize_keyboard":true} =====
// Кнопки — простые строки (API разрешает String вместо KeyboardButton;
// request_contact/web_app и пр. — через tg_call с готовым JSON).

// tg_rkb_begin(b): сброс слота + opening prefix
tg_rkb_begin(b) {
    tg_buf_reset(b);
    tg_buf_add(b, "{\"keyboard\":[");
    1;
}

// tg_rkb_open(b): место для следующей текстовой кнопки
// (после кнопки lc='"' → ',', первый ряд — '[', после row ряд уже открыт)
tg_rkb_open(b) {
    auto lc;
    auto pc;
    if b[1] == 0 tg_rkb_begin(b);
    lc = tg_kb_lc(b);
    pc = tg_kb_pc(b);
    if lc == 34 {
        tg_buf_add(b, ",");
    } else if lc == 91 {
        if pc == 58 tg_buf_add(b, "[");
    }
    1;
}

// tg_rkb_btn(b, text): текстовая кнопка-строка "text" (эскейп как в JSON)
tg_rkb_btn(b, text) {
    auto e;
    tg_rkb_open(b);
    tg_buf_add(b, "\"");
    e = tg_json_escape(text);
    tg_buf_add(b, e);
    tg_buf_add(b, "\"");
    1;
}

// tg_rkb_row(b): закрыть текущий ряд, открыть следующий
tg_rkb_row(b) {
    auto lc;
    if b[1] > 0 {
        lc = tg_kb_lc(b);
        if lc == 34 tg_buf_add(b, "],[");
    }
    1;
}

// tg_rkb_done(b): финализировать — возврат готовой строки JSON-объекта
tg_rkb_done(b) {
    auto lc;
    auto pc;
    if b[1] == 0 tg_rkb_begin(b);
    lc = tg_kb_lc(b);
    pc = tg_kb_pc(b);
    if lc == 34 {
        tg_buf_add(b, "]");
    } else if lc == 91 {
        if pc == 44 {
            b[1] = b[1] - 2;                 // срезать висячий хвост ",["
            *(b[0] + b[1]) !8 0;
        }
    }
    tg_buf_add(b, "],\"resize_keyboard\":true}");
    b[0];
}

// ===== Готовые reply-объекты (строковые литералы/статические слоты) =====
// Назначение: аргумент tg_param_json(..., "reply_markup"/"reply_parameters"/
// "link_preview_options", ...) — вставка в тело запроса БЕЗ кавычек.

// tg_kb_remove(): убрать reply-клавиатуру
tg_kb_remove() {
    "{\"remove_keyboard\":true}";
}

// tg_kb_fr[3]: Buf-слот результата tg_kb_force_reply (живёт до следующего
// вызова; статический — аргумент принимается сразу в tg_param_json)
tg_kb_fr[3];

// tg_kb_force_reply(placeholder): показать интерфейс ответа;
// placeholder = 0 → без input_field_placeholder
tg_kb_force_reply(placeholder) {
    auto e;
    tg_buf_reset(&tg_kb_fr);
    tg_buf_add(&tg_kb_fr, "{\"force_reply\":true");
    if placeholder != 0 {
        tg_buf_add(&tg_kb_fr, ",\"input_field_placeholder\":\"");
        e = tg_json_escape(placeholder);
        tg_buf_add(&tg_kb_fr, e);
        tg_buf_add(&tg_kb_fr, "\"");
    }
    tg_buf_add(&tg_kb_fr, "}");
    tg_kb_fr[0];
}

// tg_kb_rp[3]: Buf-слот результата tg_reply_params
tg_kb_rp[3];

// tg_reply_params(msg_id): {"message_id":N} — для
// tg_param_json(..., "reply_parameters", ...)
tg_reply_params(msg_id) {
    tg_buf_reset(&tg_kb_rp);
    tg_buf_add(&tg_kb_rp, "{\"message_id\":");
    tg_buf_addnum(&tg_kb_rp, msg_id);
    tg_buf_add(&tg_kb_rp, "}");
    tg_kb_rp[0];
}

// tg_link_preview_off(): отключить превью ссылок — для
// tg_param_json(..., "link_preview_options", ...)
tg_link_preview_off() {
    "{\"is_disabled\":true}";
}
