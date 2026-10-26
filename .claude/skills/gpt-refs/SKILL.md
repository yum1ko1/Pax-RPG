---
name: gpt-refs
description: Референсы и картинки через GPT (подписка ChatGPT автора, Codex CLI на его ПК) для Pax RPG — концепт-арт, рамки и элементы HUD, листы персонажей/пропсов под 3D (Meshy, Blender), планы улиц и районов города, правки по референсу, разбор картинки в JSON. Используй, когда нужно сгенерировать/отредактировать изображение, сделать референс, новый HUD, текстуру-заготовку, концепт локации, или «спросить GPT по картинке». Работает через мост к ПК (MCP-инструменты shell / job_status).
---

# GPT-референсы для Pax RPG

Картинки делает **GPT на ПК автора**: Codex CLI, вход «Sign in with ChatGPT» → встроенный `image_gen`
(по подписке, **без** `OPENAI_API_KEY`). Облако до OpenAI не достаёт — всё идёт через мост.
Скрипты — `pax_rpg/dev/gpt/` (на ПК копия в `C:\Users\mbkli\Desktop\pax_rpg_work\gpt_scripts`),
результаты — `C:\Users\mbkli\Desktop\pax_rpg_work\gpt\<имя>\`.

## 0. Мост

Инструменты моста — MCP-сервер «Мост к ПК автора мода» (имя сервера бывает разным: найди через
`ToolSearch("bridge_info shell job_status")`). `shell` — PowerShell в папке игры
(`C:\Users\mbkli\AppData\Local\Programs\Pax Universe`, это git-репо с remote `pax-rpg`). Команды дольше
55 с возвращают `job_id` → `job_status(job_id, wait_seconds=55)`, пока `running:false`.

```powershell
$PY='C:\Users\mbkli\AppData\Local\Programs\Python\Python314\python.exe'; $G='C:\Users\mbkli\Desktop\pax_rpg_work\gpt_scripts'
```
(переменные не живут между вызовами `shell` — повторяй эту строку в начале каждой команды)

## 1. Поставить/обновить скрипты на ПК (если менял `pax_rpg/dev/gpt/` — после push)

```powershell
$b='main'; $G='C:\Users\mbkli\Desktop\pax_rpg_work\gpt_scripts'; git fetch -q pax-rpg $b; git archive --format=zip -o "$env:TEMP\gpt.zip" "pax-rpg/${b}:pax_rpg/dev/gpt"; Expand-Archive -Force "$env:TEMP\gpt.zip" $G
```
(`$b` — твоя ветка, если скрипты ещё не в main). Проверка: `& $PY "$G\codex_image.py" check` →
`Logged in using ChatGPT` и `image_generation … true`. Если не залогинен — попроси автора выполнить `codex login`
на ПК (сам ключи/токены не трогай и не читай `~/.codex/auth.json`).

## 2. Сгенерировать

```powershell
& $PY "$G\codex_image.py" gen <имя> "<промпт EN>" [--style hud|yuruma|sheet3d|topdown] [--img реф.png …] [--edit] [--n 2] [--shape square|landscape|portrait] [--transparent] [--avoid "…"]
```
- ≈ 1–2 мин на картинку → почти всегда `job_id`. Повторный `gen` с тем же именем дописывает `<имя>_1.png`, `_2`…
  История промптов — `request.json` в папке.
- `--img` — пути на ПК (относительно папки игры можно: `mods\pax_rpg\textures\hud\boss_frame.png`).
  Без `--edit` — референсы стиля/формы; с `--edit` первая картинка — цель правки («change only …»).
- Одна генерация = один ассет. Разные ассеты — разные `gen`, не `--n`.
- Промпт на английском, конкретный: что это, где в игре, композиция, материалы, чего избегать. Стили в
  `pax_rpg/dev/gpt/styles/*.txt` уже несут мир Юрумы — не дублируй. Длинный промпт: `"@file:<путь>"`.
- `ask` — GPT смотрит на картинку и отвечает текстом/JSON:
  `& $PY "$G\codex_image.py" ask "<вопрос>" --img a.png [--out C:\…\a.json]`.
- Нет подписки/лимит исчерпан → запасной `gpt_image.py` (платный API, нужен `OPENAI_API_KEY` на ПК; спроси автора).

## 3. Посмотреть результат в облаке

На ПК: `& $PY "$G\send_refs.py" C:\Users\mbkli\Desktop\pax_rpg_work\gpt\<имя> [--max 1024|0]` — коммит в ветку
`gpt-refs` репозитория Pax-RPG (без force, рабочую папку игры не трогает; `--max 0` — полный размер для ассета).
В облаке:
```bash
git fetch -q origin gpt-refs && git ls-tree -r --name-only origin/gpt-refs | grep <имя>
git show origin/gpt-refs:gpt/<имя>/<имя>_0.png > <scratchpad>/<имя>_0.png   # затем Read — картинка видна
```
Смотри каждую картинку сам, прежде чем пускать в работу; не устраивает — одна точечная правка промпта или
`--edit` с этой картинкой, и снова.

## 4. Пайплайны

### HUD
1. `gen hud_<что> "<элемент: рамка полосы/слот/панель, пропорции, где пустые окна>" --style hud --transparent`
   + `--img mods\pax_rpg\textures\hud\boss_frame.png` (и другие рамки) — чтобы новый элемент совпал с текущим.
2. Проверь альфу (`PIL: im.mode=='RGBA'`, `getextrema()[-1]`). GPT часто делает внутреннее окно непрозрачным
   чёрным — если сквозь него должна быть видна полоса/портрет, вырежи окно (прямоугольник/заливка от центра →
   alpha 0) или проси «inner window fully transparent». Без альфы вовсе — генерируй на `#00FF00` и прогони
   `pax_rpg/dev/hud/key_hud.py <src> <dst>` (хромакей, despill, обрезка).
3. Ассет — `mods/pax_rpg/textures/hud/<имя>.png` (берёшь из `gpt-refs` с `--max 0`, уменьшай до нужного размера
   PIL-ом; рамки текущего HUD ≈ 512–1024 px по длинной стороне). Грузится `mod.texture("textures/hud/%s.png")` в
   `mods/pax_rpg/src/location/hud.gd`, полосы под рамкой — `shaders/hud_bar.gdshader`. Координаты окон для полос
   найди по альфе/тёмным каналам (как `key_hud.py`) и запиши в код/конфиг, не на глаз.
4. Проверка мода: `tools/ci/run_checks.sh`; в игре — инструменты моста `check_mods pax_rpg`, `game_start`, `screenshot`.

### 3D-модели (персонажи, пропсы, постройки)
1. Лист: `gen <имя>_front "<subject, front view, A-pose>" --style sheet3d --shape portrait`, затем вид сбоку/сзади:
   `gen <имя>_side "same character, exact side view, same proportions and outfit" --img …\<имя>_front_0.png --edit`.
   Один объект на лист, нейтральный фон, без теней — Meshy так лучше держит форму.
2. Image to 3D — `pax_rpg/dev/meshy/meshy_api.py create image-to-3d body.json` (`"image_url": "@file:<png>"`,
   мультивью — `multi-image-to-3d`, `"image_urls": [...]`), `wait`, `fetch`. Заметка: `obsidian/…/07 Пайплайн/Meshy.md`.
3. Blender (`pax_rpg/dev/blender/…`), облегчение `pax_rpg/dev/slim_glb.py`, бюджеты полигонов — `Пайплайн.md`.

### Планировка города / улиц
1. `gen <город>_plan "<город: районы, главная улица N–S, площадь в центре, ворота …>" --style topdown --shape square`.
   Опирайся на заметки города (`obsidian/Pax RPG Vault/03 Мир/Города/…`) и текущий план (`config/<город>_map.json`).
2. Перевести картинку в данные: `ask "Return JSON: zones [{name, rect [x0,z0,x1,z1]}], roads [{name, width_m,
   points [[x,z]…]}], gates [[x,z]]; image center = (0,0), north = up = −Z, image spans −130…130 m" --img plan.png`
   (`--out` → файл). Сверь с картинкой, поправь руками.
3. Данные — в генератор: `pax_rpg/dev/gharn/map_data.py` (зоны → `config/gharn_map.json`), `gharn_layout.py`
   (дороги ROADS/TRAILS, постройки → `config/gharn.json`), чертёж `plan_map.py`. Для нового города — копия этих
   скриптов. Оси: центр (0,0), север = −Z, метры.

### Концепт-арт локаций
`gen <локация>_shot1 "<кадр>" --style yuruma --shape landscape` — референс настроения/цвета для `gfx`
(`config/location.json`), грейдинга (`pax_rpg/dev/style/`) и расстановки. Готовые промпты кадров —
в заметках `… — промпты концепт-арта.md` (первый блок кода — стиль; передавай кадр через `@file:`).

## 5. Правила
- В репо — только то, что идёт в игру или нужно как опорный референс (`pax_rpg/reference/<тема>/`); черновики
  живут на ПК и в `gpt-refs`. Не перезаписывай ассеты молча — новая версия `…_v2.png`, если автор не просил замену.
- Ключи/токены не печатай и не запрашивай в чате. Codex запускается с `-s read-only --ignore-user-config`:
  он только рисует, файлы копирует наш скрипт.
- В отчёте автору: итоговый путь, промпт, какой путь (Codex-подписка / API), превью (ссылка на `gpt-refs`).
