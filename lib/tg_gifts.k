// tg_gifts.k — подарки, сторис, игры v1 (W3-5): getAvailableGifts, sendGift,
// giftPremiumSubscription, convertGiftToStars, upgradeGift, transferGift,
// postStory, repostStory, editStory, deleteStory, sendGame, setGameScore,
// getGameHighScores.
//
// Контракт обёрток: обязательные параметры — аргументы (вызов ≤6); ходовые
// опциональные — extras (tg_ex_* перед вызовом, съедаются автоматически).
//
// Сверка с эталоном /ref/api/methods/*.md — усечённые сигнатуры плана
// расширены обязательными API-параметрами:
//  - tg_gift_premium: user_id (в плане gift_id — опечатка, gift_id в API нет);
//  - tg_gift_to_stars / tg_upgrade_gift / tg_transfer_gift / сторис: conn_id =
//    business_connection_id (обязателен API) первым аргументом после bot;
//  - tg_repost_story: from_chat_id/from_story_id/active_period (more_content
//    в repostStory отсутствует);
//  - tg_edit_story: active_period в editStory отсутствует — не передаётся.
//
// Игры: 0-контракт «ровно один из msg_id/inline_msg_id ненулевой»: msg_id →
// message_id, иначе inline_msg_id → inline_message_id; оба 0 → ни один не
// передаётся (Telegram вернёт ошибку — контракт на вызывающем); оба ненулевые
// → message_id приоритетен. chat_id обязателен API при message_id — через
// extras: tg_ex_num("chat_id", chat_id).
//  - tg_upgrade_gift: star_count передаётся ВСЕГДА: 0 — валидное значение API
//    для prepaid-апгрейдов (gift.prepaid_upgrade_star_count > 0);
//  - tg_transfer_gift: star_count=0 → skip (ненулевой — платный перевод).
//
// Сторис: content — сырой JSON InputStoryContent (JSON-only, tg_param_json);
// caption/areas/parse_mode/post_to_chat_page/protect_content — extras.

// tg_get_available_gifts(bot) — getAvailableGifts (без параметров)
tg_get_available_gifts(bot) {
    auto body;
    tg_params_reset(&tg_paramslot);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getAvailableGifts", body);
}

// tg_send_gift(bot, gift_id, user_id, text) — sendGift
// user_id=0 → skip (chat_id — через extras); text=0 → skip;
// pay_for_upgrade/text_parse_mode/text_entities — extras.
tg_send_gift(bot, gift_id, user_id, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if user_id != 0 tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "gift_id", gift_id);
    if text != 0 tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendGift", body);
}

// tg_gift_premium(bot, user_id, month_count, star_count, text) —
// giftPremiumSubscription; text=0 → skip; text_parse_mode/text_entities — extras
tg_gift_premium(bot, user_id, month_count, star_count, text) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_num(&tg_paramslot, "month_count", month_count);
    tg_param_num(&tg_paramslot, "star_count", star_count);
    if text != 0 tg_param_str(&tg_paramslot, "text", text);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "giftPremiumSubscription", body);
}

// tg_gift_to_stars(bot, conn_id, owned_gift_id) — convertGiftToStars
tg_gift_to_stars(bot, conn_id, owned_gift_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_str(&tg_paramslot, "owned_gift_id", owned_gift_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "convertGiftToStars", body);
}

// tg_upgrade_gift(bot, conn_id, owned_gift_id, star_count) — upgradeGift;
// star_count ВСЕГДА (0 валиден — prepaid-апгрейд); keep_original_details —
// extras: tg_ex_raw("keep_original_details", "true").
tg_upgrade_gift(bot, conn_id, owned_gift_id, star_count) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_str(&tg_paramslot, "owned_gift_id", owned_gift_id);
    tg_param_num(&tg_paramslot, "star_count", star_count);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "upgradeGift", body);
}

// tg_transfer_gift(bot, conn_id, owned_gift_id, new_owner_id, star_count) —
// transferGift; new_owner_id → new_owner_chat_id; star_count=0 → skip
// (ненулевой — платный перевод, требует can_transfer_stars).
tg_transfer_gift(bot, conn_id, owned_gift_id, new_owner_id, star_count) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_str(&tg_paramslot, "owned_gift_id", owned_gift_id);
    tg_param_num(&tg_paramslot, "new_owner_chat_id", new_owner_id);
    if star_count != 0 tg_param_num(&tg_paramslot, "star_count", star_count);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "transferGift", body);
}

// tg_post_story(bot, conn_id, content_json, active_period) — postStory;
// content — сырой JSON (JSON-only контракт); caption/parse_mode/
// caption_entities/areas/post_to_chat_page/protect_content — extras.
tg_post_story(bot, conn_id, content_json, active_period) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_json(&tg_paramslot, "content", content_json);
    tg_param_num(&tg_paramslot, "active_period", active_period);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "postStory", body);
}

// tg_repost_story(bot, conn_id, from_chat_id, from_story_id, active_period) —
// repostStory; post_to_chat_page/protect_content — extras.
tg_repost_story(bot, conn_id, from_chat_id, from_story_id, active_period) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_num(&tg_paramslot, "from_chat_id", from_chat_id);
    tg_param_num(&tg_paramslot, "from_story_id", from_story_id);
    tg_param_num(&tg_paramslot, "active_period", active_period);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "repostStory", body);
}

// tg_edit_story(bot, conn_id, story_id, content_json) — editStory
// (active_period в editStory нет); caption/caption_entities/parse_mode/areas
// — extras.
tg_edit_story(bot, conn_id, story_id, content_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_num(&tg_paramslot, "story_id", story_id);
    tg_param_json(&tg_paramslot, "content", content_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "editStory", body);
}

// tg_delete_story(bot, conn_id, story_id) — deleteStory
tg_delete_story(bot, conn_id, story_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "business_connection_id", conn_id);
    tg_param_num(&tg_paramslot, "story_id", story_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteStory", body);
}

// tg_send_game(bot, chat_id, game_short_name) — sendGame;
// business_connection_id/disable_notification/protect_content/
// message_effect_id/reply_parameters/reply_markup — extras.
tg_send_game(bot, chat_id, game_short_name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "game_short_name", game_short_name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendGame", body);
}

// tg_game_target(slot, msg_id, inline_msg_id*|0): 0-контракт «ровно один из
// msg_id/inline_msg_id ненулевой». msg_id != 0 → message_id; иначе
// inline_msg_id != 0 → inline_message_id; оба 0 → ни один не передаётся
// (Telegram вернёт ошибку — проверка на вызывающем). Оба ненулевые →
// message_id приоритетен. NB: chat_id обязателен API при message_id — extras.
tg_game_target(slot, msg_id, inline_msg_id) {
    if msg_id != 0 {
        tg_param_num(slot, "message_id", msg_id);
    } else {
        if inline_msg_id != 0 tg_param_str(slot, "inline_message_id", inline_msg_id);
    }
    1;
}

// tg_set_game_score(bot, user_id, score, msg_id, inline_msg_id) — setGameScore;
// 0-контракт tg_game_target; force/disable_edit_message/chat_id — extras.
tg_set_game_score(bot, user_id, score, msg_id, inline_msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_num(&tg_paramslot, "score", score);
    tg_game_target(&tg_paramslot, msg_id, inline_msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setGameScore", body);
}

// tg_get_game_highscores(bot, user_id, msg_id, inline_msg_id) —
// getGameHighScores; 0-контракт tg_game_target; chat_id — extras при msg_id.
tg_get_game_highscores(bot, user_id, msg_id, inline_msg_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_game_target(&tg_paramslot, msg_id, inline_msg_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getGameHighScores", body);
}
