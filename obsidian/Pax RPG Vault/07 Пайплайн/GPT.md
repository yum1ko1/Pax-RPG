---
тип: пайплайн
tags: [пайплайн, gpt]
---

# GPT — референсы и картинки

Подписка ChatGPT через **Codex CLI на ПК** (`codex login` → «Sign in with ChatGPT», встроенный `image_gen`) — без
API-ключа. Скрипты — `pax_rpg/dev/gpt/`, на ПК — `Desktop\pax_rpg_work\gpt_scripts`, результаты — `…\gpt\<имя>\`.
Для Claude — skill `.claude/skills/gpt-refs/SKILL.md` (команды, пайплайны HUD / 3D / план города).

- `codex_image.py gen <имя> "<промпт>" --style hud|yuruma|sheet3d|topdown [--img реф] [--edit] [--transparent]` — картинка (1–2 мин).
- `codex_image.py ask "<вопрос>" --img a.png` — GPT разбирает картинку (раскладка HUD, план улиц → JSON).
- `send_refs.py <папка>` — картинки с ПК → ветка `gpt-refs` репозитория Pax-RPG (облачная сессия видит их через `git fetch`).
- `gpt_image.py` — запасной путь через платный API (`OPENAI_API_KEY`).
- Стили промптов — `pax_rpg/dev/gpt/styles/`. Рамки HUD — дальше как в `pax_rpg/dev/hud/key_hud.py`; листы под 3D → [[Meshy]].
