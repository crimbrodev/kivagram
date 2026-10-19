# kivagram v2 Wave-3: multipart, вебхуки, экзотические параметры, хвост API

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development + superpowers:dispatching-parallel-agents — W3-0 (ядро) и W3-Int (интеграция) последовательны, W3-1..W3-6 — параллельный фан-аут (по одному субагенту на задачу). Шаги — чекбоксы.

**Goal:** Закрыть волну 3 GAP-дока: загрузка файлов с диска (multipart), getFile+скачивание, webhook-режим (обёртки + HTTP-сервер приёма апдейтов), механизм «экзотических» опциональных параметров для ВСЕХ обёрток, и хвостовые секторы (бизнес, подарки, сторис, игры, верификация, managed bot, boosts, passport, черновики).

**Architecture:** W3-0 добавляет в ядро `lib/tg.k` два транспорта и один механизм, на которые опираются все модули волны:
1. **multipart** — глобальный слот форм + `tg_call_mp(bot, method)` поверх той же retry-логики `tg_call`;
2. **GET/скачивание** — `tg_http_get_file(url, dest)` для цепочки getFile → download;
3. **extras** — глобальный слот `tg_extraslot`, сливаемый в тело внутри `tg_params_done`: ЛЮБАЯ обёртка начинает читать экзотические опциональные параметры без изменения сигнатур.

**Tech Stack:** Kiva (kivac/kivaa `/tmp/opencode/kivac-pr`), curl через popen, сокеты libc подтверждены линковкой (`socket fd=3` — спайк пройден), эталон параметров `/tmp/opencode/ref/api/{methods,types}/*.md`, сеть в тестах — только localhost для webhook-сервера; dry-run `tg_dry_run=1` для композиции.

---

## Зависимости волн

```
W3-0 ядро (1 агент, последовательно — всё остальное зависит от компилируемости)
  lib/tg.k: multipart-слот + tg_call_mp; GET-скачивание; extras-слот в tg_params_done
Gate W3-0: вся матрица 22 тестов PASS + новые t_v3_core PASS
W3-1..W3-6 (6 агентов ПАРАЛЛЕЛЬНО, каждый — свои файлы)
  W3-1 lib/tg_files.k   multipart-методы + getFile/скачивание + attach://   + t_v3_files.k
  W3-2 lib/tg_webhook.k setWebhook/deleteWebhook/getWebhookInfo            + t_v3_webhook.k
  W3-3 lib/tg_wbserve.k HTTP-сервер приёма апдейтов (сокеты)               + t_v3_wbserve.k
  W3-4 lib/tg_business.k бизнес-аккаунт 12 + business_message ctx          + t_v3_business.k
  W3-5 lib/tg_gifts.k   подарки 6 + сторис 4 + игры 3                     + t_v3_gifts.k
  W3-6 lib/tg_tail.k    верификация 5, managed bot 4, boosts 2, passport, черновики/сейв 3, чеклисты 2, профиль/аудио-фильтры + t_v3_tail.k
Gate W3-6: 6 отчётов PASS
W3-Int (1 агент): полная матрица, README, коммиты по модулям
```

Правила собственности как в волне 1: агент создаёт/редактирует ТОЛЬКО свои файлы, git запрещён (коммиты — оркестратор/интегратор), чужие появляющиеся файлы не трогать. W3-1..6 читают W3-0-контракт (спецификацию ниже) из этого плана — их тесты собираются только после landed ядра, но спецификация стабильна.

## Контракт ядра W3-0 (спецификация для всех агентов)

### A. multipart

```k
tg_mpslot[3];            // Buf: накопленные -F фрагменты
tg_mp_reset();           // сброс слота
tg_mf_str(key, val);     // -F 'key=val'  (val эскейпится: ' → '\'' внутри одинарных кавычек)
tg_mf_num(key, n);       // -F 'key=n'
tg_mf_file(key, path);   // -F 'key=@path' (path эскейпится так же)
tg_mp_attach(name);      // ВАЖНО: для attach:// — объявить имя части (пустой -F 'name='); см. ниже
tg_call_mp(bot, method); // тело НЕ передаётся: params строится вызывающим в tg_paramslot
                         // как обычно (chat_id и пр. строковые поля), а файловые поля — в tg_mpslot.
                         // retry/429/409/on_error — та же логика, что в tg_call (рефактор: вынести
                         // общий цикл обработки ответа, НЕ дублировать код ретраев).
                         // dry-run: в tg_composed пишется "<url>|MP <curl -F ... строка>".
```

Реализация curl: `curl -s -m 35 -F 'k=v' -F 'k=@path' 'url'` — каждый -F в одинарных кавычках, `'` внутри значения → `'\''`. Контракт: если значения/пути не эскейпить — инъекция; эскейп обязателен. `tg_mf_file` не проверяет существование файла (curl сам вернёт ошибку).

### B. скачивание

```k
tg_get_file(bot, file_id);        // tg_call getFile → копирует result.file_path в tg_fpath-слот, возврат ptr|0
tg_http_get_file(url, dest_path); // curl -s -m 60 -o <dest> <url>; возврат 1 при curl exit 0 и пустом stderr-коде
tg_download_file(bot, file_path, dest); // URL = bot[1] "/file/bot" bot[0] "/" file_path — через tg_http_get_file
```

### C. extras — экзотические опциональные параметры для всех обёрток

```k
tg_extraslot[3];       // Buf
tg_ex_reset();         // сброс
tg_ex_str(key, val); tg_ex_num(key, n); tg_ex_json(key, json); tg_ex_raw(key, lit);
                       // тонкие обёртки tg_param_*(b,...) в &tg_extraslot
```

`tg_params_done(b)`: если `tg_extraslot[1] > 0` — вставить содержимое extraslot (как есть, с завершающей запятой внутрь тела) перед закрывающей скобкой, затем `tg_ex_reset()`. Контракт: **extras применяются к СЛЕДУЮЩЕМУ вызову обёртки и съедаются автоматически**; вызывающий, не сбросивший слот, съедается следующей обёрткой — документировать: «всегда tg_ex_reset() после использования либо сразу перед обёрткой». `tg_call(bot, method, 0)` напрямую — extras НЕ читаются (только через tg_params_done); документировать.

### D. тест ядра `tests/t_v3_core.k`

Кейсы (dry-run):
1. extras: `tg_ex_reset(); tg_ex_str("business_connection_id","bc1"); tg_send_to(bot,55,"hi");` → в tg_composed тело содержит `,"business_connection_id":"bc1"` перед `}`, слот пуст после вызова.
2. extras + пустые params: прямой `tg_params_reset/done` без параметров с extras → `{"business_connection_id":"bc1"}` (не `,,`).
3. multipart: `tg_mp_reset(); tg_mf_str("chat_id","55"); tg_mf_file("document","/tmp/a b.txt"); tg_call_mp(bot,"sendDocument")` dry → URL `/sendDocument|` + строка `-F 'chat_id=55' -F 'document=@/tmp/a b.txt'`.
4. эскейп: `tg_mf_str("caption","it's")` → `-F 'caption=it'\''s'`.
5. `tg_get_file` — dry: URL `/getFile|`, тело `{"file_id":"x"}`+мок `tg_composed`? — НЕЛЬЗЯ мокать ответ в dry; вместо этого: unit-тест `tg_download_file` URL-композиции через dry GET-режим (см. реализацию: `tg_http_get_file` в dry пишет `GET <url>` в tg_composed — проверка URL `/file/bot123:fake/voice/x.ogg`).

---

## W3-0 (Task 1): ядро — транспорты + extras

**Files:** Modify `lib/tg.k` (эксклюзив), Create `tests/t_v3_core.k`

- [ ] RED: `tests/t_v3_core.k` по контракту D (./build.sh tests/t_v3_core.k /tmp/w3_t → FAIL, записать вывод)
- [ ] Реализация: tg_mpslot-слоты (после HTTP-блока), рефактор общего response-handler из tg_call в `tg_call_common(bot, method)` (retry-цикл 429 ×3, 409 → deleteWebhook, transport error → on_error), `tg_call_mp` = compose URL + popen curl -F + tg_call_common; `tg_http_get_file` (curl -o, сухой режим GET-композиция); extraslot + `tg_ex_*` + модификация `tg_params_done`
- [ ] GREEN: PASS
- [ ] Регрессия: все 22 существующих теста PASS (матрица `for t in tests/t_*.k`)
- [ ] Пример `examples/bot.k` собирается

**Gate W3-0:** регрессия зелёная → оркестратор коммитит ядро одним коммитом и запускает W3-1..W3-6 параллельно.

## W3-2 (Task 3): webhook API-обёртки

**Files:** Create `lib/tg_webhook.k`, `tests/t_v3_webhook.k`

| Обёртка | Метод | Аргументы |
|---|---|---|
| `tg_set_webhook(bot, url, secret)` | setWebhook | url обязателен; secret=0→skip; остальное (certificate — multipart через tg_mf_file+tg_call_mp, ip_address, max_connections, allowed_updates через tg_ex_json, drop_pending_updates через tg_ex_raw) — документируется в шапке + один тестовый кейс с extras: `tg_ex_raw("drop_pending_updates","true")` |
| `tg_delete_webhook(bot, drop_pending)` | deleteWebhook | drop_pending 0/1 → raw true/false (экспортируемая замена внутреннего вызова; внутренний вызов в tg_polling НЕ трогать) |
| `tg_get_webhook_info(bot)` | getWebhookInfo | без параметров, тело `{}` |

Эталоны: setwebhook.md, deletewebhook.md, getwebhookinfo.md. Тест: URL+тела, extras-кейс, `tg_mf_file("certificate","/tmp/cert.pem"); tg_call_mp(bot,"setWebhook")` dry → проверка строки `-F 'certificate=@/tmp/cert.pem'`.

## W3-3 (Task 4): HTTP-сервер приёма апдейтов

**Files:** Create `lib/tg_wbserve.k`, `tests/t_v3_wbserve.k`

Входная точка: `tg_webhook_serve(bot, port, secret*|0)` — блокирующий accept-цикл (как tg_polling, но сокетный):
- `socket(AF_INET,SOCK_STREAM)`, `bind(0.0.0.0,port)`, `listen`, `accept`; обработка EADDRINUSE → on_error + 0; extern: socket/bind/listen/accept/htons/inet_addr/shutdown/close/recv (спайк линковки пройден).
- На соединение: читать запрос до `\r\n\r\n` (лимит 8 КБ заголовка), парсить `Content-Length`, дочитать тело (лимит 1 МБ), ответить `HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok` СРАЗУ (до диспатча — Telegram требует быстрый 200), затем `tg_ctx_build(bot, body)` + диспетчер (вызвать существующую функцию диспатча — изучить в lib/tg.k как tg_polling вызывает хендлеры и переиспользовать ту же точку).
- Если secret задана: заголовок `X-Telegram-Bot-Api-Secret-Token` обязан совпасть, иначе 403 и тело не диспатчится.
- GET/прочие методы → 404. Пустое тело → 400 (и 400 НЕ диспатчится).
- Разбор запроса вынести в чистую функцию `tg_wb_parse(buf, len)` → слот с методом/заголовком-секретом/body-ptr/len (unit-тестить без сети).

Тест `tests/t_v3_wbserve.k` (localhost): unit-парсер (сырые строки запросов: валидный POST, отсутствие Content-Length, секрет-матч/мимо, обрезанное тело) + живой мини-тест: запуск сервера в фоне НЕЛЬЗЯ (нет fork в тесте?) — РЕШЕНИЕ: сервер тестируется последовательным `tg_wb_step(bot)` — вынести одну итерацию (poll-одного соединения с таймаутом через select/setsockopt SO_RCVTIMEO) в отдельную функцию, `tg_webhook_serve` = while(tg_wb_step). Тест: серверный сокет на эфемерном порту (bind port 0 + getsockname? — если сложно, фиксированный 18081 + повтор при EADDRINUSE), затем клиентский curl через popen POST на localhost с валидным/невалидным секретом, проверка что диспетчер получил апдейт (лог-слот как в t_dispatch) и статусы 200/403. Если сеть/сокеты недоступны в окружении — тест печатает `FAIL: no network` (конвенция t_http).

## W3-1 (Task 2): файловые методы (multipart)

**Files:** Create `lib/tg_files.k`, `tests/t_v3_files.k`

| Обёртка | Метод | Механика |
|---|---|---|
| `tg_send_document_file(bot, chat_id, path, caption)` | sendDocument | mp: chat_id + document=@path (+caption); caption — mp-поле |
| `tg_send_photo_file(bot, chat_id, path, caption)` | sendPhoto | аналогично |
| `tg_send_audio_file(bot, chat_id, path, caption)` | sendAudio | |
| `tg_send_video_file(bot, chat_id, path, caption)` | sendVideo | |
| `tg_send_voice_file(bot, chat_id, path, caption)` | sendVoice | |
| `tg_send_video_note_file(bot, chat_id, path)` | sendVideoNote | |
| `tg_send_animation_file(bot, chat_id, path, caption)` | sendAnimation | |
| `tg_send_sticker_file(bot, chat_id, path)` | sendSticker | |
| `tg_send_media_group_files(bot, chat_id, paths_json, media_json)` | sendMediaGroup | media JSON внутри ссылается `attach://имя`; пути — `tg_mf_file(имя,path)`; имена parts: "file0","file1"... генерируются: paths_json — JSON-массив путей, media_json — массив InputMedia со ссылками; упрощение v1: пути идут по порядку и media_json обязан ссылаться на file0..fileN |
| `tg_send_live_photo_file(bot, chat_id, vpath, ppath)` | sendLivePhoto | live_photo=@vpath, photo=@ppath |
| `tg_set_chat_photo_file(bot, chat_id, path)` | setChatPhoto | |
| `tg_set_profile_photo_file(bot, path)` | setMyProfilePhoto | business_connection_id — extras |
| `tg_upload_sticker_file(bot, sticker_format, path)` | uploadStickerFile | возврат — file_id из ответа (копия result в слот) |
| `tg_get_file(bot, file_id)` + `tg_download_file(bot, file_path, dest)` | getFile | из контракта B ядра |
| `tg_edit_media_attach(bot, chat_id, msg_id, media_json, attach_name, path)` | editMessageMedia | media_json с `attach://имя` + mp |
| `tg_post_story_file(bot, content_json, path)` / `tg_edit_story_file(...)` | poststory/editstory | content с attach:// |

Тест (dry): URL + MP-строка `-F 'chat_id=55' -F 'document=@/tmp/x.txt'` на каждую обёртку; caption уходит mp-полем (`-F 'caption=...'`); media-group: проверка состава частей и тела; скачивание: URL композиции `/file/bot.../`.

## W3-4 (Task 5): бизнес-аккаунт

**Files:** Create `lib/tg_business.k`, `tests/t_v3_business.k`

12 методов (эталоны по .md, все works-now кроме фото): `tg_get_business_connection(bot, conn_id)`, `tg_read_business_message(bot, conn_id, chat_id, msg_id)`, `tg_delete_business_messages(bot, conn_id, msg_ids_json)`, `tg_set_business_name(bot, conn_id, name)`, `tg_set_business_username(bot, conn_id, username)`, `tg_set_business_bio(bot, conn_id, bio)`, `tg_set_business_profile_photo(bot, conn_id, path)` (multipart), `tg_remove_business_profile_photo(bot, conn_id)`, `tg_set_business_gift_settings(bot, conn_id, json)`, `tg_get_business_star_balance(bot, conn_id)`, `tg_transfer_business_stars(bot, conn_id, star_count)`, `tg_get_business_gifts(bot, conn_id, filters_json)`.

Плюс диспетчерная часть: kind 11 `business_message` + 12 `edited_business_message` — минимально: регистрация `tg_on_business(bot,name,fn)`, аксессор `tg_business_conn(ctx)` уже есть (слот 17); chat_id/text из `business_message.*` — расширить tg_ctx_build (ФАЙЛ lib/tg.k! НЕЛЬЗЯ волне W3-4 — перенесено в W3-Int либо в W3-0... РЕШЕНИЕ: kind 11/12 делает W3-0 в ядре сразу (см. ниже дополнение к W3-0), а W3-4 только методы. Если kind не нужен тестировщику — методы тестируются сами по себе).

Дополнение к W3-0 (включено в Task 1): kind 11 `business_message`, 12 `edited_business_message` — ctx как kind 1/4, но пути `business_message.*`/`edited_business_message.*`; `tg_on_business`/`tg_on_business_edited`; тест в t_v3_dispatch.k? — существующий тест не трогаем (W3-0 в своём t_v3_core.k добавляет 2 кейса: kind и вызов хендлера).

## W3-5 (Task 6): подарки, сторис, игры

**Files:** Create `lib/tg_gifts.k`, `tests/t_v3_gifts.k`

Подарки (6): `tg_get_available_gifts(bot)`, `tg_send_gift(bot, gift_id, user_id, text)` (text=0→skip), `tg_gift_premium(bot, gift_id, month_count, star_count, text)` (text=0→skip), `tg_gift_to_stars(bot, owned_gift_id)`, `tg_upgrade_gift(bot, owned_gift_id, star_count)`, `tg_transfer_gift(bot, owned_gift_id, new_owner_id, star_count)`.
Сторис (4, JSON-only): `tg_post_story(bot, content_json, active_period)`, `tg_repost_story(bot, story_msg_id, more_content_json*|0)`, `tg_edit_story(bot, story_msg_id, content_json, active_period)`, `tg_delete_story(bot, story_msg_id)`.
Игры (3): `tg_send_game(bot, chat_id, game_short_name)`, `tg_set_game_score(bot, user_id, score, msg_id|inline_msg_id*)`, `tg_get_game_highscores(bot, user_id, msg_id|inline_msg_id*)` — msg_id/inline_msg_id: 0-контракт (ровно один ненулевой).
Тест: URL+тела, 0-кейсы.

## W3-6 (Task 7): хвост API

**Files:** Create `lib/tg_tail.k`, `tests/t_v3_tail.k`

Верификация (5): `tg_verify_user(bot, user_id, custom_description)`, `tg_verify_chat(bot, chat_id, custom_description)`, `tg_unverify_user`, `tg_unverify_chat`, `tg_passport_errors(bot, errors_json)`.
Managed bot (4): `tg_get_managed_token(bot)`, `tg_replace_managed_token(bot)`, `tg_get_managed_access(bot)`, `tg_set_managed_access(bot, json)`.
Boosts (2): `tg_get_user_boosts(bot, chat_id, user_id)`, `tg_get_chat_boosts(bot, chat_id)`.
Черновики/сейв (3): `tg_save_inline_message(bot, button_json*|0, content_json)`, `tg_save_keyboard_button(bot, button_json*|0)` (сверить .md: параметры именованные), `tg_set_passport_errors` — уже passport выше, не дублировать.
Прочее: `tg_get_topic_icons(bot)` — уже в форум-модуле (не дублировать!), `tg_remove_profile_photo(bot)` (removeMyProfilePhoto), business gifts фильтры — уже в W3-4. Чеклисты (2): `tg_send_checklist(bot, chat_id, title, tasks_json)`, `tg_edit_checklist(bot, chat_id, msg_id, tasks_json)`.
Плюс «профиля-фильтры» из GAP: `tg_get_user_personal_messages(bot, user_id, limit)`, `tg_get_user_gifts(bot, user_id, filters_json)`, `tg_get_chat_gifts(bot, chat_id, filters_json)`.
Тест: URL+тела по каждому методу (сверять .md — параметры именованные, многие опциональны).

## W3-Int (Task 8): интеграция

**Files:** Modify по необходимости (интероп), README.md, docs/superpowers/plans/... (галочки)
- [ ] Полная матрица `for t in tests/t_*.k` → все PASS; фиксы интероп в файлах виновников
- [ ] `examples/bot.k` собирается; webhook-смоук: собрать `examples/webhook_bot.k` (мини-пример: set_webhook + serve на 8443 с секретом, echo-хендлер) — сборка + `test -x`; живой прогон НЕ обязателен (нужен реальный токен/домен)
- [ ] Проверка токена grep-паттерном
- [ ] Коммиты по модулям (по одному на пару файлов, ядро уже закоммичено)
- [ ] README: секции «multipart», «Webhook-режим», «Экзотические параметры (extras)» + обновить «Вне скоупа»
- [ ] Финальный `git log`, чистый `git status`

**Self-review:** волна 3 GAP закрыта полностью (multipart, getFile+скачивание, sticker-загрузка, вебхук-набор + сервер, бизнес 12, подарки 6, сторис 4, игры 3, верификация 5, managed 4, boosts 2, passport, черновики, чеклисты, профиль-фильтры); экзотические параметры доступны во ВСЕХ обёртках через extras без ломки сигнатур; каждый новый файл имеет свой тест; ни одна задача не редактирует чужой файл.
