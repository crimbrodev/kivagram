// t_http.k — HTTP-слой (popen+curl) и вызов API kivagram
// Нужна сеть: ходит в api.telegram.org за 401 с фейковым токеном.
extern printf
extern exit
extern strlen

fails[1];
bot[16];
errc[3];

// свой on_error: ловит вызовы
myerr(b, method, code, desc) {
    errc[0] = errc[0] + 1;
    errc[1] = code;
    if strlen(desc) > 0 errc[2] = 1;
    1;
}

chk(cond, name) {
    if cond {
        1;
    } else {
        printf("FAIL: %s\n", name);
        fails[0] = fails[0] + 1;
        0;
    }
}

global main
main() {
    auto ok;
    auto r;
    auto body;

    fails[0] = 0;
    errc[0] = 0;
    errc[1] = 0;
    errc[2] = 0;

    // бот-слот вручную (tg_bot появится в Task 5)
    bot[0] = "123:fake";
    bot[1] = "https://api.telegram.org";
    bot[7] = &myerr;

    // (а) прямой пост: живой 401 от api.telegram.org
    ok = tg_http_post("https://api.telegram.org/bot123:fake/getMe", "");
    if ok == 0 {
        printf("FAIL: no network\n");
        exit(1);
    }
    chk(tg_http_last_ok == 1, "http: last_ok == 1");
    body = tg_http_body();
    chk(tg_get_bool(body, "ok") == 0, "http: ok == false");
    chk(tg_get_num(body, "error_code") == 401, "http: error_code == 401");

    // (б) мёртвый домен: транспортная ошибка
    ok = tg_http_post("https://no-such-host-zzz.invalid/getMe", "");
    chk(ok == 0, "http: мёртвый домен -> 0");
    chk(tg_http_curlcode != 0, "http: код curl ненулевой");

    // (в)+(г) tg_call: 401 → 0, on_error поймал код и описание
    r = tg_call(&bot, "getMe", 0);
    chk(r == 0, "call: 401 -> 0");
    chk(errc[0] == 1, "call: on_error вызван 1 раз");
    chk(errc[1] == 401, "call: on_error code == 401");
    chk(errc[2] == 1, "call: on_error desc непустой");

    // повторный вызов — счётчик растёт, код тот же
    r = tg_call(&bot, "getMe", 0);
    chk(r == 0, "call: повторный 401 -> 0");
    chk(errc[0] == 2, "call: on_error вызван 2-й раз");
    chk(errc[1] == 401, "call: on_error code == 401 (2-й)");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
