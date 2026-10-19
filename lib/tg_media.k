// tg_media.k — медиа-обёртки v1 (B1): sendAudio, sendDocument, sendVideo,
// sendAnimation, sendVoice, sendVideoNote.
//
// Контракт обёрток: обязательные параметры — аргументы (вызов ≤6); ходовые
// опциональные — аргумент с контрактом «0 = не передавать»
// (if x != 0 tg_param_*(...)).
//
// Примечания (параметры, НЕ вошедшие в v1 — через tg_call(bot, "method", params)):
//  - parse_mode — через tg_sendx (lib/tg_ext.k) либо tg_call;
//  - tg_send_audio: duration/performer/title/thumbnail/caption_entities/
//    message_thread_id/disable_notification/protect_content/allow_paid_broadcast/
//    message_effect_id/reply_parameters/reply_markup — через tg_call;
//  - tg_send_document: disable_content_type_detection/thumbnail и т.д. — через tg_call;
//  - tg_send_video: duration/width/height/thumbnail/cover/start_timestamp/
//    supports_streaming/has_spoiler/show_caption_above_media — через tg_call;
//  - tg_send_animation: duration/width/height/thumbnail/has_spoiler/
//    show_caption_above_media — через tg_call;
//  - tg_send_voice: duration/thumbnail — через tg_call;
//  - tg_send_video_note: length/thumbnail — через tg_call;
//  - business_connection_id — общий для всех, через tg_call.

// tg_send_audio(bot, chat_id, audio, caption) — sendAudio
tg_send_audio(bot, chat_id, audio, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "audio", audio);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendAudio", body);
}

// tg_send_document(bot, chat_id, doc, caption) — sendDocument
tg_send_document(bot, chat_id, doc, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "document", doc);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendDocument", body);
}

// tg_send_video(bot, chat_id, video, caption) — sendVideo
tg_send_video(bot, chat_id, video, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "video", video);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendVideo", body);
}

// tg_send_animation(bot, chat_id, anim, caption) — sendAnimation
tg_send_animation(bot, chat_id, anim, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "animation", anim);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendAnimation", body);
}

// tg_send_voice(bot, chat_id, voice, caption) — sendVoice
tg_send_voice(bot, chat_id, voice, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "voice", voice);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendVoice", body);
}

// tg_send_video_note(bot, chat_id, vnote, duration) — sendVideoNote;
// duration=0 → поле не передаётся (0 = не передавать)
tg_send_video_note(bot, chat_id, vnote, duration) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "video_note", vnote);
    if duration != 0 tg_param_num(&tg_paramslot, "duration", duration);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendVideoNote", body);
}
