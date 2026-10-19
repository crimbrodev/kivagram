// t_v3_gifts.k — W3-5: подарки 6 + сторис 4 + игры 3 (lib/tg_gifts.k).
// Контракт: URL + тело в tg_composed (dry-run), 0-кейсы:
//  - send_gift/gift_premium: text=0 →skip;
//  - send_gift: user_id=0 →skip (chat_id через extras);
//  - transfer_gift: star_count=0 →skip; upgrade_gift: star_count ВСЕГДА
//    (0 — валидное значение prepaid-апгрейда);
//  - игры: ровно один из msg_id/inline_msg_id (0-контракт); оба 0 → ни один
//    не передаётся; оба ненулевые → message_id приоритетен.
// Только dry-run, без сети.
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

    // ===== 1. getAvailableGifts: без параметров, тело {} =====
    r = tg_get_available_gifts(bot);
    chk(r == 1, "gifts: dry-возврат 1");
    chk(strstr(&tg_composed, "/getAvailableGifts|{}") != 0,
        "gifts: URL /getAvailableGifts + тело {}");

    // ===== 2. sendGift: user_id + gift_id + text =====
    r = tg_send_gift(bot, "g1", 55, "hi");
    chk(r == 1, "send_gift: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendGift|{\"user_id\":55,\"gift_id\":\"g1\",\"text\":\"hi\"}") != 0,
        "send_gift: user_id + gift_id + text");

    // 0-кейс: text=0 → "text" отсутствует
    tg_send_gift(bot, "g1", 55, 0);
    chk(strstr(&tg_composed, "/sendGift|{\"user_id\":55,\"gift_id\":\"g1\"}") != 0,
        "send_gift: text=0 → skip");

    // 0-кейс: user_id=0 → skip, chat_id через extras; слот съеден
    tg_ex_reset();
    tg_ex_str("chat_id", "@chan");
    tg_send_gift(bot, "g1", 0, 0);
    chk(strstr(&tg_composed, "/sendGift|{\"gift_id\":\"g1\",\"chat_id\":\"@chan\"}") != 0,
        "send_gift: user_id=0 → skip, chat_id из extras");
    chk(tg_extraslot[1] == 0, "send_gift: extras слот пуст после обёртки");

    // ===== 3. giftPremiumSubscription: user_id + month_count + star_count + text =====
    r = tg_gift_premium(bot, 55, 3, 1000, "w");
    chk(r == 1, "gift_premium: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/giftPremiumSubscription|{\"user_id\":55,\"month_count\":3,\"star_count\":1000,\"text\":\"w\"}") != 0,
        "gift_premium: user_id + month_count + star_count + text");
    tg_gift_premium(bot, 55, 12, 2500, 0);
    chk(strstr(&tg_composed,
        "/giftPremiumSubscription|{\"user_id\":55,\"month_count\":12,\"star_count\":2500}") != 0,
        "gift_premium: text=0 → skip");

    // ===== 4. convertGiftToStars =====
    r = tg_gift_to_stars(bot, "bc1", "g42");
    chk(r == 1, "gift_to_stars: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/convertGiftToStars|{\"business_connection_id\":\"bc1\",\"owned_gift_id\":\"g42\"}") != 0,
        "gift_to_stars: business_connection_id + owned_gift_id");

    // ===== 5. upgradeGift: star_count ВСЕГДА (0 валиден), keep_original_details — extras =====
    r = tg_upgrade_gift(bot, "bc1", "g42", 250);
    chk(r == 1, "upgrade_gift: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/upgradeGift|{\"business_connection_id\":\"bc1\",\"owned_gift_id\":\"g42\",\"star_count\":250}") != 0,
        "upgrade_gift: conn + gift + star_count");
    tg_ex_reset();
    tg_ex_raw("keep_original_details", "true");
    tg_upgrade_gift(bot, "bc1", "g42", 0);
    chk(strstr(&tg_composed,
        "/upgradeGift|{\"business_connection_id\":\"bc1\",\"owned_gift_id\":\"g42\",\"star_count\":0,\"keep_original_details\":true}") != 0,
        "upgrade_gift: star_count=0 передаётся + extras raw true");

    // ===== 6. transferGift: star_count=0 → skip =====
    r = tg_transfer_gift(bot, "bc1", "g42", 777, 100);
    chk(r == 1, "transfer_gift: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/transferGift|{\"business_connection_id\":\"bc1\",\"owned_gift_id\":\"g42\",\"new_owner_chat_id\":777,\"star_count\":100}") != 0,
        "transfer_gift: conn + gift + new_owner_chat_id + star_count");
    tg_transfer_gift(bot, "bc1", "g42", 777, 0);
    chk(strstr(&tg_composed,
        "/transferGift|{\"business_connection_id\":\"bc1\",\"owned_gift_id\":\"g42\",\"new_owner_chat_id\":777}") != 0,
        "transfer_gift: star_count=0 → skip");

    // ===== 7. postStory: content — сырой JSON =====
    r = tg_post_story(bot, "bc1", "{\"type\":\"photo\",\"photo\":\"f1\"}", 86400);
    chk(r == 1, "post_story: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/postStory|{\"business_connection_id\":\"bc1\",\"content\":{\"type\":\"photo\",\"photo\":\"f1\"},\"active_period\":86400}") != 0,
        "post_story: conn + content(json) + active_period");

    // ===== 8. repostStory =====
    r = tg_repost_story(bot, "bc1", 42, 900, 86400);
    chk(r == 1, "repost_story: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/repostStory|{\"business_connection_id\":\"bc1\",\"from_chat_id\":42,\"from_story_id\":900,\"active_period\":86400}") != 0,
        "repost_story: conn + from_chat_id + from_story_id + active_period");

    // ===== 9. editStory: content — сырой JSON (без active_period в API) =====
    r = tg_edit_story(bot, "bc1", 900, "{\"type\":\"video\",\"video\":\"f2\"}");
    chk(r == 1, "edit_story: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/editStory|{\"business_connection_id\":\"bc1\",\"story_id\":900,\"content\":{\"type\":\"video\",\"video\":\"f2\"}}") != 0,
        "edit_story: conn + story_id + content(json)");

    // ===== 10. deleteStory =====
    r = tg_delete_story(bot, "bc1", 900);
    chk(r == 1, "delete_story: dry-возврат 1");
    chk(strstr(&tg_composed,
        "/deleteStory|{\"business_connection_id\":\"bc1\",\"story_id\":900}") != 0,
        "delete_story: conn + story_id");

    // ===== 11. sendGame =====
    r = tg_send_game(bot, 55, "gm");
    chk(r == 1, "send_game: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendGame|{\"chat_id\":55,\"game_short_name\":\"gm\"}") != 0,
        "send_game: chat_id + game_short_name");

    // ===== 12. setGameScore: 0-контракт msg_id/inline_msg_id =====
    r = tg_set_game_score(bot, 55, 100, 12, 0);
    chk(r == 1, "set_score: dry-возврат 1");
    chk(strstr(&tg_composed, "/setGameScore|{\"user_id\":55,\"score\":100,\"message_id\":12}") != 0,
        "set_score: msg_id → message_id");
    chk(strstr(&tg_composed, "inline_message_id") == 0, "set_score: msg_id → без inline");

    // chat_id обязателен API при message_id — через extras
    tg_ex_reset();
    tg_ex_num("chat_id", 42);
    tg_set_game_score(bot, 55, 100, 12, 0);
    chk(strstr(&tg_composed, "/setGameScore|{\"user_id\":55,\"score\":100,\"message_id\":12,\"chat_id\":42}") != 0,
        "set_score: chat_id из extras");

    tg_set_game_score(bot, 55, 100, 0, "AAQ");
    chk(strstr(&tg_composed, "/setGameScore|{\"user_id\":55,\"score\":100,\"inline_message_id\":\"AAQ\"}") != 0,
        "set_score: inline_msg_id → inline_message_id");
    chk(strstr(&tg_composed, "\"message_id\"") == 0, "set_score: inline → без message_id");

    // оба 0 → ни один не передаётся (контракт на вызывающем)
    tg_set_game_score(bot, 55, 100, 0, 0);
    chk(strstr(&tg_composed, "/setGameScore|{\"user_id\":55,\"score\":100}") != 0,
        "set_score: оба 0 → ничего не передано");

    // оба ненулевые → message_id приоритетен
    tg_set_game_score(bot, 55, 100, 12, "AAQ");
    chk(strstr(&tg_composed, "\"message_id\":12") != 0, "set_score: оба → message_id");
    chk(strstr(&tg_composed, "inline_message_id") == 0, "set_score: оба → без inline");

    // ===== 13. getGameHighScores: тот же 0-контракт =====
    r = tg_get_game_highscores(bot, 55, 12, 0);
    chk(r == 1, "highscores: dry-возврат 1");
    chk(strstr(&tg_composed, "/getGameHighScores|{\"user_id\":55,\"message_id\":12}") != 0,
        "highscores: msg_id → message_id");

    tg_get_game_highscores(bot, 55, 0, "AAQ");
    chk(strstr(&tg_composed, "/getGameHighScores|{\"user_id\":55,\"inline_message_id\":\"AAQ\"}") != 0,
        "highscores: inline_msg_id → inline_message_id");

    tg_get_game_highscores(bot, 55, 0, 0);
    chk(strstr(&tg_composed, "/getGameHighScores|{\"user_id\":55}") != 0,
        "highscores: оба 0 → только user_id");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
