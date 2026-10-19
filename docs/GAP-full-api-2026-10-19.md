# Полный gap-анализ: kivagram vs Telegram Bot API

Эталон: официальное зеркало Bot API (`/tmp/opencode/ref/api/` — 185 методов + 400 типов с полными таблицами параметров, скачано 19.10.2026). Сверялось с `lib/tg.k`.

**Важное уточнение по транспорту:** `tg_http_post` шлёт тело как JSON (`Content-Type: application/json`, `curl -d @file`) — этого хватает на всё, кроме загрузки файлов. multipart/form-data нет ⇒ любые методы с InputFile/attach:// = multipart-blocked. Файлы по file_id/URL — работают уже сейчас через `tg_call`.

## Итоги по секторам

| Сектор | Методов | HAVE | PARTIAL | MISSING |
|---|---|---|---|---|
| 1. send/forward/copy | 27 | 0 | 3 | 24 |
| 2. правки/ответы/реакции | 27 | 1 | 2 | 24 |
| 3. админка/чат/конфиг/файлы/стикеры | 82 | 0 | 1 | 81 |
| 4. платежи/игры/подарки/бизнес/прочее | 46 | 1 | 0 | 45 |
| **Методы итого** | **182** | **2** | **6** | **174** |
| 5а. типы апдейтов (dispatch) | 28 | 3 handled | 22 partial | 3 ignored |
| 5б. параметры существующих обёрток | 8 | 1 полная | — | 61 дыра параметров |
| 5в. клавиатуры/хелперы | 12 | 0 | 2 manual-JSON | 10 |

## Предлагаемые волны v2

**Волна 1 — «базовый бот» (works-now, дёшево, огромный прирост):**
- Параметры в существующие обёртки: `parse_mode` + HTML-эскейпер, `reply_parameters`/`reply_to_message_id`, `reply_markup`, `caption`, `message_thread_id`, `disable_notification` (61 дыра в 8 обёртках)
- `allowed_updates` в getUpdates (иначе 3 типа апдейтов физически не приходят)
- `tg_answer` без обязательного text + `show_alert`/`cache_time`
- `editMessageReplyMarkup`, `editMessageCaption` (смена/снятие клавиатуры — основной UX-паттерн)
- Билдеры клавиатур (inline + reply) + `ReplyKeyboardRemove`/`ForceReply`
- `setMyCommands` — меню команд
- Новые kind'ы диспетчера: `edited_message`, `channel_post`, `my_chat_member`, `chat_join_request` + аксессоры
- send-семейство по file_id/URL: document/video/audio/voice/sticker/animation/dice/location/contact/poll/venue, forward/copy

**Волна 2 — «группы и админка»:**
- getChat/getChatMember/getChatAdministrators/getChatMemberCount + фильтр is_admin
- ban/unban/restrict/promote, pin/unpin, setChatPermissions, leaveChat
- invite-links, approve/decline chat_join_request
- форум-топики (12 методов + message_thread_id)
- inline-режим: answerInlineQuery + inline_query kind + аксессоры
- sendMediaGroup, sendPoll (34 параметра), stopPoll, setMessageReaction

**Волна 3 — «деньги и контент»:**
- платежи: sendInvoice/createInvoiceLink/answerPreCheckoutQuery/answerShippingQuery/refundStarPayment/getMyStarBalance + pre_checkout/shipping kinds
- multipart (curl -F): upload файлов, getFile+скачивание, загрузка стикеров
- стикер-наборы, подарки, webapp-ответы

**Волна 4 — длинный хвост (низкий приоритет):**
- бизнес-аккаунт (12), сторис (4, частично multipart), игры (3), верификация (4), управление токеном (4), passport, rich-message/черновики, suggested posts, чат-бусты, story/mini-app save, webhook-режим (setWebhook/getWebhookInfo), ephemeral-сообщения, paid media, чеклисты

---

## Сектор 1. send/forward/copy (27 методов: HAVE 0, PARTIAL 3, MISSING 24)

- [PARTIAL] sendmessage — params: business_connection_id, chat_id, message_thread_id, direct_messages_topic_id, ephemeral_message_parameters, text, parse_mode, entities, link_preview_options, disable_notification, protect_content, allow_paid_broadcast, message_effect_id, suggested_post_parameters, reply_parameters, reply_markup | lib: tg_send_text (lib/tg.k:1352), tg_send_to (lib/tg.k:1366) — только chat_id+text; generic tg_call (777), билдеры tg_params_* (635-681) | gap: 14 из 16 не покрыты (вручную через tg_call+tg_param_json возможно) | note: works-now
- [PARTIAL] sendphoto — params: business_connection_id, chat_id, message_thread_id, direct_messages_topic_id, ephemeral_message_parameters, photo, caption, parse_mode, caption_entities, show_caption_above_media, has_spoiler, disable_notification, protect_content, allow_paid_broadcast, message_effect_id, suggested_post_parameters, reply_parameters, reply_markup | lib: tg_send_photo_url (1445) — только chat_id+photo (URL/file_id) | gap: нет caption, parse_mode, reply_markup, reply_parameters, has_spoiler, disable_notification, message_thread_id; ctx-варианта нет; загрузка с диска невозможна | note: works-now
- [MISSING] sendaudio — params: business_connection_id, chat_id, message_thread_id, direct_messages_topic_id, ephemeral_message_parameters, audio, caption, parse_mode, caption_entities, duration, performer, title, thumbnail, disable_notification, protect_content, allow_paid_broadcast, message_effect_id, suggested_post_parameters, reply_parameters, reply_markup | gap: нет обёртки; thumbnail — multipart | note: works-now
- [MISSING] senddocument — params: business_connection_id, chat_id, message_thread_id, direct_messages_topic_id, ephemeral_message_parameters, document, thumbnail, caption, parse_mode, caption_entities, disable_content_type_detection, disable_notification, protect_content, allow_paid_broadcast, message_effect_id, suggested_post_parameters, reply_parameters, reply_markup | note: works-now
- [MISSING] sendvideo — params: …, video, duration, width, height, thumbnail, cover, start_timestamp, caption, parse_mode, caption_entities, show_caption_above_media, has_spoiler, supports_streaming, disable_notification, protect_content, reply_parameters, reply_markup (+общие) | note: works-now (thumbnail/cover — multipart)
- [MISSING] sendanimation — params: animation, duration, width, height, thumbnail, caption, parse_mode, caption_entities, show_caption_above_media, has_spoiler, … | note: works-now
- [MISSING] sendvoice — params: voice, caption, parse_mode, caption_entities, duration, … | note: works-now
- [MISSING] sendvideonote — params: video_note, duration, length, thumbnail, … | note: works-now (URL запрещён — только file_id/multipart)
- [MISSING] sendmediagroup — params: media (JSON-массив 2-10 InputMedia), disable_notification, protect_content, allow_paid_broadcast, message_effect_id, reply_parameters | note: works-now (file_id/URL внутри)
- [MISSING] sendlocation — params: latitude, longitude, horizontal_accuracy, live_period, heading, proximity_alert_radius, … | note: works-now
- [MISSING] sendvenue — params: latitude, longitude, title, address, foursquare_id, foursquare_type, google_place_id, google_place_type, … | note: works-now
- [MISSING] sendcontact — params: phone_number, first_name, last_name, vcard, … | note: works-now
- [MISSING] sendpoll — params: chat_id, question, question_parse_mode, question_entities, options, is_anonymous, type, allows_multiple_answers, allows_revoting, shuffle_options, allow_adding_options, hide_results_until_closes, members_only, country_codes, correct_option_ids, explanation, explanation_parse_mode, explanation_entities, explanation_media, open_period, close_date, is_closed, description, description_parse_mode, description_entities, media, disable_notification, protect_content, allow_paid_broadcast, message_effect_id, reply_parameters, reply_markup (34) | note: works-now
- [MISSING] senddice — params: emoji, … | note: works-now
- [MISSING] sendsticker — params: sticker, emoji, … | note: works-now (.TGS/.WEBM — file_id/multipart)
- [PARTIAL] sendchataction — params: business_connection_id, chat_id, message_thread_id, action | lib: tg_action (1395) — chat_id (только из ctx) + action | gap: нет business_connection_id, message_thread_id, нет явной версии вне ctx | note: works-now
- [MISSING] sendpaidmedia — params: star_count, media, payload, caption, parse_mode, … | note: works-now
- [MISSING] sendlivephoto — params: live_photo, photo, caption, … | note: works-now (URL запрещён — только file_id)
- [MISSING] sendchecklist — params: business_connection_id, checklist (JSON), … | note: works-now
- [MISSING] forwardmessage — params: chat_id, from_chat_id, message_id, message_thread_id, video_start_timestamp, disable_notification, protect_content, message_effect_id, … | note: works-now
- [MISSING] forwardmessages — params: chat_id, from_chat_id, message_ids (JSON)… | note: works-now
- [MISSING] copymessage — params: chat_id, from_chat_id, message_id, caption, parse_mode, caption_entities, reply_parameters, reply_markup, … | note: works-now
- [MISSING] copymessages — params: chat_id, from_chat_id, message_ids, remove_caption, … | note: works-now
- [MISSING] sendchatjoinrequestwebapp — params: chat_join_request_query_id, web_app_url | note: works-now
- [MISSING] sendmessagedraft — params: chat_id, message_thread_id, draft_id, text, parse_mode, entities, can_stop, keep_on_stop | note: works-now
- [MISSING] sendrichmessagedraft — params: chat_id, message_thread_id, draft_id, rich_message (JSON), can_stop, keep_on_stop | note: works-now
- [MISSING] sendrichmessage — params: business_connection_id, chat_id, rich_message (JSON), … | note: works-now

ТОП-5: sendmessage без parse_mode/reply_markup/reply_parameters ⇒ через хелперы нельзя форматирование, кнопки и ответы; sendpoll (34 params) без обёртки; sendmediagroup; forward/copy; sendphoto/sendchataction без caption/thread.

## Сектор 2. правки/ответы/реакции (27 методов: HAVE 1, PARTIAL 2, MISSING 24)

- [PARTIAL] answercallbackquery — params: callback_query_id, text, show_alert, url, cache_time | lib: tg_answer (1376-1392) — callback_query_id + text | gap: text всегда обязателен (в API опционален — нельзя просто снять спиннер), нет show_alert, url, cache_time | note: works-now
- [MISSING] answerchatjoinrequestquery — params: chat_join_request_query_id, result | note: works-now
- [MISSING] answerguestquery — params: guest_query_id, result | note: works-now
- [MISSING] answerinlinequery — params: inline_query_id, results (JSON), cache_time, is_personal, next_offset, button | note: works-now
- [MISSING] answerprecheckoutquery — params: pre_checkout_query_id, ok, error_message | note: works-now
- [MISSING] answershippingquery — params: shipping_query_id, ok, shipping_options, error_message | note: works-now
- [MISSING] answerwebappquery — params: web_app_query_id, result | note: works-now
- [MISSING] approvesuggestedpost — params: chat_id, message_id, send_date | note: works-now
- [MISSING] declinesuggestedpost — params: chat_id, message_id, comment | note: works-now
- [HAVE] deletemessage — params: chat_id, message_id | lib: tg_delete (1434-1442) | gap: нет | note: works-now
- [MISSING] deletemessages — params: chat_id, message_ids (JSON) | note: works-now
- [MISSING] deleteephemeralmessage — params: chat_id, receiver_user_id, ephemeral_message_id | note: works-now
- [MISSING] deletemessagereaction — params: chat_id, message_id, user_id, actor_chat_id | note: works-now
- [MISSING] deleteallmessagereactions — params: chat_id, user_id, actor_chat_id | note: works-now
- [MISSING] editmessagecaption — params: business_connection_id, chat_id, message_id, inline_message_id, caption, parse_mode, caption_entities, show_caption_above_media, reply_markup | note: works-now
- [MISSING] editmessagechecklist — params: business_connection_id, chat_id, message_id, checklist, reply_markup | note: works-now
- [MISSING] editmessagelivelocation — params: chat_id, message_id, inline_message_id, latitude, longitude, live_period, horizontal_accuracy, heading, proximity_alert_radius, reply_markup | gap: float-параметров в билдере нет вообще (нет tg_param_float!) | note: works-now
- [MISSING] editmessagemedia — params: chat_id, message_id, inline_message_id, media (JSON), reply_markup | note: works-now (attach:// → multipart)
- [MISSING] editmessagereplymarkup — params: business_connection_id, chat_id, message_id, inline_message_id, reply_markup | note: works-now
- [PARTIAL] editmessagetext — params: business_connection_id, chat_id, message_id, inline_message_id, text, parse_mode, entities, link_preview_options, rich_message, reply_markup | lib: tg_edit_text (1408-1417), tg_edit_inline (1419-1432) | gap: нет parse_mode, entities, link_preview_options, reply_markup, business_connection_id; chat/inline-версии не пересекаются | note: works-now
- [MISSING] editephemeralmessagetext / editephemeralmessagecaption / editephemeralmessagemedia / editephemeralmessagereplymarkup — params: chat_id, receiver_user_id, ephemeral_message_id + … | note: works-now (media attach:// → multipart)
- [MISSING] setmessagereaction — params: chat_id, message_id, reaction (JSON), is_big | note: works-now
- [MISSING] stoppoll — params: business_connection_id, chat_id, message_id, reply_markup | note: works-now
- [MISSING] stopmessagelivelocation — params: business_connection_id, chat_id, message_id, inline_message_id, reply_markup | note: works-now

ТОП-5: answercallbackquery (нет show_alert/безтекстового ответа); editmessagetext без parse_mode/reply_markup; editmessagereplymarkup («кнопка нажата → убрать кнопки»); editmessagecaption; setmessagereaction.

## Сектор 3. админка/чат/конфиг/файлы/стикеры (82 метода: HAVE 0, PARTIAL 1, MISSING 81)

Модерация: [MISSING] banchatmember (chat_id, user_id, until_date, revoke_messages), unbanchatmember (only_if_banned), restrictchatmember (permissions JSON, use_independent_chat_permissions, until_date), promotechatmember (19 опциональных флагов!), banchatsenderchat, unbanchatsenderchat, getchatmember, getchatmembercount, getchat, getchatadministrators (return_bots), setchatpermissions, setchatmembertag (tag), setchatadministratorcustomtitle — все note: works-now, в lib: 0 совпадений.

Управление чатом: [MISSING] pinchatmessage (disable_notification), unpinchatmessage, unpinallchatmessages, setchattitle, setchatdescription, setchatphoto (multipart-blocked), deletechatphoto, setchatstickerset, leavechat, exportchatinvitelink, createchatinvitelink (name/expire_date/member_limit/creates_join_request), editchatinvitelink, revokechatinvitelink, createchatsubscriptioninvitelink (subscription_period/price), editchatsubscriptioninvitelink, approvechatjoinrequest, declinechatjoinrequest — все works-now.

Вебхук: [PARTIAL] deletewebhook — только внутренние вызовы `tg_call(bot,"deleteWebhook",0)` в tg_polling (1550, 1591), нет экспортируемой обёртки, drop_pending_updates не пробрасывается; [MISSING] setwebhook (url, certificate, ip_address, max_connections, allowed_updates, drop_pending_updates, secret_token), getwebhookinfo — README объявляет webhooks вне скоупа v1.

Форум-топики: [MISSING] createforumtopic (name, icon_color, icon_custom_emoji_id), editforumtopic, closeforumtopic, reopenforumtopic, deleteforumtopic, unpinallforumtopicmessages, editgeneralforumtopic, closegeneralforumtopic, reopengeneralforumtopic, hidegeneralforumtopic, unhidegeneralforumtopic, unpinallgeneralforumtopicmessages, getforumtopiciconstickers — 0 совпадений в kivagram; все works-now.

Конфиг бота: [MISSING] setmycommands (commands JSON, scope, language_code), getmycommands, deletemycommands, setmyname, getmyname, setmydescription, getmydescription, setmyshortdescription, getmyshortdescription, setchatmenubutton (menu_button JSON), getchatmenubutton, setmydefaultadministratorrights (rights JSON, for_channels), getmydefaultadministratorrights, setmyprofilephoto (multipart-blocked), removemyprofilephoto — все works-now кроме фото.

Файлы/пользователи: [MISSING] getfile (file_id; далее скачивание требует GET-запроса, которого транспорт не умеет — multipart-blocked для цепочки), getuserprofilephotos (offset/limit), getuserprofileaudios, getuserpersonalchatmessages, getusergifts (9 фильтров), getchatgifts (11 фильтров), getuserchatboosts — works-now кроме getfile.

Наборы стикеров: [MISSING] uploadstickerfile (multipart-blocked), createnewstickerset (stickers JSON, но file внутри — InputFile), addstickertoset, setstickerpositioninset, deletestickerfromset, replacestickerinset, setstickeremojilist, setstickerkeywords, setstickermaskposition, setstickersettitle, setstickersetthumbnail, setcustomemojistickersetthumbnail, getstickerset, getcustomemojistickers — в kivagram 0 совпадений по «sticker».

ТОП-5: getChat+getChatMember+getChatAdministrators (база управления); баны/restrict/promote; вебхук-набор; пины; join-requests + invite-links.

## Сектор 4. платежи/игры/подарки/бизнес/прочее (46 методов: HAVE 1, PARTIAL 0, MISSING 45)

- Платежи: [MISSING] sendinvoice (31 параметр: prices/payload/provider_data — JSON), createinvoicelink, getmystarbalance, getstartransactions, refundstarpayment, edituserstarsubscription — works-now
- Игры: [MISSING] sendgame, setgamescore, getgamehighscores — works-now
- Подарки: [MISSING] getavailablegifts, sendgift (text/text_parse_mode), giftpremiumsubscription, convertgifttostars, upgradegift, transfergift — works-now
- Сторис: [MISSING] poststory (content — attach:// ⇒ multipart-blocked), repoststory, editstory (multipart-blocked), deletestory
- Бизнес: [MISSING] getbusinessconnection, readbusinessmessage, deletebusinessmessages, setbusinessaccountname/username/bio, setbusinessaccountprofilephoto (multipart-blocked), removebusinessaccountprofilephoto, setbusinessaccountgiftsettings, getbusinessaccountstarbalance, transferbusinessaccountstars, getbusinessaccountgifts — 12/12 works-now
- Токен/сервер: [MISSING] getmanagedbottoken, replacemanagedbottoken, getmanagedbotaccesssettings, setmanagedbotaccesssettings, logout, close — [HAVE] getme (tg_identify → tg_call "getMe", 1497-1504)
- Верификация: [MISSING] verifyuser, verifychat, removeuserverification, removechatverification, setpassportdataerrors (errors JSON) — works-now
- Прочее: [MISSING] savepreparedinlinemessage, savepreparedkeyboardbutton, getforumtopiciconstickers — works-now

ТОП-3: sendInvoice + звёздный биллинг (4 метода вокруг); бизнес-аккаунт 12/12; сторис/фото-профиля — multipart.

## Сектор 5а. Типы апдейтов vs диспетчер (28 полей Update)

- [HANDLED] message — kind 1/2, полный ctx (chat_id/msg_id/from/text/command/args/mine/exclusive); нетекстовое — kind 0 через tg_flt_msg; caption/sticker/reply_to — только через tg_raw
- [HANDLED] callback_query — kind 3, ctx: cbq_id/data/inline_msg_id/chat_id/msg_id/from; gap: chat_instance, game_short_name, business_connection_id — только через tg_raw
- [HANDLED] update_id — инфраструктура offset'а ✓
- [ACCESSED-PARTIAL] edited_message, channel_post, edited_channel_post, business_message, edited_business_message, guest_message — ловятся только kind=0 catch-all'ем, НО ctx пуст: аксессоры читают `message.*` (1223-1228) ⇒ chat_id/msg_id/text = 0, хендлер обязан лезть в tg_raw
- [ACCESSED-PARTIAL] inline_query (нет аксессоров и answerInlineQuery), chosen_inline_result, shipping_query, pre_checkout_query (нет аксессоров и answer* — платежи не закрыть), purchased_paid_media, poll, poll_answer, my_chat_member, chat_join_request (ни одного аксессора: from/chat/bio/invite_link; нет approve/decline), chat_boost, removed_chat_boost, business_connection, deleted_business_messages, managed_bot, subscription, stopped_message_generation
- [IGNORED] message_reaction, message_reaction_count, chat_member — физически НЕ ПРИХОДЯТ: allowed_updates не передаётся в getUpdates (tg_polling:1553-1556), а по умолчанию эти типы исключены

ТОП-5: allowed_updates (3 типа недоступны физически); kind для edited_message/channel_post/business (ctx пуст); chat_join_request (0 аксессоров); платежные query (цикл не закрывается); business_connection_id нигде не извлекается.

## Сектор 5б. Параметры существующих обёрток (8 обёрток, 61 дыра)

- tg_send_text (1352) / tg_send_to (1366): передают 2 из 16 (chat_id, text) — нет parse_mode, entities, reply_markup, reply_parameters, message_thread_id, disable_notification, protect_content, link_preview_options, business_connection_id и др. (14 дыр каждая)
- tg_edit_text (1409): 3 из 10 — нет parse_mode, entities, reply_markup, link_preview_options, business_connection_id, rich_message (6)
- tg_edit_inline (1420): 2 из 10 — те же 6 (reply_markup критичен: клавиатуру нельзя ни поставить, ни снять при редактировании)
- tg_delete (1435): 2 из 2 — полная ✓
- tg_action (1395): 2 из 4 — нет business_connection_id, message_thread_id (typing в темах форума)
- tg_answer (1376): 2 из 5 — нет show_alert, url, cache_time; text обязателен, хотя в API опционален
- tg_send_photo_url (1445): 2 из 18 — 16 дыр (нет caption, parse_mode, reply_markup, has_spoiler, disable_notification…)
- getUpdates (внутри tg_polling 1553-1557): 2 из 4 — нет allowed_updates, limit

## Сектор 5в. Клавиатуры/хелперы (12 типов: 0 SUPPORTED, 2 MANUAL-JSON, 10 MISSING)

- [MANUAL-JSON] InlineKeyboardMarkup/InlineKeyboardButton — сырой JSON в examples/bot.k:28 через tg_param_json; нет билдера, нет эскейпинга текста кнопок
- [MISSING] ReplyKeyboardMarkup (is_persistent/resize_keyboard/one_time_keyboard/input_field_placeholder/selective), KeyboardButton (request_users/request_chat/request_contact/request_location/request_poll/web_app), ReplyKeyboardRemove, ForceReply
- [MISSING] ReplyParameters (message_id/chat_id/allow_sending_without_reply/quote…) + проброс во все send-обёртки — сейчас «ответить на сообщение» невозможно
- [MISSING] LinkPreviewOptions (is_disabled/…) — предпросмотр нельзя отключить
- [MISSING] MessageEntity — только чтение entities у входящего (tg_upd_is_cmd), конструктора отправки нет
- [MISSING] Билдер клавиатур (аналог aiogram builders): add/row/adjust
- [MISSING] tg_html_escape (`<`,`>`,`&`) + поддержка parse_mode="HTML"/"MarkdownV2" — сейчас весь текст обязан быть plain
