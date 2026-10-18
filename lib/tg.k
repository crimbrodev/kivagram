// kivagram — Telegram Bot API library for Kiva
// Подключается склейкой: build.sh склеивает этот файл с файлом бота/теста.
// Требует тулчейн crimbrodev/kivac-plus (master >= 60ca869: function
// pointers, UTF-8 identifiers, raised string literal limits).
//
// Внутренние правила: все символы с префиксом tg_; вызов fn-указателя —
// только через локальную переменную; функция используется как значение
// только после определения; <=6 аргументов на вызов.

// ===== Buffers =====

extern malloc
extern free
extern memcpy
extern strlen
extern sprintf

// scratch: 2048 слов = 16 КБ рабочего пространства форматирования
scratchbuf[2048];
scrpos;

// tg_scratch(): сброс позиции, указатель на начало scratch
tg_scratch() {
    scrpos = 0;
    &scratchbuf;
}

// tg_scr_b(c): дописать один байт в scratch
tg_scr_b(c) {
    *(&scratchbuf+scrpos) !8 c;
    scrpos = scrpos + 1;
    1;
}

// tg_scr_add(s): дописать C-строку в scratch, вернуть указатель на кусок
tg_scr_add(s) {
    auto i;
    auto start;
    i = 0;
    start = scrpos;
    while @8 *(s+i) {
        tg_scr_b(@8 *(s+i));
        i = i + 1;
    }
    *(&scratchbuf+scrpos) !8 0;  // NUL без продвижения позиции
    &scratchbuf + start;
}

// tg_json_escape(src): экранировать src как содержимое JSON-строки,
// дописать в scratch, вернуть указатель на кусок.
// " -> \", \ -> \\, \n -> \n, \r -> \r, \t -> \t, прочие <0x20 -> \u00XX,
// байты >=0x80 (UTF-8) — как есть.
tg_json_escape(src) {
    auto i;
    auto c;
    auto h;
    auto start;
    i = 0;
    start = scrpos;
    while @8 *(src+i) {
        c = @8 *(src+i);
        if c == 34 {
            tg_scr_b(92);
            tg_scr_b(34);
        } else if c == 92 {
            tg_scr_b(92);
            tg_scr_b(92);
        } else if c == 10 {
            tg_scr_b(92);
            tg_scr_b(110);
        } else if c == 13 {
            tg_scr_b(92);
            tg_scr_b(114);
        } else if c == 9 {
            tg_scr_b(92);
            tg_scr_b(116);
        } else if c < 32 {
            tg_scr_b(92);
            tg_scr_b(117);
            tg_scr_b(48);
            tg_scr_b(48);
            h = (c >> 4) & 15;
            if h < 10 tg_scr_b(48 + h); else tg_scr_b(87 + h);
            h = c & 15;
            if h < 10 tg_scr_b(48 + h); else tg_scr_b(87 + h);
        } else {
            tg_scr_b(c);
        }
        i = i + 1;
    }
    *(&scratchbuf+scrpos) !8 0;  // NUL без продвижения позиции
    &scratchbuf + start;
}

// Buf-слот: слова 0 ptr*, 1 len, 2 cap. Поверх malloc, рост ×2.
// Передаётся как &слот.

tg_buf_init(b) {
    b[0] = 0;
    b[1] = 0;
    b[2] = 0;
    1;
}

tg_buf_add(b, s) {
    auto n;
    auto need;
    auto np;
    n = strlen(s);
    need = b[1] + n + 1;
    if need > b[2] {
        np = malloc(need + need);
        if b[0] memcpy(np, b[0], b[1]);
        if b[0] free(b[0]);
        b[0] = np;
        b[2] = need + need;
    }
    memcpy(b[0] + b[1], s, n + 1);
    b[1] = b[1] + n;
    1;
}

// tg_buf_addnum(b, num): decimal через sprintf в scratch
tg_buf_addnum(b, num) {
    auto p;
    p = tg_scratch();
    sprintf(p, "%d", num);
    tg_buf_add(b, p);
}

tg_buf_reset(b) {
    b[1] = 0;
    1;
}

tg_buf_free(b) {
    if b[0] free(b[0]);
    b[0] = 0;
    b[1] = 0;
    b[2] = 0;
    1;
}

// ===== JSON scan =====
// Dot-path сканер по сырому тексту ответа. Указатели возвращаются ВНУТРЬ
// resp — жизнь до следующего вызова API. Malformed JSON: циклы
// останавливаются на NUL, поведение не определено (Telegram валиден).

extern strtoull

tg_last_err;   // 0 — ок, 1 — путь не найден

// tg_skipspace(p): пробелы/табы/переводы → p
tg_skipspace(p) {
    auto c;
    auto done;
    done = 0;
    while done == 0 {
        c = @8 *p;
        if c == 32 p = p + 1;
        else if c == 10 p = p + 1;
        else if c == 13 p = p + 1;
        else if c == 9 p = p + 1;
        else done = 1;
    }
    p;
}

// tg_skipstr(p): p — на opening "; возврат — за закрывающей кавычкой
tg_skipstr(p) {
    auto c;
    auto done;
    auto r;
    p = p + 1;
    done = 0;
    while done == 0 {
        c = @8 *p;
        if c == 0 {
            done = 1;
        } else if c == 92 {
            p = p + 2;
        } else if c == 34 {
            done = 2;
        } else {
            p = p + 1;
        }
    }
    r = p;
    if done == 2 r = p + 1;
    r;
}

// tg_skipdepth(p): p — на { или [; возврат — за закрывающей скобкой
tg_skipdepth(p) {
    auto c;
    auto dep;
    auto done;
    dep = 1;
    p = p + 1;
    done = 0;
    while done == 0 {
        c = @8 *p;
        if c == 0 done = 1;
        else if c == 34 p = tg_skipstr(p);
        else if c == 123 {
            dep = dep + 1;
            p = p + 1;
        } else if c == 91 {
            dep = dep + 1;
            p = p + 1;
        } else if c == 125 {
            dep = dep - 1;
            p = p + 1;
        } else if c == 93 {
            dep = dep - 1;
            p = p + 1;
        } else p = p + 1;
        if dep == 0 done = 1;
    }
    p;
}

// tg_skipval(p): пропустить одно значение; возврат — позиция ПОСЛЕ значения
tg_skipval(p) {
    auto c;
    c = @8 *p;
    if c == 34 {
        tg_skipstr(p);
    } else if c == 123 {
        tg_skipdepth(p);
    } else if c == 91 {
        tg_skipdepth(p);
    } else {
        // литерал: true/false/null/число — до разделителя
        while 1 {
            c = @8 *p;
            if c == 0 break;
            if c == 44 break;
            if c == 125 break;
            if c == 93 break;
            if c == 32 break;
            if c == 10 break;
            if c == 13 break;
            if c == 9 break;
            p = p + 1;
        }
        p;
    }
}

// tg_keyeqn(ks, se, seg, m): байтовое равенство ключа[ks,se) с seg[0,m)
tg_keyeqn(ks, se, seg, m) {
    auto i;
    auto ok;
    ok = 1;
    if (se - ks) != m ok = 0;
    if ok {
        i = 0;
        while i < m {
            if @8 *(ks+i) != @8 *(seg+i) ok = 0;
            i = i + 1;
        }
    }
    ok;
}

// tg_find_key(obj, key, m): obj — на {; ищет ключ key[0,m) → ptr на значение
tg_find_key(obj, key, m) {
    auto p;
    auto e;
    auto v;
    auto nv;
    auto r;
    auto done;
    r = 0;
    done = 0;
    p = tg_skipspace(obj + 1);
    while done == 0 {
        if @8 *p == 34 {
            e = tg_skipstr(p);
            v = tg_skipspace(e);
            if @8 *v == 58 {
                v = tg_skipspace(v + 1);
                if tg_keyeqn(p + 1, e - 1, key, m) {
                    r = v;
                    done = 1;
                } else {
                    nv = tg_skipval(v);
                    p = tg_skipspace(nv);
                    if @8 *p == 44 p = tg_skipspace(p + 1);
                    if @8 *p == 125 done = 1;
                }
            } else {
                done = 1;
            }
        } else {
            done = 1;
        }
        if @8 *p == 0 done = 1;
    }
    r;
}

// tg_arrelt(arr, idx): arr — на [; ptr на элемент idx или 0
tg_arrelt(arr, idx) {
    auto p;
    auto i;
    auto r;
    r = 0;
    p = tg_skipspace(arr + 1);
    if @8 *p != 93 {
        i = 0;
        while i < idx {
            p = tg_skipval(p);
            p = tg_skipspace(p);
            if @8 *p == 44 p = tg_skipspace(p + 1);
            i = i + 1;
        }
        if @8 *p == 93 r = 0;
        else if @8 *p == 0 r = 0;
        else r = p;
    }
    r;
}

// tg_find(resp, path): ptr на значение по dot-path или 0
tg_find(resp, path) {
    auto cur;
    auto seg;
    auto m;
    auto i;
    auto num;
    auto isnum;
    cur = tg_skipspace(resp);
    seg = path;
    while @8 *seg {
        m = 0;
        while @8 *(seg+m) {
            if @8 *(seg+m) == 46 break;
            m = m + 1;
        }
        if m == 0 {
            cur = 0;
            seg = seg + m + 1;
        } else if cur == 0 {
            seg = seg + m + 1;
        } else {
            isnum = 1;
            i = 0;
            while i < m {
                if @8 *(seg+i) < 48 isnum = 0;
                if @8 *(seg+i) > 57 isnum = 0;
                i = i + 1;
            }
            if isnum {
                num = 0;
                i = 0;
                while i < m {
                    num = num * 10 + (@8 *(seg+i) - 48);
                    i = i + 1;
                }
                if @8 *cur == 91 {
                    cur = tg_arrelt(cur, num);
                } else {
                    cur = 0;
                }
            } else {
                cur = tg_find_key(cur, seg, m);
            }
            seg = seg + m + 1;
        }
    }
    cur;
}

// tg_get(resp, path): ptr на значение или 0; tg_last_err — флаг промаха
tg_get(resp, path) {
    auto r;
    r = tg_find(resp, path);
    tg_last_err = 0;
    if r == 0 tg_last_err = 1;
    r;
}

// tg_get_num(resp, path): число; 0 — не найдено/не число
tg_get_num(resp, path) {
    auto r;
    auto n;
    n = 0;
    r = tg_get(resp, path);
    if r != 0 n = strtoull(r, 0, 10);
    n;
}

// tg_get_bool(resp, path): 1 — литерал true, 0 — иначе
tg_get_bool(resp, path) {
    auto r;
    auto b;
    b = 0;
    r = tg_get(resp, path);
    if r != 0 {
        if @8 *r == 116 b = 1;
    }
    b;
}

// tg_get_str(resp, path): копия значения в scratch (кавычки сняты,
// анэскейп \" \\ \n \t \r; \uXXXX не поддержан — Telegram шлёт UTF-8 сырыми);
// 0 — не найдено
tg_get_str(resp, path) {
    auto r;
    auto p;
    auto c;
    auto e;
    auto out;
    auto done;
    out = 0;
    r = tg_get(resp, path);
    if r != 0 {
        out = tg_scratch();
        if @8 *r == 34 {
            p = r + 1;
            done = 0;
            while done == 0 {
                c = @8 *p;
                if c == 0 done = 1;
                else if c == 34 done = 2;
                else if c == 92 {
                    e = @8 *(p+1);
                    if e == 34 tg_scr_b(34);
                    else if e == 92 tg_scr_b(92);
                    else if e == 110 tg_scr_b(10);
                    else if e == 116 tg_scr_b(9);
                    else if e == 114 tg_scr_b(13);
                    else tg_scr_b(e);
                    p = p + 2;
                } else {
                    tg_scr_b(c);
                    p = p + 1;
                }
            }
        } else {
            done = 0;
            while done == 0 {
                c = @8 *r;
                if c == 0 done = 1;
                else if c == 44 done = 1;
                else if c == 125 done = 1;
                else if c == 93 done = 1;
                else if c == 32 done = 1;
                else if c == 10 done = 1;
                else if c == 13 done = 1;
                else if c == 9 done = 1;
                else {
                    tg_scr_b(c);
                    r = r + 1;
                }
            }
        }
        *(&scratchbuf+scrpos) !8 0;
    }
    out;
}

// tg_count(resp, path): число элементов массива по пути; 0 — не массив/пусто
tg_count(resp, path) {
    auto r;
    auto p;
    auto n;
    auto done;
    n = 0;
    r = tg_get(resp, path);
    if r != 0 {
        if @8 *r == 91 {
            p = tg_skipspace(r + 1);
            if @8 *p != 93 {
                n = 1;
                done = 0;
                while done == 0 {
                    p = tg_skipval(p);
                    p = tg_skipspace(p);
                    if @8 *p == 44 {
                        n = n + 1;
                        p = tg_skipspace(p + 1);
                    } else {
                        done = 1;
                    }
                    if @8 *p == 0 done = 1;
                }
            }
        }
    }
    n;
}

// ===== Params =====
// Билдер параметров запроса: Params = Buf-слот (0 ptr*, 1 len, 2 cap).
// Жизнь результата — до следующего tg_params_reset того же слота.

// tg_params_reset(b): сброс + opening brace
tg_params_reset(b) {
    tg_buf_reset(b);
    tg_buf_add(b, "{");
    1;
}

// tg_param_str(b, key, val): "key":"val" (оба через tg_json_escape) + ,
tg_param_str(b, key, val) {
    tg_buf_add(b, "\"");
    tg_buf_add(b, tg_json_escape(key));
    tg_buf_add(b, "\":\"");
    tg_buf_add(b, tg_json_escape(val));
    tg_buf_add(b, "\",");
    1;
}

// tg_param_num(b, key, num): "key":число + ,
tg_param_num(b, key, num) {
    tg_buf_add(b, "\"");
    tg_buf_add(b, tg_json_escape(key));
    tg_buf_add(b, "\":");
    tg_buf_addnum(b, num);
    tg_buf_add(b, ",");
    1;
}

// tg_param_json(b, key, json): "key":<сырой json> + , (reply_markup и т.п.)
tg_param_json(b, key, json) {
    tg_buf_add(b, "\"");
    tg_buf_add(b, tg_json_escape(key));
    tg_buf_add(b, "\":");
    tg_buf_add(b, json);
    tg_buf_add(b, ",");
    1;
}

// tg_params_done(b): убрать последнюю запятую, закрыть скобку; возврат — тело
tg_params_done(b) {
    if b[1] > 0 {
        if @8 *(b[0] + b[1] - 1) == 44 {
            b[1] = b[1] - 1;
            *(b[0] + b[1]) !8 0;
        }
    }
    tg_buf_add(b, "}");
    b[0];
}
