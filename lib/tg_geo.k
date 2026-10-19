// tg_geo.k — гео/стикер/контакт/дайс/лайв-фото (kivagram v2, волна B2).
// Методы: sendLocation, sendVenue, sendContact, sendDice, sendSticker,
// sendLivePhoto. Координаты — СТРОКИ через tg_param_raw: latitude/longitude
// уходят в JSON как дробные числа БЕЗ кавычек (latitude=55.75).
// Редкие экзотические опциональные параметры (business_connection_id,
// message_thread_id, disable_notification, protect_content, reply_parameters,
// reply_markup, foursquare/google-идентификаторы, vcard и т.п.) — через
// tg_call(bot, "method", params) напрямую.

// tg_send_location(bot, chat_id, lat, lng) — sendLocation.
// lat/lng — строки вида "55.75" (дробные без кавычек в JSON, tg_param_raw).
tg_send_location(bot, chat_id, lat, lng) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_raw(&tg_paramslot, "latitude", lat);
    tg_param_raw(&tg_paramslot, "longitude", lng);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendLocation", body);
}

// tg_send_venue(bot, chat_id, lat, lng, title, address) — sendVenue.
// lat/lng — raw-строки, как в tg_send_location; title/address обязательны.
tg_send_venue(bot, chat_id, lat, lng, title, address) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_raw(&tg_paramslot, "latitude", lat);
    tg_param_raw(&tg_paramslot, "longitude", lng);
    tg_param_str(&tg_paramslot, "title", title);
    tg_param_str(&tg_paramslot, "address", address);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendVenue", body);
}

// tg_send_contact(bot, chat_id, phone, first_name, last_name) — sendContact.
// last_name=0 → не передаётся (по API опционален); vcard — через tg_call.
tg_send_contact(bot, chat_id, phone, first_name, last_name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "phone_number", phone);
    tg_param_str(&tg_paramslot, "first_name", first_name);
    if last_name != 0 tg_param_str(&tg_paramslot, "last_name", last_name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendContact", body);
}

// tg_send_dice(bot, chat_id, emoji) — sendDice.
// emoji=0 → не передаётся (Telegram выберёт дефолтную "🎲").
tg_send_dice(bot, chat_id, emoji) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if emoji != 0 tg_param_str(&tg_paramslot, "emoji", emoji);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendDice", body);
}

// tg_send_sticker(bot, chat_id, sticker) — sendSticker.
// sticker — file_id или URL (.WEBP); emoji — через tg_call.
tg_send_sticker(bot, chat_id, sticker) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendSticker", body);
}

// tg_send_live_photo(bot, chat_id, live_photo, photo) — sendLivePhoto.
// live_photo=0 → не передаётся; caption/parse_mode — через tg_call.
tg_send_live_photo(bot, chat_id, live_photo, photo) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    if live_photo != 0 tg_param_str(&tg_paramslot, "live_photo", live_photo);
    tg_param_str(&tg_paramslot, "photo", photo);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendLivePhoto", body);
}
