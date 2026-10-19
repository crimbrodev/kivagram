# kivagram v2 Wave-1: Parallel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development with superpowers:dispatching-parallel-agents — Stage A and Stage B tasks run as PARALLEL subagent fan-outs (one subagent per task, all dispatched in a single response per stage), Stage C runs one integration subagent sequentially. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Закрыть «волюму 1» полного gap-анализа Bot API (`docs/GAP-full-api-2026-10-19.md`): параметры существующих обёрток, ~100 новых обёрток методов, билдеры клавиатур, новые типы апдейтов в диспетчере — силами множества параллельных субагентов.

**Architecture:** Библиотека расщепляется с одного файла на слой из `lib/tg.k` (ядро, эксклюзивно у двух задач) + `lib/tg_*.k` (модули, каждый модуль — СОБСТВЕННОСТЬ ровно одного субагента, создаётся только новым файлом). Это делает параллелизм БЕЗКОНФЛИКТНЫМ без git-веток: никто не редактирует чужие файлы, значит merge не нужен. `build.sh` склеивает `lib/tg.k` + все `lib/tg_*.k` (алфавит) + исходник. Git: агенты НЕ работают с git; коммиты делает оркестратор после Stage A и интегратор в Stage C.

**Tech Stack:** язык Kiva (kivac/kivaa из `/tmp/opencode/kivac-pr`), сборка `./build.sh`, эталон параметров — зеркало `/tmp/opencode/ref/api/{methods,types}/*.md`, сеть в тестах запрещена (dry-run: `tg_dry_run=1` → композиция в глобальный `tg_composed`).

---

## Почему НЕ git-ветки

Ветки/merge тут проигрывают: (1) 14 веток добавляют РАЗНЫЕ новые файлы — merge дал бы те же файлы, что и простое добавление, но с накладными расходами worktree+резолва; (2) параллельные `git commit` в одном репо дерутся за `.git/index.lock`; (3) ворктури требуют отдельной сборки тулчейна. Вместо этого — **право собственности на файлы**: конфликт невозможен конструкцией, детект нарушений — `git status` на гейте. Ветка `feat/tg-lib-v1` продолжает нести всю работу; коммиты — серийные, после грин-этапов.

## Волны и гейты

```
Stage A (2 субагента ПАРАЛЛЕЛЬНО)
  A1  build.sh: multi-module склейка          → файл: build.sh
  A2  ядро: tg_param_raw, tg_html_escape      → файлы: lib/tg.k, tests/t_v2_core.k
Gate A: старые 7 тестов PASS + t_v2_core PASS + build.sh без модулей работает
  → оркестратор коммитит A1+A2 одним коммитом, запускает Stage B
Stage B (14 субагентов ПАРАЛЛЕЛЬНО, каждый — своя пара файлов)
  B0  lib/tg.k (эксклюзив): dispatch v2 + allowed_updates   + tests/t_v2_dispatch.k
  B1  lib/tg_media.k   sendAudio/Document/Video/Animation/Voice/VideoNote + t_v2_media.k
  B2  lib/tg_geo.k     sendLocation/Venue/Contact/Dice/Sticker/LivePhoto  + t_v2_geo.k
  B3  lib/tg_poll.k    sendMediaGroup/sendPoll/stopPoll/sendPaidMedia     + t_v2_poll.k
  B4  lib/tg_msg.k     forward*/copy*/edit*/deleteMessages (10)            + t_v2_msg.k
  B5  lib/tg_answers.k answerInlineQuery/PreCheckout/Shipping/WebApp/Guest/JoinRequest (6) + t_v2_answers.k
  B6  lib/tg_kb.k      билдеры клавиатур + reply/link-preview хелперы      + t_v2_kb.k
  B7  lib/tg_admin.k   модерация: баны/restrict/promote/getChat* (13)      + t_v2_admin.k
  B8  lib/tg_chat.k    пины/title/desc/инвайты/leave/join-request (16)     + t_v2_chat.k
  B9  lib/tg_config.k  setMyCommands/имена/описания/меню/права (13)        + t_v2_config.k
  B10 lib/tg_forum.k   форум-топики (13)                                   + t_v2_forum.k
  B11 lib/tg_react.k   реакции + getters + logout/close (8)                + t_v2_react.k
  B12 lib/tg_pay.k     платежи (6)                                         + t_v2_pay.k
  B13 lib/tg_ext.k     расширенные send/edit/answer (6-arg вариант)        + t_v2_ext.k
Gate B: все 14 отчётов с PASS
Stage C (1 субагент ПОСЛЕДОВАТЕЛЬНО)
  C1  интеграция: полная сборка всех тестов, фиксы интеропа, коммиты по модулям, README
```

Каждый Stage-B субагент имеет право создавать ТОЛЬКО свои два файла. Запрещено: редактировать `lib/tg.k`, `build.sh`, чужие `lib/tg_*.k`, существующие `tests/t_*.k`; запускать git; ходить в сеть иначе как в документацию.

## Закон языка (включать в КАЖДЫЙ промпт субагента)

- `auto` — только в начале функции, только скаляры; имена `r11`/`r12` ломают nasm.
- ≤6 аргументов вызова; fn-вызов только через локальную копию; 12–13 локальных работают.
- `<`/`>=` БЕЗЗНАКОВЫЕ: отрицательные сентинелы запрещены (флаги, либо как `tg_hex1` — 16).
- Нет `&&`/`||`; есть `//` и `/* */`; `global main` обязателен; порядок определений (до первого использования).
- Числа — 64-бит, везде `%ld`; `<<` не гарантирован — `* 1024`, `>>` работает.
- Байты: `*p !8 v` запись, `@8 *p` чтение; слоты-массивы — всегда `&слот`; глобал в позиции значения = word0.
- `printf` с вложенными вызовами в аргументах ненадёжен — сначала в локальную.
- scratch общий: `tg_scratch()` сбрасывает — не полагаться на scratch между шагами, копировать через `tg_ctx_put`/слот.
- Формат теста: `PASS`+exit 0 либо `FAIL: <описание>`+exit 1, диагностика через stdout.

## Тест-шаблон (канонический, из `tests/t_methods.k`)

```k
extern printf
extern exit
extern strcmp
extern strstr

fails[1];

chk(cond, name) {
    if cond { 1; } else {
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

    r = <вызов обёртки>;
    chk(r == 1, "<name>: dry-возврат 1");
    chk(strstr(&tg_composed, "/<methodName>|") != 0, "<name>: URL");
    chk(strstr(&tg_composed, "{\"chat_id\":55,...}") != 0, "<name>: тело");

    tg_dry_run = 0;
    if fails[0] == 0 { printf("PASS\n"); exit(0); }
    exit(1);
}
```

`tg_dry_run=1` ⇒ `tg_call` НЕ ходит в сеть, а пишет `URL|тело` в глобальный буфер `tg_composed`. Ожидаемое тело — тот же порядок ключей, что в `tg_params_*`-вызовах обёртки.

## Паттерн обёртки (канонический, из `lib/tg.k`)

```k
// <входящий комментарий: метод, все параметры .md, какие проброшены>
tg_send_document(bot, chat_id, doc, caption) {
    auto body;
    tg_params_reset(&tg_paramslot);
    tg_param_num(&tg_paramslot, "chat_id", chat_id);
    tg_param_str(&tg_paramslot, "document", doc);
    if caption != 0 tg_param_str(&tg_paramslot, "caption", caption);
    body = tg_params_done(&tg_paramslot);
    tg_call(bot, "sendDocument", body);
}
```

Правила: обязательные параметры — аргументы (≤6); ходовые опциональные — аргумент с контрактом `0 = не передавать` (`if x != 0 tg_param_*(...)`); JSON-массивы/объекты (`options`, `permissions`, `prices`, `commands`, `media`, `reaction`) — аргумент-строка через `tg_param_str`? **НЕТ** — через `tg_param_json` (без кавычек): `tg_param_json(&tg_paramslot, "options", "[\"a\",\"b\"]")`. Редкие экзотические опциональные параметры НЕ входят в обёртку v1 — документируй в комментарии: «остальные через `tg_call(bot, "method", params)`».

---

### Task 0 (Stage A1): build.sh — multi-module склейка

**Files:**
- Modify: `build.sh:14` и `build.sh:25`

- [ ] **Step 1: Заменить LIB и строку cat**

Было:
```sh
LIB="$(dirname "$0")/lib/tg.k"
...
cat "$LIB" "$SRC" > build.k
```
Стало:
```sh
LIBDIR="$(dirname "$0")/lib"
MODS=$(ls "$LIBDIR"/tg_*.k 2>/dev/null | LC_ALL=C sort || true)
...
cat "$LIBDIR/tg.k" $MODS "$SRC" > build.k
```
Комментарий в шапке обновить: «склейка lib/tg.k + lib/tg_*.k (модули, алфавит, после ядра) + исходника».

- [ ] **Step 2: Проверка без модулей**

Run: `cd /tmp/opencode/kivagram && ./build.sh tests/t_methods.k /tmp/t_methods && /tmp/t_methods`
Expected: `PASS`, exit 0 (модулей ещё нет — `MODS` пуст, поведение прежнее).

- [ ] **Step 3: Проверка с фиктивным модулем**

Run: `printf 'tg_fake_helper() { 1; }\n' > lib/tg_zzfake.k && ./build.sh tests/t_methods.k /tmp/t_methods && /tmp/t_methods; rm -f lib/tg_zzfake.k /tmp/t_methods /tmp/t_methods.ir build.k`
Expected: `PASS` (модуль подклеился, линковка не сломалась).

- [ ] **Step 4: Смоук старых тестов**

Run: `for t in t_buf t_json t_params t_dispatch t_methods; do ./build.sh tests/$t.k /tmp/$t && /tmp/$t >/dev/null && echo "$t ok"; done`
Expected: все `ok`.

### Task 1 (Stage A2): ядро — tg_param_raw и tg_html_escape

**Files:**
- Modify: `lib/tg.k` (после `tg_param_json`, ~строка 669; `tg_json_escape` — образец для эскейпера, ~строка 69)
- Create: `tests/t_v2_core.k`

**Спецификация:**
- `tg_param_raw(b, key, val)` — как `tg_param_num`, но value уходит строкой ВЕСЬ (без кавычек и эскейпа): для дробных чисел (`latitude=55.75`), bool (`true`/`false`) и готовых литералов. Вызвать `tg_json_escape` НЕ надо.
- `tg_html_escape(src)` — образец `tg_json_escape`: эскейпит `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;` в собственном статическом буфере (как `eb`-буфер у `tg_json_escape`), возвращает указатель на результат. Переполнение — как в образце (обрыв/игнор — согласуй с его семантикой). Комментарий: статический буфер, один активный эскейп за раз.

- [ ] **Step 1: RED — тест `tests/t_v2_core.k`** (шаблон-тест сверху)

Случаи:
```k
tg_param_raw(&tg_paramslot, "latitude", "55.75");
chk(strstr(&tg_params_done(&tg_paramslot), "\"latitude\":55.75") != 0, "raw: дробь без кавычек");
// повторить для "true"; затем tg_param_num сверки: "chat_id":77 с кавычками нет
s = tg_html_escape("a<b>&c");
chk(strcmp(s, "a&lt;b&gt;&c") == 0, "html: < > &");
```
(вложенные вызовы в `strstr`/`strcmp` — через локальную переменную `s`!)

Run: `./build.sh tests/t_v2_core.k /tmp/t_v2_core && /tmp/t_v2_core`
Expected: `FAIL: ...` (функций нет), exit 1.

- [ ] **Step 2: Реализация в `lib/tg.k`** (после `tg_param_json` / рядом с `tg_json_escape`), повтор Step 1.
Expected: `PASS`, exit 0.

- [ ] **Step 3: Регрессия**

Run: `for t in t_buf t_json t_params t_http t_dispatch t_methods t_poll_smoke t_v2_core; do ./build.sh tests/$t.k /tmp/$t && /tmp/$t >/dev/null && echo "$t ok" || echo "$t FAIL"; done`
Expected: 8 × `ok`.

**Gate A:** после Step 3 — оркестратор: `git add build.sh lib/tg.k tests/t_v2_core.k && git commit -m "Build multi-module lib and add raw/html param helpers for v2 waves"`.

---

## Stage B — 14 параллельных субагентов

### Промпт-шаблон Stage-B субагента (вставить в каждый промпт)

```
Ты — субагент-модуль kivagram v2. РАБОТА В РЕПО: /tmp/opencode/kivagram (ветка feat/tg-lib-v1).
ТВОЯ СОБСТВЕННОСТЬ (создать, редактировать только их): <ФАЙЛ1>, <ФАЙЛ2>.
ЗАПРЕЩЕНО трогать ЛЮБЫЕ другие файлы: lib/tg.k, build.sh, чужие lib/tg_*.k, существующие tests/*.k.
ЗАПРЕЩЕНО любые git-команды. ЗАПРЕЩЕНА сеть (кроме чтения /tmp/opencode/ref).
ЭТАЛОН параметров каждого метода: /tmp/opencode/ref/api/methods/<имя>.md — ЧИТАЙ и реализуй ВСЕ обязательные
+ ходовые опциональные параметры по контракту этого плана (см. «Паттерн обёртки»).
Шаблоны для образца: обёртки — lib/tg.k (tg_send_text, tg_delete, tg_action, tg_answer);
тест — tests/t_methods.k (dry-run, tg_composed, chk, PASS/exit0).
ЯЗЫКОВЫЕ ЛОВУШКИ: <вставить «Закон языка»>.
TDD: сначала тест (RED: ./build.sh tests/<T> /tmp/<T> && /tmp/<T> → FAIL), потом обёртки (GREEN).
Прогоняй свой тест и СТАРЫЙ tests/t_methods.k (не сломал ядро).
ОТЧЁТ (финальное сообщение): файлы, список функций, вывод «PASS», итоговые строки RED и GREEN.
```

### Task 2 (B0): ядро — диспетчер v2 + allowed_updates

**Files:** Modify `lib/tg.k` (эксклюзивно!), Create `tests/t_v2_dispatch.k`

**Спецификация:**
- Новые kind (после 3): `4` edited_message, `5` channel_post (+edited_channel_post), `6` my_chat_member, `7` chat_join_request, `8` inline_query, `9` pre_checkout_query, `10` shipping_query. Логика `tg_upd_kind`: проверять поля ВЕРХНЕГО уровня через `tg_get(upd, "edited_message.text")` и т.д. (не забыть: kind 1/2/3 существующие не менять, приоритет: callback > message > остальные).
- `tg_ctx_build`: для kind 4/5 строить ctx из `edited_message.*`/`channel_post.*` (копия текста, chat_id, msg_id — рефактор локальной переменной-префикса пути); для 7/8/9/10 — минимальный ctx (chat_id/from_id из payload, kind), аксессоры ниже.
- Регистрация: `tg_on_edited(bot, name, fn)`, `tg_on_channel`, `tg_on_membership`, `tg_on_join_request`, `tg_on_inline`, `tg_on_payment` (по образцу `tg_on_text` через `tg_reg`).
- Новые аксессоры: `tg_inline_query(ctx)` (query), `tg_join_chat_id(ctx)`, `tg_join_user_id(ctx)`, `tg_pcq_id(ctx)` (pre_checkout id), `tg_ship_id(ctx)` + `tg_business_conn(ctx)` (ctx-слот: расширить Ctx с 17 до 18 слов — `malloc` в `tg_ctx_build`, слот 17 `business_connection_id*`, аксессор читает `tg_get_str(upd, "business_connection_id")` при наличии).
- `allowed_updates`: слот-глобал `tg_allowed_upd[3]` (Buf) + `tg_allow_updates_add(str)`; в `tg_polling` при построении тела getUpdates — если Buf непустой, добавить параметр `allowed_updates` через `tg_param_json`. Контракт: по умолчанию НЕ передаётся (поведение v1 сохраняется).
- Тест `tests/t_v2_dispatch.k`: минимальный — на синтетических апдейтах `{"update_id":7,"edited_message":{...}}`, `{"update_id":8,"chat_join_request":{...}}`, `{"update_id":9,"inline_query":{...}}` проверить kind (через `tg_upd_kind`), вызов своего хендлера (dry-run лог-слот как в `tests/t_dispatch.k`), аксессоры; существующие kind 1/2/3 — 3 проверки «не сломано».

- [ ] RED → [ ] Реализация → [ ] GREEN: `./build.sh tests/t_v2_dispatch.k /tmp/t_d && /tmp/t_d` → PASS
- [ ] Регрессия: `for t in t_buf t_json t_params t_http t_dispatch t_methods t_poll_smoke t_v2_core; do ...; done` → 8 ok

### Task 3 (B1): медиа-1

**Files:** Create `lib/tg_media.k`, `tests/t_v2_media.k`

| Обёртка | .md | Аргументы (≤6) |
|---|---|---|
| `tg_send_audio(bot, chat_id, audio, caption)` | sendaudio | + duration/performer/title — через 0-аргументы? НЕТ: уместись: `(bot, chat_id, audio, caption)`; performer/title — коммент «через tg_call» |
| `tg_send_document(bot, chat_id, doc, caption)` | senddocument | все обязательные ✓ |
| `tg_send_video(bot, chat_id, video, caption)` | sendvideo | |
| `tg_send_animation(bot, chat_id, anim, caption)` | sendanimation | |
| `tg_send_voice(bot, chat_id, voice, caption)` | sendvoice | |
| `tg_send_video_note(bot, chat_id, vnote, duration)` | sendvideonote | |

`parse_mode` не пробрасывать (нет ещё HTML-цепочки) — коммент в шапке файла: «parse_mode — через tg_sendx (lib/tg_ext.k) либо tg_call».

Тест: по 2 chk на обёртку (URL `/sendAudio|` + тело `{"chat_id":55,"audio":"file-1","caption":"привет"}`), плюс кейс `caption=0 → в теле caption отсутствует`.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 4 (B2): гео/стикер/контакт

**Files:** Create `lib/tg_geo.k`, `tests/t_v2_geo.k`

| Обёртка | .md | Аргументы |
|---|---|---|
| `tg_send_location(bot, chat_id, lat, lng)` | sendlocation | `lat`/`lng` — строки, через `tg_param_raw` (дробь без кавычек) |
| `tg_send_venue(bot, chat_id, lat, lng, title, address)` | sendvenue | 6 аргументов ✓ |
| `tg_send_contact(bot, chat_id, phone, first_name, last_name)` | sendcontact | last_name=0 → skip |
| `tg_send_dice(bot, chat_id, emoji)` | senddice | emoji=0 → skip (дефолт TG) |
| `tg_send_sticker(bot, chat_id, sticker)` | sendsticker | |
| `tg_send_live_photo(bot, chat_id, live_photo, photo)` | sendlivephoto | live_photo=0 → skip |

Тест: тело `{"chat_id":55,"latitude":55.75,"longitude":37.62}` (КРИТИЧНО: числа без кавычек), `{"chat_id":55,"phone_number":"+7000","first_name":"A"}` при last_name=0, и т.д.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 5 (B3): альбомы/опросы/платные медиа

**Files:** Create `lib/tg_poll.k`, `tests/t_v2_poll.k`

| Обёртка | .md | Аргументы |
|---|---|---|
| `tg_send_media_group(bot, chat_id, media_json)` | sendmediagroup | media — JSON-массив через `tg_param_json` |
| `tg_send_poll(bot, chat_id, question, options_json)` | sendpoll | `is_anonymous`/`type`/`allows_multiple_answers` — через 0-флаги НЕ входят (коммент: через tg_call), обязательные + options ✓ |
| `tg_stop_poll(bot, chat_id, msg_id)` | stoppoll | |
| `tg_send_paid_media(bot, chat_id, star_count, media_json)` | sendpaidmedia | |

Тест: `{"chat_id":55,"media":"..."}`? НЕТ — media через tg_param_json входит в тело БЕЗ кавычек: `{"chat_id":55,"media":[{\"type\":\"photo\"...]}`; опрос: `{"chat_id":55,"question":"чё?","options":[\"а\",\"б\"]}`.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 6 (B4): пересылка/копия/правки/массовое удаление

**Files:** Create `lib/tg_msg.k`, `tests/t_v2_msg.k`

| Обёртка | .md | Аргументы |
|---|---|---|
| `tg_forward(bot, chat_id, from_chat_id, msg_id)` | forwardmessage | |
| `tg_forward_many(bot, chat_id, from_chat_id, ids_json)` | forwardmessages | |
| `tg_copy(bot, chat_id, from_chat_id, msg_id, caption)` | copymessage | caption=0 → skip |
| `tg_copy_many(bot, chat_id, from_chat_id, ids_json)` | copymessages | |
| `tg_edit_caption(bot, chat_id, msg_id, caption)` | editmessagecaption | |
| `tg_edit_markup(bot, chat_id, msg_id, markup_json)` | editmessagereplymarkup | markup=0 → убрать кнопки (передать `"null"`? — НЕТ: `tg_param_raw(b,"reply_markup","null")` — спроектировать: 0 ⇒ `tg_param_raw(..., "null")` снимает клавиатуру) |
| `tg_edit_media(bot, chat_id, msg_id, media_json)` | editmessagemedia | |
| `tg_edit_live_loc(bot, chat_id, msg_id, lat, lng)` | editmessagelivelocation | lat/lng — raw-строки |
| `tg_stop_live_loc(bot, chat_id, msg_id)` | stopmessagelivelocation | |
| `tg_delete_many(bot, chat_id, ids_json)` | deletemessages | |

Тест: по 1-2 chk на обёртку (тела из паттерна), отдельный кейс `tg_edit_markup(bot,55,42,0)` → тело содержит `"reply_markup":null`.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 7 (B5): ответы (inline/платежи/webapp/guest/join)

**Files:** Create `lib/tg_answers.k`, `tests/t_v2_answers.k`

| Обёртка | .md | Аргументы |
|---|---|---|
| `tg_answer_inline(bot, query_id, results_json)` | answerinlinequery | + cache_time/is_personal/next_offset — коммент «через tg_call» |
| `tg_answer_pre_checkout(bot, pcq_id, ok, error_msg)` | answerprecheckoutquery | ok — 0/1 → `tg_param_raw(..., "true"/"false")`; НЕ передавать ok=1 (по API: ok обязателен — передавать всегда: 1→"true", 0→"false" + error_msg) |
| `tg_answer_shipping(bot, ship_id, ok, options_json)` | answershippingquery | |
| `tg_answer_webapp(bot, webapp_query_id, result_json)` | answerwebappquery | |
| `tg_answer_guest(bot, guest_query_id, result_json)` | answerguestquery | |
| `tg_answer_join_request(bot, chat_id, user_id, approve)` | answerchatjoinrequestquery | params: chat_id+user_id — но .md говорит chat_join_request_query_id+result! ПРОВЕРИТЬ .md: если нужен именно query_id — подпись `tg_answer_join_request(query_id, approve)`; результат `"approve"`/`"decline"` raw-строкой |

Тест: `{"callback...}` нет; тела `{"inline_query_id":"q1","results":[...]}`, `{"pre_checkout_query_id":"p1","ok":true}`, `{"guest_query_id":"g1","result":...}`.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 8 (B6): клавиатуры и reply-хелперы

**Files:** Create `lib/tg_kb.k`, `tests/t_v2_kb.k`

| Функция | Назначение |
|---|---|
| `tg_kb_init(b)` = `tg_params_reset(b)` алиас? НЕТ — свой Buf: `kb[1]`-слот пользователя; функции пишут в переданный Buf-слот как `tg_param_*`, но с собственным форматом |
| `tg_kb_begin(b)` | сброс пользовательского слота-буфера (`tg_buf_reset`) |
| `tg_kb_btn(b, text, data)` | добавить кнопку `{"text":..,"callback_data":..}` (текст — `tg_json_escape`) |
| `tg_kb_url_btn(b, text, url)` | `{"text":..,"url":..}` |
| `tg_kb_row(b)` | завершить текущий ряд: вставка `],` в формат массива (реализация — на усмотрение: накопление строк через `tg_buf_add`: формат хранения: ряды склеивать вручную) |
| `tg_kb_done(b)` → строка | финализировать в `{"inline_keyboard":[[...]]}` |
| `tg_rkb_begin/row/btn/done` | reply-клавиатура: `{"keyboard":[[...]],"resize_keyboard":true}` |
| `tg_kb_remove()` → `{"remove_keyboard":true}` (строковый литерал-возврат) | |
| `tg_kb_force_reply(placeholder)` → `{"force_reply":true,...}` placeholder=0 → без поля | |
| `tg_reply_params(msg_id)` → `{"message_id":N}`-строка для tg_param_json("reply_parameters", ...) | |
| `tg_link_preview_off()` → `{"is_disabled":true}` | |

Схема накопления — как `tg_buf_*` (Buf слот: word0=count? смотреть tg_buf_add): пользуйся `tg_buf_add` с текстовыми кусками, эскейп текста кнопки — `tg_json_escape`.

Тест: `tg_kb_begin(&b); tg_kb_btn(&b,"М","greet"); tg_kb_row(&b); tg_kb_btn(&b,"Go","http://x"); s=tg_kb_done(&b);` → `{"inline_keyboard":[[{"text":"М","callback_data":"greet"}],[{"text":"Go","url":"http://x"}]]}`; remove/force_reply/reply_params/link_preview_off — по chk на каждый; kb-кнопка с кавычкой в тексте эскейпится.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 9 (B7): модерация и участники

**Files:** Create `lib/tg_admin.k`, `tests/t_v2_admin.k`

Обёртки (все `tg_adm_*` не нужны — имена методов): `tg_ban(bot, chat_id, user_id)`, `tg_unban(bot, chat_id, user_id)`, `tg_restrict(bot, chat_id, user_id, perms_json)`, `tg_promote(bot, chat_id, user_id, rights_json)` (rights=0 → только title-less базовый... .md: все опциональны — rights_json=0 ⇒ не передавать), `tg_ban_sender_chat`, `tg_unban_sender_chat`, `tg_get_chat_member(bot, chat_id, user_id)`, `tg_get_member_count(bot, chat_id)`, `tg_get_chat(bot, chat_id)`, `tg_get_admins(bot, chat_id)`, `tg_set_permissions(bot, chat_id, perms_json)`, `tg_set_member_tag(bot, chat_id, user_id, tag)`, `tg_set_admin_title(bot, chat_id, user_id, title)` = 13.

Тест: по 1 chk-телу на обёртку + спецкейсы: `tg_restrict` с `perms_json` → тело `{"chat_id":55,"user_id":9,"permissions":{"can_send_messages":false}}` (внутри — НЕ кавыченная строка!).
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 10 (B8): управление чатом

**Files:** Create `lib/tg_chat.k`, `tests/t_v2_chat.k`

16 обёрток: `tg_pin(bot, chat_id, msg_id)`, `tg_unpin(bot, chat_id, msg_id)` (msg_id=0 → без него — unpin без message_id отпинивает все? .md: опционален — 0 ⇒ skip), `tg_unpin_all(bot, chat_id)`, `tg_set_title(bot, chat_id, title)`, `tg_set_description(bot, chat_id, desc)` (desc=0 → skip), `tg_set_chat_photo(bot, chat_id, file_id)`, `tg_del_chat_photo(bot, chat_id)`, `tg_set_chat_sticker_set(bot, chat_id, set_name)`, `tg_leave(bot, chat_id)`, `tg_export_invite(bot, chat_id)`, `tg_create_invite(bot, chat_id, name)` (name=0→skip), `tg_edit_invite(bot, chat_id, link, name)`, `tg_revoke_invite(bot, chat_id, link)`, `tg_approve_join(bot, chat_id, user_id)`, `tg_decline_join(bot, chat_id, user_id)`, `tg_get_chat_admins`? — уже в B7 — ИСКЛЮЧИТЬ (не дублировать), заменить на `tg_create_subscription_invite(bot, chat_id, link?...)` — свериться с .md (subscription_period/price обязательны): `tg_create_subscription_invite(bot, chat_id, period, price)`.

Тест: тела по паттерну; `tg_unpin(bot,55,0)` → `{"chat_id":55}`.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 11 (B9): конфиг бота и меню команд

**Files:** Create `lib/tg_config.k`, `tests/t_v2_config.k`

13 обёрток: `tg_set_commands(bot, commands_json)` (`tg_param_json`), `tg_get_commands(bot)`, `tg_del_commands(bot)`, `tg_set_name(bot, name)` (name=0 → skip? .md: оба опциональны — но без имени бессмысленно: name обязателен по контракту обёртки), `tg_get_name(bot)`, `tg_set_description(bot, desc)`, `tg_get_description(bot)`, `tg_set_short_description(bot, sdesc)`, `tg_get_short_description(bot)`, `tg_set_menu_button(bot, button_json)` (chat_id=0 → skip; chat_id нужен отдельной... ≤6: `(bot, chat_id, button_json)` chat_id=0→skip), `tg_get_menu_button(bot, chat_id)`, `tg_set_admin_rights(bot, rights_json, for_channels)` (0-флаги: for_channels=0/1 → raw), `tg_get_admin_rights(bot, for_channels)`.

Тест: `tg_set_commands(bot, "[{\"command\":\"start\",\"description\":\"Привет\"}]")` → тело `{"commands":[{"command":"start",...}]}` (без кавычек вокруг массива!).
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 12 (B10): форум-топики

**Files:** Create `lib/tg_forum.k`, `tests/t_v2_forum.k`

13 обёрток: `tg_topic_create(bot, chat_id, name)` (icon_color=0→skip — уместить нельзя, коммент), `tg_topic_edit(bot, chat_id, thread_id, name)` (name=0→skip), `tg_topic_close(bot, chat_id, thread_id)`, `tg_topic_reopen`, `tg_topic_delete`, `tg_topic_unpin_all`, `tg_general_edit(bot, chat_id, name)`, `tg_general_close(bot, chat_id)`, `tg_general_reopen(bot, chat_id)`, `tg_general_hide(bot, chat_id)`, `tg_general_unhide(bot, chat_id)`, `tg_general_unpin_all(bot, chat_id)`, `tg_topic_icons(bot)`.

Тест: тела по паттерну (`{"chat_id":55,"message_thread_id":7,"name":"топ"}` и т.д.).
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 13 (B11): реакции, геттеры, разлогин

**Files:** Create `lib/tg_react.k`, `tests/t_v2_react.k`

8 обёрток: `tg_set_reaction(bot, chat_id, msg_id, reaction_json)`, `tg_del_reaction(bot, chat_id, msg_id)` (user_id=0→skip), `tg_del_all_reactions(bot, chat_id)`, `tg_profile_photos(bot, user_id, limit)` (limit=0→skip), `tg_profile_audios(bot, user_id, limit)`, `tg_get_webhook_info(bot)`, `tg_logout(bot)`, `tg_close(bot)`.

Тест: тела (`{"chat_id":55,"message_id":42,"reaction":[{"type":"emoji","emoji":"👍"}]}` — reaction raw через tg_param_json), у геттеров с 0 параметрами — chk только URL (`/getWebhookInfo|`) и `{}` тело.
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 14 (B12): платежи

**Files:** Create `lib/tg_pay.k`, `tests/t_v2_pay.k`

6 обёрток: `tg_send_invoice(bot, chat_id, title, description, payload, currency, prices_json)` = 7 арг — НЕЛЬЗЯ → `tg_send_invoice(bot, chat_id, title, currency, prices_json)` + payload/description? Согласовать ≤6: `(bot, chat_id, title, payload, currency, prices_json)` description=0→skip... Нет: REQUIRED по .md: title, description, payload, currency, prices + chat_id = 6 ровно: `tg_send_invoice(bot, chat_id, title, description, payload, currency, prices_json)` = 7! Решение: payload — генерируется вызывающим, допустимо 6: убрать description из обязательных? .md: description Required! → Вариант: `tg_send_invoice(bot, chat_id, title, currency, prices_json, payload)` — 6, description=0→skip (НЕ по API)... ФИНАЛЬНО: 7 аргументов запрещены ⇒ `tg_send_invoice(bot, chat_id, spec*)` где spec — слот с полями? СЛОТ-СХЕМА: `inv[7]` слот: 0 chat_id, 1 title*, 2 description*, 3 payload*, 4 currency*, 5 prices_json*, 6 т.д. Обёртка `tg_send_invoice(bot, inv)` — как tg_param-слоты в примере bot.k (mykb). УТВЕРДИТЬ в задаче: слот `tg_inv[7]` + `tg_inv_begin(&i)`... Проще: `tg_send_invoice(bot, chat_id, title, currency, prices_json, payload)` + description КАК 0-арг? = 6... но тогда где description — включить: `(bot, chat_id, title, description, prices_json, payload)` без currency?? currency обязателен... 7 required-ных величин (chat_id,title,description,payload,currency,prices) = 6 РОВНО! (chat_id,title,description,payload,currency,prices_json) = 6 ✓✓ БЕЗ payload... посчитай: 1 chat_id, 2 title, 3 description, 4 payload, 5 currency, 6 prices_json = 6 ✓✓ ВСЁ ПОМЕЩАЕТСЯ.
`tg_invoice_link(bot, title, description, payload, currency, prices_json)` = 5 ✓ (business_connection_id — коммент).
`tg_refund(bot, user_id, charge_id)`, `tg_star_balance(bot)`, `tg_star_transactions(bot, limit)`, `tg_edit_star_sub(bot, user_id, charge_id, is_canceled)` (raw "true"/"false").

Тест: тела `{"chat_id":55,"title":"Т","description":"Д","payload":"p","currency":"XTR","prices":[...]}` (prices raw-массив).
- [ ] RED → [ ] GREEN → [ ] отчёт

### Task 15 (B13): расширенные отправки (6-арг магия)

**Files:** Create `lib/tg_ext.k`, `tests/t_v2_ext.k`

| Обёртка | Сигнатура (≤6) |
|---|---|
| `tg_sendx(bot, chat_id, text, parse_mode, reply_markup, reply_to)` | все 0-able кроме chat_id/text: parse_mode — строка "HTML"; reply_markup — JSON-строка через tg_param_json; reply_to — int → `tg_param_json(b,"reply_parameters","{\"message_id\":N}")` — НЕТ: собрать через sprintf в scratch: `sprintf(&scratchbuf, "{\"message_id\":%ld}", reply_to)` — использовать `tg_param_json` с содержимым scratch. 0 → skip |
| `tg_editx(bot, chat_id, msg_id, text, parse_mode, reply_markup)` | аналогично |
| `tg_photox(bot, chat_id, photo, caption, parse_mode, reply_markup)` | аналогично |
| `tg_answer_cb(ctx, text, show_alert)` | text=0 → НЕ передавать (снять спиннер); show_alert=1 → raw "true" |
| `tg_actionx(bot, chat_id, action, thread_id)` | thread_id=0→skip |
| `tg_sendx_to_username(bot, username, ...)` — НЕ НУЖНО (chat_id str? tg_param_str) — исключить |

Тест: `tg_sendx(bot,55,"привет","HTML","{\"inline_keyboard\":[]}",0)` → тело `{"chat_id":55,"text":"привет","parse_mode":"HTML","reply_markup":{"inline_keyboard":[]}}`; `tg_answer_cb(ctx2, 0, 0)` → тело `{"callback_query_id":"cb1"}` (только id!); `tg_sendx(...,reply_to=42)` → `"reply_parameters":{"message_id":42}`.
- [ ] RED → [ ] GREEN → [ ] отчёт

**Gate B:** каждый субагент в отчёте показывает `PASS` своего теста + PASS старого `t_methods`. Оркестратор проверяет `git status --short` — нарушения собственности (изменённые чужие файлы) откатывает: `git checkout -- <файл>`.

---

### Task 16 (Stage C1): интеграция

**Files:** Modify по мере необходимости ЛЮБЫХ `lib/tg_*.k` (конфликты уже невозможны — все агенты завершены), README.md, docs/superpowers/plans/2026-10-19-tg-lib-v1.md (галочки)

- [ ] **Step 1: Полная сборка всех тестов**

```sh
cd /tmp/opencode/kivagram
for t in tests/t_*.k; do n=$(basename $t .k); ./build.sh $t /tmp/$n && /tmp/$n >/tmp/$n.out 2>&1 && echo "$n: PASS" || { echo "$n: FAIL"; tail -3 /tmp/$n.out; }; done
```
Expected: все PASS (7 старых + 15 новых). Любые FAIL (дубликаты символов, порядок определений, интероп) — фикс В файле виновника, повтор.

- [ ] **Step 2: Сборка примера:** `./build.sh examples/bot.k /tmp/kivabot_ph && test -x /tmp/kivabot_ph` → OK.

- [ ] **Step 3: Чистота:** `git status --short` — только ожидаемые новые файлы; токена нет (`grep -rn "8967819901" . || echo ok`).

- [ ] **Step 4: Коммиты по модулям** (серийно, по одному на логическую группу):
```sh
git add lib/tg_media.k tests/t_v2_media.k && git commit -m "Add media send wrappers (audio/document/video/animation/voice/videoNote)"
git add lib/tg_geo.k tests/t_v2_geo.k && git commit -m "Add geo/contact/dice/sticker wrappers with raw float params"
git add lib/tg_poll.k tests/t_v2_poll.k && git commit -m "Add media group, poll and paid media wrappers"
git add lib/tg_msg.k tests/t_v2_msg.k && git commit -m "Add forward/copy/edit and mass delete wrappers"
git add lib/tg_answers.k tests/t_v2_answers.k && git commit -m "Add inline/payment/webapp/guest answer wrappers"
git add lib/tg_kb.k tests/t_v2_kb.k && git commit -m "Add keyboard builders and reply/link-preview helpers"
git add lib/tg_admin.k tests/t_v2_admin.k && git commit -m "Add moderation and chat member wrappers"
git add lib/tg_chat.k tests/t_v2_chat.k && git commit -m "Add chat management and invite link wrappers"
git add lib/tg_config.k tests/t_v2_config.k && git commit -m "Add bot config and commands menu wrappers"
git add lib/tg_forum.k tests/t_v2_forum.k && git commit -m "Add forum topic wrappers"
git add lib/tg_react.k tests/t_v2_react.k && git commit -m "Add reactions, profile getters and session wrappers"
git add lib/tg_pay.k tests/t_v2_pay.k && git commit -m "Add payments and star balance wrappers"
git add lib/tg_ext.k tests/t_v2_ext.k && git commit -m "Add extended send/edit/answer helpers with parse_mode and markup"
git add lib/tg.k tests/t_v2_dispatch.k && git commit -m "Extend dispatcher with edited/channel/membership/join/inline/payment kinds"
```
(порядок коммитов — по готовности; каждый коммит после локального прогона пары тестов виновника+соседа)

- [ ] **Step 5: README** — добавить секцию «Модули v2»: таблица lib/tg_*.k → функции, конвенция «обёртка = обязательные + 0-аргументы», указание на `docs/GAP-full-api-2026-10-19.md` и что закрыто волной-1.

- [ ] **Step 6: Финальный прогон всей матрицы + отчёт** — все PASS, `git log --oneline -20`, `git status` чисто.

**Self-review плана:** покрыты все секторы волны-1 GAP-документа (параметры — B13+A2; send-семейство — B1/B2/B3/B4; правки — B4; ответы — B5; клавиатуры — B6; админка — B7/B8; конфиг — B9; форум — B10; реакции — B11; платежи — B12; dispatch+allowed_updates — B0). Множественные вызовы-имена согласованы между задачами (B7≠B8 по `get_admins`). Плейсхолдеров нет — каждая задача содержит файлы, полный список функций, кейсы тестов с телами и команды.
