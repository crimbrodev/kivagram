# kivagram

Библиотека Telegram Bot API для языка **Kiva**. Long-polling бот с
диспетчером хендлеров — одним файлом `lib/tg.k`, который склеивается с
вашим `.k`-файлом при сборке. Написана на чистой Kive: только libc и
`curl` из PATH, никаких обёрток над C-биндингами.

```k
эхо(ctx) {
    tg_send_text(ctx, tg_text(ctx));
    1;
}

global main
main() {
    auto bot;
    bot = tg_bot("токен:от_botfather");
    tg_on_text(bot, "эхо", &эхо);
    tg_polling(bot);
    0;
}
```

Полный пример — `examples/bot.k` (команды, inline-кнопка, ответы на
callback'и, русские имена функций).

---

## Зависимость: форк тулчейна `crimbrodev/kivac-plus`

kivagram собран на трёх фичах, которых нет в апстриме `Gudhein3/kivac`:

1. **Функции-указатели** (PR #2) — без них невозможен реестр хендлеров:
   библиотека хранит `fn`-указатели в слотах и вызывает их через
   локальные копии.
2. **UTF-8 идентификаторы** — лексер принимает байты ≥0x80 в именах:
   русские имена функций и хендлеров (`&приветствие`).
3. **Лимиты строк** (коммит `60ca869`) — литерал ≤65000 байт, пул 1 МиБ.

### Сборка тулчейна

```sh
git clone https://github.com/crimbrodev/kivac-plus
cd kivac-plus
cc -o kivaa kivaa.c && ./kivaa bootstrap/kiva.ir kivac
export KIVA_TC=$PWD   # путь к kivac/kivaa; по умолчанию /tmp/opencode/kivac-pr
```

**Важно:** `kivaa` возвращает exit 0 даже при ошибке nasm/cc/ld — успех
сборки проверяйте через `test -x <бинарник>`, не по коду возврата.

## Сборка бота

`build.sh` склеивает `lib/tg.k` + модули `lib/tg_*.k` (алфавит,
`LC_ALL=C`) + ваш файл, компилирует и линкует:

```sh
./build.sh examples/bot.k bot
./bot
```

Внутри — обычная склейка (в уникальный на сборку `*.glue.k`,
поэтому параллельные сборки не мешают друг другу), поэтому никаких
`import` в Kive нет: одна программа — один файл. Модули `lib/tg_*.k`
автоподключаются: свой модуль = просто новый файл в `lib/`.

Тесты: `./build.sh tests/t_buf.k /tmp/t_buf && /tmp/t_buf` (и так для
каждого `tests/t_*.k`; часть тестов ходит в сеть за 401 с фейковым
токеном).

---

## API в четырёх строках

| Что | Как |
|---|---|
| Создать бота | `bot = tg_bot("токен")` |
| Повесить хендлер | `tg_on_text(bot, "имя", &функция)` |
| Крутить поллинг | `tg_polling(bot)` |
| Остановить | `tg_stop(bot)` (сбрасывает `polling_flag`) |

Семейство регистрации: `tg_on_update` (ловит всё), `tg_on_text`,
`tg_on_command`, `tg_on_callback`, `tg_on_message` (сообщения без
текста: фото и т.п.), примитив `tg_on(bot, имя, фильтр, fn)`.
Имена — **плоский неймспейс**: повторная регистрация по тому же имени
заменяет хендлер на прежней позиции.

Методы: `tg_send_text(ctx, text)`, `tg_send_to(bot, chat_id, text)`,
`tg_answer(ctx, text)`, `tg_action(ctx, action)`,
`tg_edit_text(bot, chat_id, msg_id, text)`,
`tg_edit_inline(bot, inline_msg_id, text)`,
`tg_delete(bot, chat_id, msg_id)`, `tg_send_photo_url(bot, chat_id, url)`;
низкий уровень — `tg_call(bot, method, params)` и билдер параметров
(`tg_params_reset`/`tg_param_str`/`tg_param_num`/`tg_param_json`/
`tg_params_done`) для `reply_markup` и прочего.

Аксессоры контекста: `tg_kind`, `tg_chat_id`, `tg_msg_id`, `tg_from_id`,
`tg_from_name`, `tg_text`, `tg_command`, `tg_target_bot`, `tg_mine`,
`tg_exclusive`, `tg_arg(ctx,n)`, `tg_cbq_id`, `tg_data`,
`tg_inline_msg_id`, `tg_raw(ctx)` — всё остальное через
`tg_raw` + `tg_get`.

## Контракт хендлера

`fn(ctx)`, последнее выражение — возврат:

- **`1`** — продолжить цепочку хендлеров;
- **`0`** — прервать (аналог `return false` в ggram).

Обязательный **порядок определений**: функция, передаваемая как значение
(`&хендлер`), должна быть определена текстово **до** первого
`tg_on_*` — иначе мусорный указатель и SEGV. В примере все хендлеры —
над `main`.

Исключений в Kive нет: **падение хендлера = падение процесса**,
изоляции вроде `pcall` из ggram нет. Пиши аккуратно.

## Жизненный цикл строк

- **Поля контекста** (`tg_text`, `tg_from_name`, `tg_data`, …) скопированы
  в приватный буфер `ctx` и **стабильны всю диспетчеризацию**: можно
  слать ответы и форматировать что угодно — данные не исчезнут.
- **Сырые указатели** (`tg_raw`, `tg_get`, ответы `tg_http_body`) живут
  **до следующего вызова API** — копируй, если нужно дольше.
- **`tg_scratch()`** — рабочий буфер под `sprintf` и внутренности;
  считай, что после следующего API-вызова содержимое может быть
  переиспользовано. Передавать scratch-строки в `tg_send_text` и
  параметры — **можно** (escape и числа в буферы-помощники не пишут
  в scratch).

## Offset и at-least-once

`tg_polling` пишет файл `tg_<bot_id>.offset` **после каждого**
обработанного апдейта (`update_id + 1`). Семантика — **at-least-once**:
падение между обработкой и записью ⇒ апдейт доставится повторно,
хендлеры должны быть идемпотентны (у ggram наоборот — теряются).
Первый запуск без файла обрабатывает бэклог целиком — нормально.

---

## Сознательные расхождения с ggram

ggram (MIT, TRIGON.IM) — вдохновитель дизайна API; kivagram — не порт,
а другая модель исполнения (синхронный `popen` вместо промисов).
Расхождения **сознательные**:

- **Команды не попадают в текстовые хендлеры** (kind команды = 2
  исключительно). Нужен ловец всего — `tg_on_update` + свой фильтр.
- **Нет pcall-изоляции** ошибок хендлеров: Kiva без исключений.
- **Плоский неймспейс** имён хендлеров (у ggram — с префиксами).
- **`callback_query` без `message`** → `tg_chat_id(ctx) == 0`;
  для инлайн-сообщений используйте `tg_edit_inline(bot, tg_inline_msg_id(ctx), text)`.
- **Не-текстовые сообщения** — отдельный `tg_on_message`, а не
  фолбэк текста.
- **Логирование тихое**: по умолчанию печатаются только ошибки API
  (`[tg] method error code: description`); свой обработчик —
  `bot.on_error` (слот word7).

## Скоуп v1 и волна v2

Есть: long-polling, диспетчер с фильтрами, команды (ASCII-гард:
`/команда` с кириллицей распознаётся как обычный текст), callback'и,
текстовые методы, ответы на кнопки, сушка параметров, 429-ретраи,
409 → `deleteWebhook`, «terminated by other getUpdates» → стоп.

Вне скоупа: отправка файлов с диска (multipart — отдельная волна),
webhooks, сессии/kv-хранилище, свои variadic.

## Модули v2 (волна 1)

Полный gap-анализ Bot API — `docs/GAP-full-api-2026-10-19.md`;
волна-1 закрыла:

| Модуль | Содержимое |
|---|---|
| `lib/tg.k` (ядро) | диспетчер: kind 4–10 (edited/channel/my_chat_member/chat_join_request/inline/pre_checkout/shipping), `tg_allow_updates_add` → `allowed_updates`, `tg_param_raw`, `tg_html_escape`, `tg_business_conn` |
| `lib/tg_media.k` | sendAudio/Document/Video/Animation/Voice/VideoNote |
| `lib/tg_geo.k` | Location (дроби через raw)/Venue/Contact/Dice/Sticker/LivePhoto |
| `lib/tg_poll.k` | MediaGroup/Poll/stopPoll/PaidMedia |
| `lib/tg_msg.k` | forward*/copy*/edit* /deleteMessages (`tg_edit_markup(...,0)` → `reply_markup:null`) |
| `lib/tg_answers.k` | InlineQuery/PreCheckout/Shipping/WebApp/Guest/JoinRequest |
| `lib/tg_kb.k` | билдеры `tg_kb_*`/`tg_rkb_*`, remove/force_reply/reply_params/link_preview |
| `lib/tg_admin.k` | баны/restrict/promote/getChat* |
| `lib/tg_chat.k` | пины/title/инвайты/leave/approve+declineJoin |
| `lib/tg_config.k` | setMyCommands/имена/описания/меню-кнопка/права |
| `lib/tg_forum.k` | форум-топики и general-топик |
| `lib/tg_react.k` | реакции, профиль-геттеры, getWebhookInfo/logOut/close |
| `lib/tg_pay.k` | sendInvoice (description — через `tg_call`)/createInvoiceLink/звёзды |
| `lib/tg_ext.k` | `tg_sendx`/`tg_editx`/`tg_photox` (parse_mode+markup+reply_to), `tg_answer_cb`, `tg_actionx` |

Конвенция: обёртка принимает обязательные параметры + ходовые
опциональные с контрактом `0 = не передавать` (≤6 аргументов);
JSON-объекты/массивы (`options`, `permissions`, `prices`, `commands`,
`reaction`...) — аргумент-строка в `tg_param_json` (в тело входит без
кавычек); всё, что не вошло в обёртку, — задокументировано в шапке
модуля и вызывается через `tg_call` напрямую. Тесты — `tests/t_v2_*.k`
(dry-run, `tg_composed`).

## Известные языковые ловушки Kiva

- `x[i]` на **локальном указателе**/параметре — value-семантика (слот
  читается по указателю); на глобальном массиве — адрес-семантика.
  Глобальный массив в позиции значения — его **первое слово**: в libc —
  всегда `&buf`.
- Сравнения `<` / `>=` **беззнаковые**: `-1 >= 0` истинно —
  отрицательные сентинелы не работают, используйте флаги.
- `fprintf(stderr, …)` **в аргументах с вложенным вызовом** затирает
  результат вызова — отладка только через `printf`.
- Нет `&&`/`||`; до 6 аргументов (седьмой молча → 0); fn-вызов — только
  через локальную переменную; комментарии `//` и `/* */`.
- Числа — 64-битные: выводить `%ld` (id Telegram уже больше 2³¹).

## Атрибуция

API-дизайн вдохновлён [ggram](https://github.com/TRIGON.IM/ggram)
(MIT, TRIGON.IM). Kiva — https://github.com/Gudhein3/kivac;
фортулчейна — `crimbrodev/kivac-plus`.
