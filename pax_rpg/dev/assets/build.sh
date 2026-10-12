#!/bin/sh
# Модели мода для игры: из исходников pax_rpg/dev/models_src/ (glb с JPEG) →
#   mods/pax_rpg/models/<name>.tex/*.dds — сжатые текстуры (bake_textures.gd);
#   mods/pax_rpg/models/<name>.glb — тот же glb без картинок (strip_glb.py).
# Новая или изменённая модель: положить исходник в models_src/ и запустить:  GODOT=<godot editor> sh build.sh
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
SRC=$R/pax_rpg/dev/models_src
DST=$R/mods/pax_rpg/models
P=$(mktemp -d)
echo 'config_version=5' > "$P/project.godot"
"$GODOT" --headless --path "$P" -s "$R/pax_rpg/dev/assets/bake_textures.gd" -- "$SRC" "$DST" 2>&1 | grep -v '^Godot\|^$\|leaked\|PagedAllocator\|at: \|Leaked'
cd "$SRC"
find . -name '*.glb' | while read f; do python3 "$R/pax_rpg/dev/assets/strip_glb.py" "$f" "$DST/${f#./}"; done
rm -rf "$P"
