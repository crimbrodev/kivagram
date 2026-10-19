// tg_forum.k — форум-топики v1 (B10): createForumTopic, editForumTopic,
// closeForumTopic, reopenForumTopic, deleteForumTopic,
// unpinAllForumTopicMessages, editGeneralForumTopic, closeGeneralForumTopic,
// reopenGeneralForumTopic, hideGeneralForumTopic, unhideGeneralForumTopic,
// unpinAllGeneralForumTopicMessages, getForumTopicIconStickers.
//
// Контракт обёрток: обязательные параметры — аргументы (вызов ≤6); ходовые
// опциональные — аргумент с контрактом «0 = не передавать»
// (if x != 0 tg_param_*(...)).
//
// Примечания (параметры, НЕ вошедшие в v1 — через tg_call(bot, "method", params)):
//  - tg_topic_create: icon_color / icon_custom_emoji_id — не умещаются в ≤6
//    аргументов, через tg_call;
//  - tg_topic_edit: icon_custom_emoji_id — через tg_call;
//  - business_connection_id / message_thread_id сверх thread_id у
//    general-обёрток — через tg_call;
//  - ответ createForumTopic (ForumTopic) — через tg_get*(tg_composed) после вызова.

// tg_topic_create(bot, chat_id, name) — createForumTopic
tg_topic_create(bot, chat_id, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "createForumTopic", body);
}

// tg_topic_edit(bot, chat_id, thread_id, name) — editForumTopic; name=0 → skip
tg_topic_edit(bot, chat_id, thread_id, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    if name != 0 tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editForumTopic", body);
}

// tg_topic_close(bot, chat_id, thread_id) — closeForumTopic
tg_topic_close(bot, chat_id, thread_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "closeForumTopic", body);
}

// tg_topic_reopen(bot, chat_id, thread_id) — reopenForumTopic
tg_topic_reopen(bot, chat_id, thread_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "reopenForumTopic", body);
}

// tg_topic_delete(bot, chat_id, thread_id) — deleteForumTopic
tg_topic_delete(bot, chat_id, thread_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteForumTopic", body);
}

// tg_topic_unpin_all(bot, chat_id, thread_id) — unpinAllForumTopicMessages
tg_topic_unpin_all(bot, chat_id, thread_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_num(&tg_paramslot, "message_thread_id", thread_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unpinAllForumTopicMessages", body);
}

// tg_general_edit(bot, chat_id, name) — editGeneralForumTopic (name обязателен)
tg_general_edit(bot, chat_id, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editGeneralForumTopic", body);
}

// tg_general_close(bot, chat_id) — closeGeneralForumTopic
tg_general_close(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "closeGeneralForumTopic", body);
}

// tg_general_reopen(bot, chat_id) — reopenGeneralForumTopic
tg_general_reopen(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "reopenGeneralForumTopic", body);
}

// tg_general_hide(bot, chat_id) — hideGeneralForumTopic
tg_general_hide(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "hideGeneralForumTopic", body);
}

// tg_general_unhide(bot, chat_id) — unhideGeneralForumTopic
tg_general_unhide(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unhideGeneralForumTopic", body);
}

// tg_general_unpin_all(bot, chat_id) — unpinAllGeneralForumTopicMessages
tg_general_unpin_all(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "unpinAllGeneralForumTopicMessages", body);
}

// tg_topic_icons(bot) — getForumTopicIconStickers (без параметров)
tg_topic_icons(bot) {
    tg_call(bot, "getForumTopicIconStickers", 0);
}
