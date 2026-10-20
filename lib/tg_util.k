// lib/tg_util.k — V4-B: утилиты поверх ядра kivagram (карта aiogram utils/).
//
//   1) tg_kbu_*  — билдер клавиатур: inline / url / web_app / reply-кнопки,
//      ряды, adjust, выдача JSON [utils/keyboard.py]. Реестр ≤4 билдеров,
//      ≤64 кнопок и ≤16 рядов на хранилище; переполнение — printf + игнор.
//   2) tg_fmt_*  — HTML-форматтеры parse_mode=HTML [utils/formatting.py]:
//      содержимое и URL экранируются tg_html_escape, результат — в пуле из
//      4 растущих (realloc) буферов с ротацией (fmt_cat принимает два
//      готовых куска — они из разных слотов пула).
//   3) tg_sha256_hex / tg_deep_* — SHA-256 на чистой Kiva (NIST-векторы в
//      tests/t_v4_util.k) + deep-linking [utils/deep_linking.py].
//   4) tg_backoff_delay / tg_sleep_sec / tg_action_* — экспоненциальный
//      бэкофф с джиттером, обёртка sleep и тикер sendChatAction (раз в ≥4с).
//   5) tg_mg_*   — агрегатор медиагрупп → sendMediaGroup [utils/media_group.py].
//
// Порядок склейки (build.sh): tg.k + модули lib/tg_*.k по алфавиту + исходник
// — все tg_buf_*/tg_param_*/tg_call/tg_json_escape/tg_html_escape/tg_ctx_*
// из ядра уже определены к этому месту.
//
// Жизнь указателей результатов (как в ядре): *_json, *_create, *_sign,
// *_extract, sha256_hex — до СЛЕДУЮЩЕГО вызова той же функции (у *_create и
// *_sign свои слоты, поэтому между собой не перетираются); tg_fmt_* живут до
// ротации пула (4 буфера — держите ≤4 свежих результата одновременно);
// кнопочные JSON копируются в буфер билдера сразу после tg_json_escape
// (общий tg_escbuf ядра).

extern strlen
extern strcmp
extern memcpy
extern realloc
extern sprintf
extern printf
extern strstr
extern rand
extern time
extern sleep

// =====1. Keyboard builder (tg_kbu_*) =====
// Хранилище кнопок: Buf из NUL-строк (каждая строка — готовый JSON-объект
// кнопки), ряды — счётчики кнопок в ряду (17 слов на билдер × 4). Render
// склеивает строки, расставляя "[" "]," "]" по счётчикам.

tg_kbu_used[4];       // 1 — слот реестра занят
tg_kbu_last[4];       // последний вид кнопок: 1 inline, 2 reply, 0 — не было
tg_kbu_islot[12];     // 4 × Buf(3): inline-кнопки
tg_kbu_rslot[12];     // 4 × Buf(3): reply-кнопки
tg_kbu_inb[4];        // inline: кнопок
tg_kbu_inr[4];        // inline: рядов
tg_kbu_ino[4];        // inline: последний ряд открыт (1/0)
tg_kbu_rnb[4];        // reply: кнопок
tg_kbu_rnn[4];
tg_kbu_rno[4];
tg_kbu_irows[68];     // 4 × 17: кнопок в ряду (inline)
tg_kbu_rrows[68];     // 4 × 17: кнопок в ряду (reply)
tg_kbu_out[3];        // Buf результата tg_kbu_*_json
tg_kbu_tmp[3];        // Buf сборки одной кнопки

// tg_kbu_ip(k) / tg_kbu_rp(k): слот Buf кнопок k-го билдера (байтовая
// адресация: слот = 3 слова = 24 байта)
tg_kbu_ip(k) { &tg_kbu_islot + k * 24; }
tg_kbu_rp(k) { &tg_kbu_rslot + k * 24; }

// tg_kbu_irws(k) / tg_kbu_rrws(k): указатель на счётчики рядов k-го билдера
// (17 слов = 136 байт)
tg_kbu_irws(k) { &tg_kbu_irows + k * 17 * 8; }
tg_kbu_rrws(k) { &tg_kbu_rrows + k * 17 * 8; }

// tg_kbu_valid(kb): 1 — хэндл (1..4) указывает на занятый слот
tg_kbu_valid(kb) {
    auto ok;
    ok = 0;
    if kb > 0 {
        if kb < 5 {
            if tg_kbu_used[kb - 1] == 1 ok = 1;
        }
    }
    ok;
}

// tg_kbu_jsonesc(s): JSON-эскейп значения (обёртка над tg_json_escape ядра:
// кавычка -> \", слэш -> \\, \n/\r/\t, <0x20 -> \u00XX, UTF-8 — как есть).
// Результат — в общем tg_escbuf: КОПИРОВАТЬ в свой буфер сразу после вызова.
tg_kbu_jsonesc(s) {
    tg_json_escape(s);
}

// tg_kbu_new(): выдать свободный слот реестра (1..4), 0 — реестр полон
tg_kbu_new() {
    auto i;
    auto r;
    auto found;
    r = 0;
    found = 0;
    i = 0;
    while i < 4 {
        if found == 0 {
            if tg_kbu_used[i] == 0 {
                tg_kbu_used[i] = 1;
                tg_kbu_last[i] = 0;
                tg_kbu_inb[i] = 0;
                tg_kbu_inr[i] = 0;
                tg_kbu_ino[i] = 0;
                tg_kbu_rnb[i] = 0;
                tg_kbu_rnn[i] = 0;
                tg_kbu_rno[i] = 0;
                tg_buf_init(tg_kbu_ip(i));
                tg_buf_init(tg_kbu_rp(i));
                found = 1;
                r = i + 1;
            }
        }
        i = i + 1;
    }
    if r == 0 printf("tg_kbu_new: реестр переполнен (4 билдера)\n");
    r;
}

// tg_kbu_push(k, kind, json): дописать готовый JSON кнопки в слот k
// (kind 1 = inline, 2 = reply); 1 — принята, 0 — лимит/ошибка
tg_kbu_push(k, kind, json) {
    auto nb;
    auto nr;
    auto open;
    auto rarr;
    auto slot;
    auto ok;
    ok = 1;
    if kind == 2 {
        nb = tg_kbu_rnb[k];
        nr = tg_kbu_rnn[k];
        open = tg_kbu_rno[k];
        rarr = tg_kbu_rrws(k);
        slot = tg_kbu_rp(k);
    } else {
        nb = tg_kbu_inb[k];
        nr = tg_kbu_inr[k];
        open = tg_kbu_ino[k];
        rarr = tg_kbu_irws(k);
        slot = tg_kbu_ip(k);
    }
    if nb > 63 {
        printf("tg_kbu: лимит кнопок (64) исчерпан\n");
        ok = 0;
    }
    if ok == 1 {
        if open == 0 {
            if nr > 15 {
                printf("tg_kbu: лимит рядов (16) исчерпан\n");
                ok = 0;
            }
        }
    }
    if ok == 1 {
        if open == 0 {
            rarr[nr] = 0;
            nr = nr + 1;
            open = 1;
            if kind == 2 {
                tg_kbu_rnn[k] = nr;
                tg_kbu_rno[k] = 1;
            } else {
                tg_kbu_inr[k] = nr;
                tg_kbu_ino[k] = 1;
            }
        }
        rarr[nr - 1] = rarr[nr - 1] + 1;
        if kind == 2 {
            tg_kbu_rnb[k] = nb + 1;
            tg_kbu_last[k] = 2;
        } else {
            tg_kbu_inb[k] = nb + 1;
            tg_kbu_last[k] = 1;
        }
        // NB: tg_buf_add перетирает NUL предыдущей строки — сдвигаем len на 1,
        // чтобы NUL остался РАЗДЕЛИТЕЛЁМ кнопок (обход render через strlen).
        tg_buf_add(slot, json);
        slot[1] = slot[1] + 1;
    }
    ok;
}

// tg_kbu_row(kb): закрыть текущий ряд (следующая кнопка откроет новый)
tg_kbu_row(kb) {
    auto k;
    if tg_kbu_valid(kb) {
        k = kb - 1;
        if tg_kbu_last[k] == 2 {
            tg_kbu_rno[k] = 0;
        } else {
            tg_kbu_ino[k] = 0;
        }
    }
    1;
}

// tg_kbu_adj(k, kind, n): переразбить все кнопки хранилища рядами по n;
// рядов > 16 — printf + игнор
tg_kbu_adj(k, kind, n) {
    auto nb;
    auto rarr;
    auto need;
    auto rem;
    auto r;
    auto take;
    if kind == 2 {
        nb = tg_kbu_rnb[k];
        rarr = tg_kbu_rrws(k);
    } else {
        nb = tg_kbu_inb[k];
        rarr = tg_kbu_irws(k);
    }
    if nb > 0 {
        need = 0;
        rem = nb;
        while rem > 0 {
            need = need + 1;
            // БЕЗЗНАКОВОЕ сравнение: rem - n может уйти в −1 → цикл навсегда.
            if rem > n {
                rem = rem - n;
            } else {
                rem = 0;
            }
        }
        if need > 16 {
            printf("tg_kbu_adjust: нужно %ld рядов (лимит 16) — игнор\n",
                need);
        } else {
            rem = nb;
            r = 0;
            while rem > 0 {
                take = n;
                if rem < n take = rem;
                rarr[r] = take;
                rem = rem - take;
                r = r + 1;
            }
            if kind == 2 {
                tg_kbu_rnn[k] = r;
                tg_kbu_rno[k] = 1;
            } else {
                tg_kbu_inr[k] = r;
                tg_kbu_ino[k] = 1;
            }
        }
    }
    1;
}

// tg_kbu_adjust(kb, n): .adjust() aiogram — переразбить накопленные кнопки
// рядами по n; n <= 0 — игнор
tg_kbu_adjust(kb, n) {
    auto k;
    if tg_kbu_valid(kb) {
        k = kb - 1;
        if n > 0 {
            tg_kbu_adj(k, 1, n);
            tg_kbu_adj(k, 2, n);
        }
    }
    1;
}

// tg_kbu_render(k, kind): JSON-объект клавиатуры или 0 (кнопок нет);
// общий результат-слот tg_kbu_out — жизнь до следующего render
tg_kbu_render(k, kind) {
    auto slot;
    auto rarr;
    auto nr;
    auto nb;
    auto p;
    auto r;
    auto i;
    auto c;
    auto res;
    if kind == 2 {
        slot = tg_kbu_rp(k);
        rarr = tg_kbu_rrws(k);
        nr = tg_kbu_rnn[k];
        nb = tg_kbu_rnb[k];
    } else {
        slot = tg_kbu_ip(k);
        rarr = tg_kbu_irws(k);
        nr = tg_kbu_inr[k];
        nb = tg_kbu_inb[k];
    }
    res = 0;
    if nb > 0 {
        tg_buf_reset(&tg_kbu_out);
        if kind == 2 {
            tg_buf_add(&tg_kbu_out, "{\"keyboard\":[");
        } else {
            tg_buf_add(&tg_kbu_out, "{\"inline_keyboard\":[");
        }
        p = slot[0];
        r = 0;
        while r < nr {
            tg_buf_add(&tg_kbu_out, "[");
            i = 0;
            c = rarr[r];
            while i < c {
                if i > 0 tg_buf_add(&tg_kbu_out, ",");
                tg_buf_add(&tg_kbu_out, p);
                p = p + strlen(p) + 1;
                i = i + 1;
            }
            tg_buf_add(&tg_kbu_out, "]");
            if r + 1 < nr tg_buf_add(&tg_kbu_out, ",");
            r = r + 1;
        }
        if kind == 2 {
            tg_buf_add(&tg_kbu_out, "],\"resize_keyboard\":true}");
        } else {
            tg_buf_add(&tg_kbu_out, "]}");
        }
        res = tg_kbu_out[0];
    }
    res;
}

// tg_kbu_inline(kb, text, callback_data): inline-кнопка в текущий ряд
tg_kbu_inline(kb, text, callback_data) {
    auto e;
    auto ok;
    ok = 0;
    if tg_kbu_valid(kb) {
        tg_buf_reset(&tg_kbu_tmp);
        tg_buf_add(&tg_kbu_tmp, "{\"text\":\"");
        e = tg_kbu_jsonesc(text);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\",\"callback_data\":\"");
        e = tg_kbu_jsonesc(callback_data);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\"}");
        ok = tg_kbu_push(kb - 1, 1, tg_kbu_tmp[0]);
    }
    ok;
}

// tg_kbu_url(kb, text, url): кнопка перехода по ссылке
tg_kbu_url(kb, text, url) {
    auto e;
    auto ok;
    ok = 0;
    if tg_kbu_valid(kb) {
        tg_buf_reset(&tg_kbu_tmp);
        tg_buf_add(&tg_kbu_tmp, "{\"text\":\"");
        e = tg_kbu_jsonesc(text);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\",\"url\":\"");
        e = tg_kbu_jsonesc(url);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\"}");
        ok = tg_kbu_push(kb - 1, 1, tg_kbu_tmp[0]);
    }
    ok;
}

// tg_kbu_webapp(kb, text, url): кнопка Mini App (web_app.url)
tg_kbu_webapp(kb, text, url) {
    auto e;
    auto ok;
    ok = 0;
    if tg_kbu_valid(kb) {
        tg_buf_reset(&tg_kbu_tmp);
        tg_buf_add(&tg_kbu_tmp, "{\"text\":\"");
        e = tg_kbu_jsonesc(text);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\",\"web_app\":{\"url\":\"");
        e = tg_kbu_jsonesc(url);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\"}}");
        ok = tg_kbu_push(kb - 1, 1, tg_kbu_tmp[0]);
    }
    ok;
}

// tg_kbu_reply(kb, text): текстовая reply-кнопка (отдельное хранилище)
tg_kbu_reply(kb, text) {
    auto e;
    auto ok;
    ok = 0;
    if tg_kbu_valid(kb) {
        tg_buf_reset(&tg_kbu_tmp);
        tg_buf_add(&tg_kbu_tmp, "\"");
        e = tg_kbu_jsonesc(text);
        tg_buf_add(&tg_kbu_tmp, e);
        tg_buf_add(&tg_kbu_tmp, "\"");
        ok = tg_kbu_push(kb - 1, 2, tg_kbu_tmp[0]);
    }
    ok;
}

// tg_kbu_inline_json(kb) → {"inline_keyboard":[[...]]} или 0 (нет inline)
tg_kbu_inline_json(kb) {
    auto r;
    r = 0;
    if tg_kbu_valid(kb) r = tg_kbu_render(kb - 1, 1);
    r;
}

// tg_kbu_reply_json(kb) → {"keyboard":[[...]],"resize_keyboard":true} или 0
tg_kbu_reply_json(kb) {
    auto r;
    r = 0;
    if tg_kbu_valid(kb) r = tg_kbu_render(kb - 1, 2);
    r;
}

// tg_kbu_reset(kb): очистить оба хранилища билдера (слот остаётся занятым)
tg_kbu_reset(kb) {
    auto k;
    if tg_kbu_valid(kb) {
        k = kb - 1;
        tg_buf_reset(tg_kbu_ip(k));
        tg_buf_reset(tg_kbu_rp(k));
        tg_kbu_inb[k] = 0;
        tg_kbu_inr[k] = 0;
        tg_kbu_ino[k] = 0;
        tg_kbu_rnb[k] = 0;
        tg_kbu_rnn[k] = 0;
        tg_kbu_rno[k] = 0;
        tg_kbu_last[k] = 0;
    }
    1;
}

// =====2. HTML-форматтеры (tg_fmt_*) =====
// Пул из 4 буферов с ротацией: каждый вызов берёт следующий, сбрасывает len
// и наращивает через realloc — можно держать до 4 свежих результатов сразу
// (fmt_cat как раз читает два предыдущих).

tg_fmt_slots[12];    // 4 × Buf(3)
tg_fmt_cur;          // индекс следующего слота пула (0..3)
tg_fmt_tmp[3];       // временный слот (копия URL до второго escape)

// tg_fmt_pick(): слот следующего буфера пула (len сброшен)
tg_fmt_pick() {
    auto s;
    s = &tg_fmt_slots + tg_fmt_cur * 24;
    s[1] = 0;
    tg_fmt_cur = tg_fmt_cur + 1;
    if tg_fmt_cur > 3 tg_fmt_cur = 0;
    s;
}

// tg_fmt_puts(b, s): дописать строку в слот, ёмкость растёт через realloc
tg_fmt_puts(b, s) {
    auto n;
    auto cap;
    auto np;
    n = strlen(s);
    if b[1] + n + 1 > b[2] {
        cap = b[2];
        if cap == 0 cap = 256;
        while cap < b[1] + n + 1 cap = cap * 2;
        np = realloc(b[0], cap);
        if np == 0 {
            printf("tg_fmt: realloc failed (%ld bytes)\n", cap);
        } else {
            b[0] = np;
            b[2] = cap;
        }
    }
    if b[0] != 0 {
        memcpy(b[0] + b[1], s, n + 1);
        b[1] = b[1] + n;
    }
    1;
}

// tg_fmt_tag(o, c, s): <o>escape(s)</c> в новом слоте пула
tg_fmt_tag(o, c, s) {
    auto b;
    auto e;
    b = tg_fmt_pick();
    e = tg_html_escape(s);
    tg_fmt_puts(b, o);
    tg_fmt_puts(b, e);
    tg_fmt_puts(b, c);
    b[0];
}

tg_fmt_bold(s) { tg_fmt_tag("<b>", "</b>", s); }
tg_fmt_italic(s) { tg_fmt_tag("<i>", "</i>", s); }
tg_fmt_underline(s) { tg_fmt_tag("<u>", "</u>", s); }
tg_fmt_strike(s) { tg_fmt_tag("<s>", "</s>", s); }
tg_fmt_spoiler(s) { tg_fmt_tag("<tg-spoiler>", "</tg-spoiler>", s); }
tg_fmt_code(s) { tg_fmt_tag("<code>", "</code>", s); }
tg_fmt_pre(s) { tg_fmt_tag("<pre>", "</pre>", s); }

// tg_fmt_link(url, s): <a href="escape(url)">escape(s)</a>; URL экранируется
// отдельно (второй tg_html_escape затирает первый результат — копия в tmp)
tg_fmt_link(url, s) {
    auto b;
    auto u;
    auto e;
    auto t;
    b = tg_fmt_pick();
    u = tg_html_escape(url);
    tg_fmt_tmp[1] = 0;
    tg_fmt_puts(&tg_fmt_tmp, u);
    e = tg_html_escape(s);
    t = tg_fmt_tmp[0];
    tg_fmt_puts(b, "<a href=\"");
    tg_fmt_puts(b, t);
    tg_fmt_puts(b, "\">");
    tg_fmt_puts(b, e);
    tg_fmt_puts(b, "</a>");
    b[0];
}

// tg_fmt_cat(a, b): конкатенация двух готовых кусков (новый слот пула)
tg_fmt_cat(a, b) {
    auto r;
    r = tg_fmt_pick();
    tg_fmt_puts(r, a);
    tg_fmt_puts(r, b);
    r[0];
}

// =====3. SHA-256 (tg_sha_*) =====
// Канонический FIPS 180-4: K[64], H[8], 64-раундные блоки, padding,
// потоковая обработка побайтно (сообщение — C-строка).

tg_sha_k[64];        // константы раундов
tg_sha_h[8];         // цепочное состояние
tg_sha_w[64];        // расписание слов
tg_sha_blk[64];      // текущий 64-байтовый блок (байты как слова 0..255)
tg_sha_dig[32];      // дайджест (байты)
tg_sha_hexb[66];     // hex-строка результата (64 + NUL)
tg_sha_bl;           // байтов в tg_sha_blk
tg_sha_tot;          // всего байт сообщения
tg_sha_mask;         // 0xffffffff

// tg_sha_rotr(x, n): циклический вправо внутри 32 бит
tg_sha_rotr(x, n) {
    ((x >> n) | (x << (32 - n))) & tg_sha_mask;
}

// tg_sha_init(): K, H, счётчики
tg_sha_init() {
    tg_sha_mask = 0xffffffff;
    tg_sha_k[0] = 0x428a2f98;
    tg_sha_k[1] = 0x71374491;
    tg_sha_k[2] = 0xb5c0fbcf;
    tg_sha_k[3] = 0xe9b5dba5;
    tg_sha_k[4] = 0x3956c25b;
    tg_sha_k[5] = 0x59f111f1;
    tg_sha_k[6] = 0x923f82a4;
    tg_sha_k[7] = 0xab1c5ed5;
    tg_sha_k[8] = 0xd807aa98;
    tg_sha_k[9] = 0x12835b01;
    tg_sha_k[10] = 0x243185be;
    tg_sha_k[11] = 0x550c7dc3;
    tg_sha_k[12] = 0x72be5d74;
    tg_sha_k[13] = 0x80deb1fe;
    tg_sha_k[14] = 0x9bdc06a7;
    tg_sha_k[15] = 0xc19bf174;
    tg_sha_k[16] = 0xe49b69c1;
    tg_sha_k[17] = 0xefbe4786;
    tg_sha_k[18] = 0x0fc19dc6;
    tg_sha_k[19] = 0x240ca1cc;
    tg_sha_k[20] = 0x2de92c6f;
    tg_sha_k[21] = 0x4a7484aa;
    tg_sha_k[22] = 0x5cb0a9dc;
    tg_sha_k[23] = 0x76f988da;
    tg_sha_k[24] = 0x983e5152;
    tg_sha_k[25] = 0xa831c66d;
    tg_sha_k[26] = 0xb00327c8;
    tg_sha_k[27] = 0xbf597fc7;
    tg_sha_k[28] = 0xc6e00bf3;
    tg_sha_k[29] = 0xd5a79147;
    tg_sha_k[30] = 0x06ca6351;
    tg_sha_k[31] = 0x14292967;
    tg_sha_k[32] = 0x27b70a85;
    tg_sha_k[33] = 0x2e1b2138;
    tg_sha_k[34] = 0x4d2c6dfc;
    tg_sha_k[35] = 0x53380d13;
    tg_sha_k[36] = 0x650a7354;
    tg_sha_k[37] = 0x766a0abb;
    tg_sha_k[38] = 0x81c2c92e;
    tg_sha_k[39] = 0x92722c85;
    tg_sha_k[40] = 0xa2bfe8a1;
    tg_sha_k[41] = 0xa81a664b;
    tg_sha_k[42] = 0xc24b8b70;
    tg_sha_k[43] = 0xc76c51a3;
    tg_sha_k[44] = 0xd192e819;
    tg_sha_k[45] = 0xd6990624;
    tg_sha_k[46] = 0xf40e3585;
    tg_sha_k[47] = 0x106aa070;
    tg_sha_k[48] = 0x19a4c116;
    tg_sha_k[49] = 0x1e376c08;
    tg_sha_k[50] = 0x2748774c;
    tg_sha_k[51] = 0x34b0bcb5;
    tg_sha_k[52] = 0x391c0cb3;
    tg_sha_k[53] = 0x4ed8aa4a;
    tg_sha_k[54] = 0x5b9cca4f;
    tg_sha_k[55] = 0x682e6ff3;
    tg_sha_k[56] = 0x748f82ee;
    tg_sha_k[57] = 0x78a5636f;
    tg_sha_k[58] = 0x84c87814;
    tg_sha_k[59] = 0x8cc70208;
    tg_sha_k[60] = 0x90befffa;
    tg_sha_k[61] = 0xa4506ceb;
    tg_sha_k[62] = 0xbef9a3f7;
    tg_sha_k[63] = 0xc67178f2;
    tg_sha_h[0] = 0x6a09e667;
    tg_sha_h[1] = 0xbb67ae85;
    tg_sha_h[2] = 0x3c6ef372;
    tg_sha_h[3] = 0xa54ff53a;
    tg_sha_h[4] = 0x510e527f;
    tg_sha_h[5] = 0x9b05688c;
    tg_sha_h[6] = 0x1f83d9ab;
    tg_sha_h[7] = 0x5be0cd19;
    tg_sha_bl = 0;
    tg_sha_tot = 0;
    1;
}

// tg_sha_comp(): сжатие одного 64-байтового блока
tg_sha_comp() {
    auto i;
    auto a;
    auto b;
    auto c;
    auto d;
    auto e;
    auto f;
    auto g;
    auto h;
    auto t1;
    auto t2;
    auto s0;
    auto s1;
    auto ch;
    auto mj;
    auto x;
    i = 0;
    while i < 16 {
        x = i * 4;
        tg_sha_w[i] = ((tg_sha_blk[x] << 24) + (tg_sha_blk[x + 1] << 16)
            + (tg_sha_blk[x + 2] << 8) + tg_sha_blk[x + 3]);
        i = i + 1;
    }
    i = 16;
    while i < 64 {
        s0 = tg_sha_rotr(tg_sha_w[i - 15], 7)
            ^ tg_sha_rotr(tg_sha_w[i - 15], 18)
            ^ (tg_sha_w[i - 15] >> 3);
        s1 = tg_sha_rotr(tg_sha_w[i - 2], 17)
            ^ tg_sha_rotr(tg_sha_w[i - 2], 19)
            ^ (tg_sha_w[i - 2] >> 10);
        tg_sha_w[i] = (tg_sha_w[i - 16] + s0 + tg_sha_w[i - 7] + s1)
            & tg_sha_mask;
        i = i + 1;
    }
    a = tg_sha_h[0];
    b = tg_sha_h[1];
    c = tg_sha_h[2];
    d = tg_sha_h[3];
    e = tg_sha_h[4];
    f = tg_sha_h[5];
    g = tg_sha_h[6];
    h = tg_sha_h[7];
    i = 0;
    while i < 64 {
        s1 = tg_sha_rotr(e, 6) ^ tg_sha_rotr(e, 11) ^ tg_sha_rotr(e, 25);
        ch = (e & f) ^ ((tg_sha_mask ^ e) & g);
        t1 = (h + s1 + ch + tg_sha_k[i] + tg_sha_w[i]) & tg_sha_mask;
        s0 = tg_sha_rotr(a, 2) ^ tg_sha_rotr(a, 13) ^ tg_sha_rotr(a, 22);
        mj = (a & b) ^ (a & c) ^ (b & c);
        t2 = (s0 + mj) & tg_sha_mask;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & tg_sha_mask;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & tg_sha_mask;
        i = i + 1;
    }
    tg_sha_h[0] = (tg_sha_h[0] + a) & tg_sha_mask;
    tg_sha_h[1] = (tg_sha_h[1] + b) & tg_sha_mask;
    tg_sha_h[2] = (tg_sha_h[2] + c) & tg_sha_mask;
    tg_sha_h[3] = (tg_sha_h[3] + d) & tg_sha_mask;
    tg_sha_h[4] = (tg_sha_h[4] + e) & tg_sha_mask;
    tg_sha_h[5] = (tg_sha_h[5] + f) & tg_sha_mask;
    tg_sha_h[6] = (tg_sha_h[6] + g) & tg_sha_mask;
    tg_sha_h[7] = (tg_sha_h[7] + h) & tg_sha_mask;
    1;
}

// tg_sha_next(c): байт сообщения в блок (64 байта → сжатие)
tg_sha_next(c) {
    tg_sha_blk[tg_sha_bl] = c;
    tg_sha_bl = tg_sha_bl + 1;
    tg_sha_tot = tg_sha_tot + 1;
    if tg_sha_bl == 64 {
        tg_sha_comp();
        tg_sha_bl = 0;
    }
    1;
}

// tg_sha_pad(): 0x80, нули до 56 байт блока, 8 байт длины в битах (BE)
tg_sha_pad() {
    auto i;
    auto j;
    auto bits;
    auto c;
    tg_sha_blk[tg_sha_bl] = 128;
    tg_sha_bl = tg_sha_bl + 1;
    while tg_sha_bl != 56 {
        if tg_sha_bl == 64 {
            tg_sha_comp();
            tg_sha_bl = 0;
        }
        tg_sha_blk[tg_sha_bl] = 0;
        tg_sha_bl = tg_sha_bl + 1;
    }
    bits = tg_sha_tot * 8;
    i = 0;
    while i < 8 {
        j = 7 - i;
        c = (bits >> (j * 8)) & 255;
        tg_sha_blk[tg_sha_bl] = c;
        tg_sha_bl = tg_sha_bl + 1;
        if tg_sha_bl == 64 {
            tg_sha_comp();
            tg_sha_bl = 0;
        }
        i = i + 1;
    }
    1;
}

// tg_sha_final(): H → 32 байта дайджеста → указатель.
// Байты пишутся ПОБАЙТОВО (&buf + i*4): индексация tg_sha_dig[i*4] —
// словесная (шаг 8 байт), а читается дайджест как сплошные байты.
tg_sha_final() {
    auto i;
    auto v;
    i = 0;
    while i < 8 {
        v = (tg_sha_h[i] >> 24) & 255;
        *(&tg_sha_dig + i * 4) !8 v;
        v = (tg_sha_h[i] >> 16) & 255;
        *(&tg_sha_dig + i * 4 + 1) !8 v;
        v = (tg_sha_h[i] >> 8) & 255;
        *(&tg_sha_dig + i * 4 + 2) !8 v;
        v = tg_sha_h[i] & 255;
        *(&tg_sha_dig + i * 4 + 3) !8 v;
        i = i + 1;
    }
    &tg_sha_dig;
}

// tg_sha256_digest(data) → 32 байта в статик-буфере (для base64-сигнатур)
tg_sha256_digest(data) {
    auto i;
    auto c;
    tg_sha_init();
    i = 0;
    c = @8 *(data + i);
    while c != 0 {
        tg_sha_next(c);
        i = i + 1;
        c = @8 *(data + i);
    }
    tg_sha_pad();
    tg_sha_final();
}

// tg_sha256_hex(data) → 64-символьный hex в статик-буфере
tg_sha256_hex(data) {
    auto d;
    auto i;
    auto c;
    auto hi;
    auto lo;
    auto h1;
    auto h2;
    d = tg_sha256_digest(data);
    i = 0;
    while i < 64 {
        c = @8 *(d + i);
        hi = c >> 4;
        lo = c & 15;
        h1 = 48 + hi;
        h2 = 48 + lo;
        if hi > 9 h1 = 87 + hi;
        if lo > 9 h2 = 87 + lo;
        *(&tg_sha_hexb + i * 2) !8 h1;
        *(&tg_sha_hexb + i * 2 + 1) !8 h2;
        i = i + 1;
    }
    *(&tg_sha_hexb + 64) !8 0;
    &tg_sha_hexb;
}

// =====4. Deep linking (tg_deep_*) =====

tg_deep_link[3];     // Buf результата *_create
tg_deep_extb[512];   // 4 КБ: значение start= из *_extract
tg_deep_b64[26];     // 208 байт: base64url-сигнатура (22 + NUL)
tg_deep_vsign[3];    // Buf: копия аргумента sign для verify (анти-aliasing)

// tg_b64c(v): символ base64url для значения 0..63 (A-Za-z0-9-_)
tg_b64c(v) {
    auto c;
    c = 65 + v;
    if v > 25 c = 71 + v;
    if v > 51 c = v - 4;
    if v > 61 c = 45;
    if v > 62 c = 95;
    c;
}

// tg_deep_b64enc(d): base64url(16 байт) без '=' → статик-буфер (22 символа)
tg_deep_b64enc(d) {
    auto g;
    auto i;
    auto b0;
    auto b1;
    auto b2;
    auto pos;
    auto c;
    g = 0;
    while g < 6 {
        i = g * 3;
        b0 = @8 *(d + i);
        b1 = 0;
        b2 = 0;
        if i + 1 < 16 b1 = @8 *(d + i + 1);
        if i + 2 < 16 b2 = @8 *(d + i + 2);
        pos = g * 4;
        c = tg_b64c(b0 >> 2);
        *(&tg_deep_b64 + pos) !8 c;
        c = tg_b64c(((b0 & 3) << 4) | (b1 >> 4));
        *(&tg_deep_b64 + pos + 1) !8 c;
        if i + 1 < 16 {
            c = tg_b64c(((b1 & 15) << 2) | (b2 >> 6));
            *(&tg_deep_b64 + pos + 2) !8 c;
        }
        if i + 2 < 16 {
            c = tg_b64c(b2 & 63);
            *(&tg_deep_b64 + pos + 3) !8 c;
        }
        g = g + 1;
    }
    *(&tg_deep_b64 + 22) !8 0;
    &tg_deep_b64;
}

// tg_deep_create(bot_username, payload) → https://t.me/<bot>?start=<payload>
tg_deep_create(bot_username, payload) {
    tg_buf_reset(&tg_deep_link);
    tg_buf_add(&tg_deep_link, "https://t.me/");
    tg_buf_add(&tg_deep_link, bot_username);
    tg_buf_add(&tg_deep_link, "?start=");
    tg_buf_add(&tg_deep_link, payload);
    tg_deep_link[0];
}

// tg_deep_sign(payload) → base64url(первые 16 байт sha256) без '='
tg_deep_sign(payload) {
    auto d;
    d = tg_sha256_digest(payload);
    tg_deep_b64enc(d);
}

// tg_deep_create_signed(bot, payload) → ссылка с payload-<sign>
tg_deep_create_signed(bot_username, payload) {
    auto sg;
    sg = tg_deep_sign(payload);
    tg_buf_reset(&tg_deep_link);
    tg_buf_add(&tg_deep_link, "https://t.me/");
    tg_buf_add(&tg_deep_link, bot_username);
    tg_buf_add(&tg_deep_link, "?start=");
    tg_buf_add(&tg_deep_link, payload);
    tg_buf_add(&tg_deep_link, "-");
    tg_buf_add(&tg_deep_link, sg);
    tg_deep_link[0];
}

// tg_deep_verify(payload, sign) → 1 — подпись верна (побайтовое сравнение)
tg_deep_verify(payload, sign) {
    auto got;
    auto exp;
    auto i;
    auto a;
    auto b;
    auto st;
    tg_buf_reset(&tg_deep_vsign);
    tg_buf_add(&tg_deep_vsign, sign);
    got = tg_deep_vsign[0];
    exp = tg_deep_sign(payload);
    st = 1;
    i = 0;
    while st == 1 {
        a = @8 *(exp + i);
        b = @8 *(got + i);
        if a != b {
            st = 0;
        } else if a == 0 {
            st = 2;
        }
        i = i + 1;
    }
    if st == 2 st = 1; else st = 0;
    st;
}

// tg_deep_extract(url) → значение параметра start= (до '&' или конца) или 0
tg_deep_extract(url) {
    auto p;
    auto q;
    auto c;
    auto done;
    auto i;
    auto j;
    auto r;
    p = url;
    done = 0;
    q = 0;
    while done == 0 {
        q = strstr(p, "start=");
        if q == 0 {
            done = 1;
        } else {
            if q == p {
                p = p + 1;
            } else {
                c = @8 *(q - 1);
                if c == 63 done = 2;
                if c == 38 done = 2;
                if done == 0 p = q + 1;
            }
        }
    }
    r = 0;
    if done == 2 {
        p = q + 6;
        i = 0;
        c = @8 *(p + i);
        while c != 0 {
            if c == 38 {
                c = 0;
            } else {
                i = i + 1;
                c = @8 *(p + i);
            }
        }
        if i > 4094 i = 4094;
        if i > 0 {
            j = 0;
            while j < i {
                c = @8 *(p + j);
                *(&tg_deep_extb + j) !8 c;
                j = j + 1;
            }
            *(&tg_deep_extb + i) !8 0;
            r = &tg_deep_extb;
        }
    }
    r;
}

// =====5. Backoff / sleep / chat-action =====

// tg_backoff_delay(attempt): сек exp 1,2,4,8,16,32 (cap 60) + jitter
// (rand() % base) — попытки с 1; попытка ≥ 7 → 60 + jitter (60..119)
tg_backoff_delay(attempt) {
    auto base;
    auto j;
    base = 1;
    if attempt > 1 {
        if attempt > 6 {
            base = 60;
        } else {
            base = 1 << (attempt - 1);
        }
    }
    j = 0;
    if base > 1 j = rand() % base;
    base + j;
}

// tg_sleep_sec(n) — обёртка libc sleep; 1 — всегда (нормальный выход)
tg_sleep_sec(n) {
    sleep(n);
    1;
}

// Реестр chat-action: 32 записи [chat_id, time(), action-строка 96 байт]
tg_act_id[32];
tg_act_t[32];
tg_act_buf[384];     // 32 × 96 байт
tg_act_n;            // не используется как лимит: занятость = id != 0

// tg_act_store(e, s): копия строки действия в запись e (≤95 байт + NUL)
tg_act_store(e, s) {
    auto i;
    auto c;
    auto done;
    done = 0;
    if s == 0 done = 1;
    i = 0;
    while done == 0 {
        c = @8 *(s + i);
        if i > 94 {
            done = 1;
        } else if c == 0 {
            done = 1;
        } else {
            *(&tg_act_buf + e * 96 + i) !8 c;
            i = i + 1;
        }
    }
    *(&tg_act_buf + e * 96 + i) !8 0;
    1;
}

// tg_action_tick(bot, chat_id, action): sendChatAction не чаще 1 раза в 4с
// на чат (первая доставка — сразу); 1 — отправлено, 0 — no-op.
// chat_id == 0 — вырожденный вход: запись не найдётся (id 0 = «свободно»).
tg_action_tick(bot, chat_id, action) {
    auto i;
    auto sl;
    auto e;
    auto live;
    auto now;
    auto send;
    auto body;
    auto r;
    r = 0;
    sl = 0;
    live = 0;
    e = 0;
    i = 0;
    while i < 32 {
        if tg_act_id[i] != 0 {
            live = live + 1;
            if tg_act_id[i] == chat_id {
                if sl == 0 sl = i + 1;
            }
        }
        i = i + 1;
    }
    now = time(0);
    send = 0;
    if sl == 0 {
        if live < 32 {
            while tg_act_id[e] != 0 {
                e = e + 1;
            }
            tg_act_id[e] = chat_id;
            tg_act_t[e] = now;
            tg_act_store(e, action);
            sl = e + 1;
            send = 1;
        } else {
            printf("tg_action_tick: реестр переполнен (32 чата)\n");
        }
    } else {
        if now - tg_act_t[sl - 1] >= 4 {
            tg_act_t[sl - 1] = now;
            send = 1;
        }
    }
    if send == 1 {
        tg_params_reset(&tg_paramslot);
        tg_param_num(&tg_paramslot, "chat_id", chat_id);
        tg_param_str(&tg_paramslot, "action", action);
        body = tg_params_done(&tg_paramslot);
        tg_call(bot, "sendChatAction", body);
        r = 1;
    }
    r;
}

// tg_action_reset(chat_id): стереть запись (следующий tick отправит сразу)
tg_action_reset(chat_id) {
    auto i;
    i = 0;
    while i < 32 {
        if tg_act_id[i] == chat_id {
            tg_act_id[i] = 0;
            tg_act_t[i] = 0;
        }
        i = i + 1;
    }
    1;
}

// =====6. Media-group агрегатор (tg_mg_*) =====
// Элементы лежат в Buf через ", " (готовые JSON-объекты), счётчик отдельно;
// последний add фиксирует time() — ready через ≥1с (хвост альбома).

tg_mg_slot[3];       // Buf элементов media-массива (без скобок)
tg_mg_arr[3];        // Buf результата sendMediaGroup (массив целиком)
tg_mg_g[3];          // Buf текущего media_group_id
tg_mg_tmp[3];        // Buf сборки одного объекта медиа
tg_mg_path[64];      // 512 байт: dot-path "%s.photo.%ld.file_id"
tg_mg_cnt;           // число элементов (≤10)
tg_mg_chat;          // chat_id группы
tg_mg_last;          // time() последнего add

// tg_mg_reset(): очистить агрегатор
tg_mg_reset() {
    tg_buf_reset(&tg_mg_slot);
    tg_buf_reset(&tg_mg_g);
    tg_mg_cnt = 0;
    tg_mg_chat = 0;
    tg_mg_last = 0;
    1;
}

// tg_mg_obj(type, fid, cap): {"type":..,"media":..(,"caption":..)} → Buf
tg_mg_obj(type, fid, cap) {
    auto e;
    tg_buf_reset(&tg_mg_tmp);
    tg_buf_add(&tg_mg_tmp, "{\"type\":\"");
    tg_buf_add(&tg_mg_tmp, type);
    tg_buf_add(&tg_mg_tmp, "\",\"media\":\"");
    e = tg_json_escape(fid);
    tg_buf_add(&tg_mg_tmp, e);
    tg_buf_add(&tg_mg_tmp, "\"");
    if cap != 0 {
        tg_buf_add(&tg_mg_tmp, ",\"caption\":\"");
        e = tg_json_escape(cap);
        tg_buf_add(&tg_mg_tmp, e);
        tg_buf_add(&tg_mg_tmp, "\"");
    }
    tg_buf_add(&tg_mg_tmp, "}");
    tg_mg_tmp[0];
}

// tg_mg_add_raw(media_json, chat_id, group_id): принять готовый объект медиа;
// 1 — принят, 0 — лимит (10) / чужая группа / пустой вход
tg_mg_add_raw(media_json, chat_id, group_id) {
    auto ok;
    auto eq;
    ok = 0;
    if media_json == 0 media_json = "{}";
    if group_id == 0 group_id = "";
    if tg_mg_cnt > 9 {
        printf("tg_mg_add: агрегатор переполнен (10 элементов)\n");
    } else {
        if tg_mg_cnt == 0 {
            tg_buf_reset(&tg_mg_g);
            tg_buf_add(&tg_mg_g, group_id);
            tg_mg_chat = chat_id;
            ok = 1;
        } else {
            eq = strcmp(tg_mg_g[0], group_id);
            if eq == 0 {
                if tg_mg_chat == chat_id ok = 1;
            }
        }
        if ok == 1 {
            if tg_mg_cnt > 0 tg_buf_add(&tg_mg_slot, ",");
            tg_buf_add(&tg_mg_slot, media_json);
            tg_mg_cnt = tg_mg_cnt + 1;
            tg_mg_last = time(0);
        }
    }
    ok;
}

// tg_mg_add(ctx): разобрать сообщение ctx — media_group_id + медиа-тип
// (photo/document/audio/video/voice) → объект медиа в агрегатор;
// photo → file_id ПОСЛЕДНЕГО (крупного) элемента массива; 0 — не медиагруппа
tg_mg_add(ctx) {
    auto raw;
    auto pre;
    auto found;
    auto mgid;
    auto fid;
    auto cap;
    auto mt;
    auto n;
    auto mj;
    auto cid;
    auto r;
    r = 0;
    raw = tg_raw(ctx);
    pre = "message";
    found = 0;
    if tg_get(raw, "message") != 0 found = 1;
    if found == 0 {
        if tg_get(raw, "edited_message") != 0 {
            pre = "edited_message";
            found = 1;
        }
    }
    if found == 0 {
        if tg_get(raw, "channel_post") != 0 {
            pre = "channel_post";
            found = 1;
        }
    }
    if found == 1 {
        tg_ctx_path(pre, "media_group_id");
        mgid = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
        if mgid != 0 {
            mt = 0;
            fid = 0;
            tg_ctx_path(pre, "photo");
            n = tg_count(raw, &tg_pathbuf);
            if n > 0 {
                sprintf(&tg_mg_path, "%s.photo.%ld.file_id", pre, n - 1);
                fid = tg_ctx_getstr(ctx, raw, &tg_mg_path);
                if fid != 0 mt = "photo";
            }
            if mt == 0 {
                tg_ctx_path(pre, "document.file_id");
                fid = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
                if fid != 0 mt = "document";
            }
            if mt == 0 {
                tg_ctx_path(pre, "audio.file_id");
                fid = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
                if fid != 0 mt = "audio";
            }
            if mt == 0 {
                tg_ctx_path(pre, "video.file_id");
                fid = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
                if fid != 0 mt = "video";
            }
            if mt == 0 {
                tg_ctx_path(pre, "voice.file_id");
                fid = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
                if fid != 0 mt = "voice";
            }
            if mt != 0 {
                cap = 0;
                tg_ctx_path(pre, "caption");
                cap = tg_ctx_getstr(ctx, raw, &tg_pathbuf);
                mj = tg_mg_obj(mt, fid, cap);
                cid = tg_chat_id(ctx);
                r = tg_mg_add_raw(mj, cid, mgid);
            }
        }
    }
    r;
}

// tg_mg_count(): число накопленных элементов
tg_mg_count() {
    tg_mg_cnt;
}

// tg_mg_ready(): 1 — есть элементы и с последнего add прошло ≥1с
tg_mg_ready() {
    auto r;
    r = 0;
    if tg_mg_cnt > 0 {
        if time(0) - tg_mg_last >= 1 r = 1;
    }
    r;
}

// tg_mg_send(bot, chat_id): sendMediaGroup со всеми элементами; успех → reset
tg_mg_send(bot, chat_id) {
    auto arr;
    auto body;
    auto ok;
    ok = 0;
    if tg_mg_cnt > 0 {
        tg_buf_reset(&tg_mg_arr);
        tg_buf_add(&tg_mg_arr, "[");
        tg_buf_add(&tg_mg_arr, tg_mg_slot[0]);
        tg_buf_add(&tg_mg_arr, "]");
        arr = tg_mg_arr[0];
        tg_params_reset(&tg_paramslot);
        tg_param_num(&tg_paramslot, "chat_id", chat_id);
        tg_param_raw(&tg_paramslot, "media", arr);
        body = tg_params_done(&tg_paramslot);
        ok = tg_call(bot, "sendMediaGroup", body);
        if ok == 1 tg_mg_reset();
    }
    ok;
}
