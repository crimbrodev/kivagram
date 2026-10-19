// t_v2_kb.k — B6: билдеры клавиатур и reply/link-preview хелперы (без сети,
// только strcmp готовых строк). Контракты — docs/superpowers/plans/
// 2026-10-19-v2-parallel-wave1.md Task 8.
extern printf
extern exit
extern strcmp
extern strstr

fails[1];
kb[3];          // пользовательский Buf-слот для билдеров (0 ptr*, 1 len, 2 cap)

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
    auto body;

    fails[0] = 0;

    // 1. Контракт плана: begin + btn(М,greet) + row + btn(Go,http://x) + done
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "М", "greet");
    tg_kb_row(&kb);
    tg_kb_btn(&kb, "Go", "http://x");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"М\",\"callback_data\":\"greet\"}],[{\"text\":\"Go\",\"url\":\"http://x\"}]]}") == 0,
        "kb: план-контракт inline");

    // 2. Одна кнопка без row
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "A", "d1");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"A\",\"callback_data\":\"d1\"}]]}") == 0,
        "kb: одна кнопка без row");

    // 3. begin + done без кнопок → пустой массив
    tg_kb_begin(&kb);
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[]}") == 0,
        "kb: begin+done → []");

    // 4. Висячий row в конце не создаёт пустой ряд
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "A", "d1");
    tg_kb_row(&kb);
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"A\",\"callback_data\":\"d1\"}]]}") == 0,
        "kb: висячий row убран");

    // 5. Две кнопки в одном ряду (разделитель между объектами)
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "1", "x");
    tg_kb_btn(&kb, "2", "y");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"1\",\"callback_data\":\"x\"},{\"text\":\"2\",\"callback_data\":\"y\"}]]}") == 0,
        "kb: две кнопки в ряду");

    // 6. tg_kb_url_btn — явный url-тип (не-http схема тоже через него)
    tg_kb_begin(&kb);
    tg_kb_url_btn(&kb, "Site", "tg://user?id=1");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"Site\",\"url\":\"tg://user?id=1\"}]]}") == 0,
        "kb: url_btn");

    // 7. Кавычка в тексте кнопки эскейпится через tg_json_escape
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "Ск\"о", "d");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"Ск\\\"о\",\"callback_data\":\"d\"}]]}") == 0,
        "kb: кавычка в тексте эскейпится");

    // 8. Кавычка в callback_data эскейпится
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "B", "a\"b");
    s = tg_kb_done(&kb);
    chk(strcmp(s, "{\"inline_keyboard\":[[{\"text\":\"B\",\"callback_data\":\"a\\\"b\"}]]}") == 0,
        "kb: кавычка в data эскейпится");

    // 9. Reply-клавиатура: два ряда, resize_keyboard:true
    tg_rkb_begin(&kb);
    tg_rkb_btn(&kb, "Да");
    tg_rkb_row(&kb);
    tg_rkb_btn(&kb, "Нет");
    s = tg_rkb_done(&kb);
    chk(strcmp(s, "{\"keyboard\":[[\"Да\"],[\"Нет\"]],\"resize_keyboard\":true}") == 0,
        "rkb: два ряда");

    // 10. Reply-клавиатура: одна кнопка в одном ряду
    tg_rkb_begin(&kb);
    tg_rkb_btn(&kb, "Меню");
    s = tg_rkb_done(&kb);
    chk(strcmp(s, "{\"keyboard\":[[\"Меню\"]],\"resize_keyboard\":true}") == 0,
        "rkb: одна кнопка");

    // 11. Reply-клавиатура пустая
    tg_rkb_begin(&kb);
    s = tg_rkb_done(&kb);
    chk(strcmp(s, "{\"keyboard\":[],\"resize_keyboard\":true}") == 0,
        "rkb: begin+done → []");

    // 12. tg_kb_remove
    s = tg_kb_remove();
    chk(strcmp(s, "{\"remove_keyboard\":true}") == 0,
        "remove: {remove_keyboard:true}");

    // 13. tg_kb_force_reply(0) — без input_field_placeholder
    s = tg_kb_force_reply(0);
    chk(strcmp(s, "{\"force_reply\":true}") == 0,
        "force_reply(0)");

    // 14. tg_kb_force_reply(placeholder) — поле добавлено, кавычка эскейпом
    s = tg_kb_force_reply("Ответ \"здесь\"");
    chk(strcmp(s, "{\"force_reply\":true,\"input_field_placeholder\":\"Ответ \\\"здесь\\\"\"}") == 0,
        "force_reply(placeholder): эскейп");

    // 15. tg_reply_params(msg_id)
    s = tg_reply_params(42);
    chk(strcmp(s, "{\"message_id\":42}") == 0,
        "reply_params: {message_id:42}");

    // 16. tg_link_preview_off
    s = tg_link_preview_off();
    chk(strcmp(s, "{\"is_disabled\":true}") == 0,
        "link_preview_off");

    // 17. Интеграция: готовая строка вставляется через tg_param_json
    //     как reply_markup в тело запроса
    tg_params_reset(&tg_paramslot);
    tg_kb_begin(&kb);
    tg_kb_btn(&kb, "М", "greet");
    s = tg_kb_done(&kb);
    tg_param_json(&tg_paramslot, "reply_markup", s);
    body = tg_params_done(&tg_paramslot);
    chk(strstr(body, "\"reply_markup\":{\"inline_keyboard\":[[{\"text\":\"М\",\"callback_data\":\"greet\"}]]}") != 0,
        "kb: вставка в тело через tg_param_json");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
