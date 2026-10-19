// t_v2_poll.k — B3 v2: sendMediaGroup/sendPoll/stopPoll/sendPaidMedia (dry-run, без сети)
// Критично: массивы options/media входят в тело через tg_param_json БЕЗ кавычек.
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

    // 1. tg_send_media_group(bot, chat_id, media_json)
    r = tg_send_media_group(bot, 55,
        "[{\"type\":\"photo\",\"media\":\"f1\"},{\"type\":\"photo\",\"media\":\"f2\"}]");
    chk(r == 1, "media_group: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendMediaGroup|") != 0, "media_group: URL /sendMediaGroup");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"media\":[{\"type\":\"photo\",\"media\":\"f1\"},{\"type\":\"photo\",\"media\":\"f2\"}]}") != 0,
        "media_group: тело media без кавычек");

    // 2. tg_send_poll(bot, chat_id, question, options_json)
    r = tg_send_poll(bot, 55, "чё?", "[\"а\",\"б\"]");
    chk(r == 1, "send_poll: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendPoll|") != 0, "send_poll: URL /sendPoll");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"question\":\"чё?\",\"options\":[\"а\",\"б\"]}") != 0,
        "send_poll: тело options без кавычек");

    // 3. tg_stop_poll(bot, chat_id, msg_id)
    r = tg_stop_poll(bot, 55, 42);
    chk(r == 1, "stop_poll: dry-возврат 1");
    chk(strstr(&tg_composed, "/stopPoll|") != 0, "stop_poll: URL /stopPoll");
    chk(strstr(&tg_composed, "{\"chat_id\":55,\"message_id\":42}") != 0,
        "stop_poll: тело {chat_id,message_id}");

    // 4. tg_send_paid_media(bot, chat_id, star_count, media_json)
    r = tg_send_paid_media(bot, 55, 10, "[{\"type\":\"photo\",\"media\":\"p1\"}]");
    chk(r == 1, "paid_media: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendPaidMedia|") != 0, "paid_media: URL /sendPaidMedia");
    chk(strstr(&tg_composed,
        "{\"chat_id\":55,\"star_count\":10,\"media\":[{\"type\":\"photo\",\"media\":\"p1\"}]}") != 0,
        "paid_media: тело star_count+media без кавычек");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
