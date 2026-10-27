"""Превью картинок для облачной сессии: уменьшенный JPEG в base64 прямо в вывод (мост отдаёт ≈ 30 000 символов
за раз — при --max 384 одна картинка влезает целиком). В облаке: текст между маркерами → base64 -d → файл → Read.

    python preview.py <папка или файлы…> [--max 384] [--q 70]
Альфа кладётся на серый фон, чтобы прозрачные места были видны.
"""
import base64
import os
import sys
from io import BytesIO

from PIL import Image

EXT = (".png", ".jpg", ".jpeg", ".webp")


def main():
    a = sys.argv[1:]
    mx, q, src = 384, 70, []
    i = 0
    while i < len(a):
        if a[i] in ("--max", "--q") and i + 1 < len(a):
            mx, q = (int(a[i + 1]), q) if a[i] == "--max" else (mx, int(a[i + 1]))
            i += 2
        else:
            src.append(a[i])
            i += 1
    files = []
    for s in src:
        if os.path.isdir(s):
            files += [os.path.join(s, f) for f in sorted(os.listdir(s)) if f.lower().endswith(EXT)]
        else:
            files.append(s)
    if not files:
        sys.exit(__doc__)
    for f in files:
        im = Image.open(f)
        size, mode = im.size, im.mode
        if im.mode in ("RGBA", "LA", "P"):
            im = im.convert("RGBA")
            bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
            im = Image.alpha_composite(bg, im)
        im = im.convert("RGB")
        im.thumbnail((mx, mx), Image.LANCZOS)
        b = BytesIO()
        im.save(b, format="JPEG", quality=q)
        print(f"=== {os.path.basename(f)} {size[0]}x{size[1]} {mode}")
        print("BEGIN_B64")
        print(base64.b64encode(b.getvalue()).decode())
        print("END_B64")


if __name__ == "__main__":
    main()
