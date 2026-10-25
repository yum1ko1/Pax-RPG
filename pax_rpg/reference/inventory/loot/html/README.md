# Прокрутка лута — HTML-тест

Собирается из прототипа подсказки (`reference/inventory/tooltip_prototype`, исходник `tooltip_src.html`) и `loot_roll.js`:

    python build_loot.py <папка с tooltip_src.html, ui/, items*.jpg и loot/>

В `loot/` — картинки из `mods/pax_rpg/textures/loot`, звуки `sounds/loot_*.ogg` и `katana_sheet.webp`
(80 кадров 3D-катаны из `roll.gd`: `tools/ci/project/ci/preview_loot.gd --kat=<папка>`, склейка 10 × 8 по 192 × 320).
Тайминги и размеры — те же, что в `src/location/loot/roll.gd`.
