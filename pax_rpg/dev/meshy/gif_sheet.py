"""Контактный лист превью анимаций библиотеки Meshy: python gif_sheet.py out.png Roll_Dodge Stand_Dodge ..."""
import urllib.request, io, sys
from PIL import Image, ImageDraw
names = sys.argv[2:]
out = sys.argv[1]
rows = []
for n in names:
    data = urllib.request.urlopen("https://cdn.meshy.ai/webapp-assets/feature-demo/animation/preview/biped/%s.gif" % n, timeout=60).read()
    im = Image.open(io.BytesIO(data))
    frames = []
    try:
        while True:
            frames.append(im.convert("RGB").copy())
            im.seek(im.tell() + 1)
    except EOFError:
        pass
    pick = [frames[int(i * (len(frames) - 1) / 7)] for i in range(8)]
    w = 200
    row = Image.new("RGB", (w * 8, w + 20), "white")
    for i, f in enumerate(pick):
        f.thumbnail((w, w))
        row.paste(f, (i * w, 20))
    ImageDraw.Draw(row).text((4, 4), "%s  (%d frames)" % (n, len(frames)), fill="black")
    rows.append(row)
sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), "white")
y = 0
for r in rows:
    sheet.paste(r, (0, y)); y += r.height
sheet.save(out)
print("ok", out)
