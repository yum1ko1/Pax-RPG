# pax-images — MCP-мост к картинкам OpenAI

Claude (Claude Code в папке репозитория, Claude Desktop или облачная сессия) генерирует референсы для мода сам:
концепт-кадры, листы персонажей под Meshy Image to 3D, предметы, иконки, текстуры. Сервер — один файл на
стандартной библиотеке Python, ставить пакеты не надо.

## Два пути

| Бэкенд | Что нужно | Чем платим |
|---|---|---|
| `codex` (по умолчанию без ключа) | подписка ChatGPT Plus / Pro / Team, Codex CLI (`npm i -g @openai/codex`), вход `codex login` | лимитами подписки: картинку рисует встроенный инструмент `image_generation` в Codex |
| `api` (если задан `OPENAI_API_KEY`) | ключ с platform.openai.com | отдельно, по токенам |

Выбор вручную — переменная `PAX_IMAGES_BACKEND=codex|api`.

## Подключение

**ПК (Windows), подписка:** `python pax_rpg\dev\install_openai_mcp.py` — поставит Codex CLI, откроет вход через
ChatGPT, пропишет сервер `pax-images` в Claude Desktop. С ключом API — тот же скрипт с `--api-key`.
Claude Code берёт сервер из `.mcp.json` в корне репозитория — при первом запуске в папке Pax-RPG разрешить
`pax-images`, `/mcp` — проверить.

**Облачная сессия Claude Code (подписка):** в настройках окружения, Network access, разрешить `chatgpt.com` и
`auth.openai.com`; в сессии Claude ставит Codex и запускает `codex login --device-auth` — вы открываете ссылку,
вводите код и входите в ChatGPT у себя. Вход живёт, пока жив контейнер сессии. Отозвать — выйти из сессий в
настройках безопасности ChatGPT.

Проверка: `python pax_rpg/dev/openai/openai_image_mcp.py --selftest` — бэкенд, найден ли codex и вошёл ли он.

## Инструменты

| Инструмент | Что |
|---|---|
| `generate_image` | картинка по промпту: `prompt`, `name`, `style`, `kind`, `size`, `quality` (по умолчанию medium), `n` 1–4, `background` |
| `edit_image` | по своим образцам `images` (1–16 путей; от корня репозитория тоже можно) и `mask` — лист персонажа по концепту, перерисовка в стиле Юрумы, замена деталей |
| `list_images` | последние сгенерированные: пути и промпты |

Промпт собирается так: блок типа (`kind`) + блок стиля (`style`) + ваш текст + «Avoid: …» из стиля. Блоки —
в `presets.json`, правятся без кода:

- стили: `yuruma` (мир в целом), `gharn` (столица орды — из заметки «Гхарн — промпты концепт-арта»), `hud`;
- типы: `concept` 1536×1024, `character` (вид спереди/сбоку/сзади, A-поза, серый фон), `object` (3/4, серый фон),
  `icon` (прозрачный фон), `texture` (бесшовная).

Через Codex размер, качество и фон передаются словами в задании — Codex выбирает модель картинок сам и
обычно их соблюдает, но не гарантирует. Одна картинка — от полуминуты до нескольких минут.

Картинки и JSON с промптом сохраняются в `pax_rpg/reference/openai/` (папка в .gitignore — удачные переносить в
`pax_rpg/reference/` вручную).

## Настройки (переменные окружения)

| Переменная | По умолчанию |
|---|---|
| `PAX_IMAGES_BACKEND` | `api`, если есть ключ, иначе `codex` |
| `PAX_IMAGES_DIR` | `pax_rpg/reference/openai` |
| `PAX_IMAGES_INLINE_MAX` | `3000000` — картинки крупнее не вкладываются в ответ, только путь |
| `PAX_CODEX_BIN`, `PAX_CODEX_TIMEOUT`, `PAX_CODEX_SANDBOX` | `codex` из PATH, `600` с, `workspace-write` |
| `OPENAI_IMAGE_MODEL`, `OPENAI_BASE_URL` | `gpt-image-2`, `https://api.openai.com/v1` (только `api`) |
