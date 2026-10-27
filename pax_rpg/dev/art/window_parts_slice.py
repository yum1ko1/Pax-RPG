"""Детали окон (ranks/window_parts_v1.webp) → ui/: 9-slice рамка окна описаний, отдельно ромб верха, гнездо иконки,
рамка видео, разделитель, полоска шкалы, ромб-отметка. Иконки рангов ranks/rank_0…6.webp → ui/rank_N_s.png.
    python parts_slice.py <pax_rpg/reference/inventory/ranks> <ui>"""
import sys, os
import numpy as np
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
w = Image.open(os.path.join(src, "window_parts_v1.webp")).convert("RGBA")
B = {"frame": (35, 68, 819, 575), "socket": (858, 170, 1232, 538), "video": (52, 643, 731, 994),
     "divider": (761, 813, 1230, 882), "marker": (1044, 1051, 1176, 1181), "track": (58, 1066, 963, 1159)}
def trim(c):
    a = np.asarray(c)[..., 3]; ys, xs = np.where(a > 20)
    return c.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
def fit(c, w=None, h=None):
    s = (w / c.width) if w else (h / c.height)
    return c.resize((round(c.width * s), round(c.height * s)), Image.LANCZOS)
P = {n: trim(w.crop(b)) for n, b in B.items()}
# рамка: углы с сакурой и гнездом кольца целиком, края — короткий ровный кусок; ромб верха — отдельной картинкой
f = P["frame"]; W, H = f.size; L, R, T, Bo, E = 135, 130, 165, 130, 60
nine = Image.new("RGBA", (L + E + R, T + E + Bo))
def put(box, at): nine.paste(f.crop(box), at)
put((0, 0, L, T), (0, 0)); put((W - R, 0, W, T), (L + E, 0)); put((0, H - Bo, L, H), (0, T + E)); put((W - R, H - Bo, W, H), (L + E, T + E))
put((180, 0, 180 + E, T), (L, 0)); put((180, H - Bo, 180 + E, H), (L, T + E))
put((0, 200, L, 200 + E), (0, T)); put((W - R, 200, W, 200 + E), (L + E, T)); put((300, 200, 300 + E, 200 + E), (L, T))
fit(nine, h=round(nine.height * 0.5)).save(os.path.join(out, "wf_frame_s.png"), optimize=True)
fit(f.crop((W // 2 - 70, 0, W // 2 + 70, 75)), h=36).save(os.path.join(out, "wf_gem_s.png"), optimize=True)
fit(P["socket"], h=120).save(os.path.join(out, "wf_socket_s.png"), optimize=True)
fit(P["video"], w=480).save(os.path.join(out, "wf_video_s.png"), optimize=True)
fit(P["divider"], w=420).save(os.path.join(out, "wf_div_s.png"), optimize=True)
fit(P["track"], w=600).save(os.path.join(out, "wf_track_s.png"), optimize=True)
fit(P["marker"], h=48).save(os.path.join(out, "wf_marker_s.png"), optimize=True)
print("nine", nine.size, "slices", T, R, Bo, L, "→ ×0.5")
for i in range(7):
    c = trim(Image.open(os.path.join(src, f"rank_{i}.webp")).convert("RGBA"))
    s = 144 / max(c.size); c = c.resize((round(c.width * s), round(c.height * s)), Image.LANCZOS)
    sq = Image.new("RGBA", (144, 144)); sq.alpha_composite(c, ((144 - c.width) // 2, (144 - c.height) // 2))
    sq.save(os.path.join(out, f"rank_{i}_s.png"), optimize=True)
for n in ["video", "track"]:
    print(n, fit(P[n], w=480 if n == "video" else 600).size)
