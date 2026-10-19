// t_buf.k — юнит-тест буферов и JSON-экранирования kivagram
extern printf
extern exit
extern strlen
extern strcmp
extern strtoull

fails[1];
buf[3];
numbuf[3];
bigbuf[3];
rawbuf[16];
ctrlbuf[8];

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

// вход для escape: a " b \ c \n пробел A — собираем байтами, т.к. в
// строковых литералах кавычка/бэкслэш требуют экранирования
mkraw() {
    *(&rawbuf+0) !8 97;   // a
    *(&rawbuf+1) !8 34;   // "
    *(&rawbuf+2) !8 98;   // b
    *(&rawbuf+3) !8 92;   // backslash
    *(&rawbuf+4) !8 99;   // c
    *(&rawbuf+5) !8 10;   // newline
    *(&rawbuf+6) !8 32;   // space
    *(&rawbuf+7) !8 65;   // A
    *(&rawbuf+8) !8 0;
    &rawbuf;
}

// управляющий символ 0x01
mkctrl() {
    *(&ctrlbuf+0) !8 1;
    *(&ctrlbuf+1) !8 0;
    &ctrlbuf;
}

global main
main() {
    auto i;
    auto e;
    auto c;
    auto s;
    auto p1;
    auto p2;

    fails[0] = 0;

    // (а) конкатенация последовательных tg_buf_add
    tg_buf_init(&buf);
    tg_buf_add(&buf, "foo");
    tg_buf_add(&buf, "bar");
    tg_buf_add(&buf, "baz");
    chk(strcmp(buf[0], "foobarbaz") == 0, "concat: foobarbaz");
    chk(buf[1] == 9, "concat: len slot == 9");

    // (б) tg_buf_addnum: 0, большое, отрицательное
    tg_buf_init(&numbuf);
    tg_buf_addnum(&numbuf, 0);
    tg_buf_addnum(&numbuf, 1234567);
    tg_buf_addnum(&numbuf, -42);
    tg_buf_addnum(&numbuf, strtoull("5000000000", 0, 10));
    chk(strcmp(numbuf[0], "01234567-425000000000") == 0,
        "addnum: 0/1234567/-42/5000000000 (64-бит id > 2^31)");

    // рост буфера: 30 × 10 байт
    tg_buf_init(&bigbuf);
    i = 0;
    while i < 30 {
        tg_buf_add(&bigbuf, "0123456789");
        i = i + 1;
    }
    chk(bigbuf[1] == 300, "grow: len slot == 300");
    chk(strlen(bigbuf[0]) == 300, "grow: strlen == 300");

    // (в) escape: кавычка, обратный слэш, \n, обычные байты
    tg_scratch();
    e = tg_json_escape(mkraw());
    chk(@8 *(e+0) == 97, "escape: a on place");
    chk(@8 *(e+1) == 92, "escape: quote -> backslash");
    chk(@8 *(e+2) == 34, "escape: quote -> quote");
    chk(@8 *(e+3) == 98, "escape: b on place");
    chk(@8 *(e+4) == 92, "escape: backslash -> escaped 1");
    chk(@8 *(e+5) == 92, "escape: backslash -> escaped 2");
    chk(@8 *(e+6) == 99, "escape: c on place");
    chk(@8 *(e+7) == 92, "escape: newline -> backslash");
    chk(@8 *(e+8) == 110, "escape: newline -> n");
    chk(@8 *(e+9) == 32, "escape: space untouched");
    chk(@8 *(e+10) == 65, "escape: A untouched");
    chk(strlen(e) == 11, "escape: length 11");

    // управляющие → \u00XX
    tg_scratch();
    c = tg_json_escape(mkctrl());
    chk(@8 *(c+0) == 92, "u00: backslash");
    chk(@8 *(c+1) == 117, "u00: u");
    chk(@8 *(c+2) == 48, "u00: 0");
    chk(@8 *(c+5) == 49, "u00: last digit 1");
    chk(strlen(c) == 6, "u00: length 6");

    // (г) кириллица проходит без изменений
    tg_scratch();
    s = tg_json_escape("привет");
    chk(strcmp(s, "привет") == 0, "escape: cyrillic unchanged");

    // (д) scratch: один указатель, сброс позиции, ёмкость ≥1000 байт
    p1 = tg_scratch();
    p2 = tg_scratch();
    chk(p1 == p2, "scratch: stable pointer");
    i = 0;
    while i < 105 {
        tg_scr_add("0123456789");
        i = i + 1;
    }
    chk(strlen(p1) == 1050, "scratch: holds 1050 bytes");
    tg_scratch();
    tg_scr_add("z");
    chk(strlen(p1) == 1, "scratch: reset works");

    // освобождение
    tg_buf_free(&buf);
    tg_buf_free(&numbuf);
    tg_buf_free(&bigbuf);

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
