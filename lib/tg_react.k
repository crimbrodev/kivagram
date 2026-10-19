// tg_react.k — B11: реакции, геттеры профиля, сессия бота.
// 8 обёрток Bot API: setMessageReaction / deleteMessageReaction /
// deleteAllMessageReactions / getUserProfilePhotos / getUserProfileAudios /
// getWebhookInfo / logOut / close.
// reaction — сырой JSON-массив ReactionType через tg_param_json (без кавычек).
// Опциональные, не входящие в v1-обёртки (is_big; user_id/actor_chat_id в
// delete*; offset в getters) — через tg_call напрямую.
// getWebhookInfo/logOut/close — методы БЕЗ параметров: тело "{}" (reset+done).

// tg_set_reaction(bot, chat_id, msg_id, reaction_json) — setMessageReaction;
// reaction_json — массив ReactionType-объектов вида
// [{"type":"emoji","emoji":"👍"}] через tg_param_json (is_big — через tg_call)
tg_set_reaction(bot, chat_id, msg_id, reaction_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    tg_param_json(&tg_paramslot, "reaction", reaction_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setMessageReaction", body);
}

// tg_del_reaction(bot, chat_id, msg_id) — deleteMessageReaction;
// user_id/actor_chat_id — через tg_call (не входят в v1-обёртку)
tg_del_reaction(bot, chat_id, msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_id", msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteMessageReaction", body);
}

// tg_del_all_reactions(bot, chat_id) — deleteAllMessageReactions;
// user_id/actor_chat_id — через tg_call
tg_del_all_reactions(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteAllMessageReactions", body);
}

// tg_profile_photos(bot, user_id, limit) — getUserProfilePhotos;
// limit=0 → не передавать (Telegram вернёт до 100); offset — через tg_call
tg_profile_photos(bot, user_id, limit) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if limit != 0 tg_param_num(&tg_paramslot, "limit", limit);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getUserProfilePhotos", body);
}

// tg_profile_audios(bot, user_id, limit) — getUserProfileAudios;
// limit=0 → не передавать; offset — через tg_call
tg_profile_audios(bot, user_id, limit) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if limit != 0 tg_param_num(&tg_paramslot, "limit", limit);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getUserProfileAudios", body);
}

// tg_get_webhook_info(bot) — getWebhookInfo, параметров нет → тело "{}"
tg_get_webhook_info(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getWebhookInfo", body);
}

// tg_logout(bot) — logOut, параметров нет → тело "{}"
tg_logout(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "logOut", body);
}

// tg_close(bot) — close, параметров нет → тело "{}"
tg_close(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "close", body);
}
