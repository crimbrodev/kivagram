// t_v2_stickers.k — стикер-наборы Bot API (15 обёрток): композиция URL+тела
// в dry-режиме (без сети). Параметры — эталон /tmp/opencode/ref/api/methods/*.md.
// Спецкейсы: thumb=0 → литерал null БЕЗ кавычек; keywords/mask_position=0 →
// поле отсутствует; emoji_list: простая строка с кириллицей/эмодзи → массив
// с экранированием, JSON-массив → как есть.
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

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;
    tg_ex_reset();

    // 1. tg_create_sticker_set(bot, user_id, name, title, stickers_json)
    r = tg_create_sticker_set(bot, 7, "animals_by_fakebot", "Животные",
        "[{\"sticker\":\"f1\",\"format\":\"static\",\"emoji_list\":[\"🐶\"]}]");
    chk(r == 1, "create: dry-возврат 1");
    chk(strstr(&tg_composed, "/createNewStickerSet|") != 0, "create: URL");
    chk(strstr(&tg_composed, "{\"user_id\":7,\"name\":\"animals_by_fakebot\",\"title\":\"Животные\",\"stickers\":[{\"sticker\":\"f1\",\"format\":\"static\",\"emoji_list\":[\"🐶\"]}]}") != 0,
        "create: тело {user_id,name,title,stickers}");

    // create: 0-контракт sticker_format/sticker_type — extras-строки
    tg_ex_str("sticker_format", "animated");
    tg_ex_str("sticker_type", "custom_emoji");
    tg_create_sticker_set(bot, 7, "emoji_by_fakebot", "Эмодзи", "[]");
    chk(strstr(&tg_composed, "\"sticker_format\":\"animated\"") != 0,
        "create: sticker_format из extras");
    chk(strstr(&tg_composed, "\"sticker_type\":\"custom_emoji\"") != 0,
        "create: sticker_type из extras");
    tg_create_sticker_set(bot, 7, "plain_by_fakebot", "Просто", "[]");
    chk(strstr(&tg_composed, "sticker_format") == 0,
        "create: без extras поля нет");
    chk(strstr(&tg_composed, "sticker_type") == 0,
        "create: без extras sticker_type нет");

    // 2. tg_add_sticker(bot, user_id, name, sticker) — sticker = объект InputSticker
    r = tg_add_sticker(bot, 7, "animals_by_fakebot",
        "{\"sticker\":\"f1\",\"format\":\"static\",\"emoji_list\":[\"x\"]}");
    chk(r == 1, "add: dry-возврат 1");
    chk(strstr(&tg_composed, "/addStickerToSet|") != 0, "add: URL");
    chk(strstr(&tg_composed, "{\"user_id\":7,\"name\":\"animals_by_fakebot\",\"sticker\":{\"sticker\":\"f1\",\"format\":\"static\",\"emoji_list\":[\"x\"]}}") != 0,
        "add: тело {user_id,name,sticker-объект}");

    // 3. tg_get_sticker_set(bot, name)
    r = tg_get_sticker_set(bot, "animals_by_fakebot");
    chk(r == 1, "get_set: dry-возврат 1");
    chk(strstr(&tg_composed, "/getStickerSet|") != 0, "get_set: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\"}") != 0,
        "get_set: тело {name}");

    // 4. tg_set_sticker_emojis(bot, name, sticker, emojis)
    //    name по эталону в методе ОТСУТСТВУЕТ — в тело не входит
    r = tg_set_sticker_emojis(bot, "animals_by_fakebot", "f1", "привет,😀");
    chk(r == 1, "emojis: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerEmojiList|") != 0, "emojis: URL");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"emoji_list\":[\"привет\",\"😀\"]}") != 0,
        "emojis: строка с кириллицей/эмодзи → массив");
    chk(strstr(&tg_composed, "\"name\"") == 0, "emojis: name не в теле");

    // emojis: готовый JSON-массив уходит как есть
    tg_set_sticker_emojis(bot, "animals_by_fakebot", "f1", "[\"кот\",\"🐱\"]");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"emoji_list\":[\"кот\",\"🐱\"]}") != 0,
        "emojis: JSON-массив как есть");

    // emojis: экранирование кавычки в элементе
    tg_set_sticker_emojis(bot, "animals_by_fakebot", "f1", "a\"b");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"emoji_list\":[\"a\\\"b\"]}") != 0,
        "emojis: кавычка в элементе экранирована");

    // 5. tg_set_sticker_keywords(bot, name, sticker, keywords_json); 0 → skip
    r = tg_set_sticker_keywords(bot, "animals_by_fakebot", "f1", "[\"cat\",\"кот\"]");
    chk(r == 1, "keywords: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerKeywords|") != 0, "keywords: URL");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"keywords\":[\"cat\",\"кот\"]}") != 0,
        "keywords: тело {sticker,keywords}");
    tg_set_sticker_keywords(bot, "animals_by_fakebot", "f1", 0);
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\"}") != 0,
        "keywords=0: тело только {sticker}");
    chk(strstr(&tg_composed, "keywords") == 0,
        "keywords=0: поле отсутствует");

    // 6. tg_set_sticker_mask_pos(bot, name, sticker, mask_pos_json); 0 → снять
    r = tg_set_sticker_mask_pos(bot, "animals_by_fakebot", "f1",
        "{\"point\":\"eyes\",\"x_shift\":1.5,\"scale\":2}");
    chk(r == 1, "mask_pos: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerMaskPosition|") != 0, "mask_pos: URL");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"mask_position\":{\"point\":\"eyes\",\"x_shift\":1.5,\"scale\":2}}") != 0,
        "mask_pos: тело {sticker,mask_position}");
    tg_set_sticker_mask_pos(bot, "animals_by_fakebot", "f1", 0);
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\"}") != 0,
        "mask_pos=0: тело только {sticker} — позиция снята");
    chk(strstr(&tg_composed, "mask_position") == 0,
        "mask_pos=0: поле отсутствует");

    // 7. tg_set_sticker_pos(bot, name, sticker, position)
    r = tg_set_sticker_pos(bot, "animals_by_fakebot", "f1", 3);
    chk(r == 1, "pos: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerPositionInSet|") != 0, "pos: URL");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\",\"position\":3}") != 0,
        "pos: тело {sticker,position}");

    // 8. tg_del_sticker(bot, name, sticker)
    r = tg_del_sticker(bot, "animals_by_fakebot", "f1");
    chk(r == 1, "del_sticker: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteStickerFromSet|") != 0, "del_sticker: URL");
    chk(strstr(&tg_composed, "{\"sticker\":\"f1\"}") != 0,
        "del_sticker: тело {sticker}");

    // 9. tg_set_sticker_title(bot, name, title)
    r = tg_set_sticker_title(bot, "animals_by_fakebot", "Звери");
    chk(r == 1, "title: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerSetTitle|") != 0, "title: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\",\"title\":\"Звери\"}") != 0,
        "title: тело {name,title}");

    // 10. tg_set_sticker_thumb(bot, name, user_id, thumb) — file_id в thumbnail
    r = tg_set_sticker_thumb(bot, "animals_by_fakebot", 7, "AgACAgAD");
    chk(r == 1, "thumb: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerSetThumbnail|") != 0, "thumb: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\",\"user_id\":7,\"thumbnail\":\"AgACAgAD\"}") != 0,
        "thumb: тело {name,user_id,thumbnail}");

    // thumb: format (обязателен API) — extras
    tg_ex_str("format", "static");
    tg_set_sticker_thumb(bot, "animals_by_fakebot", 7, "AgACAgAD");
    chk(strstr(&tg_composed, "\"format\":\"static\"") != 0, "thumb: format из extras");

    // thumb=0 → "thumbnail":null (без кавычек у значения)
    r = tg_set_sticker_thumb(bot, "animals_by_fakebot", 7, 0);
    chk(r == 1, "thumb=0: dry-возврат 1");
    chk(strstr(&tg_composed, "/setStickerSetThumbnail|") != 0, "thumb=0: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\",\"user_id\":7,\"thumbnail\":null}") != 0,
        "thumb=0: thumbnail:null без кавычек");
    chk(strstr(&tg_composed, "\"thumbnail\":\"null\"") == 0,
        "thumb=0: null НЕ в кавычках");

    // 11. tg_del_sticker_set(bot, name)
    r = tg_del_sticker_set(bot, "animals_by_fakebot");
    chk(r == 1, "del_set: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteStickerSet|") != 0, "del_set: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\"}") != 0,
        "del_set: тело {name}");

    // 12. tg_del_chat_sticker_set(bot, chat_id)
    r = tg_del_chat_sticker_set(bot, -100123);
    chk(r == 1, "del_chat_set: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteChatStickerSet|") != 0, "del_chat_set: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":-100123}") != 0,
        "del_chat_set: тело {chat_id}");

    // 13. tg_replace_sticker(bot, name, old_sticker, new_sticker_json)
    //     user_id (обязателен API) — extras
    tg_ex_num("user_id", 7);
    r = tg_replace_sticker(bot, "animals_by_fakebot", "old1",
        "{\"sticker\":\"f2\",\"format\":\"animated\",\"emoji_list\":[\"😀\"]}");
    chk(r == 1, "replace: dry-возврат 1");
    chk(strstr(&tg_composed, "/replaceStickerInSet|") != 0, "replace: URL");
    chk(strstr(&tg_composed, "{\"name\":\"animals_by_fakebot\",\"old_sticker\":\"old1\",\"sticker\":{\"sticker\":\"f2\",\"format\":\"animated\",\"emoji_list\":[\"😀\"]},\"user_id\":7}") != 0,
        "replace: тело {name,old_sticker,sticker,user_id}");

    // 14. tg_get_custom_emojis(bot, custom_emoji_ids_json)
    r = tg_get_custom_emojis(bot, "[\"5368324170671202286\",\"5368324170671202287\"]");
    chk(r == 1, "custom_emojis: dry-возврат 1");
    chk(strstr(&tg_composed, "/getCustomEmojiStickers|") != 0, "custom_emojis: URL");
    chk(strstr(&tg_composed, "{\"custom_emoji_ids\":[\"5368324170671202286\",\"5368324170671202287\"]}") != 0,
        "custom_emojis: тело {custom_emoji_ids}");

    // 15. tg_set_custom_emoji_thumb(bot, name, thumb)
    r = tg_set_custom_emoji_thumb(bot, "custom_by_fakebot", "5368324170671202286");
    chk(r == 1, "custom_thumb: dry-возврат 1");
    chk(strstr(&tg_composed, "/setCustomEmojiStickerSetThumbnail|") != 0,
        "custom_thumb: URL");
    chk(strstr(&tg_composed, "{\"name\":\"custom_by_fakebot\",\"custom_emoji_id\":\"5368324170671202286\"}") != 0,
        "custom_thumb: тело {name,custom_emoji_id}");

    // custom_thumb=0 → снять: литерал null без кавычек
    r = tg_set_custom_emoji_thumb(bot, "custom_by_fakebot", 0);
    chk(r == 1, "custom_thumb=0: dry-возврат 1");
    chk(strstr(&tg_composed, "/setCustomEmojiStickerSetThumbnail|") != 0,
        "custom_thumb=0: URL");
    chk(strstr(&tg_composed, "{\"name\":\"custom_by_fakebot\",\"custom_emoji_id\":null}") != 0,
        "custom_thumb=0: custom_emoji_id:null без кавычек");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
