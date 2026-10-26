# Два вертикальных шортса 1080×1920 из готового ролика (без пересборки плёнок): картинка 3:4 из кадра рамки
# 2.39 по центру, рамка следует за героями по склейкам; фон — тот же кадр, размытый и притемнённый; субтитры —
# заново, крупнее (шрифты мода, мягкая тень), выше нижнего интерфейса Shorts. Нужен ролик без вшитых субтитров
# не обязательно: полоса рамки в вырез не попадает. python shorts.py <ролик.mp4> <папка> [ru|en]
import os, sys, subprocess
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import overlays

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
W, H, BAR = 1920, 1080, 138
CW = 603                                   # ширина выреза: 804 × 3/4
OUT_W, OUT_H, PIC_Y, SUB_Y = 1080, 1920, 240, 1250
SUB_H = 300

# имя, с, по, ключи центра рамки (время ролика, доля ширины кадра)
SHORTS = [
    ("short1_volna_i_klinok", 13.90, 25.40,
     [(13.90, 0.50), (15.24, 0.50), (15.26, 0.30), (16.5, 0.32), (19.5, 0.48), (20.28, 0.50), (20.30, 0.43),
      (25.40, 0.42)]),
    ("short2_predatelstvo", 28.40, 41.80,
     [(28.40, 0.50), (28.74, 0.50), (28.76, 0.59), (31.24, 0.59), (31.26, 0.525), (32.74, 0.525), (32.76, 0.60),
      (37.90, 0.60), (37.92, 0.50), (41.80, 0.50)]),
]


def x_expr(a, keys):
    # кусочно-линейный центр рамки → левый край выреза в пикселях; t — время от начала шортса
    k = [(t - a, c * W - CW / 2) for t, c in keys]
    e = f"{k[-1][1]:.1f}"
    for (t0, x0), (t1, x1) in reversed(list(zip(k, k[1:]))):
        e = f"if(lt(t,{t1:.3f}),{x0:.1f}+({x1 - x0:.1f})*(t-{t0:.3f})/{max(t1 - t0, 1e-3):.3f},{e})"
    return f"clip({e},0,{W - CW})"


def sub_png(lang, who, text, path):
    # имя капителью над строкой курсивом; тень — размытый тёмный контур под буквами, без плашки
    img = Image.new("RGBA", (OUT_W, SUB_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ft = overlays.font("cormorant_garamond_italic.ttf", 66, 600)
    fn = overlays.font("cormorant_sc.ttf", 36, 600)
    name = overlays.NAMES[lang].get(who, "")
    y_text = 120 if name else 100
    tw = d.textlength(text, font=ft)
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    if name:
        nw = overlays.spaced_w(d, name, fn, 8)
        overlays.spaced(ds, ((OUT_W - nw) / 2, 66), name, fn, (8, 4, 14, 255), 8)
    ds.text(((OUT_W - tw) / 2, y_text), text, font=ft, fill=(8, 4, 14, 255), stroke_width=6, stroke_fill=(8, 4, 14, 255))
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(9)))
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(3)))
    d = ImageDraw.Draw(img)
    if name:
        overlays.spaced(d, ((OUT_W - nw) / 2, 66), name, fn, overlays.NAME_COL[who] + (255,), 8)
    d.text(((OUT_W - tw) / 2, y_text), text, font=ft, fill=overlays.TEXT_COL[who] + (255,))
    img.save(path)


def make(src, out_dir, name, a, b, keys, lang):
    d = b - a
    subs = [(who, max(t0, a), min(t1, b), text) for who, t0, t1, text in overlays.SUBS[lang] if t1 > a and t0 < b]
    ins = ["-i", src]
    g = [f"[0:v]trim=start={a}:end={b},setpts=PTS-STARTPTS,split=2[v1][v2]",
         f"[v1]crop=452:804:734:{BAR},scale=270:480,boxblur=12:2,scale={OUT_W}:{OUT_H},eq=brightness=-0.16:saturation=0.85[bg]",
         f"[v2]crop={CW}:804:'{x_expr(a, keys)}':{BAR},scale={OUT_W}:1440:flags=lanczos[pic]",
         f"[bg][pic]overlay=0:{PIC_Y}[c0]"]
    last = "c0"
    for i, (who, t0, t1, text) in enumerate(subs):
        png = os.path.join(out_dir, f"{name}_sub{i}.png")
        sub_png(lang, who, text, png)
        ins += ["-loop", "1", "-t", f"{t1 - t0:.3f}", "-i", png]
        s0, dd = t0 - a, t1 - t0
        g.append(f"[{i + 1}:v]format=rgba,fade=t=in:st=0:d=0.2:alpha=1,fade=t=out:st={dd - 0.25:.3f}:d=0.25:alpha=1,"
                 f"setpts=PTS-STARTPTS+{s0:.3f}/TB[s{i}]")
        g.append(f"[{last}][s{i}]overlay=0:{SUB_Y}:eof_action=pass[c{i + 1}]")
        last = f"c{i + 1}"
    g.append(f"[{last}]format=yuv420p[v]")
    g.append(f"[0:a]atrim=start={a}:end={b},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.04,afade=t=out:st={d - 0.25:.2f}:d=0.25[a]")
    out = os.path.join(out_dir, f"{name}_{lang}.mp4")
    subprocess.run([FFMPEG, "-v", "error", "-y"] + ins + ["-filter_complex", ";".join(g), "-map", "[v]", "-map", "[a]",
                    "-c:v", "libx264", "-crf", "16", "-preset", "slow", "-r", "24", "-c:a", "aac", "-b:a", "256k",
                    "-movflags", "+faststart", "-t", f"{d:.3f}", out], check=True)
    print("short", out, flush=True)


if __name__ == "__main__":
    src, out_dir = sys.argv[1], sys.argv[2]
    lang = sys.argv[3] if len(sys.argv) > 3 else "ru"
    os.makedirs(out_dir, exist_ok=True)
    for s in SHORTS:
        make(src, out_dir, *s, lang)
