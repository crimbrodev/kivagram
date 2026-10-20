// lib/tg_kv.k — V4-A: KV-хранилище (memory/sqlite) для ядра и lib/tg_fsm.k.
//
// Контракт (зафиксирован волной V4, опираются ядро и параллельные модули):
//   tg_kv_open(path) — path (строка, файл .db) → sqlite-backend; path=0 →
//     memory-backend. Глобальный единственный инстанс (как storage у бота):
//     повторный open сначала закрывает предыдущий (tg_kv_close). Создаёт
//     таблицу `kv(k TEXT PRIMARY KEY, v TEXT)` если нет. Возврат 1 — ок, 0 —
//     ошибка (сообщение через printf "kv: ...").
//   tg_kv_get(key)   → указатель на NUL-терминированное значение в общем
//     статик-буфере (рост через extern realloc) либо 0, если ключа нет
//     (или бэкенда нет / sqlite-ошибка — «делаем вид, что ключа нет»).
//   tg_kv_set(key, val) — upsert, 1 — ок, 0 — нет бэкенда/ошибка.
//   tg_kv_del(key) — 1 если ключ был удалён, 0 если отсутствует/ошибка.
//   tg_kv_close() — сброс: memory освобождает цепочку, sqlite закрывает
//     дескриптор. Вызывать и перед повторным open.
//
// Жизнь указателя (слот-кэш): указатель из tg_kv_get валиден ТОЛЬКО до
// следующего вызова tg_kv_get / tg_kv_set / tg_kv_del / tg_kv_close —
// после любого из них буфер может быть переиспользован. Значения копируются
// в общий буфер ДО sqlite3_finalize.
//
// Лимиты: memory-backend — до 512 записей (при переполнении printf + отказ);
// sqlite — ИСКЛЮЧИТЕЛЬНО параметризованные запросы
// (sqlite3_bind_text(stmt, i, s, -1, -1), последний -1 = SQLITE_TRANSIENT),
// никакой подстановки строк в SQL.

extern malloc
extern free
extern realloc
extern strlen
extern strcmp
extern strcpy
extern memcpy
extern sprintf
extern printf

extern sqlite3_open
extern sqlite3_close
extern sqlite3_exec
extern sqlite3_prepare_v2
extern sqlite3_step
extern sqlite3_finalize
extern sqlite3_column_text
extern sqlite3_bind_text
extern sqlite3_changes
extern sqlite3_errmsg

tg_kv_bufptr;   // общий статик-буфер значения (0 — ещё не выделен)
tg_kv_buflen;   // ёмкость буфера, байт
tg_kv_backend;  // 0 = закрыто, 1 = memory, 2 = sqlite
tg_kv_db;       // sqlite3*
tg_kv_stmt;     // временный sqlite3_stmt* (готовится и финализируется на операцию)
tg_kv_mhead;    // memory: голова цепочки узлов [0]=next*, [1]=key*, [2]=val*
tg_kv_mcount;   // memory: число узлов (лимит 512)

// ===== Общий буфер значения =====

// tg_kv_reserve(n): ёмкость >= n байт; 0 — realloc не удался
tg_kv_reserve(n) {
    auto np;
    auto cap;
    if tg_kv_buflen >= n {
        1;
    } else {
        cap = tg_kv_buflen;
        if cap == 0 cap = 64;
        while cap < n cap = cap * 2;
        np = realloc(tg_kv_bufptr, cap);
        if np == 0 {
            printf("kv: realloc failed (%ld bytes)\n", cap);
            0;
        } else {
            tg_kv_bufptr = np;
            tg_kv_buflen = cap;
            1;
        }
    }
}

// tg_kv_copy(src): копия C-строки в общий буфер → указатель; src=0 → 0
tg_kv_copy(src) {
    auto n;
    if src == 0 {
        0;
    } else {
        n = strlen(src);
        if tg_kv_reserve(n + 1) == 0 {
            0;
        } else {
            memcpy(tg_kv_bufptr, src, n + 1);
            tg_kv_bufptr;
        }
    }
}

// ===== SQLite-помощники =====

// tg_kv_exec(sql): sqlite3_exec без результата → 1 — ок, 0 — ошибка
tg_kv_exec(sql) {
    auto rc;
    auto msg;
    auto ok;
    ok = 1;
    rc = sqlite3_exec(tg_kv_db, sql, 0, 0, 0);
    if rc != 0 {
        msg = sqlite3_errmsg(tg_kv_db);
        printf("kv: %s\n", msg);
        ok = 0;
    }
    ok;
}

// tg_kv_prep(sql): sqlite3_prepare_v2 → tg_kv_stmt; 1 — ок, 0 — ошибка
tg_kv_prep(sql) {
    auto rc;
    auto msg;
    auto ok;
    ok = 1;
    rc = sqlite3_prepare_v2(tg_kv_db, sql, -1, &tg_kv_stmt, 0);
    if rc != 0 {
        msg = sqlite3_errmsg(tg_kv_db);
        printf("kv: prepare: %s\n", msg);
        tg_kv_stmt = 0;
        ok = 0;
    }
    ok;
}

// ===== Memory-backend: цепочка пар (копии строк через malloc) =====

// tg_kv_mfind(key): узел с ключом или 0
tg_kv_mfind(key) {
    auto p;
    auto r;
    r = 0;
    p = tg_kv_mhead;
    while p != 0 {
        if strcmp(*(p+8), key) == 0 {
            r = p;
            p = 0;
        } else {
            p = *p;
        }
    }
    r;
}

// tg_kv_mset(key, val): upsert; 0 — лимит 512 или OOM
tg_kv_mset(key, val) {
    auto n;
    auto k;
    auto v;
    auto ok;
    ok = 1;
    n = tg_kv_mfind(key);
    if n != 0 {
        v = malloc(strlen(val) + 1);
        if v == 0 {
            printf("kv: malloc failed (value)\n");
            ok = 0;
        } else {
            strcpy(v, val);
            free(*(n+16));
            *(n+16) = v;
        }
    } else {
        if tg_kv_mcount >= 512 {
            printf("kv: memory backend full (512 entries)\n");
            ok = 0;
        } else {
            k = malloc(strlen(key) + 1);
            v = malloc(strlen(val) + 1);
            n = malloc(24);
            if k == 0 ok = 0;
            if v == 0 ok = 0;
            if n == 0 ok = 0;
            if ok == 0 {
                printf("kv: malloc failed (memory backend)\n");
                free(k);
                free(v);
                free(n);
            } else {
                strcpy(k, key);
                strcpy(v, val);
                *n = tg_kv_mhead;
                *(n+8) = k;
                *(n+16) = v;
                tg_kv_mhead = n;
                tg_kv_mcount = tg_kv_mcount + 1;
            }
        }
    }
    ok;
}

// tg_kv_mdel(key): удалить узел; 1 — был, 0 — не найден
tg_kv_mdel(key) {
    auto p;
    auto prev;
    auto ok;
    ok = 0;
    p = tg_kv_mhead;
    prev = 0;
    while p != 0 {
        if strcmp(*(p+8), key) == 0 {
            if prev == 0 {
                tg_kv_mhead = *p;
            } else {
                *prev = *p;
            }
            free(*(p+8));
            free(*(p+16));
            free(p);
            tg_kv_mcount = tg_kv_mcount - 1;
            ok = 1;
            p = 0;
        } else {
            prev = p;
            p = *p;
        }
    }
    ok;
}

// tg_kv_mget(key): значение через общий буфер (слот-кэш) или 0
tg_kv_mget(key) {
    auto n;
    auto r;
    r = 0;
    n = tg_kv_mfind(key);
    if n != 0 r = tg_kv_copy(*(n+16));
    r;
}

// ===== Публичный API =====

// tg_kv_close(): сброс инстанса (memory — free цепочки, sqlite — close)
tg_kv_close() {
    auto p;
    auto n;
    if tg_kv_stmt != 0 {
        sqlite3_finalize(tg_kv_stmt);
        tg_kv_stmt = 0;
    }
    if tg_kv_backend == 2 {
        if tg_kv_db != 0 {
            sqlite3_close(tg_kv_db);
            tg_kv_db = 0;
        }
    }
    if tg_kv_backend == 1 {
        p = tg_kv_mhead;
        while p != 0 {
            n = *p;
            free(*(p+8));
            free(*(p+16));
            free(p);
            p = n;
        }
        tg_kv_mhead = 0;
        tg_kv_mcount = 0;
    }
    tg_kv_backend = 0;
    1;
}

// tg_kv_open(path): закрыть предыдущий инстанс и открыть новый
// (path=0 → memory, иначе sqlite-файл + DDL); 1 — ок, 0 — ошибка
tg_kv_open(path) {
    auto ok;
    auto rc;
    ok = 1;
    tg_kv_close();
    if path == 0 {
        tg_kv_backend = 1;
        tg_kv_mhead = 0;
        tg_kv_mcount = 0;
    } else {
        rc = sqlite3_open(path, &tg_kv_db);
        if rc != 0 {
            printf("kv: open failed: %s\n", path);
            if tg_kv_db != 0 {
                sqlite3_close(tg_kv_db);
                tg_kv_db = 0;
            }
            ok = 0;
        } else {
            tg_kv_backend = 2;
            if tg_kv_exec("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT)") == 0 {
                sqlite3_close(tg_kv_db);
                tg_kv_db = 0;
                tg_kv_backend = 0;
                ok = 0;
            }
        }
    }
    ok;
}

// tg_kv_get(key): значение в общем буфере (слот-кэш) или 0 — ключа нет
tg_kv_get(key) {
    auto r;
    auto rc;
    auto msg;
    auto tv;
    r = 0;
    if tg_kv_backend == 1 {
        r = tg_kv_mget(key);
    } else if tg_kv_backend == 2 {
        if tg_kv_prep("SELECT v FROM kv WHERE k = ?1") != 0 {
            sqlite3_bind_text(tg_kv_stmt, 1, key, -1, -1);
            rc = sqlite3_step(tg_kv_stmt);
            if rc == 100 {
                tv = sqlite3_column_text(tg_kv_stmt, 0);
                r = tg_kv_copy(tv);   // копия ДО finalize
            } else if rc != 101 {
                msg = sqlite3_errmsg(tg_kv_db);
                printf("kv: get: %s\n", msg);
            }
            sqlite3_finalize(tg_kv_stmt);
            tg_kv_stmt = 0;
        }
    }
    r;
}

// tg_kv_set(key, val): upsert; 1 — ок, 0 — нет бэкенда/ошибка
tg_kv_set(key, val) {
    auto ok;
    auto rc;
    auto msg;
    ok = 1;
    if tg_kv_backend == 1 {
        ok = tg_kv_mset(key, val);
    } else if tg_kv_backend == 2 {
        if tg_kv_prep("INSERT OR REPLACE INTO kv(k, v) VALUES(?1, ?2)") == 0 {
            ok = 0;
        } else {
            sqlite3_bind_text(tg_kv_stmt, 1, key, -1, -1);
            sqlite3_bind_text(tg_kv_stmt, 2, val, -1, -1);
            rc = sqlite3_step(tg_kv_stmt);
            if rc != 101 {
                msg = sqlite3_errmsg(tg_kv_db);
                printf("kv: set: %s\n", msg);
                ok = 0;
            }
            sqlite3_finalize(tg_kv_stmt);
            tg_kv_stmt = 0;
        }
    } else {
        printf("kv: set: no backend (tg_kv_open first)\n");
        ok = 0;
    }
    ok;
}

// tg_kv_del(key): 1 — ключ удалён, 0 — отсутствует/ошибка
tg_kv_del(key) {
    auto ok;
    auto rc;
    auto msg;
    ok = 0;
    if tg_kv_backend == 1 {
        ok = tg_kv_mdel(key);
    } else if tg_kv_backend == 2 {
        if tg_kv_prep("DELETE FROM kv WHERE k = ?1") == 0 {
            ok = 0;
        } else {
            sqlite3_bind_text(tg_kv_stmt, 1, key, -1, -1);
            rc = sqlite3_step(tg_kv_stmt);
            if rc == 101 {
                if sqlite3_changes(tg_kv_db) > 0 ok = 1;
            } else {
                msg = sqlite3_errmsg(tg_kv_db);
                printf("kv: del: %s\n", msg);
            }
            sqlite3_finalize(tg_kv_stmt);
            tg_kv_stmt = 0;
        }
    }
    ok;
}
