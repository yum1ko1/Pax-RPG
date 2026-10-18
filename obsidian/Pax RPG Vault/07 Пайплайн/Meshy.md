---
тип: пайплайн
tags: [пайплайн, meshy]
---

# Meshy

Клиент API — `pax_rpg/dev/meshy/` (ключ — переменная `MESHY_API_KEY` на ПК, в чат не вставлять).

- `meshy_api.py` — balance / create / status / wait / fetch по любому endpoint.
- `batch_motions.py` — пакет анимаций (Text to Motion → на риг), состояние в `W\meshy\batch_motions.json`.
- `concept_images.py` — концепт-арт (Text to Image) из заметки с промптами, напр. [[Гхарн — промпты концепт-арта]].
- Промпты персонажей — `pax_rpg/docs/Meshy_промпты.md`. Стиль Юрумы дописывать явно: `East Asian fantasy`.
- Клипы Meshy облегчать `pax_rpg/dev/slim_glb.py`; горизонтальный сдвиг бёдер убирать `flatten_root.py`.
- Text-to-motion: промпт ≤ 400 символов.
