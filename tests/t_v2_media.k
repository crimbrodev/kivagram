// t_v2_media.k — медиа-обёртки v1 (B1): dry-композиция URL+тела, без сети.
// Обёртки: tg_send_audio / tg_send_document / tg_send_video /
// tg_send_animation / tg_send_voice / tg_send_video_note.
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

    // 1. tg_send_audio(bot, chat_id, audio, caption)
    r = tg_send_audio(bot, 55, "file-1", "привет");
    chk(r == 1, "audio: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendAudio|") != 0, "audio: URL /sendAudio");
    s = "{\"chat_id\":55,\"audio\":\"file-1\",\"caption\":\"привет\"}";
    chk(strstr(&tg_composed, s) != 0, "audio: тело {chat_id,audio,caption}");

    // 2. tg_send_document(bot, chat_id, doc, caption)
    r = tg_send_document(bot, 55, "file-d", "текст");
    chk(r == 1, "document: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendDocument|") != 0, "document: URL /sendDocument");
    s = "{\"chat_id\":55,\"document\":\"file-d\",\"caption\":\"текст\"}";
    chk(strstr(&tg_composed, s) != 0, "document: тело {chat_id,document,caption}");

    // 3. tg_send_video(bot, chat_id, video, caption)
    r = tg_send_video(bot, 55, "file-v", "видео");
    chk(r == 1, "video: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendVideo|") != 0, "video: URL /sendVideo");
    s = "{\"chat_id\":55,\"video\":\"file-v\",\"caption\":\"видео\"}";
    chk(strstr(&tg_composed, s) != 0, "video: тело {chat_id,video,caption}");

    // 4. tg_send_animation(bot, chat_id, anim, caption)
    r = tg_send_animation(bot, 55, "file-a", "гиф");
    chk(r == 1, "animation: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendAnimation|") != 0, "animation: URL /sendAnimation");
    s = "{\"chat_id\":55,\"animation\":\"file-a\",\"caption\":\"гиф\"}";
    chk(strstr(&tg_composed, s) != 0, "animation: тело {chat_id,animation,caption}");

    // 5. tg_send_voice(bot, chat_id, voice, caption)
    r = tg_send_voice(bot, 55, "file-vo", "голос");
    chk(r == 1, "voice: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendVoice|") != 0, "voice: URL /sendVoice");
    s = "{\"chat_id\":55,\"voice\":\"file-vo\",\"caption\":\"голос\"}";
    chk(strstr(&tg_composed, s) != 0, "voice: тело {chat_id,voice,caption}");

    // 6. tg_send_video_note(bot, chat_id, vnote, duration)
    r = tg_send_video_note(bot, 55, "file-vn", 10);
    chk(r == 1, "vnote: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendVideoNote|") != 0, "vnote: URL /sendVideoNote");
    s = "{\"chat_id\":55,\"video_note\":\"file-vn\",\"duration\":10}";
    chk(strstr(&tg_composed, s) != 0, "vnote: тело {chat_id,video_note,duration}");

    // 7. caption=0 → в теле caption отсутствует (контракт 0 = не передавать)
    tg_send_audio(bot, 55, "file-1", 0);
    chk(strstr(&tg_composed, "caption") == 0, "audio: caption=0 → поля нет");
    s = "{\"chat_id\":55,\"audio\":\"file-1\"}";
    chk(strstr(&tg_composed, s) != 0, "audio: caption=0 → тело без caption");

    tg_send_document(bot, 55, "file-d", 0);
    chk(strstr(&tg_composed, "caption") == 0, "document: caption=0 → поля нет");

    // 8. duration=0 у video_note → поля нет
    tg_send_video_note(bot, 55, "file-vn", 0);
    chk(strstr(&tg_composed, "duration") == 0, "vnote: duration=0 → поля нет");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
