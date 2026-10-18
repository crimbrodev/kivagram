// t_params.k — билдер параметров запроса kivagram
extern printf
extern exit
extern strcmp

fails[1];
b[3];

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
    auto p;

    fails[0] = 0;

    // базовый сценарий: сборка {"a":1,"b":"x"} без висящей запятой
    tg_buf_init(&b);
    tg_params_reset(&b);
    tg_param_num(&b, "a", 1);
    tg_param_str(&b, "b", "x");
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"a\":1,\"b\":\"x\"}") == 0, "done: {\"a\":1,\"b\":\"x\"}");

    // пустой билдер → {}
    tg_params_reset(&b);
    p = tg_params_done(&b);
    chk(strcmp(p, "{}") == 0, "empty: {}");

    // экранирование ключа и значения
    tg_params_reset(&b);
    tg_param_str(&b, "te\"xt", "va\\lue");
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"te\\\"xt\":\"va\\\\lue\"}") == 0, "escape: ключ и значение");

    // числа: 0 и отрицательное
    tg_params_reset(&b);
    tg_param_num(&b, "z", 0);
    tg_param_num(&b, "n", -5);
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"z\":0,\"n\":-5}") == 0, "num: 0 и -5");

    // сырой JSON (reply_markup) — без изменений
    tg_params_reset(&b);
    tg_param_json(&b, "reply_markup", "{\"inline_keyboard\":[[{}]]}");
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"reply_markup\":{\"inline_keyboard\":[[{}]]}}") == 0, "json: сырой объект");

    // кириллица
    tg_params_reset(&b);
    tg_param_str(&b, "text", "привет");
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"text\":\"привет\"}") == 0, "cyrillic: значение");

    // повторное использование буфера после done
    tg_params_reset(&b);
    tg_param_num(&b, "one", 1);
    p = tg_params_done(&b);
    chk(strcmp(p, "{\"one\":1}") == 0, "reuse: после done снова чисто");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
