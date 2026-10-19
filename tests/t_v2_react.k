// t_v2_react.k — B11: реакции, геттеры профиля, getWebhookInfo/logOut/close
// (dry-run, без сети): композиция URL+тела в tg_composed.
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

    // 1. tg_set_reaction(bot, chat_id, msg_id, reaction_json) — setMessageReaction
    r = tg_set_reaction(bot, 55, 42, "[{\"type\":\"emoji\",\"emoji\":\"👍\"}]");
    chk(r == 1, "set_reaction: dry-возврат 1");
    chk(strstr(&tg_composed, "/setMessageReaction|") != 0, "set_reaction: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42,\"reaction\":[{\"type\":\"emoji\",\"emoji\":\"👍\"}]}") != 0,
        "set_reaction: тело {chat_id,message_id,reaction-массив без кавычек}");

    // 2. tg_del_reaction(bot, chat_id, msg_id) — deleteMessageReaction (user_id=0 → skip)
    r = tg_del_reaction(bot, 55, 42);
    chk(r == 1, "del_reaction: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteMessageReaction|") != 0, "del_reaction: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "del_reaction: тело {chat_id,message_id}");
    chk(strstr(&tg_composed, "user_id") == 0, "del_reaction: user_id отсутствует");

    // 3. tg_del_all_reactions(bot, chat_id) — deleteAllMessageReactions
    r = tg_del_all_reactions(bot, 55);
    chk(r == 1, "del_all_reactions: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteAllMessageReactions|") != 0, "del_all_reactions: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55}") != 0, "del_all_reactions: тело {chat_id}");

    // 4. tg_profile_photos(bot, user_id, limit) — getUserProfilePhotos
    r = tg_profile_photos(bot, 9, 10);
    chk(r == 1, "profile_photos: dry-возврат 1");
    chk(strstr(&tg_composed, "/getUserProfilePhotos|") != 0, "profile_photos: URL");
    chk(strstr(&tg_composed, "{\"user_id\":9,\"limit\":10}") != 0,
        "profile_photos: тело {user_id,limit}");

    // 4b. limit=0 → limit не передаётся
    tg_profile_photos(bot, 9, 0);
    chk(strstr(&tg_composed, "/getUserProfilePhotos|") != 0, "profile_photos nolimit: URL");
    chk(strstr(&tg_composed, "{\"user_id\":9}") != 0, "profile_photos nolimit: тело {user_id}");
    chk(strstr(&tg_composed, "limit") == 0, "profile_photos nolimit: limit отсутствует");

    // 5. tg_profile_audios(bot, user_id, limit) — getUserProfileAudios
    r = tg_profile_audios(bot, 9, 5);
    chk(r == 1, "profile_audios: dry-возврат 1");
    chk(strstr(&tg_composed, "/getUserProfileAudios|") != 0, "profile_audios: URL");
    chk(strstr(&tg_composed, "{\"user_id\":9,\"limit\":5}") != 0,
        "profile_audios: тело {user_id,limit}");

    // 5b. limit=0 → limit не передаётся
    tg_profile_audios(bot, 9, 0);
    chk(strstr(&tg_composed, "{\"user_id\":9}") != 0, "profile_audios nolimit: тело {user_id}");

    // 6. tg_get_webhook_info(bot) — getWebhookInfo, параметров нет: тело {}
    r = tg_get_webhook_info(bot);
    chk(r == 1, "get_webhook_info: dry-возврат 1");
    chk(strstr(&tg_composed, "/getWebhookInfo|") != 0, "get_webhook_info: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "get_webhook_info: пустое тело {}");

    // 7. tg_logout(bot) — logOut, параметров нет
    r = tg_logout(bot);
    chk(r == 1, "logout: dry-возврат 1");
    chk(strstr(&tg_composed, "/logOut|") != 0, "logout: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "logout: пустое тело {}");

    // 8. tg_close(bot) — close, параметров нет
    r = tg_close(bot);
    chk(r == 1, "close: dry-возврат 1");
    chk(strstr(&tg_composed, "/close|") != 0, "close: URL");
    chk(strstr(&tg_composed, "|{}") != 0, "close: пустое тело {}");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
