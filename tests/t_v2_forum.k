// t_v2_forum.k — форум-топики v1 (B10): dry-композиция URL+тела, без сети.
// Обёртки: tg_topic_create / tg_topic_edit / tg_topic_close / tg_topic_reopen /
// tg_topic_delete / tg_topic_unpin_all / tg_general_edit / tg_general_close /
// tg_general_reopen / tg_general_hide / tg_general_unhide / tg_general_unpin_all /
// tg_topic_icons.
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
    auto s;

    fails[0] = 0;

    bot = tg_bot("123:fake");
    tg_dry_run = 1;

    // 1. tg_topic_create(bot, chat_id, name) — createForumTopic
    r = tg_topic_create(bot, 55, "топ");
    chk(r == 1, "topic_create: dry-возврат 1");
    chk(strstr(&tg_composed, "/createForumTopic|") != 0, "topic_create: URL");
    s = "{\"chat_id\":55,\"name\":\"топ\"}";
    chk(strstr(&tg_composed, s) != 0, "topic_create: тело {chat_id,name}");

    // 2. tg_topic_edit(bot, chat_id, thread_id, name) — editForumTopic
    r = tg_topic_edit(bot, 55, 7, "новый");
    chk(r == 1, "topic_edit: dry-возврат 1");
    chk(strstr(&tg_composed, "/editForumTopic|") != 0, "topic_edit: URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7,\"name\":\"новый\"}";
    chk(strstr(&tg_composed, s) != 0, "topic_edit: тело {chat_id,thread,name}");

    // 2b. name=0 → name не передаётся
    tg_topic_edit(bot, 55, 7, 0);
    chk(strstr(&tg_composed, "/editForumTopic|") != 0, "topic_edit(name=0): URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7}";
    chk(strstr(&tg_composed, s) != 0, "topic_edit(name=0): тело без name");

    // 3. tg_topic_close(bot, chat_id, thread_id) — closeForumTopic
    r = tg_topic_close(bot, 55, 7);
    chk(r == 1, "topic_close: dry-возврат 1");
    chk(strstr(&tg_composed, "/closeForumTopic|") != 0, "topic_close: URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7}";
    chk(strstr(&tg_composed, s) != 0, "topic_close: тело {chat_id,thread}");

    // 4. tg_topic_reopen(bot, chat_id, thread_id) — reopenForumTopic
    r = tg_topic_reopen(bot, 55, 7);
    chk(r == 1, "topic_reopen: dry-возврат 1");
    chk(strstr(&tg_composed, "/reopenForumTopic|") != 0, "topic_reopen: URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7}";
    chk(strstr(&tg_composed, s) != 0, "topic_reopen: тело {chat_id,thread}");

    // 5. tg_topic_delete(bot, chat_id, thread_id) — deleteForumTopic
    r = tg_topic_delete(bot, 55, 7);
    chk(r == 1, "topic_delete: dry-возврат 1");
    chk(strstr(&tg_composed, "/deleteForumTopic|") != 0, "topic_delete: URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7}";
    chk(strstr(&tg_composed, s) != 0, "topic_delete: тело {chat_id,thread}");

    // 6. tg_topic_unpin_all(bot, chat_id, thread_id) — unpinAllForumTopicMessages
    r = tg_topic_unpin_all(bot, 55, 7);
    chk(r == 1, "topic_unpin_all: dry-возврат 1");
    chk(strstr(&tg_composed, "/unpinAllForumTopicMessages|") != 0, "topic_unpin_all: URL");
    s = "{\"chat_id\":55,\"message_thread_id\":7}";
    chk(strstr(&tg_composed, s) != 0, "topic_unpin_all: тело {chat_id,thread}");

    // 7. tg_general_edit(bot, chat_id, name) — editGeneralForumTopic
    r = tg_general_edit(bot, 55, "Главная");
    chk(r == 1, "general_edit: dry-возврат 1");
    chk(strstr(&tg_composed, "/editGeneralForumTopic|") != 0, "general_edit: URL");
    s = "{\"chat_id\":55,\"name\":\"Главная\"}";
    chk(strstr(&tg_composed, s) != 0, "general_edit: тело {chat_id,name}");

    // 8. tg_general_close(bot, chat_id) — closeGeneralForumTopic
    r = tg_general_close(bot, 55);
    chk(r == 1, "general_close: dry-возврат 1");
    chk(strstr(&tg_composed, "/closeGeneralForumTopic|") != 0, "general_close: URL");
    s = "{\"chat_id\":55}";
    chk(strstr(&tg_composed, s) != 0, "general_close: тело {chat_id}");

    // 9. tg_general_reopen(bot, chat_id) — reopenGeneralForumTopic
    r = tg_general_reopen(bot, 55);
    chk(r == 1, "general_reopen: dry-возврат 1");
    chk(strstr(&tg_composed, "/reopenGeneralForumTopic|") != 0, "general_reopen: URL");
    s = "{\"chat_id\":55}";
    chk(strstr(&tg_composed, s) != 0, "general_reopen: тело {chat_id}");

    // 10. tg_general_hide(bot, chat_id) — hideGeneralForumTopic
    r = tg_general_hide(bot, 55);
    chk(r == 1, "general_hide: dry-возврат 1");
    chk(strstr(&tg_composed, "/hideGeneralForumTopic|") != 0, "general_hide: URL");
    s = "{\"chat_id\":55}";
    chk(strstr(&tg_composed, s) != 0, "general_hide: тело {chat_id}");

    // 11. tg_general_unhide(bot, chat_id) — unhideGeneralForumTopic
    r = tg_general_unhide(bot, 55);
    chk(r == 1, "general_unhide: dry-возврат 1");
    chk(strstr(&tg_composed, "/unhideGeneralForumTopic|") != 0, "general_unhide: URL");
    s = "{\"chat_id\":55}";
    chk(strstr(&tg_composed, s) != 0, "general_unhide: тело {chat_id}");

    // 12. tg_general_unpin_all(bot, chat_id) — unpinAllGeneralForumTopicMessages
    r = tg_general_unpin_all(bot, 55);
    chk(r == 1, "general_unpin_all: dry-возврат 1");
    chk(strstr(&tg_composed, "/unpinAllGeneralForumTopicMessages|") != 0, "general_unpin_all: URL");
    s = "{\"chat_id\":55}";
    chk(strstr(&tg_composed, s) != 0, "general_unpin_all: тело {chat_id}");

    // 13. tg_topic_icons(bot) — getForumTopicIconStickers (без параметров)
    r = tg_topic_icons(bot);
    chk(r == 1, "topic_icons: dry-возврат 1");
    chk(strstr(&tg_composed, "/getForumTopicIconStickers|") != 0, "topic_icons: URL");
    chk(strstr(&tg_composed, "chat_id") == 0, "topic_icons: тело без параметров");

    tg_dry_run = 0;
    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
