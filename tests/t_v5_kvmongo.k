// t_v5_kvmongo.k — V5-C: BSON + OP_MSG (lib/tg_kv_mongo.k), БЕЗ сети.
//
// Детерминированно тестируется кодировщик/декодер BSON и сборка wire-фрейма
// OP_MSG (opcode 2013):
//   1) put_str → точные байты документа {k:"v"}: int32 total_len (LE) == размер,
//      тип поля 0x02, ключ-cstring, int32 len (с NUL), данные, NUL;
//   2) get_str / get_i64 / get_doc round-trip (+i32, отрицательные, пропуск
//      неизвестных полей и вложенных документов);
//   3) вложенный документ (put_doc_begin/wrap_begin/end) → get_doc из внешнего;
//   4) OP_MSG: первые 4 байта = длина фрейма, opcode по смещению 12 == 2013,
//      flagBits == 0, sectionKind == 0, BSON начинается со смещения 21;
//   5) команды insert/find/delete/hello — содержимое BSON-документов.
//
// Без сети остаётся сокетный слой: tg_mongo_connect / tg_mongo_call /
// tg_kv_mongo_connect/get/set/del/close требуют живого mongod (здесь его нет и
// покрыты тестом не будут; ручная проверка — mongod на 127.0.0.1:27017).
extern printf
extern exit
extern strcmp
extern strlen
extern sprintf
extern strcpy

fails[1];
b[4];       // Buf-слот под документ
rb[4];      // Buf-слот под фильтр/второй документ
expb[16];   // ожидаемые байты документа {k:"v"}

rd32(p) {
    auto v;
    v = @8 *p;
    v = v + ((@8 *(p + 1)) << 8);
    v = v + ((@8 *(p + 2)) << 16);
    v = v + ((@8 *(p + 3)) << 24);
    if @8 *(p + 3) > 127 v = v - 4294967296;
    v;
}

// eqs(s, want): 1 — строки равны (0-указатель ≠ want)
eqs(s, want) {
    if s == 0 return 0;
    strcmp(s, want) == 0;
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
    auto doc;
    auto sub;
    auto f;
    auto bson;
    auto arr;
    auto row;
    auto i;
    auto bad;

    fails[0] = 0;

    // ===== 1. put_str: точные байты {k:"v"} =====
    tg_buf_init(&b);
    tg_mongo_bson_wrap_begin(&b);
    tg_mongo_bson_put_str(&b, "k", "v");
    tg_mongo_bson_wrap_end(&b);
    doc = b[0];
    // 0E 00 00 00 | 02 | 'k' 00 | 02 00 00 00 | 'v' 00 | 00
    expb[0] = 14;   expb[1] = 0;   expb[2] = 0;   expb[3] = 0;
    expb[4] = 2;    expb[5] = 107; expb[6] = 0;   expb[7] = 2;
    expb[8] = 0;    expb[9] = 0;   expb[10] = 0;  expb[11] = 118;
    expb[12] = 0;   expb[13] = 0;
    chk(b[1] == 14, "bson: put_str → размер 14");
    chk(tg_mongo_bson_len(&b) == 14, "bson: bson_len == 14");
    chk(rd32(doc) == 14, "bson: первые 4 байта (LE-int32) == размер");
    chk(tg_mongo_bson_doclen(doc) == 14, "bson: doclen == размер буфера");
    bad = 0;
    i = 0;
    while i < 14 {
        if @8 *(doc + i) != expb[i] bad = 1;
        i = i + 1;
    }
    chk(bad == 0, "bson: точные байты документа {k:\"v\"}");
    chk(@8 *(doc + 4) == 2, "bson: поле 0x02 (string)");

    // ===== 2. get_str round-trip =====
    chk(tg_mongo_bson_get_str(doc, "k") != 0, "bson: get_str есть");
    sub = tg_mongo_bson_get_str(doc, "k");
    chk(eqs(sub, "v"), "bson: get_str → 'v'");
    chk(tg_mongo_bson_get_str(doc, "missing") == 0, "bson: нет ключа → 0");
    bad = tg_mongo_bson_get_str(doc, "k");
    chk(eqs(bad, "v"), "bson: get_str воспроизводим");

    // ===== 3. i64 / i32 round-trip =====
    tg_buf_reset(&b);
    tg_mongo_bson_wrap_begin(&b);
    tg_mongo_bson_put_i64(&b, "big", 1234567890123);
    tg_mongo_bson_put_i64(&b, "neg", 0 - 42);
    tg_mongo_bson_put_i32(&b, "small", 7);
    tg_mongo_bson_put_str(&b, "s", "значение 🎉");
    tg_mongo_bson_wrap_end(&b);
    doc = b[0];
    chk(tg_mongo_bson_get_i64(doc, "big") == 1234567890123, "bson: i64 round-trip");
    chk(tg_mongo_bson_get_i64(doc, "neg") == 0 - 42, "bson: i64 отрицательное");
    chk(tg_mongo_bson_get_i64(doc, "small") == 7, "bson: i32 → get_i64");
    chk(tg_mongo_bson_get_i64(doc, "nope") == 0, "bson: нет ключа → 0");
    sub = tg_mongo_bson_get_str(doc, "s");
    chk(eqs(sub, "значение 🎉"), "bson: строка с кириллицей/эмодзи (байтовая длина)");
    chk(strlen("значение 🎉") == 21, "bson: длина 'значение 🎉' = 21 байт");

    // ===== 4. вложенный документ =====
    tg_buf_reset(&b);
    tg_mongo_bson_wrap_begin(&b);
    tg_mongo_bson_put_str(&b, "k", "v");
    tg_mongo_bson_put_doc_begin(&b, "nested");
    tg_mongo_bson_put_str(&b, "ik", "iv");
    tg_mongo_bson_wrap_end(&b);
    tg_mongo_bson_wrap_end(&b);
    doc = b[0];
    chk(rd32(doc) == b[1], "bson: внешний док — длина включает вложенный");
    sub = tg_mongo_bson_get_doc(doc, "nested");
    chk(sub != 0, "bson: get_doc(nested) из внешнего по ключу");
    if sub != 0 {
        chk(tg_mongo_bson_doclen(sub) == 16, "bson: длина вложенного = 16");
        bad = tg_mongo_bson_get_str(sub, "ik");
        chk(eqs(bad, "iv"), "bson: get_str из вложенного → 'iv'");
    }
    chk(tg_mongo_bson_get_str(doc, "nested") == 0, "bson: док ≠ строка → 0");
    bad = tg_mongo_bson_get_str(doc, "k");
    chk(eqs(bad, "v"), "bson: поле после вложенного дока найдено");

    // ===== 5. OP_MSG =====
    tg_buf_reset(&b);
    tg_mongo_bson_wrap_begin(&b);
    tg_mongo_bson_put_str(&b, "k", "v");
    tg_mongo_bson_wrap_end(&b);
    doc = b[0];
    f = tg_mongo_opmsg(doc);
    chk(f != 0, "opmsg: фрейм собран");
    chk(f[1] == 21 + tg_mongo_bson_doclen(doc), "opmsg: размер = 21 + bson");
    chk(rd32(f[0]) == f[1], "opmsg: первые 4 байта = длина фрейма");
    chk(rd32(f[0] + 4) == 0, "opmsg: requestId = 0");
    chk(rd32(f[0] + 8) == 0, "opmsg: responseTo = 0");
    chk(rd32(f[0] + 12) == 2013, "opmsg: opcode 2013 по смещению 12");
    chk(rd32(f[0] + 16) == 0, "opmsg: flagBits = 0");
    chk(@8 *(f[0] + 20) == 0, "opmsg: sectionKind = 0");
    chk(rd32(f[0] + 21) == tg_mongo_bson_doclen(doc), "opmsg: BSON в секции kind 0");

    // ===== 6. команды =====
    tg_buf_reset(&rb);
    tg_mongo_bson_wrap_begin(&rb);
    tg_mongo_bson_put_str(&rb, "k", "v");
    tg_mongo_bson_put_str(&rb, "val", "значение 🎉");
    tg_mongo_bson_wrap_end(&rb);

    // insert: {insert:coll, documents:[{...}], $db:"tgkv"}
    f = tg_mongo_insert("kv", rb[0]);
    bson = f[0] + 21;
    chk(eqs(tg_mongo_bson_get_str(bson, "insert"), "kv"), "cmd: insert = 'kv'");
    chk(eqs(tg_mongo_bson_get_str(bson, "$db"), "tgkv"), "cmd: $db = 'tgkv' (по умолчанию)");
    arr = tg_mongo_bson_get_doc(bson, "documents");
    chk(arr != 0, "cmd: documents — массив (тип 0x04)");
    if arr != 0 {
        row = tg_mongo_bson_get_doc(arr, "0");
        chk(row != 0, "cmd: documents[0]");
        if row != 0 {
            chk(eqs(tg_mongo_bson_get_str(row, "k"), "v"), "cmd: documents[0].k = 'v'");
            chk(eqs(tg_mongo_bson_get_str(row, "val"), "значение 🎉"),
                "cmd: documents[0] с кириллицей/эмодзи");
        }
    }

    // find: {find:coll, filter:{k:key}, $db:"tgkv"}
    f = tg_mongo_query("kv", rb[0]);
    bson = f[0] + 21;
    chk(eqs(tg_mongo_bson_get_str(bson, "find"), "kv"), "cmd: find = 'kv'");
    arr = tg_mongo_bson_get_doc(bson, "filter");
    chk(arr != 0, "cmd: filter — документ");
    if arr != 0 {
        chk(eqs(tg_mongo_bson_get_str(arr, "k"), "v"), "cmd: filter.k = 'v'");
    }

    // delete: {delete:coll, deletes:[{q:filter, limit:0}], $db:"tgkv"}
    f = tg_mongo_delete("kv", rb[0]);
    bson = f[0] + 21;
    chk(eqs(tg_mongo_bson_get_str(bson, "delete"), "kv"), "cmd: delete = 'kv'");
    arr = tg_mongo_bson_get_doc(bson, "deletes");
    chk(arr != 0, "cmd: deletes — массив");
    if arr != 0 {
        row = tg_mongo_bson_get_doc(arr, "0");
        chk(row != 0, "cmd: deletes[0]");
        if row != 0 {
            sub = tg_mongo_bson_get_doc(row, "q");
            chk(sub != 0, "cmd: deletes[0].q — документ");
            if sub != 0 {
                chk(eqs(tg_mongo_bson_get_str(sub, "k"), "v"), "cmd: deletes[0].q.k = 'v'");
            }
            chk(tg_mongo_bson_get_i64(row, "limit") == 0, "cmd: limit = 0");
        }
    }

    // hello (handshake): {hello:1, $db:"admin"}
    f = tg_mongo_ismaster();
    bson = f[0] + 21;
    chk(tg_mongo_bson_get_i64(bson, "hello") == 1, "cmd: hello = 1");
    chk(eqs(tg_mongo_bson_get_str(bson, "$db"), "admin"), "cmd: hello $db = 'admin'");

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
