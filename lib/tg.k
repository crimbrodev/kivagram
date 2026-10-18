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
