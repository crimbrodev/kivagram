// t_v4_fsm.k — FSM lib/tg_fsm.k (волна V4): стратегии global/isolated,
// state/data/clear, shallow-merge update_data, sqlite-персистентность,
// кириллица. Канон tests/t_v4_kv.k. Удаляет /tmp/v4_fsm_test.db.
extern printf
extern exit
extern strcmp
extern strstr
extern remove

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
    auto p;

    fails[0] = 0;

    // ===== 1. memory-backend, стратегия global (дефолт) =====
    chk(tg_kv_open(0) == 1, "fsm: kv open(0)");
    tg_fsm_strategy(0);
    chk(tg_fsm_state(1, 9) == 0, "global: нет состояния → 0");
    chk(tg_fsm_set(1, 9, "G:S") == 1, "global: set → 1");
    p = tg_fsm_state(1, 9);
    chk(p != 0, "global: state есть");
    if p != 0 chk(strcmp(p, "G:S") == 0, "global: state == G:S");

    // глобальная стратегия: другой chat, тот же user — тот же ключ
    chk(tg_fsm_set(55, 9, "G:S2") == 1, "global: set в другом chat");
    p = tg_fsm_state(1, 9);
    chk(p != 0, "global: state после set в другом chat");
    if p != 0 chk(strcmp(p, "G:S2") == 0, "global: состояние общее между чатами");

    // state=0 стирает состояние, data остаётся (как set_state(None) в aiogram)
    chk(tg_fsm_set_data(1, 9, "{\"x\":1}") == 1, "global: set_data → 1");
    chk(tg_fsm_set(1, 9, 0) == 1, "global: set(0) → 1 (стирание)");
    chk(tg_fsm_state(1, 9) == 0, "global: state стёрт");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "global: data пережила стирание state");
    if p != 0 chk(strcmp(p, "{\"x\":1}") == 0, "global: data == {\"x\":1}");

    // data set/get
    chk(tg_fsm_set_data(1, 9, "{\"a\":1}") == 1, "set_data → 1");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "data есть");
    if p != 0 chk(strcmp(p, "{\"a\":1}") == 0, "data == {\"a\":1}");

    // update_data: shallow-merge {"a":1} + {"b":2} → содержит и a, и b
    chk(tg_fsm_update_data(1, 9, "{\"b\":2}") == 1, "update_data → 1");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "merge: data есть");
    if p != 0 {
        chk(strstr(p, "\"a\":1") != 0, "merge: содержит a:1");
        chk(strstr(p, "\"b\":2") != 0, "merge: содержит b:2");
    }

    // shallow: ключ нового объекта перезаписывает старое значение
    tg_fsm_update_data(1, 9, "{\"a\":3}");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "merge2: data есть");
    if p != 0 {
        chk(strstr(p, "\"a\":3") != 0, "merge2: a перезаписан → 3");
        chk(strstr(p, "\"a\":1") == 0, "merge2: старого a:1 нет");
        chk(strstr(p, "\"b\":2") != 0, "merge2: b уцелел");
    }

    // вложенные значения не рвутся (shallow: объект целиком копируется)
    tg_fsm_set_data(1, 9, "{\"cfg\":{\"n\":1},\"t\":2}");
    tg_fsm_update_data(1, 9, "{\"z\":9}");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "merge3: data есть");
    if p != 0 {
        chk(strstr(p, "\"cfg\":{\"n\":1}") != 0, "merge3: вложенный объект уцелел");
        chk(strstr(p, "\"t\":2") != 0, "merge3: t уцелел");
        chk(strstr(p, "\"z\":9") != 0, "merge3: z добавлен");
    }

    // json=0 стирает data
    chk(tg_fsm_update_data(1, 9, 0) == 1, "update_data(0) → 1");
    chk(tg_fsm_data(1, 9) == 0, "update_data(0) → data стёрта");

    // update_data с пустым существующим data → просто записать json
    tg_fsm_update_data(1, 9, "{\"n\":5}");
    p = tg_fsm_data(1, 9);
    chk(p != 0, "merge4: data из пустого");
    if p != 0 chk(strcmp(p, "{\"n\":5}") == 0, "merge4: data == {\"n\":5}");

    // clear: state + data
    tg_fsm_set(1, 9, "X:Y");
    tg_fsm_set_data(1, 9, "{\"q\":1}");
    chk(tg_fsm_clear(1, 9) == 1, "clear → 1");
    chk(tg_fsm_state(1, 9) == 0, "clear: state нет");
    chk(tg_fsm_data(1, 9) == 0, "clear: data нет");

    // ===== 2. стратегия isolated =====
    tg_fsm_strategy(1);
    tg_fsm_set(10, 20, "I:S1");
    tg_fsm_set(11, 20, "I:S2");
    p = tg_fsm_state(10, 20);
    chk(p != 0, "isolated: state chat10 есть");
    if p != 0 chk(strcmp(p, "I:S1") == 0, "isolated: chat10 → I:S1");
    p = tg_fsm_state(11, 20);
    chk(p != 0, "isolated: state chat11 есть");
    if p != 0 chk(strcmp(p, "I:S2") == 0, "isolated: chat11 → I:S2");

    // isolated-ключи не видят global-состояние и наоборот
    tg_fsm_strategy(0);
    tg_fsm_set(1, 9, "G:N");
    tg_fsm_strategy(1);
    chk(tg_fsm_state(1, 9) == 0, "isolated: не видит global-ключ");
    tg_fsm_strategy(0);
    p = tg_fsm_state(1, 9);
    chk(p != 0, "global: ключ уцелел");
    if p != 0 chk(strcmp(p, "G:N") == 0, "global: G:N");
    tg_fsm_clear(1, 9);
    tg_fsm_strategy(1);
    tg_fsm_clear(10, 20);
    tg_fsm_clear(11, 20);
    tg_fsm_strategy(0);

    // ===== 3. кириллица в состоянии =====
    tg_fsm_set(1, 9, "Ожидание:Ввод");
    p = tg_fsm_state(1, 9);
    chk(p != 0, "кириллица: state есть");
    if p != 0 chk(strcmp(p, "Ожидание:Ввод") == 0, "кириллица: state == Ожидание:Ввод");
    tg_fsm_clear(1, 9);

    tg_kv_close();
    chk(tg_fsm_state(1, 9) == 0, "fsm: state без бэкенда → 0");

    // ===== 4. sqlite-персистентность =====
    remove("/tmp/v4_fsm_test.db");
    chk(tg_kv_open("/tmp/v4_fsm_test.db") == 1, "fsm: kv open sqlite");
    tg_fsm_strategy(0);
    tg_fsm_set(77, 88, "P:S");
    tg_fsm_set_data(77, 88, "{\"p\":1}");
    tg_kv_close();
    chk(tg_kv_open("/tmp/v4_fsm_test.db") == 1, "fsm: reopen");
    p = tg_fsm_state(77, 88);
    chk(p != 0, "sqlite: state пережил reopen");
    if p != 0 chk(strcmp(p, "P:S") == 0, "sqlite: state == P:S");
    p = tg_fsm_data(77, 88);
    chk(p != 0, "sqlite: data пережила reopen");
    if p != 0 chk(strcmp(p, "{\"p\":1}") == 0, "sqlite: data == {\"p\":1}");

    // стратегия isolated на sqlite
    tg_fsm_strategy(1);
    tg_fsm_set(77, 88, "I:P");
    p = tg_fsm_state(77, 88);
    if p != 0 chk(strcmp(p, "I:P") == 0, "sqlite isolated: I:P");
    tg_fsm_strategy(0);
    p = tg_fsm_state(77, 88);
    if p != 0 chk(strcmp(p, "P:S") == 0, "sqlite global: P:S уцелел");

    tg_kv_close();
    remove("/tmp/v4_fsm_test.db");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
