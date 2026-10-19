// t_v2_core.k — ядро v2: tg_param_raw (значение как есть) и tg_html_escape
extern printf
extern exit
extern strcmp
extern strstr

fails[1];

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
    auto s;

    fails[0] = 0;

    // 1. tg_param_raw: дробь latitude=55.75 — без кавычек вокруг значения
    tg_params_reset(&tg_paramslot);
    tg_param_raw(&tg_paramslot, "latitude", "55.75");
    s = tg_params_done(&tg_paramslot);
    chk(strstr(s, "\"latitude\":55.75") != 0, "raw: дробь latitude без кавычек");
    chk(strstr(s, "\"55.75\"") == 0, "raw: значение 55.75 не в кавычках");

    // 2. tg_param_raw: литерал true — тоже без кавычек
    tg_params_reset(&tg_paramslot);
    tg_param_raw(&tg_paramslot, "enabled", "true");
    s = tg_params_done(&tg_paramslot);
    chk(strstr(s, "\"enabled\":true") != 0, "raw: литерал true без кавычек");

    // 3. контраст: tg_param_str даёт кавычки, tg_param_num — нет кавычек
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "latitude", "55.75");
    s = tg_params_done(&tg_paramslot);
    chk(strstr(s, "\"latitude\":\"55.75\"") != 0, "contrast: str — значение в кавычках");

    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", 77);
    s = tg_params_done(&tg_paramslot);
    chk(strstr(s, "\"chat_id\":77") != 0, "contrast: num — число без кавычек");

    // 4. tg_html_escape: < > & эскейпятся, кавычки не трогаем
    // NB: ожидание по правилу "& → &amp;": input "a<b>&c" → "a&lt;b&gt;&amp;c"
    // (в спеке в ожидании был потерян "amp;" — кейс 5 подтверждает правило)
    s = tg_html_escape("a<b>&c");
    chk(strcmp(s, "a&lt;b&gt;&amp;c") == 0, "html: < > & эскейпятся");

    // 5. амперсанд первым: & → &amp; (до замены остальных)
    s = tg_html_escape("&x");
    chk(strcmp(s, "&amp;x") == 0, "html: & → &amp; первым");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
