// lib/tg_stickers.k — стикер-наборы Bot API (волна v2, 15 обёрток):
// createNewStickerSet, addStickerToSet, getStickerSet, setStickerEmojiList,
// setStickerKeywords, setStickerMaskPosition, setStickerPositionInSet,
// deleteStickerFromSet, setStickerSetTitle, setStickerSetThumbnail,
// deleteStickerSet, deleteChatStickerSet, replaceStickerInSet,
// getCustomEmojiStickers, setCustomEmojiStickerSetThumbnail.
//
// Опирается ТОЛЬКО на ядро lib/tg.k (не дублирует): tg_param_str/num/json/raw,
// tg_params_reset/done, tg_call, tg_ex_* (extras), tg_composed/tg_dry_run.
//
// МУЛЬТИПАРТ (здесь НЕ реализуется и НЕ дублируется): загрузка файла стикера
// в набор идёт через уже существующие средства —
//   tg_upload_sticker_file(bot, user_id, sticker_format, path)  (lib/tg_files.k)
//     → возвращает file_id (слот tg_upfid), который подставляется в
//       stickers_json / sticker / old_sticker / thumbnail;
//   tg_mf_file / tg_call_mp                                     (ядро lib/tg.k)
//     → сырой multipart, если поле обязано быть файлом, а не file_id.
// Тела этих 15 методов — чистый JSON (file_id/URL/готовый JSON), поэтому
// все обёртки идут через tg_call, а не tg_call_mp.
//
// ===== Контракт параметров (эталон /tmp/opencode/ref/api/methods/*.md) =====
//  - в тело входят ТОЛЬКО поля из .md: неизвестные поля API не шлём;
//  - сигнатуры — по спеке волны (≤6 аргументов с bot). Обязательные поля
//    API, не поместившиеся в сигнатуру, — extras ПЕРЕД вызовом (съедаются
//    tg_params_done автоматически, как в tg_files.k/tg_gifts.k):
//      createNewStickerSet:  sticker_format / sticker_type (0-контракт
//                            строка|0 через tg_stk_opt_str), needs_repainting
//                            (tg_ex_raw("needs_repainting","true"));
//      setStickerSetThumbnail: format (обязателен API!) — tg_stk_opt_str;
//      replaceStickerInSet:   user_id (обязателен API!) — tg_ex_num.
//  - name по эталону ОТСУТСТВУЕТ в setStickerEmojiList / setStickerKeywords /
//    setStickerMaskPosition / setStickerPositionInSet / deleteStickerFromSet /
//    replaceStickerInSet: аргумент name оставлен по спеке волны (контекст
//    набора, единообразие вызова) и в тело НЕ входит;
//  - tg_set_sticker_thumb: 2-й аргумент — user_id владельца набора (в спеке
//    волны назван `sticker`: поля sticker у setStickerSetThumbnail нет,
//    позиция в ref = user_id);
//  - thumb=0 → снятие через tg_param_raw с литералом null: "thumbnail":null /
//    "custom_emoji_id":null (БЕЗ кавычек у значения). NB по эталону:
//    setStickerSetThumbnail снимает thumbnail ОПУСКАНИЕМ параметра,
//    setCustomEmojiStickerSetThumbnail — пустой строкой; null шлём по спеке
//    волны (параметр с тем же именем, что в эталоне: `sticker_set_thumbnail`
//    в Bot API НЕ существует — канонический ключ `thumbnail`);
//  - chat_id — числовой (конвенция всех модулей; @username — через tg_call);
//  - keywords_json / mask_pos_json = 0 → поле не передаётся (для
//    mask_position это и есть «снять позицию» — ref: omit removes it).
//
// ===== emoji_list (setStickerEmojiList) =====
// Аргумент emojis — строка в двух формах:
//   "[\"а\",\"б\"]"  — готовый JSON-массив: уходит как есть (tg_param_json);
//   "а,б"            — простая строка: собирается массив, КАЖДЫЙ элемент
//                      проходит tg_json_escape (кавычки/слэш — \", \\,
//                      UTF-8 как есть), разделитель — запятая без обрезки.
// Элемент, содержащий запятую, — только в JSON-форме. Пустой аргумент (0) —
// поле не передаётся (Telegram вернёт 400: поле обязательное).

// tg_stk_ebuf[128] — 1024 байта: копия простой строки emojis под разбиение
// на элементы (split ставит NUL в копию, исходная строка не трогается)
tg_stk_ebuf[128];

// tg_stk_opt_str(key, val): extras с 0-контрактом — val=0 → поле НЕ
// задаётся (tg_ex_str(0) недопустим: tg_json_escape разыменовал бы 0)
tg_stk_opt_str(key, val) {
    if val != 0 {
        tg_ex_str(key, val);
    }
    1;
}

// tg_stk_elist(b, key, s): поле-массив строк (см. шапку): '[' → сырой JSON,
// иначе "a,b" → ["a","b"] с tg_json_escape на элемент; 0 → не передаётся.
// Пишет "key":[...] с завершающей запятой — как прочие tg_param_*.
tg_stk_elist(b, key, s) {
    auto p;
    auto e;
    auto c;
    auto saved;
    auto first;
    auto done;
    auto seg;
    if s != 0 {
        if @8 *s == 91 {
            tg_param_json(b, key, s);
        } else {
            // копия в tg_stk_ebuf с отсечкой по границе буфера
            p = &tg_stk_ebuf;
            c = @8 *s;
            done = 0;
            while done == 0 {
                if c == 0 done = 1;
                else if p >= &tg_stk_ebuf + 1000 done = 1;
                else {
                    *p !8 c;
                    p = p + 1;
                    s = s + 1;
                    c = @8 *s;
                }
            }
            *p !8 0;
            // "key":[
            tg_buf_add(b, "\"");
            tg_buf_add(b, tg_json_escape(key));
            tg_buf_add(b, "\":[");
            p = &tg_stk_ebuf;
            first = 1;
            done = 0;
            while done == 0 {
                // граница сегмента: ',' или конец копии
                e = p;
                seg = 0;
                while seg == 0 {
                    c = @8 *e;
                    if c == 0 seg = 1;
                    else if c == 44 seg = 1;
                    else e = e + 1;
                }
                saved = @8 *e;
                *e !8 0;                    // NUL-терминировать сегмент
                if first == 0 tg_buf_add(b, ",");
                first = 0;
                tg_buf_add(b, "\"");
                tg_buf_add(b, tg_json_escape(p));
                tg_buf_add(b, "\"");
                *e !8 saved;
                if saved == 0 done = 1;
                else p = e + 1;
            }
            tg_buf_add(b, "],");
        }
    }
    1;
}

// ===== 15 обёрток =====

// tg_create_sticker_set(bot, user_id, name, title, stickers_json) —
// createNewStickerSet. stickers_json: JSON-массив 1-50 InputSticker.
// sticker_format/sticker_type (0-контракт строки) и needs_repainting — extras:
//   tg_stk_opt_str("sticker_format", "animated");   // 0 → не передаётся
//   tg_stk_opt_str("sticker_type", "custom_emoji"); // 0 → не передаётся
//   tg_ex_raw("needs_repainting", "true");
tg_create_sticker_set(bot, user_id, name, title, stickers_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "name", name);
    tg_param_str(&tg_paramslot, "title", title);
    if stickers_json != 0 tg_param_json(&tg_paramslot, "stickers", stickers_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "createNewStickerSet", body);
}

// tg_add_sticker(bot, user_id, name, sticker) — addStickerToSet.
// sticker: JSON-объект InputSticker → tg_param_json (без кавычек, как есть)
tg_add_sticker(bot, user_id, name, sticker) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    tg_param_str(&tg_paramslot, "name", name);
    if sticker != 0 tg_param_json(&tg_paramslot, "sticker", sticker);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "addStickerToSet", body);
}

// tg_get_sticker_set(bot, name) — getStickerSet
tg_get_sticker_set(bot, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getStickerSet", body);
}

// tg_set_sticker_emojis(bot, name, sticker, emojis) — setStickerEmojiList.
// name в методе по эталону нет — в тело не входит; форматы emojis — в шапке.
tg_set_sticker_emojis(bot, name, sticker, emojis) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    tg_stk_elist(&tg_paramslot, "emoji_list", emojis);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerEmojiList", body);
}

// tg_set_sticker_keywords(bot, name, sticker, keywords_json) —
// setStickerKeywords; keywords_json=0 → поле не передаётся
tg_set_sticker_keywords(bot, name, sticker, keywords_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    if keywords_json != 0 tg_param_json(&tg_paramslot, "keywords", keywords_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerKeywords", body);
}

// tg_set_sticker_mask_pos(bot, name, sticker, mask_pos_json) —
// setStickerMaskPosition; mask_pos_json=0 → параметр ОПУЩЕН (ref: omit
// снимает позицию); mask_position: JSON-объект MaskPosition
tg_set_sticker_mask_pos(bot, name, sticker, mask_pos_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    if mask_pos_json != 0 tg_param_json(&tg_paramslot, "mask_position", mask_pos_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerMaskPosition", body);
}

// tg_set_sticker_pos(bot, name, sticker, position) — setStickerPositionInSet
tg_set_sticker_pos(bot, name, sticker, position) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    tg_param_num(&tg_paramslot, "position", position);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerPositionInSet", body);
}

// tg_del_sticker(bot, name, sticker) — deleteStickerFromSet
tg_del_sticker(bot, name, sticker) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "sticker", sticker);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteStickerFromSet", body);
}

// tg_set_sticker_title(bot, name, title) — setStickerSetTitle
tg_set_sticker_title(bot, name, title) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    tg_param_str(&tg_paramslot, "title", title);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerSetTitle", body);
}

// tg_set_sticker_thumb(bot, name, user_id, thumb) — setStickerSetThumbnail.
// user_id — владелец набора (2-й аргумент спеки волны, см. шапку);
// thumb — file_id: tg_param_str; thumb=0 → снять: "thumbnail":null;
// format (обязателен API) — extras: tg_stk_opt_str("format","static")
tg_set_sticker_thumb(bot, name, user_id, thumb) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    tg_param_num(&tg_paramslot, "user_id", user_id);
    if thumb == 0 {
        tg_param_raw(&tg_paramslot, "thumbnail", "null");
    } else {
        tg_param_str(&tg_paramslot, "thumbnail", thumb);
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setStickerSetThumbnail", body);
}

// tg_del_sticker_set(bot, name) — deleteStickerSet
tg_del_sticker_set(bot, name) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteStickerSet", body);
}

// tg_del_chat_sticker_set(bot, chat_id) — deleteChatStickerSet.
// chat_id числовой (конвенция модулей); @username — через tg_call напрямую
tg_del_chat_sticker_set(bot, chat_id) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "deleteChatStickerSet", body);
}

// tg_replace_sticker(bot, name, old_sticker, new_sticker_json) —
// replaceStickerInSet; new_sticker_json = объект InputSticker.
// user_id (обязателен API!) — extras: tg_ex_num("user_id", uid) перед вызовом
tg_replace_sticker(bot, name, old_sticker, new_sticker_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    tg_param_str(&tg_paramslot, "old_sticker", old_sticker);
    if new_sticker_json != 0 tg_param_json(&tg_paramslot, "sticker", new_sticker_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "replaceStickerInSet", body);
}

// tg_get_custom_emojis(bot, custom_emoji_ids_json) — getCustomEmojiStickers;
// custom_emoji_ids_json: JSON-массив строк (до 200 id)
tg_get_custom_emojis(bot, custom_emoji_ids_json) {
    auto body;
    tg_params_reset(&tg_paramslot);
    if custom_emoji_ids_json != 0 tg_param_json(&tg_paramslot, "custom_emoji_ids", custom_emoji_ids_json);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "getCustomEmojiStickers", body);
}

// tg_set_custom_emoji_thumb(bot, name, thumb) — setCustomEmojiStickerSetThumbnail;
// thumb — custom_emoji_id; thumb=0 → снять: "custom_emoji_id":null
// (NB: ref для снятия также допускает пустую строку "")
tg_set_custom_emoji_thumb(bot, name, thumb) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_str(&tg_paramslot, "name", name);
    if thumb == 0 {
        tg_param_raw(&tg_paramslot, "custom_emoji_id", "null");
    } else {
        tg_param_str(&tg_paramslot, "custom_emoji_id", thumb);
    }
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "setCustomEmojiStickerSetThumbnail", body);
}
