# Деплой чат-бэка — Фаза 1 (бесплатно)

Rails + ActionCable, **один инстанс**, SQLite, adapter `async` (Redis не нужен).
Docker готов (`Dockerfile`), миграции накатываются сами (`bin/docker-entrypoint` → `db:prepare`),
Puma слушает `PORT` из env.

## Render (рекомендую — проще всего и бесплатно)

1. Закоммитить и запушить каталог `chat-demo/backend` в **отдельный GitHub-репозиторий**.
2. Render → **New → Web Service** → Connect repo. Language: **Docker** (сам подхватит `Dockerfile`).
   Instance Type: **Free** (по умолчанию может стоять платный).
3. **Environment variables** — обязательны две:
   - `RAILS_MASTER_KEY` = содержимое `config/master.key` (файл в `.gitignore`, в репо не попадёт).
   - `CORS_ORIGINS` = origin'ы фронта через запятую, см. ниже.
   `PORT` и `RAILS_ENV` задавать не надо (Render и `Dockerfile` соответственно).
   Нельзя указывать `*` в `CORS_ORIGINS`: REST и WebSocket принимают только явно перечисленные
   origin'ы. `CHAT_PUBLIC_URL` (публичный адрес сервиса, из него собираются ссылки на вложения) — тоже
   не надо: без него берётся `RENDER_EXTERNAL_URL`, который Render подставляет сам. Задавать
   вручную нужно только на хостинге, который такой переменной не даёт, иначе вложения уедут
   ссылками на `localhost` и не откроются. В production один из этих URL обязателен: он же
   формирует allowlist Host header.
   **Не** задавать `WEB_CONCURRENCY` > 1 — async-шина живёт в одном процессе.
4. **Health Check Path:** `/up`
5. Deploy. Публичный URL будет вида `https://<service>.onrender.com`.

### CORS_ORIGINS

Origin = схема + хост + порт, без слеша на конце. Несколько — через запятую.
Фронт показываем «захватом» dev-стенда (см. ниже), поэтому origin фронта — сам dev-хост:

```
http://localhost:3000,https://dev.sodrujestvo.org
```

`http://localhost:3000` — для локальной разработки (`yarn dev`), `https://dev.sodrujestvo.org` —
для задеплоенной чат-сборки на dev. Изменение переменной на Render само триггерит редеплой бэка.
В production пустая переменная или `*` намеренно останавливают загрузку приложения: иначе сторонний
сайт сможет подключаться к API/сокету от имени посетителя.

### Лимиты вложений

Один файл — до 10 МиБ, сообщение — до 5 файлов и 25 МиБ суммарно. По умолчанию бэкенд также
резервирует не более 750 МиБ для всех файлов, 100 МиБ на пользователя и 250 МиБ на комнату.
При необходимости пороги задаются байтами через `CHAT_STORAGE_TOTAL_BYTES`,
`CHAT_STORAGE_USER_BYTES` и `CHAT_STORAGE_ROOM_BYTES`.

## Фронт (community, ветка `demo_chat`) — «захват» dev-стенда

Адрес бэка уже прописан в `.env.dev`:

```
NEXT_PUBLIC_CHAT_API_BASEURL="https://chat-demo-backend-ie7j.onrender.com"
NEXT_PUBLIC_CHAT_SOCKET_URL="wss://chat-demo-backend-ie7j.onrender.com/cable"
```

Живой SSO работает без правок в Casdoor: чат-сборка едет на сам dev-хост
(`dev.sodrujestvo.org`), а его callback уже в allowlist. Порядок для показа:

1. `build-dev-chat` — собирает ветку как обычный dev-образ, но под именем `psb-frontend-dev-chat`
   (рабочий `psb-frontend-dev` не трогается).
2. `deploy-dev-chat` — временно подменяет dev-стенд чат-сборкой. Команда идёт на `dev.sodrujestvo.org`,
   логинится своими рабочими аккаунтами, щупает чат.
3. `rollback-dev` — возвращает dev на рабочий образ `psb-frontend-dev:latest`.

Все три джобы ручные (`when: manual`), только на ветке `demo_chat`.

## Ограничения free-тарифа Render (важно для показа)

- **Засыпает** после 15 мин без входящего трафика (HTTP или сообщений по открытым WS),
  просыпается ~1 мин. Прогреть перед демо. Пока открыта вкладка с чатом, пинги ActionCable
  считаются трафиком и сервис не заснёт.
- **750 instance-hours/месяц** на весь workspace — один сервис укладывается впритык.
- **Диска на free нет, ФС эфемерная.** SQLite обнулялся бы при каждом пробуждении/редеплое —
  поэтому production вынесен в отдельный Postgres (см. ниже). Сервис всё равно засыпает,
  но данные переживают сон.
- **Вложения тоже лежат в Postgres, а не на диске.** По той же причине: Disk-сервис писал файлы
  в `storage/`, они пропадали вместе с ФС, и в чате оставались мёртвые ссылки — голосовое
  показывало «недоступно», картинки не открывались. Теперь `config.active_storage.service`
  в production — `:database` (`lib/active_storage/service/database_service.rb`, таблица
  `active_storage_db_files`). Отдельная настройка на Render не нужна, миграция накатится сама.
  Вложения, загруженные ДО этого перехода, не восстановятся: у их блобов `service_name = local`,
  а файлов за ними уже нет.

## Хранение истории чата (Postgres)

Чтобы переписка не пропадала (переживала сон/редеплой; free Postgres на Render живёт до 30 дней),
production ходит в Postgres по `DATABASE_URL`. В коде уже сделано: гем `pg`, `config/database.yml`
(`production` → postgresql), `Dockerfile` (`libpq`). Локальная разработка осталась на SQLite.

Порядок на Render (**БД создать ДО деплоя** — иначе `db:prepare` не подключится и деплой упадёт):

1. **New → Postgres** → Free. Регион — тот же, что у веб-сервиса (Frankfurt), иначе выше задержки.
2. У созданной БД скопировать **Internal Database URL**.
3. В веб-сервисе → **Environment** → добавить `DATABASE_URL` = этот Internal URL.
4. Запушить бэк (изменены `Gemfile`/`Gemfile.lock`/`Dockerfile`/`config/database.yml`) — Render
   передеплоит, `bin/docker-entrypoint` сам накатит схему (`db:prepare`) в пустой Postgres.

Проверка (идентичность идёт в query, не в заголовках): `curl '.../api/rooms?external_id=me&name=Me'`
→ `[]` с кодом 200 (эндпоинт лезет в БД). Голый `curl .../api/rooms` вернёт `unauthorized` — это норма.
После переписки данные остаются доступны и после засыпания.
Ограничения free Postgres: 1 ГБ (для демо с запасом) и удаление инстанса через 30 дней с момента
создания (Render предупреждает; для «день-неделя» неактуально). По-настоящему durable — контур
`chat_test` (Фаза 2).

## Альтернатива: Fly.io

`flyctl launch` (Docker) + volume для durable SQLite, WebSocket «из коробки», не засыпает так агрессивно.
Требует `flyctl` и аккаунт. Конфиг тот же (Dockerfile + `PORT` + env).
