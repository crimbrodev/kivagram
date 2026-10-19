// t_poll_smoke.k — негативный smoke: identify с фейковым токеном (нужна сеть).
// Контракт: tg_identify → 0, флаг ошибки установлен, on_error поймал 401.
// Без сети on_error получит код curl → FAIL: no network.
extern printf
extern exit

fails[1];
caught[1];
calls[1];

myerr(bot, method, code, desc) {
    calls[0] = calls[0] + 1;
    caught[0] = code;
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
    auto bot;
    auto r;

    fails[0] = 0;
    caught[0] = 0;
    calls[0] = 0;

    bot = tg_bot("123:fake");
    *(bot + 56) = &myerr;   // on_error = счётчик (слот word7)

    r = tg_identify(bot);

    if caught[0] != 401 {
        printf("FAIL: no network\n");
        exit(1);
    }
    chk(r == 0, "identify: фейковый токен → возврат 0");
    chk(tg_last_err != 0, "identify: флаг ошибки установлен");
    chk(calls[0] > 0, "identify: on_error вызван");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
