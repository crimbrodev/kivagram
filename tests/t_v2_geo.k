// t_v2_geo.k — гео/стикер/контакт/дайс/лайв-фото: композиция URL+тела в
// dry-режиме (без сети). КРИТИЧНО: latitude/longitude — числа БЕЗ кавычек
// (через tg_param_raw).
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
    auto bot;
    auto r;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // 1. tg_send_location(bot, chat_id, lat, lng) — lat/lng raw-строки
    r = tg_send_location(bot, 55, "55.75", "37.62");
    chk(r == 1, "location: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendLocation|") != 0, "location: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"latitude\":55.75,\"longitude\":37.62}") != 0,
        "location: тело {chat_id,latitude,longitude}");
    chk(strstr(&tg_composed, "\"latitude\":\"") == 0,
        "location: latitude без кавычек");

    // 2. tg_send_venue(bot, chat_id, lat, lng, title, address) — 6 аргументов
    r = tg_send_venue(bot, 55, "55.75", "37.62", "Точка", "Москва");
    chk(r == 1, "venue: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendVenue|") != 0, "venue: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"latitude\":55.75,\"longitude\":37.62,\"title\":\"Точка\",\"address\":\"Москва\"}") != 0,
        "venue: тело {chat_id,lat,lng,title,address}");
    chk(strstr(&tg_composed, "\"longitude\":\"") == 0,
        "venue: longitude без кавычек");

    // 3. tg_send_contact(bot, chat_id, phone, first_name, last_name)
    r = tg_send_contact(bot, 55, "+7000", "A", 0);
    chk(r == 1, "contact: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendContact|") != 0, "contact: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"phone_number\":\"+7000\",\"first_name\":\"A\"}") != 0,
        "contact: тело без last_name");
    chk(strstr(&tg_composed, "last_name") == 0,
        "contact: last_name=0 не передаётся");
    tg_send_contact(bot, 55, "+7000", "A", "B");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"phone_number\":\"+7000\",\"first_name\":\"A\",\"last_name\":\"B\"}") != 0,
        "contact: тело с last_name");

    // 4. tg_send_dice(bot, chat_id, emoji) — emoji=0 → skip (дефолт TG)
    r = tg_send_dice(bot, 55, 0);
    chk(r == 1, "dice: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendDice|") != 0, "dice: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0,
        "dice: тело только chat_id");
    tg_send_dice(bot, 55, "🏀");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"emoji\":\"🏀\"}") != 0,
        "dice: тело с emoji");

    // 5. tg_send_sticker(bot, chat_id, sticker)
    r = tg_send_sticker(bot, 55, "st-1");
    chk(r == 1, "sticker: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendSticker|") != 0, "sticker: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"sticker\":\"st-1\"}") != 0,
        "sticker: тело {chat_id,sticker}");

    // 6. tg_send_live_photo(bot, chat_id, live_photo, photo) — live_photo=0 → skip
    r = tg_send_live_photo(bot, 55, 0, "ph-1");
    chk(r == 1, "live_photo: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendLivePhoto|") != 0, "live_photo: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"photo\":\"ph-1\"}") != 0,
        "live_photo: тело без live_photo");
    tg_send_live_photo(bot, 55, "lv-1", "ph-1");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"live_photo\":\"lv-1\",\"photo\":\"ph-1\"}") != 0,
        "live_photo: тело с live_photo");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
