// t_json.k — dot-path JSON-сканер kivagram
extern printf
extern exit
extern strcmp

fails[1];
s_list[1];
s_empty[1];
s_one[1];
s_bool[1];
s_esc[1];
tailp[3];

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
    auto v;
    auto s;

    fails[0] = 0;

    // ответ в формате Telegram: пробелы после : и ,
    s_list = "{\"ok\":true, \"result\":[{\"update_id\":100001, \"message\":{\"chat\":{\"id\":111, \"first_name\":\"Аня\"}, \"text\":\"/start a b\", \"entities\":[{\"offset\":0, \"length\":6, \"type\":\"bot_command\"}]}}, {\"update_id\":100002, \"message\":{\"chat\":{\"id\":222}, \"text\":\"привет\\nмир\"}}]}";
    s_empty = "{\"ok\":true, \"result\":[]}";
    s_one = "{\"ok\":true, \"result\":[1]}";
    s_bool = "{\"ok\":true, \"result\":false}";
    s_esc = "{\"result\":\"she said \\\"hi\\\"\"}";

    // tg_get_num: вложенность объект→объект и массив→объект
    chk(tg_get_num(s_list, "result.0.message.chat.id") == 111, "num: chat.id == 111");
    chk(tg_get_num(s_list, "result.1.update_id") == 100002, "num: update_id == 100002");
    chk(tg_get_num(s_list, "result.0.update_id") == 100001, "num: update_id[0] == 100001");
    chk(tg_get_num(s_list, "result.0.message.entities.0.length") == 6, "num: entities.0.length == 6");
    chk(tg_get_num(s_list, "ok") == 0, "num: bool true как 0/не число");

    // tg_get_str: простые строки, кириллица, пробелы, escape \n и \"
    v = tg_get_str(s_list, "result.0.message.chat.first_name");
    chk(strcmp(v, "Аня") == 0, "str: кириллица Аня");
    v = tg_get_str(s_list, "result.0.message.text");
    chk(strcmp(v, "/start a b") == 0, "str: пробелы сохранены");
    v = tg_get_str(s_list, "result.1.message.text");
    chk(strcmp(v, "привет\nмир") == 0, "str: escape \\n");
    v = tg_get_str(s_list, "result.0.message.entities.0.type");
    chk(strcmp(v, "bot_command") == 0, "str: array->object->array");
    v = tg_get_str(s_esc, "result");
    chk(strcmp(v, "she said \"hi\"") == 0, "str: escape \\\"");
    v = tg_get_str(s_bool, "result");
    chk(strcmp(v, "false") == 0, "str: литерал false как строка");

    // tg_get_bool
    chk(tg_get_bool(s_bool, "ok") == 1, "bool: ok == true");
    chk(tg_get_bool(s_bool, "result") == 0, "bool: result == false");
    chk(tg_get_bool(s_bool, "absent") == 0, "bool: отсутствующий == 0");

    // tg_count: 0 / 1 / много
    chk(tg_count(s_empty, "result") == 0, "count: пустой массив == 0");
    chk(tg_count(s_one, "result") == 1, "count: один == 1");
    chk(tg_count(s_list, "result") == 2, "count: два == 2");
    chk(tg_count(s_list, "result.0.message.entities") == 1, "count: вложенный массив == 1");

    // отсутствующие пути: 0 + tg_last_err
    v = tg_get(s_list, "result.0.message.caption");
    chk(v == 0, "miss: caption == 0");
    chk(tg_last_err != 0, "miss: tg_last_err установлен");
    v = tg_get(s_list, "nope.thing");
    chk(v == 0, "miss: несуществующий корень == 0");
    v = tg_get(s_list, "result.5.message");
    chk(v == 0, "miss: индекс за пределами массива == 0");
    v = tg_get(s_list, "result.0");
    chk(v != 0, "hit: result.0 == объект");
    chk(tg_last_err == 0, "hit: tg_last_err сброшен");

    // повторное чтение после ошибки — путь снова читается
    chk(tg_get_num(s_list, "result.1.message.chat.id") == 222, "miss->hit: chat.id == 222");

    // хвост за NUL: путь лежит в буфере, за терминатором — мусор
    // (в живом боте scratchbuf после curl-команды: "curl -s -" == 9 байт)
    strcpy(&tailp, "result.0XXXXXXXX");
    *(&tailp + 8) !8 0;
    v = tg_get(s_list, &tailp);
    chk(v != 0, "tail: путь с хвостом за NUL находит result.0");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
