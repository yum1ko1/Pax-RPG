# pax-images — MCP-мост к OpenAI Images

Claude (Claude Code в папке репозитория, Claude Desktop или облачная сессия) генерирует референсы для мода сам:
концепт-кадры, листы персонажей под Meshy Image to 3D, предметы, иконки, текстуры. Сервер — один файл на
стандартной библиотеке Python, ставить пакеты не надо.

## Подключение

**ПК (Windows):** `python pax_rpg\dev\install_openai_mcp.py` — спросит ключ (ввод не виден), проверит его,
запишет переменную пользователя `OPENAI_API_KEY` и сервер `pax-images` в Claude Desktop. Claude Code берёт
сервер из `.mcp.json` в корне репозитория — при первом запуске в папке Pax-RPG разрешить `pax-images`, `/mcp` —
проверить.

**Облачная сессия Claude Code:** в настройках окружения добавить ключ (Network secrets или переменная
`OPENAI_API_KEY`) и разрешить хост `api.openai.com` в Network access. Новая сессия поднимет сервер из `.mcp.json`.

Проверка без сети: `python pax_rpg/dev/openai/openai_image_mcp.py --selftest`.

## Инструменты

| Инструмент | Что |
|---|---|
| `generate_image` | картинка по промпту: `prompt`, `name`, `style`, `kind`, `size`, `quality` (по умолчанию medium), `n` 1–4, `background`, `output_format`, `model` |
| `edit_image` | по своим образцам `images` (1–16 путей; от корня репозитория тоже можно) и `mask` — лист персонажа по концепту, перерисовка в стиле Юрумы, замена деталей |
| `list_images` | последние сгенерированные: пути и промпты |

Промпт собирается так: блок типа (`kind`) + блок стиля (`style`) + ваш текст + «Avoid: …» из стиля. Блоки —
в `presets.json`, правятся без кода:

- стили: `yuruma` (мир в целом), `gharn` (столица орды — из заметки «Гхарн — промпты концепт-арта»), `hud`;
- типы: `concept` 1536×1024, `character` (вид спереди/сбоку/сзади, A-поза, серый фон), `object` (3/4, серый фон),
  `icon` (прозрачный фон), `texture` (бесшовная).

Картинки и JSON с промптом, моделью, `revised_prompt` и расходом токенов сохраняются в
`pax_rpg/reference/openai/` (папка в .gitignore — удачные переносить в `pax_rpg/reference/` вручную).

## Настройки (переменные окружения)

| Переменная | По умолчанию |
|---|---|
| `OPENAI_IMAGE_MODEL` | `gpt-image-2` |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` |
| `PAX_IMAGES_DIR` | `pax_rpg/reference/openai` |
| `PAX_IMAGES_INLINE_MAX` | `3000000` — картинки крупнее не вкладываются в ответ, только путь |
