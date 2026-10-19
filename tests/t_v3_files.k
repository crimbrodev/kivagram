// t_v3_files.k — W3-1: файловые методы (multipart) lib/tg_files.k.
// Только dry-run: проверка URL + MP-строки -F для каждой обёртки, mp-поле
// caption, attach://fileN в media-group (и лимит 10 путей), extras-мост
// в mp (tg_mp_extras), композиция URL скачивания (ядро tg_download_file).
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

    // ===== 1. sendDocument: chat_id + document=@path + caption mp-полем =====
    r = tg_send_document_file(bot, 55, "/tmp/x.txt", "cap");
    chk(r == 1, "doc: dry-возврат 1");
    chk(strstr(&tg_composed, "/sendDocument|MP ") != 0, "doc: URL /sendDocument");
    chk(strstr(&tg_composed, "-F 'chat_id=55' ") != 0, "doc: -F chat_id");
    chk(strstr(&tg_composed, "-F 'document=@/tmp/x.txt' ") != 0, "doc: -F document=@path");
    chk(strstr(&tg_composed, "-F 'caption=cap' ") != 0, "doc: caption уходит mp-полем");

    // 2. caption=0 → skip (0-контракт)
    tg_send_document_file(bot, 55, "/tmp/x.txt", 0);
    chk(strstr(&tg_composed, "caption") == 0, "doc: caption=0 → skip");

    // 3. эскейп ' в caption (как в ядре: ' → '\'')
    tg_send_document_file(bot, 55, "/tmp/x.txt", "it's");
    chk(strstr(&tg_composed, "-F 'caption=it'\\''s' ") != 0, "doc: ' → '\\'' в mp");

    // ===== 4. photo / audio / video / voice / animation =====
    tg_send_photo_file(bot, 55, "/tmp/p.jpg", "ph");
    chk(strstr(&tg_composed, "/sendPhoto|MP ") != 0, "photo: URL");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/p.jpg' ") != 0, "photo: photo=@path");
    chk(strstr(&tg_composed, "-F 'caption=ph' ") != 0, "photo: caption mp-полем");

    tg_send_audio_file(bot, 55, "/tmp/a.mp3", 0);
    chk(strstr(&tg_composed, "/sendAudio|MP ") != 0, "audio: URL");
    chk(strstr(&tg_composed, "-F 'audio=@/tmp/a.mp3' ") != 0, "audio: audio=@path");

    tg_send_video_file(bot, 55, "/tmp/v.mp4", 0);
    chk(strstr(&tg_composed, "/sendVideo|MP ") != 0, "video: URL");
    chk(strstr(&tg_composed, "-F 'video=@/tmp/v.mp4' ") != 0, "video: video=@path");

    tg_send_voice_file(bot, 55, "/tmp/vg.ogg", 0);
    chk(strstr(&tg_composed, "/sendVoice|MP ") != 0, "voice: URL");
    chk(strstr(&tg_composed, "-F 'voice=@/tmp/vg.ogg' ") != 0, "voice: voice=@path");

    tg_send_animation_file(bot, 55, "/tmp/anim.gif", "gif");
    chk(strstr(&tg_composed, "/sendAnimation|MP ") != 0, "animation: URL");
    chk(strstr(&tg_composed, "-F 'animation=@/tmp/anim.gif' ") != 0, "animation: animation=@path");
    chk(strstr(&tg_composed, "-F 'caption=gif' ") != 0, "animation: caption mp-полем");

    // ===== 5. video_note / sticker — без caption-аргумента (по эталону) =====
    tg_send_video_note_file(bot, 55, "/tmp/vn.mp4");
    chk(strstr(&tg_composed, "/sendVideoNote|MP ") != 0, "vnote: URL");
    chk(strstr(&tg_composed, "-F 'video_note=@/tmp/vn.mp4' ") != 0, "vnote: video_note=@path");

    tg_send_sticker_file(bot, 55, "/tmp/s.webp");
    chk(strstr(&tg_composed, "/sendSticker|MP ") != 0, "sticker: URL");
    chk(strstr(&tg_composed, "-F 'sticker=@/tmp/s.webp' ") != 0, "sticker: sticker=@path");

    // ===== 6. sendMediaGroup: пути file0..fileN + media со ссылками attach:// =====
    tg_send_media_group_files(bot, 55,
        "[\"/tmp/a.jpg\",\"/tmp/b.jpg\"]",
        "[{\"type\":\"photo\",\"media\":\"attach://file0\"},{\"type\":\"photo\",\"media\":\"attach://file1\"}]");
    chk(strstr(&tg_composed, "/sendMediaGroup|MP ") != 0, "mg: URL");
    chk(strstr(&tg_composed, "-F 'chat_id=55' ") != 0, "mg: chat_id");
    chk(strstr(&tg_composed, "-F 'file0=@/tmp/a.jpg' ") != 0, "mg: file0=@путь0");
    chk(strstr(&tg_composed, "-F 'file1=@/tmp/b.jpg' ") != 0, "mg: file1=@путь1");
    chk(strstr(&tg_composed, "attach://file0") != 0, "mg: media со ссылкой attach://file0");

    // 6b. лимит 10 путей: 11-й путь не попадает в mp
    tg_send_media_group_files(bot, 55,
        "[\"/tmp/0.jpg\",\"/tmp/1.jpg\",\"/tmp/2.jpg\",\"/tmp/3.jpg\",\"/tmp/4.jpg\",\"/tmp/5.jpg\",\"/tmp/6.jpg\",\"/tmp/7.jpg\",\"/tmp/8.jpg\",\"/tmp/9.jpg\",\"/tmp/10.jpg\"]",
        "[]");
    chk(strstr(&tg_composed, "-F 'file9=@/tmp/9.jpg' ") != 0, "mg-limit: file9 есть");
    chk(strstr(&tg_composed, "file10") == 0, "mg-limit: нет file10 (лимит 10)");

    // ===== 7. sendLivePhoto: live_photo=@видео + photo=@статика =====
    tg_send_live_photo_file(bot, 55, "/tmp/lv.mp4", "/tmp/st.jpg");
    chk(strstr(&tg_composed, "/sendLivePhoto|MP ") != 0, "lp: URL");
    chk(strstr(&tg_composed, "-F 'live_photo=@/tmp/lv.mp4' ") != 0, "lp: live_photo=@vpath");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/st.jpg' ") != 0, "lp: photo=@ppath");

    // ===== 8. setChatPhoto (отрицательный chat_id через %ld) =====
    tg_set_chat_photo_file(bot, -100500, "/tmp/cp.jpg");
    chk(strstr(&tg_composed, "/setChatPhoto|MP ") != 0, "cphoto: URL");
    chk(strstr(&tg_composed, "-F 'chat_id=-100500' ") != 0, "cphoto: chat_id %ld со знаком");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/cp.jpg' ") != 0, "cphoto: photo=@path");

    // ===== 9. setMyProfilePhoto: business_connection_id через extras-мост =====
    tg_ex_reset();
    tg_ex_str("business_connection_id", "bc1");
    tg_set_profile_photo_file(bot, "/tmp/pp.jpg");
    chk(strstr(&tg_composed, "/setMyProfilePhoto|MP ") != 0, "pphoto: URL");
    chk(strstr(&tg_composed, "-F 'photo=@/tmp/pp.jpg' ") != 0, "pphoto: photo=@path");
    chk(strstr(&tg_composed, "-F 'business_connection_id=bc1' ") != 0,
        "pphoto: extras → -F поле");
    chk(tg_extraslot[1] == 0, "pphoto: extras съедены");

    // ===== 10. uploadStickerFile: user_id + sticker_format + sticker=@path =====
    r = tg_upload_sticker_file(bot, 7, "static", "/tmp/s.webp");
    chk(r == 0, "upload: dry без ответа → 0");
    chk(strstr(&tg_composed, "/uploadStickerFile|MP ") != 0, "upload: URL");
    chk(strstr(&tg_composed, "-F 'user_id=7' ") != 0, "upload: user_id");
    chk(strstr(&tg_composed, "-F 'sticker_format=static' ") != 0, "upload: sticker_format");
    chk(strstr(&tg_composed, "-F 'sticker=@/tmp/s.webp' ") != 0, "upload: sticker=@path");

    // ===== 11. editMessageMedia: media с attach://имя + файл этой части =====
    tg_edit_media_attach(bot, 55, 42,
        "[{\"type\":\"photo\",\"media\":\"attach://np\"}]", "np", "/tmp/new.jpg");
    chk(strstr(&tg_composed, "/editMessageMedia|MP ") != 0, "emedia: URL");
    chk(strstr(&tg_composed, "-F 'chat_id=55' ") != 0, "emedia: chat_id");
    chk(strstr(&tg_composed, "-F 'message_id=42' ") != 0, "emedia: message_id");
    chk(strstr(&tg_composed, "attach://np") != 0, "emedia: media ссылается attach://np");
    chk(strstr(&tg_composed, "-F 'np=@/tmp/new.jpg' ") != 0, "emedia: часть np=@path");

    // ===== 12. postStory: content с attach://file0 + extras bc-id/active_period =====
    tg_ex_str("business_connection_id", "bc9");
    tg_ex_num("active_period", 86400);
    tg_post_story_file(bot, "[{\"type\":\"video\",\"media\":\"attach://file0\"}]", "/tmp/stv.mp4");
    chk(strstr(&tg_composed, "/postStory|MP ") != 0, "story: URL");
    chk(strstr(&tg_composed, "-F 'file0=@/tmp/stv.mp4' ") != 0, "story: file0=@path");
    chk(strstr(&tg_composed, "attach://file0") != 0, "story: content attach://file0");
    chk(strstr(&tg_composed, "-F 'business_connection_id=bc9' ") != 0, "story: bc-id extras");
    chk(strstr(&tg_composed, "-F 'active_period=86400' ") != 0, "story: active_period extras");

    // ===== 13. editStory: story_id + content + bc-id extras =====
    tg_ex_str("business_connection_id", "bc9");
    tg_edit_story_file(bot, 77, "[{\"type\":\"photo\",\"media\":\"attach://file0\"}]", "/tmp/sp.jpg");
    chk(strstr(&tg_composed, "/editStory|MP ") != 0, "estory: URL");
    chk(strstr(&tg_composed, "-F 'story_id=77' ") != 0, "estory: story_id");
    chk(strstr(&tg_composed, "-F 'business_connection_id=bc9' ") != 0, "estory: bc-id extras");

    // ===== 14. скачивание (ядро, не дублирую): композиция URL =====
    r = tg_download_file(bot, "document/x.pdf", "/tmp/w31_out.pdf");
    chk(r == 1, "download: dry-возврат 1");
    chk(strstr(&tg_composed, "GET https://api.telegram.org/file/bot123:fake/document/x.pdf") != 0,
        "download: GET <base>/file/bot<token>/<path>");

    tg_dry_run = 0;

    if fails[0] == 0 {
        printf("PASS\n");
        exit(0);
    }
    exit(1);
}
