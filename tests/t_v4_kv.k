// t_v4_kv.k — KV-хранилище lib/tg_kv.k (волна V4): memory/sqlite бэкенды,
// upsert, отсутствующий ключ → 0, спецсимволы (bind), персистентность sqlite,
// пустое значение, >10 записей. Контракт V4-A: указатель tg_kv_get живёт
// до следующего tg_kv_get/set/del/close.
extern printf
extern exit
extern strcmp
extern remove

fails[1];
key_buf[16];    // 128 байт — имя ключа bulk%ld
val_buf[32];    // 256 байт — значение bulk

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
    auto i;

    fails[0] = 0;

    // ===== 1. memory-backend =====
    chk(tg_kv_open(0) == 1, "mem: open(0) → 1");
    chk(tg_kv_set("alpha", "one") == 1, "mem: set → 1");
    p = tg_kv_get("alpha");
    chk(p != 0, "mem: get есть ключа → указатель");
    if p != 0 chk(strcmp(p, "one") == 0, "mem: значение one");
    chk(tg_kv_get("missing") == 0, "mem: нет ключа → 0");

    // upsert: второй set перезаписывает
    tg_kv_set("alpha", "two");
    p = tg_kv_get("alpha");
    chk(p != 0, "mem: upsert get");
    if p != 0 chk(strcmp(p, "two") == 0, "mem: upsert → two");

    // del
    chk(tg_kv_del("alpha") == 1, "mem: del → 1");
    chk(tg_kv_get("alpha") == 0, "mem: после del → 0");
    chk(tg_kv_del("alpha") == 0, "mem: del отсутствующего → 0");

    // пустое значение
    chk(tg_kv_set("empty", "") == 1, "mem: set пустого → 1");
    p = tg_kv_get("empty");
    chk(p != 0, "mem: пустое значение → указатель (не 0)");
    if p != 0 chk(@8 *p == 0, "mem: пустое значение → NUL");

    // >10 записей
    i = 0;
    while i < 12 {
        sprintf(&key_buf, "m_bulk%ld", i);
        sprintf(&val_buf, "m_val_%ld", i);
        tg_kv_set(&key_buf, &val_buf);
        i = i + 1;
    }
    i = 0;
    while i < 12 {
        sprintf(&key_buf, "m_bulk%ld", i);
        p = tg_kv_get(&key_buf);
        if p == 0 {
            printf("FAIL: mem bulk %ld отсутствует\n", i);
            fails[0] = fails[0] + 1;
        }
        i = i + 1;
    }

    // close сбрасывает
    tg_kv_close();
    chk(tg_kv_get("m_bulk0") == 0, "mem: get после close → 0 (нет бэкенда)");

    // ===== 2. sqlite-backend =====
    remove("/tmp/v4_kv_test.db");
    chk(tg_kv_open("/tmp/v4_kv_test.db") == 1, "sql: open → 1");
    chk(tg_kv_set("skey", "sval") == 1, "sql: set → 1");
    p = tg_kv_get("skey");
    chk(p != 0, "sql: get есть");
    if p != 0 chk(strcmp(p, "sval") == 0, "sql: значение sval");
    chk(tg_kv_get("nope") == 0, "sql: нет ключа → 0");

    // upsert
    tg_kv_set("skey", "sval2");
    p = tg_kv_get("skey");
    if p != 0 chk(strcmp(p, "sval2") == 0, "sql: upsert → sval2");

    // спецсимволы: ' " \ кириллица emoji — через bind, без подстановки в SQL
    chk(tg_kv_set("oleg's \"quoted\" \\path\\ 🎉", "значение 'с' \"кавычками\" \\ и 😀") == 1,
        "sql: set спецсимволов → 1");
    p = tg_kv_get("oleg's \"quoted\" \\path\\ 🎉");
    chk(p != 0, "sql: спецсимволы get");
    if p != 0 chk(strcmp(p, "значение 'с' \"кавычками\" \\ и 😀") == 0,
        "sql: спецсимволы пережили bind");

    // пустое значение
    tg_kv_set("sql_empty", "");
    p = tg_kv_get("sql_empty");
    chk(p != 0, "sql: пустое значение → указатель");
    if p != 0 chk(@8 *p == 0, "sql: пустое значение → NUL");

    // del
    chk(tg_kv_del("skey") == 1, "sql: del → 1");
    chk(tg_kv_get("skey") == 0, "sql: после del → 0");

    // >10 записей
    i = 0;
    while i < 12 {
        sprintf(&key_buf, "bulk%ld", i);
        sprintf(&val_buf, "val_%ld", i);
        tg_kv_set(&key_buf, &val_buf);
        i = i + 1;
    }

    // персистентность: close → open → get
    tg_kv_close();
    chk(tg_kv_open("/tmp/v4_kv_test.db") == 1, "sql: reopen → 1");
    i = 0;
    while i < 12 {
        sprintf(&key_buf, "bulk%ld", i);
        p = tg_kv_get(&key_buf);
        if p == 0 {
            printf("FAIL: sql bulk %ld отсутствует после reopen\n", i);
            fails[0] = fails[0] + 1;
        } else {
            sprintf(&val_buf, "val_%ld", i);
            if strcmp(p, &val_buf) != 0 {
                printf("FAIL: sql bulk %ld значение %s != %s\n", i, p, &val_buf);
                fails[0] = fails[0] + 1;
            }
        }
        i = i + 1;
    }
    p = tg_kv_get("oleg's \"quoted\" \\path\\ 🎉");
    chk(p != 0, "sql: спецсимволы пережили reopen");
    if p != 0 chk(strcmp(p, "значение 'с' \"кавычками\" \\ и 😀") == 0,
        "sql: значение спецсимволов после reopen");
    p = tg_kv_get("sql_empty");
    chk(p != 0, "sql: пустое значение после reopen");

    tg_kv_close();
    remove("/tmp/v4_kv_test.db");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
