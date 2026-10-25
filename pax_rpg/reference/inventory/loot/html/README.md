# Прокрутка лута — HTML-тест

Собирается из прототипа подсказки (`reference/inventory/tooltip_prototype`, исходник `tooltip_src.html`) и `loot_roll.js`:

    python build_loot.py <папка с tooltip_src.html, ui/, items*.jpg и loot/>

В `loot/` — картинки из `mods/pax_rpg/textures/loot`, звуки `sounds/loot_*.ogg` и `katana_sheet.webp`
(159 кадров 3D-катаны из `roll.gd`: `tools/ci/project/ci/preview_loot.gd --kat=<папка>`, склейка 12 × 14 по 384 × 480).
Тайминги и размеры — те же, что в `src/location/loot/roll.gd`.
