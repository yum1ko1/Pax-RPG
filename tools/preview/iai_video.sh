#!/usr/bin/env bash
# Видео приёма Иай: кадры из Godot (xvfb, программный рендер) + звуковая дорожка из sounds/iai_*.wav по моментам
# из лога (строки «iai_sound <имя> <с> <тон>»). Итог: <out>/iai.mp4 и раскадровка <out>/iai_sheet.jpg.
#   GODOT=<godot> tools/preview/iai_video.sh <out>
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/tools/ci/out/iai}"
PROJ="$ROOT/tools/ci/project"
rm -rf "$OUT" && mkdir -p "$OUT/frames"
rm -rf "$PROJ/mods/pax_rpg" && mkdir -p "$PROJ/mods" && cp -r "$ROOT/mods/pax_rpg" "$PROJ/mods/pax_rpg"
touch "$PROJ/mods/pax_rpg/models/.gdignore"
"$GODOT" --headless --path "$PROJ" --import > /dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$PROJ" --rendering-driver opengl3 --resolution 1280x720 \
  --fixed-fps 30 -s res://ci/preview_iai.gd -- "--out=$OUT/frames" > "$OUT/log.txt" 2>&1 || true
grep -E "SCRIPT ERROR|iai_sound|preview:" "$OUT/log.txt" | head -60
python3 "$ROOT/tools/preview/iai_audio.py" "$OUT/log.txt" "$ROOT/mods/pax_rpg/sounds" "$OUT/audio.wav"
ffmpeg -y -loglevel error -framerate 30 -i "$OUT/frames/f_%04d.jpg" -i "$OUT/audio.wav" -c:v libx264 -pix_fmt yuv420p \
  -crf 20 -c:a aac -shortest "$OUT/iai.mp4"
python3 - "$OUT" <<'PY'
import sys, glob
from PIL import Image, ImageDraw
out = sys.argv[1]
fs = sorted(glob.glob(out + "/frames/*.jpg"))
pick = [fs[int(i * (len(fs) - 1) / 15)] for i in range(16)]
W, H = 480, 270
sheet = Image.new("RGB", (W * 4, H * 4), (10, 10, 16))
d = ImageDraw.Draw(sheet)
for k, p in enumerate(pick):
    im = Image.open(p).resize((W, H))
    sheet.paste(im, ((k % 4) * W, (k // 4) * H))
    d.text(((k % 4) * W + 8, (k // 4) * H + 6), "%.1f s" % ((int(p[-8:-4]) - 10) / 30.0), fill=(255, 220, 120))
sheet.save(out + "/iai_sheet.jpg", quality=88)
PY
ls -la "$OUT"/iai.mp4 "$OUT"/iai_sheet.jpg
