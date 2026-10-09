#!/bin/sh
# Прогон механики Pax RPG без игры: заглушки PaxMod/PaxGame (stub/), сцена stub/test.tscn щёлкает по городу Гхарн,
# ходит на W, прыгает, подходит к воротам, жмёт E и проверяет возврат на карту. Снимки — /tmp/pax_rpg_shot_*.png.
#   GODOT=/путь/к/Godot_v4.5.1 sh pax_rpg/dev/godot_test/run.sh
# Без экрана: xvfb-run -s "-screen 0 1280x720x24" … --rendering-driver opengl3 (или --headless — без снимков).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/mods"
[ -e "$HERE/mods/pax_rpg" ] || ln -s "$HERE/../../../mods/pax_rpg" "$HERE/mods/pax_rpg"
"${GODOT:-godot}" --path "$HERE" --import >/dev/null 2>&1 || true
exec "${GODOT:-godot}" --path "$HERE" "$@"
