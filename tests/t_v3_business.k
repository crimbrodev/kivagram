// t_v3_business.k — бизнес-аккаунт (W3-4): 12 обёрток lib/tg_business.k.
// Только dry-run, без сети. Покрытие: URL+тела каждой обёртки, mp-кейс фото
// (business_connection_id и photo — mp-поля, extras→mp, эскейп пути),
// 0-кейсы опциональных аргументов, extras-кейсы JSON-путей.
extern printf
extern exit
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
    auto bot;
    auto r;
    auto filters;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // ===== 1. tg_get_business_connection — getBusinessConnection =====
    r = tg_get_business_connection(bot, "bc1");
    chk(r == 1, "get_conn: dry-возврат 1");
    chk(strstr(&tg_composed, "/getBusinessConnection|") != 0, "get_conn: URL");
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "get_conn: тело {business_connection_id}");

    // ===== 2. tg_read_business_message — readBusinessMessage =====
    r = tg_read_business_message(bot, "bc1", 55, 80);
    chk(r == 1, "read_msg: dry-возврат 1");
    chk(strstr(&tg_composed, "/readBusinessMessage|") != 0, "read_msg: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"chat_id\":55,\"message_id\":80}") != 0,
        "read_msg: тело {bcid,chat_id,message_id}");

    // ===== 3. tg_delete_business_messages — deleteBusinessMessages (+0) =====
    r = tg_delete_business_messages(bot, "bc1", "[80,81]");
    chk(r == 1, "del_msgs: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteBusinessMessages|") != 0, "del_msgs: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"message_ids\":[80,81]}") != 0,
        "del_msgs: тело {bcid,message_ids} — массив как есть");
    tg_delete_business_messages(bot, "bc1", 0);
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "del_msgs(0): тело только bcid");
    chk(strstr(&tg_composed, "message_ids") == 0, "del_msgs(0): без message_ids");

    // ===== 4. tg_set_business_name — setBusinessAccountName (+extras) =====
    r = tg_set_business_name(bot, "bc1", "Ivan");
    chk(r == 1, "set_name: dry-возврат 1");
    chk(strstr(&tg_composed, "/setBusinessAccountName|") != 0, "set_name: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"first_name\":\"Ivan\"}") != 0,
        "set_name: тело {bcid,first_name} — name → first_name");
    // last_name опционален → extras (механизм wave-3)
    tg_ex_str("last_name", "Petrov");
    tg_set_business_name(bot, "bc1", "Ivan");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"first_name\":\"Ivan\",\"last_name\":\"Petrov\"}") != 0,
        "set_name: extras last_name влит в тело");
    chk(tg_extraslot[1] == 0, "set_name: extras съедены");

    // ===== 5. tg_set_business_username — setBusinessAccountUsername (+0) =====
    r = tg_set_business_username(bot, "bc1", "ivan");
    chk(r == 1, "set_user: dry-возврат 1");
    chk(strstr(&tg_composed, "/setBusinessAccountUsername|") != 0, "set_user: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"username\":\"ivan\"}") != 0,
        "set_user: тело {bcid,username}");
    tg_set_business_username(bot, "bc1", 0);
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "set_user(0): тело только bcid");
    chk(strstr(&tg_composed, "username") == 0, "set_user(0): username отсутствует");

    // ===== 6. tg_set_business_bio — setBusinessAccountBio (+0) =====
    r = tg_set_business_bio(bot, "bc1", "hey");
    chk(r == 1, "set_bio: dry-возврат 1");
    chk(strstr(&tg_composed, "/setBusinessAccountBio|") != 0, "set_bio: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"bio\":\"hey\"}") != 0,
        "set_bio: тело {bcid,bio}");
    tg_set_business_bio(bot, "bc1", 0);
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "set_bio(0): тело только bcid");
    chk(strstr(&tg_composed, "\"bio\"") == 0, "set_bio(0): bio отсутствует");

    // ===== 7. tg_set_business_profile_photo — multipart (+extras→mp) =====
    tg_ex_raw("is_public", "true");
    r = tg_set_business_profile_photo(bot, "bc1", "/tmp/p.jpg");
    chk(r == 1, "photo: dry-возврат 1");
    chk(strstr(&tg_composed, "/setBusinessAccountProfilePhoto|MP ") != 0,
        "photo: URL /setBusinessAccountProfilePhoto|MP");
    chk(strstr(&tg_composed, "-F 'business_connection_id=bc1'") != 0,
        "photo: mp-поле business_connection_id");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/p.jpg'") != 0,
        "photo: mp-поле photo=@path");
    chk(strstr(&tg_composed, "-F 'is_public=true'") != 0,
        "photo: extras → mp-поле is_public");
    chk(strstr(tg_mpslot[0], "-F 'business_connection_id=bc1' -F 'photo=@/tmp/p.jpg' -F 'is_public=true' ") != 0,
        "photo: состав tg_mpslot по порядку");
    chk(tg_extraslot[1] == 0, "photo: extras съедены");
    // extras не течёт в следующий JSON-вызов
    tg_get_business_star_balance(bot, "bc1");
    chk(strstr(&tg_composed, "is_public") == 0, "photo: extras не течёт дальше");
    // эскейп одинарной кавычки в пути
    tg_set_business_profile_photo(bot, "bc1", "/tmp/biz'p.jpg");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/biz'\\''p.jpg'") != 0,
        "photo: путь с ' эскейпится в mp");
    chk(strstr(tg_mpslot[0], "is_public") == 0,
        "photo: mpslot сброшен перед вторым вызовом");

    // ===== 8. tg_remove_business_profile_photo — removeBusinessAccountProfilePhoto =====
    r = tg_remove_business_profile_photo(bot, "bc1");
    chk(r == 1, "rm_photo: dry-возврат 1");
    chk(strstr(&tg_composed, "/removeBusinessAccountProfilePhoto|") != 0, "rm_photo: URL");
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "rm_photo: тело только bcid");
    tg_ex_raw("is_public", "true");
    tg_remove_business_profile_photo(bot, "bc1");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"is_public\":true}") != 0,
        "rm_photo: extras is_public=true влит в тело");
    chk(tg_extraslot[1] == 0, "rm_photo: extras съедены");

    // ===== 9. tg_set_business_gift_settings — setBusinessAccountGiftSettings (+0) =====
    r = tg_set_business_gift_settings(bot, "bc1",
        "{\"show_gift_button\":true,\"accepted_gift_types\":{\"unlimited\":false}}");
    chk(r == 1, "gift_set: dry-возврат 1");
    chk(strstr(&tg_composed, "/setBusinessAccountGiftSettings|") != 0, "gift_set: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"show_gift_button\":true,\"accepted_gift_types\":{\"unlimited\":false}}") != 0,
        "gift_set: тело {bcid,show_gift_button,accepted_gift_types}");
    tg_set_business_gift_settings(bot, "bc1", 0);
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "gift_set(0): тело только bcid");
    chk(strstr(&tg_composed, "show_gift_button") == 0, "gift_set(0): полей нет");

    // ===== 10. tg_get_business_star_balance — getBusinessAccountStarBalance =====
    r = tg_get_business_star_balance(bot, "bc1");
    chk(r == 1, "star_bal: dry-возврат 1");
    chk(strstr(&tg_composed, "/getBusinessAccountStarBalance|") != 0, "star_bal: URL");
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "star_bal: тело только bcid");

    // ===== 11. tg_transfer_business_stars — transferBusinessAccountStars =====
    r = tg_transfer_business_stars(bot, "bc1", 100);
    chk(r == 1, "star_tr: dry-возврат 1");
    chk(strstr(&tg_composed, "/transferBusinessAccountStars|") != 0, "star_tr: URL");
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"star_count\":100}") != 0,
        "star_tr: тело {bcid,star_count}");

    // ===== 12. tg_get_business_gifts — getBusinessAccountGifts (+0, filters) =====
    r = tg_get_business_gifts(bot, "bc1", 0);
    chk(r == 1, "gifts: dry-возврат 1");
    chk(strstr(&tg_composed, "/getBusinessAccountGifts|") != 0, "gifts: URL");
    chk(strstr(&tg_composed, "{\"business_connection_id\":\"bc1\"}") != 0,
        "gifts(0): тело только bcid");
    chk(strstr(&tg_composed, "exclude_") == 0, "gifts(0): фильтров нет");
    filters = "{\"exclude_saved\":true,\"limit\":10,\"offset\":\"MTEST\"}";
    tg_get_business_gifts(bot, "bc1", filters);
    chk(strstr(&tg_composed,
        "{\"business_connection_id\":\"bc1\",\"exclude_saved\":true,\"offset\":\"MTEST\",\"limit\":10}") != 0,
        "gifts: фильтры собраны через tg_param_json (порядок ключей обёртки)");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
