#!/bin/sh
# Ролики приёмов для подсказки инвентаря (Алый Закат, Иай): Godot 4.5.1 рендерит сцену main.tscn в кадры, ffmpeg — в WebM.
#   GODOT=/путь/к/Godot_v4.5.1 sh pax_rpg/dev/skill_clips/run.sh sunset|iai
# Без экрана — через xvfb-run. Модели копируются в pax/ (чтобы импорт Godot не мусорил в mods/pax_rpg/models).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"; M="$HERE/../../../mods/pax_rpg/models"; S="${1:-sunset}"
mkdir -p "$HERE/pax/models/heroes/tian_long" "$HERE/pax/models/weapons" "$HERE/out/$S"
cp "$M/heroes/tian_long/model.glb" "$M/heroes/tian_long/anim.json" "$HERE/pax/models/heroes/tian_long/"
cp "$M/weapons/katana.glb" "$M/weapons/katana_saya.glb" "$HERE/pax/models/weapons/"
"${GODOT:-godot}" --headless --path "$HERE" --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 640x360x24" "${GODOT:-godot}" --path "$HERE" --rendering-driver opengl3 \
  --write-movie "$HERE/out/$S/f.png" --fixed-fps 30 -- "$S"
ffmpeg -y -loglevel error -framerate 30 -i "$HERE/out/$S/f%08d.png" -vf scale=480:270:flags=lanczos \
  -c:v libvpx-vp9 -b:v 0 -crf 38 -row-mt 1 -an -pix_fmt yuv420p "$HERE/out/clip_$S.webm"
echo "$HERE/out/clip_$S.webm"
