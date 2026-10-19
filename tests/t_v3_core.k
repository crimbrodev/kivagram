// t_v3_core.k — ядро wave-3 (W3-0): extras-слот в tg_params_done, multipart
// (tg_mpslot + tg_mf_* + tg_call_mp), эскейп одинарной кавычки, GET/скачивание
// (tg_http_get_file / tg_get_file / tg_download_file), kind 11/12 бизнес-чата.
// Контракт D плана wave-3 + 2 кейса диспетчера. Только dry-run, без сети.
extern printf
extern exit
extern strcmp
extern strstr

fails[1];
logb[3];     // Buf-слот журнала бизнес-хендлеров
u_biz[1];    // business_message       → kind 11
u_bized[1];  // edited_business_message → kind 12

// --- хендлеры: текстово ДО main (правило порядка определений) ---

// kind 11: ctx из business_message.*, business_connection_id в слоте 17
h_biz(ctx) {
    auto t;
    auto b;
    t = tg_text(ctx);
    b = tg_business_conn(ctx);
    tg_buf_add(&logb, "biz:");
    tg_buf_add(&logb, b);
    tg_buf_add(&logb, ":");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, ";");
    1;
}

// kind 12: ctx из edited_business_message.*
h_bized(ctx) {
    auto t;
    t = tg_text(ctx);
    tg_buf_add(&logb, "bized:");
    tg_buf_add(&logb, t);
    tg_buf_add(&logb, ";");
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
    auto body;
    auto r;

    fails[0] = 0;
    tg_buf_init(&logb);

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // ===== 1. extras: слияние в тело обёртки + автосъедание слота =====
    tg_ex_reset();
    tg_ex_str("business_connection_id", "bc1");
    r = tg_send_to(bot, 55, "hi");
    chk(r == 1, "extras: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendMessage|") != 0, "extras: URL /sendMessage");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"text\":\"hi\",\"business_connection_id\":\"bc1\"}") != 0,
        "extras: ,\"business_connection_id\":\"bc1\" перед }");
    chk(tg_extraslot[1] == 0, "extras: слот пуст после обёртки");

    // ===== 2. extras + пустые params: {...} без двойных запятых =====
    tg_ex_str("business_connection_id", "bc1");
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    chk(strcmp(body, "{\"business_connection_id\":\"bc1\"}") == 0,
        "extras: пустые params → {\"business_connection_id\":\"bc1\"}");
    chk(tg_extraslot[1] == 0, "extras: слот съеден и пустым телом");
    // слот пуст — следующая обёртка не должна получить extras
    tg_send_to(bot, 55, "hi");
    chk(strstr(&tg_composed, "business_connection_id") == 0,
        "extras: не течёт в следующий вызов");

    // ===== 3. multipart: URL + фрагменты -F =====
    tg_mp_reset();
    tg_mf_str("chat_id", "55");
    tg_mf_file("document", "/tmp/a b.txt");
    r = tg_call_mp(bot, "sendDocument");
    chk(r == 1, "mp: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendDocument|") != 0, "mp: URL /sendDocument");
    chk(strstr(tg_mpslot[0], "-F 'chat_id=55' -F 'document=@/tmp/a b.txt' ") != 0,
        "mp: -F 'k=v' -F 'k=@path' с пробелом-разделителем");
    chk(strstr(&tg_composed, "-F 'chat_id=55' -F 'document=@/tmp/a b.txt'") != 0,
        "mp: dry-композиция <url>|MP <-F фрагменты>");

    // ===== 4. эскейп одинарной кавычки в mp =====
    tg_mp_reset();
    tg_mf_str("caption", "it's");
    chk(strstr(tg_mpslot[0], "-F 'caption=it'\\''s' ") != 0,
        "mp: ' → '\\'' внутри одинарных кавычек");

    // ===== 5. getFile / скачивание: композиция URL =====
    r = tg_get_file(bot, "x");
    chk(strstr(&tg_composed, "/getFile|") != 0, "get_file: URL /getFile");
    chk(strstr(&tg_composed, "{\"file_id\":\"x\"}") != 0,
        "get_file: тело {file_id}");
    chk(r == 0, "get_file: dry без ответа → 0");

    r = tg_download_file(bot, "voice/x.ogg", "/tmp/w3_core_out.ogg");
    chk(r == 1, "download: dry-возврат 1");
    chk(strstr(&tg_composed, "GET https://api.telegram.org/file/bot123:fake/voice/x.ogg") != 0,
        "download: GET <base>/file/bot<token>/<file_path>");

    // ===== 6. kind 11/12: классификация бизнес-апдейтов =====
    u_biz = "{\"update_id\":300,\"business_connection_id\":\"bc9\",\"business_message\":{\"message_id\":80,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"бизнес\"}}";
    u_bized = "{\"update_id\":301,\"business_connection_id\":\"bc9\",\"edited_business_message\":{\"message_id\":81,\"chat\":{\"id\":55,\"type\":\"private\"},\"from\":{\"id\":9,\"first_name\":\"Ю\"},\"text\":\"правка\"}}";
    chk(tg_upd_kind(u_biz) == 11, "kind: business_message == 11");
    chk(tg_upd_kind(u_bized) == 12, "kind: edited_business_message == 12");

    // ===== 7. регистрация + диспетчеризация kind 11/12 =====
    tg_on_business(bot, "biz", &h_biz);
    tg_on_business_edited(bot, "bized", &h_bized);
    tg_buf_reset(&logb);
    tg_handle_update(bot, u_biz);
    chk(strcmp(logb[0], "biz:bc9:бизнес;") == 0,
        "dispatch: business_message → tg_on_business, ctx из business_message.*");
    tg_buf_reset(&logb);
    tg_handle_update(bot, u_bized);
    chk(strcmp(logb[0], "bized:правка;") == 0,
        "dispatch: edited_business_message → tg_on_business_edited");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
