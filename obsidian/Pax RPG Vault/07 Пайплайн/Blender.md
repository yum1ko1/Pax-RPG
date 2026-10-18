---
тип: пайплайн
tags: [пайплайн, blender]
---

# Blender

Blender на ПК, Claude управляет через мост: живой Blender (`blender_live.ps1`, код base64) или фоновый запуск
скриптом. Скрипты — `pax_rpg/dev/blender/`: рыцарь (`knight/assemble_knight.py`, `refine_knight.py`),
плащ (`build_cape.py`), портреты, город Гхарн (`gharn/` — простые модели: бочки, фонари, дороги, кладка).

Правила экспорта: glb, Y-вверх, метры, пивот на земле; меньше материалов; текстуры ≤ 2K.
