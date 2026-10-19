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

// ===== Escape buffer =====
// tg_json_escape пишет в ВЫДЕЛЕННЫЙ буфер, а не в scratch: значение может
// ЖИТЬ в scratch (sprintf) и не должно быть уничтожено сборкой параметров.
tg_escbuf[4096];   // 32 КБ (текст ≤4096 × 6 на худший случай)
tg_escpos;
tg_numbuf[8];      // 64 байта — вывод tg_buf_addnum (тоже вне scratch)

// tg_eb_b(c): дописать байт в escape-буфер (с отсечкой по границе)
tg_eb_b(c) {
    if tg_escpos < 32766 {
        *(&tg_escbuf+tg_escpos) !8 c;
        tg_escpos = tg_escpos + 1;
    }
    1;
}

// tg_json_escape(src): экранировать src как содержимое JSON-строки,
// дописать в tg_escbuf, вернуть указатель.
// " -> \", \ -> \\, \n -> \n, \r -> \r, \t -> \t, прочие <0x20 -> \u00XX,
// байты >=0x80 (UTF-8) — как есть.
tg_json_escape(src) {
    auto i;
    auto c;
    auto h;
    auto done;
    i = 0;
    tg_escpos = 0;
    done = 0;
    while done == 0 {
        c = @8 *(src+i);
        if c == 0 done = 1;
        else if tg_escpos > 32700 done = 1;
        else {
            if c == 34 {
                tg_eb_b(92);
                tg_eb_b(34);
            } else if c == 92 {
                tg_eb_b(92);
                tg_eb_b(92);
            } else if c == 10 {
                tg_eb_b(92);
                tg_eb_b(110);
            } else if c == 13 {
                tg_eb_b(92);
                tg_eb_b(114);
            } else if c == 9 {
                tg_eb_b(92);
                tg_eb_b(116);
            } else if c < 32 {
                tg_eb_b(92);
                tg_eb_b(117);
                tg_eb_b(48);
                tg_eb_b(48);
                h = (c >> 4) & 15;
                if h < 10 tg_eb_b(48 + h); else tg_eb_b(87 + h);
                h = c & 15;
                if h < 10 tg_eb_b(48 + h); else tg_eb_b(87 + h);
            } else {
                tg_eb_b(c);
            }
            i = i + 1;
        }
    }
    *(&tg_escbuf+tg_escpos) !8 0;
    &tg_escbuf;
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

// tg_buf_addnum(b, num): decimal через sprintf в tg_numbuf (ВНЕ scratch —
// сброс scratch затирал бы значения-жертвы, живущие в нём).
// NB: %ld — Kiva передаёт 64-бит слова, а реальные Telegram-id > 2^31
tg_buf_addnum(b, num) {
    sprintf(&tg_numbuf, "%ld", num);
    tg_buf_add(b, &tg_numbuf);
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
            seg = seg + m;
            if @8 *seg == 46 seg = seg + 1;
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
            seg = seg + m;
            if @8 *seg == 46 seg = seg + 1;
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
// tg_hex1(c): значение hex-цифры0-15; 16 — не цифра (флаг, без отрицательных)
tg_hex1(c) {
    auto v;
    v = 16;
    if c >= 48 {
        if c <= 57 v = c - 48;
    }
    if c >= 97 {
        if c <= 102 v = c - 87;
    }
    if c >= 65 {
        if c <= 70 v = c - 55;
    }
    v;
}

// tg_utf8_put(cp): дописать кодпоинт в scratch как UTF-8
tg_utf8_put(cp) {
    if cp < 128 {
        tg_scr_b(cp);
    } else {
        if cp < 2048 {
            tg_scr_b(192 + (cp >> 6));
            tg_scr_b(128 + (cp & 63));
        } else {
            if cp < 65536 {
                tg_scr_b(224 + (cp >> 12));
                tg_scr_b(128 + ((cp >> 6) & 63));
                tg_scr_b(128 + (cp & 63));
            } else {
                tg_scr_b(240 + (cp >> 18));
                tg_scr_b(128 + ((cp >> 12) & 63));
                tg_scr_b(128 + ((cp >> 6) & 63));
                tg_scr_b(128 + (cp & 63));
            }
        }
    }
}

// tg_uni_put(bs): bs — на \uXXXX (возможно парой \uD83D\uDE00);
// пишет UTF-8 в scratch, возврат — съеденные байты (6/10), 0 — не \u
tg_uni_put(bs) {
    auto cp;
    auto lo;
    auto ok;
    auto hok;
    auto k;
    auto h;
    auto adv;
    adv = 0;
    if @8 *(bs+1) == 117 {
        adv = 6;
        cp = 0;
        ok = 1;
        k = 0;
        while k < 4 {
            h = tg_hex1(@8 *(bs+2+k));
            if h > 15 ok = 0;
            cp = cp * 16 + (h & 15);
            k = k + 1;
        }
        if ok {
            if cp >= 55296 {
                if cp <= 56319 {
                    // высокий суррогат — обязателен низкий следом
                    ok = 0;
                    if @8 *(bs+6) == 92 {
                        if @8 *(bs+7) == 117 {
                            lo = 0;
                            hok = 1;
                            k = 0;
                            while k < 4 {
                                h = tg_hex1(@8 *(bs+8+k));
                                if h > 15 hok = 0;
                                lo = lo * 16 + (h & 15);
                                k = k + 1;
                            }
                            if hok {
                                if lo >= 56320 {
                                    if lo <= 57343 {
                                        cp = 65536 + ((cp - 55296) * 1024) + (lo - 56320);
                                        adv = 12;
                                        ok = 1;
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // одинокий низкий суррогат — невалиден
                    if cp >= 56320 {
                        if cp <= 57343 ok = 0;
                    }
                }
            }
        }
        if ok == 0 cp = 65533;   // U+FFFD — замена при невалидном escape
        tg_utf8_put(cp);
    }
    adv;
}

// анэскейп \" \\ \n \t \r \b \f и \uXXXX (суррогатные пары);
// 0 — не найдено
tg_get_str(resp, path) {
    auto r;
    auto p;
    auto c;
    auto e;
    auto out;
    auto done;
    auto adv;
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
                    adv = 2;
                    if e == 117 {
                        adv = tg_uni_put(p);
                        if adv == 0 adv = 2;
                    } else {
                        if e == 34 tg_scr_b(34);
                        else if e == 92 tg_scr_b(92);
                        else if e == 110 tg_scr_b(10);
                        else if e == 116 tg_scr_b(9);
                        else if e == 114 tg_scr_b(13);
                        else if e == 98 tg_scr_b(8);
                        else if e == 102 tg_scr_b(12);
                        else tg_scr_b(e);
                    }
                    p = p + adv;
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

// ===== HTTP =====
// Транспорт: popen + curl. POST-тело — во временный файл tg_req<pid>,
// ответ — в глобальный Buf-слот httpresp. Одинаково синхронно, порядок
// вызовов сохраняется.

extern popen
extern pclose
extern fopen
extern fclose
extern fwrite
extern fgets
extern remove
extern strcpy
extern getpid
extern printf
extern sleep

httpresp[3];       // Buf-слот ответа
fnamebuf[32];      // имя временного файла (256 байт)
httpurl[64];       // копия URL вне scratch (512 байт)
readbuf[64];       // приёмник fgets (512 байт)
tg_http_last_ok;   // 1 — curl exit 0 и ответ получен
tg_http_curlcode;  // код выхода curl последнего вызова

tg_http_body() {
    httpresp[0];
}

// tg_http_post(url, body*): POST тела body на url; возврат — 1 при curl exit 0
tg_http_post(url, body) {
    auto f;
    auto n;
    auto st;
    auto ok;
    sprintf(&fnamebuf, "tg_req%d", getpid());
    tg_http_last_ok = 0;
    tg_http_curlcode = 99;
    f = fopen(&fnamebuf, "wb");
    ok = 0;
    if f != 0 {
        n = strlen(body);
        if n > 0 fwrite(body, 1, n, f);
        fclose(f);
        strcpy(&httpurl, url);
        sprintf(tg_scratch(), "curl -s -m 35 -H \"Content-Type: application/json\" -d @%s '%s'", &fnamebuf, &httpurl);
        f = popen(&scratchbuf, "r");
        if f != 0 {
            tg_buf_reset(&httpresp);
            while fgets(&readbuf, 512, f) tg_buf_add(&httpresp, &readbuf);
            st = pclose(f);
            tg_http_curlcode = (st >> 8) & 255;
            if tg_http_curlcode == 0 {
                ok = 1;
                tg_http_last_ok = 1;
            }
        }
        remove(&fnamebuf);
    }
    ok;
}

// ===== API call =====

// tg_default_on_error(bot, method, code, desc): дефолтный принтер ошибок
tg_default_on_error(bot, method, code, desc) {
    printf("[tg] %s error %d: %s\n", method, code, desc);
    1;
}

// ===== Compose =====
tg_composed[2048];   // "<url>|<json>" композиции последнего вызова (16 КБ)
tg_dry_run;          // 1 — композировать, но не отправлять (тесты/отладка)
tg_paramslot[3];     // внутренний Params-слот обёрток

// tg_compose_body(bot, method, params*|0): <url>|<json> в tg_composed;
// возврат — указатель на начало (url до '|', тело после)
tg_compose_body(bot, method, params) {
    auto n;
    auto p;
    n = sprintf(&tg_composed, "%s/bot%s/%s", bot[1], bot[0], method);
    *(&tg_composed + n) !8 124;   // '|' вместо NUL
    p = &tg_composed;
    p = p + n + 1;
    if params == 0 {
        *p !8 0;
    } else {
        strcpy(p, params);
    }
    &tg_composed;
}

// tg_call(bot, method, params*|0): вызов Bot API. params==0 → пустое тело.
// 429 → on_error + sleep(retry_after), максимум 3 попытки. Возврат 1 — ok:true.
// dry-режим: композиция готова в tg_composed, HTTP пропускается, возврат 1.
tg_call(bot, method, params) {
    auto attempt;
    auto ok;
    auto oe;
    auto code;
    auto desc;
    auto retry;
    auto url;
    auto body;
    auto i;
    auto c;
    attempt = 0;
    ok = 0;
    tg_compose_body(bot, method, params);
    if tg_dry_run == 1 {
        ok = 1;
    }
    if tg_dry_run == 0 {
        // разбить композицию на месте: '|' → NUL; url — начало, body — после
        url = &tg_composed;
        i = 0;
        c = @8 *url;
        while c != 124 {
            i = i + 1;
            c = @8 *(url + i);
        }
        *(&tg_composed + i) !8 0;
        body = &tg_composed;
        body = body + i + 1;
        while attempt < 3 {
            tg_http_post(url, body);
            if tg_http_last_ok {
                if tg_get_bool(tg_http_body(), "ok") {
                    ok = 1;
                    attempt = 3;
                } else {
                    code = tg_get_num(tg_http_body(), "error_code");
                    desc = tg_get_str(tg_http_body(), "description");
                    if desc == 0 desc = "no description";
                    oe = bot[7];
                    oe(bot, method, code, desc);
                    if code == 429 {
                        retry = tg_get_num(tg_http_body(), "parameters.retry_after");
                        if retry > 0 {
                            sleep(retry);
                        } else {
                            sleep(1);
                        }
                        attempt = attempt + 1;
                    } else {
                        attempt = 3;
                    }
                }
            } else {
                oe = bot[7];
                oe(bot, method, tg_http_curlcode, "transport error");
                attempt = 3;
            }
        }
    }
    ok;
}

// ===== Bot & registry & dispatch =====
// Bot-слот (индексы слов): 0 token*, 1 base_url*, 2 bot_id, 3 username*,
// 4 handlers*, 5 handlers_len, 6 handlers_cap, 7 on_error fn*, 8 offset,
// 9 offset_file*, 10 last_resp*, 11 polling_flag.
// Handler-слот (4 слова): 0 name*, 1 kind, 2 filter fn*, 3 handler fn*.

extern strcmp

tg_cur_name;   // имя текущего обрабатываемого хендлера — для встроенных фильтров

// tg_flt_cmd(ctx): встроенный фильтр имени команды — сравнивает имя из
// текста апдейта (после '/', до '@'/' '/конца, ASCII-lowercase) с tg_cur_name.
// NB: tg_get возвращает raw-указатель — для строк значение начинается с
// opening-quote, его и пропускаем.
tg_flt_cmd(ctx) {
    auto upd;
    auto text;
    auto p;
    auto c;
    auto done;
    auto s;
    auto ok;
    upd = ctx[1];
    text = tg_get(upd, "message.text");
    ok = 0;
    if text != 0 {
        if @8 *text == 34 {
            p = text + 1;
            if @8 *p == 47 {
                s = tg_scratch();
                p = p + 1;
                done = 0;
                while done == 0 {
                    c = @8 *p;
                    if c == 0 done = 1;
                    else if c == 32 done = 1;
                    else if c == 64 done = 1;
                    else {
                        if c > 64 {
                            if c < 91 c = c + 32;
                        }
                        tg_scr_b(c);
                        p = p + 1;
                    }
                }
                *(&scratchbuf+scrpos) !8 0;
                if strcmp(s, tg_cur_name) == 0 ok = 1;
            }
        }
    }
    ok;
}

// tg_flt_msg(ctx): встроенный фильтр «есть message без text» (фото и т.п.)
tg_flt_msg(ctx) {
    auto upd;
    auto ok;
    upd = ctx[1];
    ok = 0;
    if tg_get(upd, "message") != 0 {
        if tg_get(upd, "message.text") == 0 ok = 1;
    }
    ok;
}

// tg_bot(token): malloc-слот бота, base_url и on_error — дефолтные
tg_bot(token) {
    auto b;
    auto hp;
    auto i;
    b = malloc(96);   // 12 слов
    i = 0;
    while i < 12 {
        *(b + i*8) = 0;
        i = i + 1;
    }
    *b = token;
    *(b + 8) = "https://api.telegram.org";
    *(b + 56) = &tg_default_on_error;
    hp = malloc(256);   // 8 записей × 4 слова
    *(b + 32) = hp;
    *(b + 40) = 0;      // handlers_len
    *(b + 48) = 8;      // handlers_cap
    b;
}

tg_bot_set_username(bot, name) {
    *(bot + 24) = name;
    1;
}

tg_stop(bot) {
    *(bot + 88) = 0;   // polling_flag
    1;
}

// tg_reg(bot, kind, name, filter, fn): примитив реестра; замена по имени
// сохраняет позицию; рост ×2. NB: сравнения < / >= в Kive БЕЗЗНАКОВЫЕ —
// отрицательные сентинелы (fpos=-1) недопустимы, используем флаг found.
tg_reg(bot, kind, name, filter, fn) {
    auto hp;
    auto len;
    auto cap;
    auto i;
    auto h;
    auto nh;
    auto fpos;
    auto found;
    hp = bot[4];
    len = bot[5];
    cap = bot[6];
    found = 0;
    fpos = 0;
    i = 0;
    while i < len {
        if found == 0 {
            h = hp + i * 32;
            if strcmp(*h, name) == 0 {
                found = 1;
                fpos = i;
            }
        }
        i = i + 1;
    }
    if found == 1 {
        h = hp + fpos * 32;
        *h = name;
        *(h + 8) = kind;
        *(h + 16) = filter;
        *(h + 24) = fn;
    } else {
        if len >= cap {
            nh = malloc(cap * 64);   // 2*cap записей × 32 байта
            memcpy(nh, hp, len * 32);
            free(hp);
            hp = nh;
            cap = cap + cap;
            *(bot + 32) = hp;
            *(bot + 48) = cap;
        }
        h = hp + len * 32;
        *h = name;
        *(h + 8) = kind;
        *(h + 16) = filter;
        *(h + 24) = fn;
        *(bot + 40) = len + 1;
    }
    1;
}

// ===== Сахар регистрации (kind + встроенный фильтр) =====

tg_on(bot, name, filter, fn) {
    tg_reg(bot, 0, name, filter, fn);
}

tg_on_update(bot, name, fn) {
    tg_reg(bot, 0, name, 0, fn);
}

tg_on_text(bot, name, fn) {
    tg_reg(bot, 1, name, 0, fn);
}

tg_on_command(bot, cmd, fn) {
    tg_reg(bot, 2, cmd, &tg_flt_cmd, fn);
}

tg_on_callback(bot, name, fn) {
    tg_reg(bot, 3, name, 0, fn);
}

tg_on_message(bot, name, fn) {
    tg_reg(bot, 0, name, &tg_flt_msg, fn);
}

// tg_upd_is_cmd(upd): kind=2-кандидат — entities.0 bot_command, offset 0,
// первая сущность только ASCII (v1-guard: не-ASCII → обычный текст)
tg_upd_is_cmd(upd) {
    auto ent;
    auto t;
    auto c;
    auto i;
    auto ok;
    auto done;
    ok = 0;
    ent = tg_get_str(upd, "message.entities.0.type");
    if ent != 0 {
        if strcmp(ent, "bot_command") == 0 {
            if tg_get_num(upd, "message.entities.0.offset") == 0 {
                ok = 1;
                t = tg_get(upd, "message.text");
                i = 0;
                done = 0;
                while done == 0 {
                    c = @8 *(t+i);
                    if c == 0 done = 1;
                    else if c == 32 done = 1;
                    else if c == 64 done = 1;
                    else {
                        if c > 127 ok = 0;
                        i = i + 1;
                    }
                    if ok == 0 done = 1;
                }
            }
        }
    }
    ok;
}

// tg_upd_kind(upd): классификация апдейта (см. правило матчинга v1)
tg_upd_kind(upd) {
    auto kind;
    kind = 0;
    if tg_get(upd, "callback_query") != 0 kind = 3;
    if kind == 0 {
        if tg_get(upd, "message.text") != 0 {
            kind = 1;
            if tg_upd_is_cmd(upd) kind = 2;
        }
    }
    kind;
}

// ===== Context =====
// Ctx-слот: 0 bot*, 1 upd_raw*, 2 kind, 3 chat_id, 4 msg_id, 5 from_id,
// 6 from_name*, 7 text*, 8 command*, 9 target_bot*, 10 mine, 11 exclusive,
// 12 args*, 13 cbq_id*, 14 cbq_data*, 15 inline_msg_id*, 16 strbuf*.
// strbuf — приватный строковый буфер (~8 КБ): слово 0 = позиция байт,
// строки копируются с offset 8 — поля ctx стабильны всю диспетчеризацию.

// tg_ctx_put(ctx, src): копия NUL-строки в strbuf ctx; возвращает указатель
tg_ctx_put(ctx, src) {
    auto sb;
    auto pos;
    auto r;
    auto d;
    auto c;
    sb = ctx[16];
    pos = *sb;
    r = sb + pos;
    d = r;
    c = @8 *src;
    while c != 0 {
        *d !8 c;
        d = d + 1;
        src = src + 1;
        c = @8 *src;
    }
    *d !8 0;
    *sb = (d - sb) + 1;
    r;
}

// tg_ctx_getstr(ctx, upd, path): tg_get_str + копия в strbuf; 0 если пути нет
tg_ctx_getstr(ctx, upd, path) {
    auto s;
    auto r;
    r = 0;
    s = tg_get_str(upd, path);
    if s != 0 r = tg_ctx_put(ctx, s);
    r;
}

// tg_ctx_parse_cmd(ctx, t): разбор скопированного текста kind==2:
// имя (ASCII-lowercase) → [«@цель»] → args-сплит по пробелам (cap 16)
tg_ctx_parse_cmd(ctx, t) {
    auto p;
    auto c;
    auto done;
    auto s;
    auto arr;
    auto n;
    auto r;
    auto end;
    p = t + 1;
    s = tg_scratch();
    done = 0;
    while done == 0 {
        c = @8 *p;
        if c == 64 done = 1;
        else if c == 32 done = 1;
        else if c == 0 done = 1;
        else {
            if c > 64 {
                if c < 91 c = c + 32;
            }
            tg_scr_b(c);
            p = p + 1;
        }
    }
    *(&scratchbuf+scrpos) !8 0;
    r = tg_ctx_put(ctx, s);
    ctx[8] = r;
    if @8 *p == 64 {
        p = p + 1;
        s = tg_scratch();
        done = 0;
        while done == 0 {
            c = @8 *p;
            if c == 32 done = 1;
            else if c == 0 done = 1;
            else {
                tg_scr_b(c);
                p = p + 1;
            }
        }
        *(&scratchbuf+scrpos) !8 0;
        r = tg_ctx_put(ctx, s);
        ctx[9] = r;
    }
    done = 0;
    while done == 0 {
        if @8 *p == 32 {
            p = p + 1;
        } else {
            done = 1;
        }
    }
    if @8 *p != 0 {
        arr = malloc(144);   // word0 = count + до 16 указателей
        n = 0;
        done = 0;
        while done == 0 {
            s = tg_scratch();
            end = 0;
            while end == 0 {
                c = @8 *p;
                if c == 32 end = 1;
                else if c == 0 end = 1;
                else {
                    tg_scr_b(c);
                    p = p + 1;
                }
            }
            *(&scratchbuf+scrpos) !8 0;
            n = n + 1;
            r = tg_ctx_put(ctx, s);
            *(arr + n*8) = r;
            end = 0;
            while end == 0 {
                if @8 *p == 32 {
                    p = p + 1;
                } else {
                    end = 1;
                }
            }
            if @8 *p == 0 done = 1;
            if n >= 16 done = 1;
        }
        *arr = n;
        ctx[12] = arr;
    }
    1;
}

// tg_ctx_build(bot, upd*): выделение слота + strbuf, извлечение полей с
// копированием строк, разбор первой entities-команды (v1-guard: kind=2
// требует offset==0 и только ASCII-байты — в tg_upd_is_cmd), mine/exclusive
tg_ctx_build(bot, upd) {
    auto ctx;
    auto sb;
    auto i;
    auto kind;
    auto t;
    auto s;
    ctx = malloc(136);   // 17 слов
    i = 0;
    while i < 17 {
        *(ctx + i*8) = 0;
        i = i + 1;
    }
    sb = malloc(8192);
    *sb = 8;
    ctx[16] = sb;
    ctx[0] = bot;
    ctx[1] = upd;
    kind = tg_upd_kind(upd);
    ctx[2] = kind;
    ctx[3] = tg_get_num(upd, "message.chat.id");
    ctx[4] = tg_get_num(upd, "message.message_id");
    ctx[5] = tg_get_num(upd, "message.from.id");
    ctx[6] = tg_ctx_getstr(ctx, upd, "message.from.first_name");
    if kind != 3 {
        ctx[7] = tg_ctx_getstr(ctx, upd, "message.text");
        if kind == 2 {
            tg_ctx_parse_cmd(ctx, ctx[7]);
        }
        t = ctx[9];
        if t == 0 {
            ctx[10] = 1;
            s = tg_get_str(upd, "message.chat.type");
            if s != 0 {
                if strcmp(s, "private") == 0 ctx[11] = 1;
            }
        } else {
            s = bot[3];
            if s != 0 {
                if strcmp(s, t) == 0 {
                    ctx[10] = 1;
                    ctx[11] = 1;
                }
            }
        }
    }
    if kind == 3 {
        ctx[3] = tg_get_num(upd, "callback_query.message.chat.id");
        ctx[4] = tg_get_num(upd, "callback_query.message.message_id");
        ctx[5] = tg_get_num(upd, "callback_query.from.id");
        ctx[6] = tg_ctx_getstr(ctx, upd, "callback_query.from.first_name");
        ctx[13] = tg_ctx_getstr(ctx, upd, "callback_query.id");
        ctx[14] = tg_ctx_getstr(ctx, upd, "callback_query.data");
        ctx[15] = tg_ctx_getstr(ctx, upd, "callback_query.inline_message_id");
    }
    ctx;
}

tg_ctx_free(ctx) {
    auto a;
    a = ctx[12];
    if a != 0 {
        free(a);
    }
    free(ctx[16]);
    free(ctx);
    1;
}

// ===== Аксессоры Ctx (закрытый список по таблице) =====
tg_bot_of(ctx) { ctx[0]; }
tg_raw(ctx) { ctx[1]; }
tg_kind(ctx) { ctx[2]; }
tg_chat_id(ctx) { ctx[3]; }
tg_msg_id(ctx) { ctx[4]; }
tg_from_id(ctx) { ctx[5]; }
tg_from_name(ctx) { ctx[6]; }
tg_text(ctx) { ctx[7]; }
tg_command(ctx) { ctx[8]; }
tg_target_bot(ctx) { ctx[9]; }
tg_mine(ctx) { ctx[10]; }
tg_exclusive(ctx) { ctx[11]; }
tg_cbq_id(ctx) { ctx[13]; }
tg_data(ctx) { ctx[14]; }
tg_inline_msg_id(ctx) { ctx[15]; }

tg_arg(ctx, n) {
    auto a;
    auto c;
    auto r;
    r = 0;
    a = ctx[12];
    if a != 0 {
        c = *a;
        if n < c {
            r = *(a + n*8 + 8);
        }
    }
    r;
}

// tg_handle_update(bot, upd*): kind → полный ctx (tg_ctx_build) → цикл
// хендлеров: подходит := (kind==0) или (kind==kind_апдейта), затем уточняющий
// фильтр; возврат 0 → break. Вызовы fn-указателей — через локальные копии.
tg_handle_update(bot, upd) {
    auto kind;
    auto ctx;
    auto i;
    auto n;
    auto hp;
    auto h;
    auto ok;
    auto fp;
    auto r;
    ctx = tg_ctx_build(bot, upd);
    kind = ctx[2];
    hp = bot[4];
    n = bot[5];
    i = 0;
    while i < n {
        h = hp + i * 32;
        ok = 0;
        if *(h + 8) == 0 ok = 1;
        if *(h + 8) == kind ok = 1;
        if ok {
            tg_cur_name = *h;
            fp = *(h + 16);
            if fp != 0 {
                r = fp(ctx);
                if r == 0 ok = 0;
            }
            if ok {
                fp = *(h + 24);
                r = fp(ctx);
                if r == 0 i = n;
            }
        }
        i = i + 1;
    }
    tg_ctx_free(ctx);
    1;
}

// ===== Methods =====
// Обёртки методов Bot API — каждая возвращает 0/1. ctx-версии берут bot/chat
// из ctx; явные — bot первым аргументом. Всё через tg_call (dry-режим
// композирует без отправки).

// tg_send_text(ctx, text) — ответ в чат апдейта
tg_send_text(ctx, text) {
    auto bot;
    auto body;
    auto id;
    bot = ctx[0];
    id = ctx[3];
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", id);
    tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendMessage", body);
}

// tg_send_to(bot, chat_id, text) — вне контекста, chat_id явный
tg_send_to(bot, chat_id, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendMessage", body);
}

// tg_answer(ctx, text) — ответ на callback_query
tg_answer(ctx, text) {
    auto bot;
    auto body;
    auto id;
    auto ok;
    ok = 0;
    bot = ctx[0];
    id = ctx[13];
    if id != 0 {
        tg_params_reset(&tg_paramslot);
        tg_param_str(&tg_paramslot, "callback_query_id", id);
        tg_param_str(&tg_paramslot, "text", text);
        body = tg_params_done(&tg_paramslot);
        ok = tg_call(bot, "answerCallbackQuery", body);
    }
    ok;
}

// tg_action(ctx, action) — sendChatAction ("typing" и т.п.)
tg_action(ctx, action) {
    auto bot;
    auto body;
    auto id;
    bot = ctx[0];
    id = ctx[3];
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", id);
    tg_param_str(&tg_paramslot, "action", action);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendChatAction", body);
}

// tg_edit_text(bot, chat_id, msg_id, text) — chat_id обязателен (иначе 400)
tg_edit_text(bot, chat_id, msg_id, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editMessageText", body);
}

// tg_edit_inline(bot, inline_msg_id, text) — инлайн-сообщение (без chat_id)
tg_edit_inline(bot, inline_msg_id, text) {
    auto body;
    auto ok;
    ok = 0;
    if inline_msg_id != 0 {
        tg_params_reset(&tg_paramslot);
        tg_param_str(&tg_paramslot, "inline_message_id", inline_msg_id);
        tg_param_str(&tg_paramslot, "text", text);
        body = tg_params_done(&tg_paramslot);
        ok = tg_call(bot, "editMessageText", body);
    }
    ok;
}

// tg_delete(bot, chat_id, msg_id)
tg_delete(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteMessage", body);
}

// tg_send_photo_url(bot, chat_id, url) — фото по URL
tg_send_photo_url(bot, chat_id, url) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "photo", url);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendPhoto", body);
}

// ===== Polling =====

extern strstr
extern fprintf

tg_namebuf[64];   // 512 байт — username бота из getMe (стабильная копия)
tg_offfile[32];   // 256 байт — имя файла offset: tg_<id>.offset

// tg_offset_read(bot): прочитать offset из файла; нет файла/пусто → 0
tg_offset_read(bot) {
    auto f;
    auto p;
    auto ok;
    auto n;
    n = 0;
    p = bot[9];
    if p != 0 {
        f = fopen(p, "r");
        if f != 0 {
            ok = fgets(&readbuf, 512, f);
            fclose(f);
            if ok != 0 {
                n = strtoull(&readbuf, 0, 10);
            }
        }
    }
    n;
}

// tg_offset_write(bot, off): offset — в слот (word8) и в файл
tg_offset_write(bot, off) {
    auto f;
    *(bot + 64) = off;
    f = fopen(bot[9], "w");
    if f != 0 {
        fprintf(f, "%ld", off);
        fclose(f);
        1;
    } else {
        0;
    }
}

// tg_identify(bot): getMe → bot_id/username в слот, имя файла offset.
// Ошибка → bot_id = цифры префикса токена до ':' (поллинг не блокируется),
// предупреждение в stdout, tg_last_err = 1, возврат 0.
tg_identify(bot) {
    auto id;
    auto s;
    auto r;
    r = tg_call(bot, "getMe", 0);
    if r == 1 {
        id = tg_get_num(tg_http_body(), "result.id");
        *(bot + 16) = id;
        s = tg_get_str(tg_http_body(), "result.username");
        if s != 0 {
            strcpy(&tg_namebuf, s);
            *(bot + 24) = &tg_namebuf;
        }
        sprintf(&tg_offfile, "tg_%ld.offset", id);
        *(bot + 72) = &tg_offfile;
        1;
    } else {
        id = strtoull(bot[0], 0, 10);
        *(bot + 16) = id;
        sprintf(&tg_offfile, "tg_%ld.offset", id);
        *(bot + 72) = &tg_offfile;
        printf("[tg] getMe failed — identify fallback, id=%ld (check token/network)\n", id);
        tg_last_err = 1;
        0;
    }
}

// tg_polling(bot): identify → чтение offset → один deleteWebhook → цикл
// getUpdates (timeout=30): по каждому апдейту — диспетчеризация, затем
// offset = update_id+1 в слот и файл (at-least-once); пустой ответ — без
// записи. Ошибка: "terminated by other getUpdates" → стоп; 409 →
// deleteWebhook + продолжить; иное → sleep(retry_after) или 5 + продолжить.
// Тело ответа СНАПШОТИТСЯ перед диспетчеризацией: хендлеры шлют свои
// запросы и перезаписывают httpresp.
tg_polling(bot) {
    auto offset;
    auto r;
    auto n;
    auto i;
    auto upd;
    auto desc;
    auto code;
    auto retry;
    auto body;
    auto done;
    auto hb;
    auto p;
    tg_identify(bot);
    offset = tg_offset_read(bot);
    *(bot + 64) = offset;
    tg_call(bot, "deleteWebhook", 0);
    *(bot + 88) = 1;
    while *(bot + 88) == 1 {
        tg_params_reset(&tg_paramslot);
        tg_param_num(&tg_paramslot, "timeout", 30);
        tg_param_num(&tg_paramslot, "offset", offset);
        body = tg_params_done(&tg_paramslot);
        r = tg_call(bot, "getUpdates", body);
        if r == 1 {
            hb = tg_http_body();
            n = tg_count(hb, "result");
            if n > 0 {
                body = malloc(strlen(hb) + 1);   // снапшот: ответы хендлеров
                strcpy(body, hb);                // не должны затирать данные
                hb = body;
                i = 0;
                while i < n {
                    p = tg_scratch();
                    sprintf(p, "result.%ld", i);
                    upd = tg_get(hb, p);
                    if upd != 0 {
                        tg_handle_update(bot, upd);
                        offset = tg_get_num(upd, "update_id") + 1;
                        tg_offset_write(bot, offset);
                    }
                    i = i + 1;
                }
                free(body);
            }
        } else {
            code = tg_get_num(tg_http_body(), "error_code");
            desc = tg_get_str(tg_http_body(), "description");
            done = 0;
            if desc != 0 {
                if strstr(desc, "terminated by other getUpdates") != 0 done = 1;
            }
            if done == 1 {
                printf("[tg] polling stopped: another getUpdates instance is running\n");
                *(bot + 88) = 0;
            } else {
                if code == 409 {
                    tg_call(bot, "deleteWebhook", 0);
                } else {
                    retry = tg_get_num(tg_http_body(), "parameters.retry_after");
                    if retry > 0 {
                        sleep(retry);
                    } else {
                        sleep(5);
                    }
                }
            }
        }
    }
    1;
}
