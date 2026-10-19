// tg_business.k — бизнес-аккаунт (W3-4): 12 обёрток Bot API для
// business-бота. Эталоны ref/api/methods: getbusinessconnection,
// readbusinessmessage, deletebusinessmessages, setbusinessaccountname,
// setbusinessaccountusername, setbusinessaccountbio,
// setbusinessaccountprofilephoto, removebusinessaccountprofilephoto,
// setbusinessaccountgiftsettings, getbusinessaccountstarbalance,
// transferbusinessaccountstars, getbusinessaccountgifts.
//
// Контракт: обязательные параметры — аргументы (≤6 на вызов); опциональные —
// 0-арг «не передавать» (username/bio: 0 → skip, "" → очистить поле;
// JSON-аргументы: 0 → skip); экзотические опциональные — через extras
// (tg_ex_str/tg_ex_raw/...): JSON-обёртки сливают слот в тело внутри
// tg_params_done, multipart-обёртка фото переносит extras в mp-поля через
// tg_biz_ex2mp и съедает слот. Вызывающий сам делает tg_ex_reset(), если
// накопленное не должно уйти в следующий вызов.
//
//   tg_set_business_name(bot, conn_id, name): name → first_name;
//     last_name (0-64) — extras: tg_ex_str("last_name", "...");
//   tg_set_business_gift_settings(bot, conn_id, json): json — объект
//     ровно с двумя обязательными полями API
//     {"show_gift_button":true,"accepted_gift_types":{...}}; каждый ключ
//     идёт в тело отдельным параметром, незнакомые ключи игнорируются;
//   tg_get_business_gifts(bot, conn_id, filters_json): filters — объект с
//     ключами-фильтрами (exclude_*, sort_by_price, offset, limit); каждый
//     ключ → отдельный параметр тела: строка → tg_param_str, литерал/число/
//     объект → tg_param_json (сырой JSON как есть), порядок — как в списке
//     ключей обёртки;
//   tg_set_business_profile_photo — multipart (tg_mf_* + tg_call_mp):
//     business_connection_id и photo (путь к файлу) — mp-поля;
//     is_public — extras → mp-поле.
//   Ключ с '.' в JSON-аргументах не поддерживается (tg_get — dot-path).

// ===== Внутренние помощники =====

tg_biz_jbuf[1024];    // 8 КБ — сырое значение ключа (литерал/объект/массив)
tg_biz_exobj[4096];   // 32 КБ — "{...}" копия extraslot для разбора
tg_biz_exk[16];       // 128 байт — текущий ключ extras
tg_biz_exv[512];      // 4 КБ — сырой объект/массив из extras

// tg_biz_jput(b, obj, key): значение key из JSON-объекта obj → параметр в
// Params-слот b. Строка → tg_param_str (разэскейп); литерал/число/объект/
// массив → сырой текст через tg_param_json (true/10/{...} — валидный JSON).
// Ключа в obj нет → параметр не передаётся.
tg_biz_jput(b, obj, key) {
    auto v;
    auto e;
    auto i;
    auto c;
    auto s;
    auto len;
    v = tg_get(obj, key);
    if v != 0 {
        if @8 *v == 34 {
            s = tg_get_str(obj, key);
            if s != 0 tg_param_str(b, key, s);
        } else {
            e = tg_skipval(v);
            len = e - v;
            if len > 7990 len = 7990;
            i = 0;
            while i < len {
                c = @8 *(v + i);
                *(&tg_biz_jbuf + i) !8 c;
                i = i + 1;
            }
            *(&tg_biz_jbuf + i) !8 0;
            tg_param_json(b, key, &tg_biz_jbuf);
        }
    }
    1;
}

// tg_biz_mpobj(key, v): сырой объект/массив v → mp-поле -F 'key=<json>'
tg_biz_mpobj(key, v) {
    auto e;
    auto i;
    auto len;
    auto c;
    e = tg_skipval(v);
    len = e - v;
    if len > 3990 len = 3990;
    i = 0;
    while i < len {
        c = @8 *(v + i);
        *(&tg_biz_exv + i) !8 c;
        i = i + 1;
    }
    *(&tg_biz_exv + i) !8 0;
    tg_mf_str(key, &tg_biz_exv);
    1;
}

// tg_biz_ex2mp(): extras (JSON-фрагменты "key":value, из tg_ex_*) → mp-поля
// -F в tg_mpslot, слот extras съедается. Строки и литералы разбираются
// tg_get_str (разэскейп), объекты/массивы уходят сырым текстом строковым
// полем формы. Возврат — 1, если перенесено хоть одно поле.
tg_biz_ex2mp() {
    auto src;
    auto n;
    auto i;
    auto c;
    auto p;
    auto keep;
    auto done;
    auto ok;
    auto ks;
    auto v;
    auto s;
    auto moved;
    moved = 0;
    if tg_extraslot[1] > 0 {
        src = tg_extraslot[0];
        n = tg_extraslot[1];
        // объект для разбора: "{" + extras без висячей запятой + "}"
        p = &tg_biz_exobj;
        *p !8 123;
        p = p + 1;
        i = 0;
        while i < n {
            c = @8 *(src + i);
            keep = 1;
            if i == n - 1 {
                if c == 44 keep = 0;
            }
            if p >= &tg_biz_exobj + 32700 keep = 0;
            if keep == 1 {
                *p !8 c;
                p = p + 1;
            }
            i = i + 1;
        }
        *p !8 125;
        *(p + 1) !8 0;
        p = &tg_biz_exobj + 1;
        done = 0;
        while done == 0 {
            if @8 *p != 34 {
                done = 1;
            } else {
                ks = p + 1;
                i = 0;
                ok = 1;
                c = @8 *ks;
                while ok == 1 {
                    if c == 34 {
                        ok = 2;
                    } else if c == 0 {
                        ok = 0;
                    } else {
                        if i > 120 {
                            ok = 0;
                        } else {
                            *(&tg_biz_exk + i) !8 c;
                            i = i + 1;
                            ks = ks + 1;
                            c = @8 *ks;
                        }
                    }
                }
                *(&tg_biz_exk + i) !8 0;
                if ok == 0 {
                    done = 1;
                } else {
                    p = ks + 1;
                    if @8 *p == 58 {
                        p = p + 1;
                        v = p;
                        if @8 *v == 123 {
                            tg_biz_mpobj(&tg_biz_exk, v);
                        } else {
                            if @8 *v == 91 {
                                tg_biz_mpobj(&tg_biz_exk, v);
                            } else {
                                s = tg_get_str(&tg_biz_exobj, &tg_biz_exk);
                                if s != 0 tg_mf_str(&tg_biz_exk, s);
                            }
                        }
                        p = tg_skipval(v);
                        moved = 1;
                        if @8 *p == 44 p = p + 1;
                    } else {
                        done = 1;
                    }
                }
            }
        }
        tg_ex_reset();
    }
    moved;
}

// ===== 12 обёрток =====

// tg_get_business_connection(bot, conn_id) — getBusinessConnection
tg_get_business_connection(bot, conn_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getBusinessConnection", body);
}

// tg_read_business_message(bot, conn_id, chat_id, msg_id) — readBusinessMessage
tg_read_business_message(bot, conn_id, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "readBusinessMessage", body);
}

// tg_delete_business_messages(bot, conn_id, msg_ids_json) — deleteBusinessMessages
// msg_ids_json: JSON-массив 1-100 id ([1,2]) → в тело как есть; 0 → не передавать
tg_delete_business_messages(bot, conn_id, msg_ids_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    if msg_ids_json != 0 tg_param_json(&tg_paramslot, "message_ids", msg_ids_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteBusinessMessages", body);
}

// tg_set_business_name(bot, conn_id, name) — setBusinessAccountName
// name → first_name (обязательный, 1-64); last_name (0-64) — extras
tg_set_business_name(bot, conn_id, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_str(&tg_paramslot, "first_name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setBusinessAccountName", body);
}

// tg_set_business_username(bot, conn_id, username) — setBusinessAccountUsername
// username 0 → не передавать; "" → очистить username (0-32 симв.)
tg_set_business_username(bot, conn_id, username) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    if username != 0 tg_param_str(&tg_paramslot, "username", username);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setBusinessAccountUsername", body);
}

// tg_set_business_bio(bot, conn_id, bio) — setBusinessAccountBio
// bio 0 → не передавать; "" → очистить bio (0-140 симв.)
tg_set_business_bio(bot, conn_id, bio) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    if bio != 0 tg_param_str(&tg_paramslot, "bio", bio);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setBusinessAccountBio", body);
}

// tg_set_business_profile_photo(bot, conn_id, path) — setBusinessAccountProfilePhoto
// multipart: business_connection_id и photo (путь к файлу) — mp-поля.
// is_public (Boolean) — extras: tg_ex_raw("is_public","true") перед вызовом;
// extras переносятся в mp-поля (tg_biz_ex2mp) и слот съедается.
tg_set_business_profile_photo(bot, conn_id, path) {
    tg_mp_reset();
    tg_mf_str("business_connection_id", conn_id);
    tg_mf_file("photo", path);
    tg_biz_ex2mp();
    tg_call_mp(bot, "setBusinessAccountProfilePhoto");
}

// tg_remove_business_profile_photo(bot, conn_id) — removeBusinessAccountProfilePhoto
// is_public — extras (JSON-путь: сливается в тело в tg_params_done)
tg_remove_business_profile_photo(bot, conn_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "removeBusinessAccountProfilePhoto", body);
}

// tg_set_business_gift_settings(bot, conn_id, json) — setBusinessAccountGiftSettings
// json: {"show_gift_button":true,"accepted_gift_types":{...}} — оба поля
// обязательны, каждый идёт в тело через tg_biz_jput; 0 → не передавать
tg_set_business_gift_settings(bot, conn_id, json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    if json != 0 {
        tg_biz_jput(&tg_paramslot, json, "show_gift_button");
        tg_biz_jput(&tg_paramslot, json, "accepted_gift_types");
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setBusinessAccountGiftSettings", body);
}

// tg_get_business_star_balance(bot, conn_id) — getBusinessAccountStarBalance
tg_get_business_star_balance(bot, conn_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getBusinessAccountStarBalance", body);
}

// tg_transfer_business_stars(bot, conn_id, star_count) — transferBusinessAccountStars
// star_count: 1-10000
tg_transfer_business_stars(bot, conn_id, star_count) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_num(&tg_paramslot, "star_count", star_count);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "transferBusinessAccountStars", body);
}

// tg_get_business_gifts(bot, conn_id, filters_json) — getBusinessAccountGifts
// filters_json: объект с ключами-фильтрами API (см. шапку файла);
// 0 → без фильтров (только business_connection_id)
tg_get_business_gifts(bot, conn_id, filters_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    if filters_json != 0 {
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_unsaved");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_saved");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_unlimited");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_limited_upgradable");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_limited_non_upgradable");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_unique");
        tg_biz_jput(&tg_paramslot, filters_json, "exclude_from_blockchain");
        tg_biz_jput(&tg_paramslot, filters_json, "sort_by_price");
        tg_biz_jput(&tg_paramslot, filters_json, "offset");
        tg_biz_jput(&tg_paramslot, filters_json, "limit");
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getBusinessAccountGifts", body);
}
