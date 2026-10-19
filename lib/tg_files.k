// lib/tg_files.k — W3-1: файловые методы Bot API через multipart.
//
// Опирается ТОЛЬКО на ядро lib/tg.k (не дублирует):
//   tg_mp_reset() / tg_mf_str / tg_mf_num / tg_mf_file / tg_call_mp — multipart;
//   tg_get_file(bot, file_id)          — из ядра: getFile → result.file_path в
//                                        слот tg_fpath, возврат ptr|0;
//   tg_download_file(bot, path, dest)  — из ядра: URL <base>/file/bot<token>/<path>
//                                        → tg_http_get_file (в dry: "GET <url>"
//                                        в tg_composed);
//   tg_http_get_file(url, dest)        — из ядра: curl -s -m 60 -o <dest> <url>.
// getFile/скачивание здесь НЕ переписываются — используются из ядра как есть.
//
// Контракт multipart (по коду ядра): tg_call_mp передаёт ТОЛЬКО tg_mpslot;
// tg_paramslot/tg_extraslot он не читает. Поэтому все теловые поля (chat_id,
// caption, media, content...) идут mp-полями через tg_mf_str/tg_mf_num.
//
// Экзотические опциональные параметры: tg_call_mp extraslot не сливает
// (сливает только tg_params_done для JSON-тела), поэтому обёртки этого модуля
// зовут tg_mp_ex() — мост tg_extraslot → tg_mpslot. Контракт как у ядра:
// extras применяются к СЛЕДУЮЩЕМУ вызову обёртки и съедаются автоматически.
// tg_mp_ex разбирает фрагменты вида "key":"str" / "key":число / "key":<json>;
// строковые значения дэскейпятся (\" \\ \n \r \t), литералы/JSON копируются
// как есть с отслеживанием глубины {} [] и строк (запятая внутри JSON не
// рвёт фрагмент). Лимит значения — 4000 байт.
//
// attach:// — tg_mp_attach в ядре отсутствует; для ссылки attach://имя из
// media_json достаточно объявить часть tg_mf_file(имя, путь) (см. media-group
// и tg_edit_media_attach). Часть с таким именем обязана совпасть со ссылкой.
//
// sendMediaGroup: пути из paths_json (JSON-массив строк) по порядку becomes
// части "file0".."file9" (лимит 10); media_json обязан ссылаться attach://fileN.
//
// Отклонение от таблицы плана: uploadStickerFile по эталону требует user_id —
// tg_upload_sticker_file(bot, user_id, sticker_format, path); возврат —
// file_id из result (копия в слот tg_upfid, стабилен до следующего вызова).

// tg_mpname[8]   — 64 байта: имя части "file0".."file9"
// tg_mpidx[4]    — 32 байта: decimal-индекс пути для dot-path tg_get_str
// tg_mpkbuf[64]  — 512 байт: ключ из extraslot для tg_mp_ex
// tg_mpvalbuf[512] — 4096 байт: значение из extraslot для tg_mp_ex
// tg_upfid[256]  — 2048 байт: file_id последнего tg_upload_sticker_file
tg_mpname[8];
tg_mpidx[4];
tg_mpkbuf[64];
tg_mpvalbuf[512];
tg_upfid[256];

// tg_mp_ex(): мост extraslot → mpslot (см. шапку); съедает extraslot.
tg_mp_ex() {
    auto p;
    auto c;
    auto k;
    auto v;
    auto done;
    auto dep;
    auto instr;
    auto esc;
    if tg_extraslot[1] > 0 {
        p = tg_extraslot[0];
        done = 0;
        while done == 0 {
            p = tg_skipspace(p);
            if @8 *p != 34 done = 1;     // нет opening " ключа — конец
            if done == 0 {
                // ключ: байты до closing " (без escapes — ключи простые)
                p = p + 1;
                k = &tg_mpkbuf;
                c = @8 *p;
                while done == 0 {
                    if c == 34 done = 2;
                    else if c == 0 done = 1;
                    else if k >= &tg_mpkbuf + 60 done = 1;
                    else {
                        *k !8 c;
                        k = k + 1;
                        p = p + 1;
                        c = @8 *p;
                    }
                }
                *k !8 0;
                if done == 2 {
                    done = 0;
                    p = p + 1;           // за закрывающую " ключа
                }
            }
            if done == 0 {
                p = tg_skipspace(p);     // p на закрывающей " ключа
                if @8 *p != 58 done = 1; // нет ':' — конец
            }
            if done == 0 {
                p = tg_skipspace(p + 1);
                v = &tg_mpvalbuf;
                if @8 *p == 34 {
                    // строковое значение: дэскейп \" \\ \n \r \t
                    p = p + 1;
                    c = @8 *p;
                    while done == 0 {
                        if c == 34 done = 2;
                        else if c == 0 done = 1;
                        else if v >= &tg_mpvalbuf + 4000 done = 1;
                        else {
                            if c == 92 {
                                p = p + 1;
                                c = @8 *p;
                                if c == 34 *v !8 34;
                                else if c == 92 *v !8 92;
                                else if c == 110 *v !8 10;
                                else if c == 114 *v !8 13;
                                else if c == 116 *v !8 9;
                                else *v !8 c;
                            } else {
                                *v !8 c;
                            }
                            v = v + 1;
                            p = p + 1;
                            c = @8 *p;
                        }
                    }
                    *v !8 0;
                    if done == 2 {
                        done = 0;
                        p = p + 1;       // за закрывающую " значения
                    }
                    tg_mf_str(&tg_mpkbuf, &tg_mpvalbuf);
                } else {
                    // литерал/число/готовый JSON: копия до ',' при depth==0;
                    // {} [] меняют глубину, " ... " — строка (запятая внутри
                    // строки/объекта фрагмент НЕ рвёт)
                    dep = 0;
                    instr = 0;
                    esc = 0;
                    c = @8 *p;
                    while done == 0 {
                        if c == 0 {
                            done = 1;
                        } else if v >= &tg_mpvalbuf + 4000 {
                            done = 1;
                        } else {
                            *v !8 c;
                            v = v + 1;
                            if instr == 1 {
                                if esc == 1 {
                                    esc = 0;
                                } else {
                                    if c == 92 esc = 1;
                                    if c == 34 instr = 0;
                                }
                            } else {
                                if c == 34 instr = 1;
                                else if c == 123 dep = dep + 1;
                                else if c == 91 dep = dep + 1;
                                else if c == 125 dep = dep - 1;
                                else if c == 93 dep = dep - 1;
                                else if c == 44 {
                                    if dep == 0 {
                                        done = 1;
                                        v = v - 1;   // запятую-разделитель не копируем
                                    }
                                }
                            }
                            p = p + 1;
                            c = @8 *p;
                        }
                    }
                    *v !8 0;
                    if done == 1 done = 0;
                    tg_mf_str(&tg_mpkbuf, &tg_mpvalbuf);
                }
            }
            if done == 0 {
                p = tg_skipspace(p);
                if @8 *p == 44 p = p + 1;  // ',' между фрагментами
                if @8 *p == 0 done = 1;
            }
        }
        tg_ex_reset();
    }
    1;
}

// tg_mp_send_file(bot, method, chat_id, field, path, caption): общая механика
// send*-file: chat_id + field=@path (+caption как mp-поле при caption != 0) +
// extras-мост; возврат — tg_call_mp.
tg_mp_send_file(bot, method, chat_id, field, path, caption) {
    tg_mp_reset();
    tg_mf_num("chat_id", chat_id);
    tg_mf_file(field, path);
    if caption != 0 tg_mf_str("caption", caption);
    tg_mp_ex();
    tg_call_mp(bot, method);
}

// tg_send_document_file(bot, chat_id, path, caption) → sendDocument
tg_send_document_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendDocument", chat_id, "document", path, caption);
}

// tg_send_photo_file(bot, chat_id, path, caption) → sendPhoto
tg_send_photo_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendPhoto", chat_id, "photo", path, caption);
}

// tg_send_audio_file(bot, chat_id, path, caption) → sendAudio
tg_send_audio_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendAudio", chat_id, "audio", path, caption);
}

// tg_send_video_file(bot, chat_id, path, caption) → sendVideo
tg_send_video_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendVideo", chat_id, "video", path, caption);
}

// tg_send_voice_file(bot, chat_id, path, caption) → sendVoice
tg_send_voice_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendVoice", chat_id, "voice", path, caption);
}

// tg_send_video_note_file(bot, chat_id, path) → sendVideoNote (caption нет)
tg_send_video_note_file(bot, chat_id, path) {
    tg_mp_send_file(bot, "sendVideoNote", chat_id, "video_note", path, 0);
}

// tg_send_animation_file(bot, chat_id, path, caption) → sendAnimation
tg_send_animation_file(bot, chat_id, path, caption) {
    tg_mp_send_file(bot, "sendAnimation", chat_id, "animation", path, caption);
}

// tg_send_sticker_file(bot, chat_id, path) → sendSticker (caption нет)
tg_send_sticker_file(bot, chat_id, path) {
    tg_mp_send_file(bot, "sendSticker", chat_id, "sticker", path, 0);
}

// tg_send_media_group_files(bot, chat_id, paths_json, media_json) →
// sendMediaGroup. paths_json — JSON-массив путей-строк; i-й путь становится
// частью "filei" (лимит 10, 0..9); media_json — массив InputMedia со ссылками
// attach://fileN. Порядок частей: chat_id, file0..fileN, media (+extras).
tg_send_media_group_files(bot, chat_id, paths_json, media_json) {
    auto i;
    auto s;
    i = 0;
    tg_mp_reset();
    tg_mf_num("chat_id", chat_id);
    while i < 10 {
        sprintf(&tg_mpidx, "%ld", i);
        s = tg_get_str(paths_json, &tg_mpidx);
        if s == 0 i = 10;
        if s != 0 {
            sprintf(&tg_mpname, "file%ld", i);
            tg_mf_file(&tg_mpname, s);
            i = i + 1;
        }
    }
    if media_json != 0 tg_mf_str("media", media_json);
    tg_mp_ex();
    tg_call_mp(bot, "sendMediaGroup");
}

// tg_send_live_photo_file(bot, chat_id, vpath, ppath) → sendLivePhoto:
// live_photo=@видео + photo=@статика
tg_send_live_photo_file(bot, chat_id, vpath, ppath) {
    tg_mp_reset();
    tg_mf_num("chat_id", chat_id);
    tg_mf_file("live_photo", vpath);
    tg_mf_file("photo", ppath);
    tg_mp_ex();
    tg_call_mp(bot, "sendLivePhoto");
}

// tg_set_chat_photo_file(bot, chat_id, path) → setChatPhoto
tg_set_chat_photo_file(bot, chat_id, path) {
    tg_mp_reset();
    tg_mf_num("chat_id", chat_id);
    tg_mf_file("photo", path);
    tg_mp_ex();
    tg_call_mp(bot, "setChatPhoto");
}

// tg_set_profile_photo_file(bot, path) → setMyProfilePhoto;
// business_connection_id — через extras: tg_ex_str("business_connection_id", id)
tg_set_profile_photo_file(bot, path) {
    tg_mp_reset();
    tg_mf_file("photo", path);
    tg_mp_ex();
    tg_call_mp(bot, "setMyProfilePhoto");
}

// tg_upload_sticker_file(bot, user_id, sticker_format, path) → uploadStickerFile.
// Возврат: file_id из result в слот tg_upfid (ptr стабилен до следующего
// вызова) либо 0 (сбой/сухой режим без ответа).
tg_upload_sticker_file(bot, user_id, sticker_format, path) {
    auto r;
    auto p;
    r = 0;
    tg_mp_reset();
    tg_mf_num("user_id", user_id);
    tg_mf_str("sticker_format", sticker_format);
    tg_mf_file("sticker", path);
    tg_mp_ex();
    if tg_call_mp(bot, "uploadStickerFile") == 1 {
        if tg_dry_run == 0 {
            p = tg_http_body();
            if p != 0 {
                p = tg_get_str(p, "result.file_id");
                if p != 0 {
                    strcpy(&tg_upfid, p);
                    r = &tg_upfid;
                }
            }
        }
    }
    r;
}

// tg_edit_media_attach(bot, chat_id, msg_id, media_json, attach_name, path) →
// editMessageMedia: media_json обязан ссылаться attach://attach_name, часть
// attach_name=@path объявляется здесь же.
tg_edit_media_attach(bot, chat_id, msg_id, media_json, attach_name, path) {
    tg_mp_reset();
    tg_mf_num("chat_id", chat_id);
    tg_mf_num("message_id", msg_id);
    if media_json != 0 tg_mf_str("media", media_json);
    tg_mf_file(attach_name, path);
    tg_mp_ex();
    tg_call_mp(bot, "editMessageMedia");
}

// tg_post_story_file(bot, content_json, path) → postStory. content —
// InputStoryContent со ссылкой attach://file0; file0=@path объявляется здесь.
// business_connection_id (обязательный!) и active_period — через extras:
//   tg_ex_str("business_connection_id", id); tg_ex_num("active_period", 86400);
tg_post_story_file(bot, content_json, path) {
    tg_mp_reset();
    if content_json != 0 tg_mf_str("content", content_json);
    tg_mf_file("file0", path);
    tg_mp_ex();
    tg_call_mp(bot, "postStory");
}

// tg_edit_story_file(bot, story_id, content_json, path) → editStory. content
// со ссылкой attach://file0; business_connection_id (обязательный!) — extras.
tg_edit_story_file(bot, story_id, content_json, path) {
    tg_mp_reset();
    tg_mf_num("story_id", story_id);
    if content_json != 0 tg_mf_str("content", content_json);
    tg_mf_file("file0", path);
    tg_mp_ex();
    tg_call_mp(bot, "editStory");
}
