# Pax RPG

Мод для **Pax Universe** (не серия Pax CorpInc): RPG от третьего лица на планете **Юрума** — азиатское фэнтези,
герой из народа они. Сейчас: планета и города на глобусе, сценарий «Юрума» (1047 год Эры Расколотого Неба, пять
империй), локации, Чёрный рыцарь с двуручником — ходьба и бег, доставание меча через плечо, комбо из трёх ударов,
увороты, плащ-ткань.

Вынесено из [yum1ko1/Pax-CorpInc](https://github.com/yum1ko1/Pax-CorpInc) вместе с историей коммитов.

## Что где

| Папка | Что |
|---|---|
| `mods/pax_rpg/` | сам мод — копируется в папку игры `mods/pax_rpg/` (подробности — `mods/pax_rpg/README.md`) |
| `mods/pax_rpg/src/` | код: `planet/` — Юрума и города, `travel/` — загрузка, `location/` — локация и герой (`hero.gd`) |
| `mods/pax_rpg/config/` | настройки: `hero.json` (скорости, комбо, увороты, плащ, следы ударов), `location.json`, `cities.json` |
| `mods/pax_rpg/models/` | `knight.glb` (рыцарь, 16 клипов), `knight_anim.json` (root motion, смена меча), `knight_cape.glb` (ткань) |
| `mods/pax_rpg/presets/Юрума/` | сценарий мира |
| `pax_rpg/dev/blender/knight/` | сборка рыцаря в Blender: `build_greatsword.py` → `assemble_knight.py` → `refine_knight.py`, проверка `check_knight2.py` |
| `pax_rpg/dev/meshy/` | клиент Meshy API (`meshy_api.py`, ключ — из переменной `MESHY_API_KEY`, в вывод не попадает) |
| `pax_rpg/dev/openai/` | MCP-мост `pax-images` к картинкам OpenAI: Claude сам генерирует референсы (концепты, листы под Meshy, иконки) — через подписку ChatGPT (Codex CLI) или ключ API; подключение — `install_openai_mcp.py` |
| `pax_rpg/dev/gpt/` | референсы через GPT по подписке ChatGPT (Codex CLI на ПК): `codex_image.py`, `send_refs.py` → ветка `gpt-refs`; skill для Claude — `.claude/skills/gpt-refs/` |
| `pax_rpg/dev/audio/` | синтез звуков: взмах меча, удар о землю |
| `pax_rpg/dev/` | генераторы планеты и сценария (`yuruma_planet.py`, `yuruma_scenario.py`), установка пресета |
| `pax_rpg/scenario/`, `pax_rpg/reference/`, `pax_rpg/docs/` | исходник сценария, карты Юрумы, заметки и промпты |

## Установка

Скопировать `mods/pax_rpg` в `<папка Pax Universe>/mods/pax_rpg` и перезапустить игру. Код мода проходит
песочницу CodeGuard игры: без `ClassDB`, `Expression`, вызовов по строке, файлового доступа вне `PaxMod`.
