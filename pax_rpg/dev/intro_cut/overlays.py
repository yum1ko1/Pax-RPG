# Слои поверх картинки: кинорамка 2.39:1 + виньетка, субтитры RU/EN (плашка, имя), титры. ProRes 4444 с альфой.
import os, sys, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
FONTS = os.environ.get("PAX_FONTS", os.path.join(ROOT, "fonts"))
BAR = 138

SUBS = {  # (кто, с, по, текст)
    "ru": [("selune", 22.25, 24.60, "Остановись, сестра."),
           ("iru", 24.45, 26.55, "Небо не вечно…"),
           ("iru", 26.70, 28.00, "Как и мы."),
           ("iru", 28.05, 30.60, "Я не исчезну."),
           ("selune", 30.65, 32.70, "Мир не заплатит…"),
           ("selune", 32.75, 33.95, "…за твой страх."),
           ("both", 46.40, 48.95, "Мир не выдержит этой ноши…"),
           ("both", 49.25, 51.20, "Вознесись.")],
    "en": [("selune", 22.25, 24.60, "Stop, sister."),
           ("iru", 24.45, 26.55, "The sky is not eternal…"),
           ("iru", 26.70, 28.00, "Neither are we."),
           ("iru", 28.05, 30.60, "I will not fade."),
           ("selune", 30.65, 32.70, "The world will not pay…"),
           ("selune", 32.75, 33.95, "…for your fear."),
           ("both", 46.40, 48.95, "The world cannot bear this burden…"),
           ("both", 49.25, 51.20, "Ascend.")],
}
NAMES = {"ru": {"iru": "ИРУ", "selune": "СЕЛУНЭ"}, "en": {"iru": "IRU", "selune": "SELUNE"}}
NAME_COL = {"iru": (222, 192, 255), "selune": (244, 138, 142)}
TEXT_COL = {"iru": (255, 240, 248), "selune": (238, 238, 242), "both": (242, 236, 228)}
CARDS = {
    "ru": {"open": ("ЮРУМА", "Последний день целого неба"), "end": ("БИТВА ПРИ РАСКОЛЕ",)},
    "en": {"open": ("YURUMA", "The last day of the unbroken sky"), "end": ("THE BATTLE OF THE RIFT",)},
}


def font(name, size, wght=None):
    f = ImageFont.truetype(os.path.join(FONTS, name), size)
    if wght:
        try:
            f.set_variation_by_axes([wght])
        except Exception:
            pass
    return f


def spaced(draw, xy, text, fnt, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + spacing


def spaced_w(draw, text, fnt, spacing):
    return sum(draw.textlength(c, font=fnt) for c in text) + spacing * (len(text) - 1)


def encode(frames_iter, n, out):
    enc = subprocess.Popen([FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-frames:v", str(n), "-c:v", "prores_ks", "-profile:v", "4444",
                            "-vendor", "apl0", "-pix_fmt", "yuva444p10le", out], stdin=subprocess.PIPE)
    for fr in frames_iter:
        enc.stdin.write(fr.tobytes())
    enc.stdin.close()
    enc.wait()


def frame_layer():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2 * 0.9)
    vig = np.clip((r - 0.55) / 0.9, 0, 1) ** 1.6

    def bars(i):
        t = i / FPS
        def ease(x): x = min(1, max(0, x)); return x * x * (3 - 2 * x)
        k = ease((t - 6.6) / 0.7) * (1 - ease((t - 46.4) / 0.8))
        return int(round(BAR * k))
    cache = {}
    for i in range(TOTAL):
        b = bars(i)
        v = 0.42 if i < 1097 else 0.28
        key = (b, v)
        if key not in cache:
            a = (vig * v)
            if b:
                a[:b] = 1
                a[H - b:] = 1
            rgba = np.zeros((H, W, 4), np.uint8)
            rgba[..., 3] = (a * 255).astype(np.uint8)
            cache[key] = rgba
        yield cache[key]


def sub_image(lang, who, text):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ft = font("cormorant_garamond_italic.ttf", 42, 600)
    fn = font("cormorant_sc.ttf", 27, 600)
    tw = d.textlength(text, font=ft)
    has_name = who in ("iru", "selune")
    name = NAMES[lang].get(who, "")
    nw = spaced_w(d, name, fn, 6) if has_name else 0
    pad_x, pad_y = 26, 14
    th, nh, gap = 44, 28 if has_name else 0, 6 if has_name else 0
    bw = max(tw, nw) + pad_x * 2
    bh = th + nh + gap + pad_y * 2
    y1 = H - BAR - 24
    y0 = y1 - bh
    x0 = (W - bw) / 2
    plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle((x0, y0, x0 + bw, y1), radius=4, fill=(4, 3, 6, 168))
    img = Image.alpha_composite(img, plate)
    d = ImageDraw.Draw(img)
    ty = y0 + pad_y
    if has_name:
        spaced(d, ((W - nw) / 2, ty - 2), name, fn, NAME_COL[who] + (255,), 6)
        ty += nh + gap
    d.text(((W - tw) / 2, ty - 6), text, font=ft, fill=TEXT_COL[who] + (255,))
    return np.asarray(img)


def fade_clip(base, n, fin, fout):
    for i in range(n):
        k = min(1.0, (i + 1) / max(1, fin), (n - i) / max(1, fout))
        fr = base.copy()
        fr[..., 3] = (fr[..., 3].astype(np.float32) * k).astype(np.uint8)
        yield fr


def card_open(lang):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    big, small = CARDS[lang]["open"]
    fb = font("cormorant_sc.ttf", 64, 600)
    fs = font("cormorant_garamond_italic.ttf", 40, 600)
    bw = spaced_w(d, big, fb, 22)
    sw = d.textlength(small, font=fs)
    yb = H * 0.40
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    spaced(ds, ((W - bw) / 2, yb), big, fb, (20, 12, 30, 200), 22)
    ds.text(((W - sw) / 2, yb + 92), small, font=fs, fill=(20, 12, 30, 200))
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse((W / 2 - 460, yb - 70, W / 2 + 460, yb + 200), fill=(10, 6, 18, 120))
    img = Image.alpha_composite(img, shade.filter(ImageFilter.GaussianBlur(70)))
    img = Image.alpha_composite(img, sh)
    d = ImageDraw.Draw(img)
    spaced(d, ((W - bw) / 2, yb), big, fb, (255, 248, 236, 255), 22)
    d.line(((W / 2 - 120, yb + 80), (W / 2 + 120, yb + 80)), fill=(255, 230, 200, 160), width=1)
    d.text(((W - sw) / 2, yb + 92), small, font=fs, fill=(255, 244, 232, 255))
    return np.asarray(img)


def card_end(lang):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ft = font("katsuno_demo.ttf", 150)
    fs = font("cormorant_sc.ttf", 40, 600)
    d = ImageDraw.Draw(img)
    title = "PAX RPG"
    tw = d.textlength(title, font=ft)
    sub = CARDS[lang]["end"][0]
    sw = spaced_w(d, sub, fs, 12)
    ty = H * 0.20
    cx = W * 0.62
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((cx - tw / 2, ty + 8), title, font=ft, fill=(255, 40, 56, 210))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse((cx - 560, ty - 20, cx + 560, ty + 440), fill=(0, 0, 0, 130))
    shade = shade.filter(ImageFilter.GaussianBlur(60))
    img = Image.alpha_composite(img, shade)
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    d.text((cx - tw / 2, ty), title, font=ft, fill=(250, 238, 242, 255))
    bb = d.textbbox((cx - tw / 2, ty), title, font=ft)
    yl = bb[3] + 34
    d.line(((cx - 150, yl), (cx + 150, yl)), fill=(255, 90, 100, 180), width=2)
    spaced(d, (cx - sw / 2, yl + 16), sub, fs, (248, 232, 236, 255), 12)
    return np.asarray(img)


def build():
    os.makedirs(OV, exist_ok=True)
    encode(frame_layer(), TOTAL, os.path.join(OV, "frame_239.mov"))
    print("frame", flush=True)
    for lang in ("ru", "en"):
        for k, (who, a, b, text) in enumerate(SUBS[lang]):
            n = int(round((b - a) * FPS))
            encode(fade_clip(sub_image(lang, who, text), n, 7, 8), n, os.path.join(OV, f"sub_{lang}_{k + 1:02d}.mov"))
        encode(fade_clip(card_open(lang), 108, 20, 24), 108, os.path.join(OV, f"card_open_{lang}.mov"))
        encode(fade_clip(card_end(lang), 94, 22, 18), 94, os.path.join(OV, f"card_end_{lang}.mov"))
        print("subs+cards", lang, flush=True)


def preview(lang, t):
    base = np.asarray(Image.open(os.path.join(ROOT, "prev", f"t{t:05.2f}.jpg")).convert("RGBA"))
    lay = next(x for i, x in enumerate(frame_layer()) if i == int(t * FPS))
    out = Image.alpha_composite(Image.fromarray(base), Image.fromarray(lay))
    for who, a, b, text in SUBS[lang]:
        if a <= t < b:
            out = Image.alpha_composite(out, Image.fromarray(sub_image(lang, who, text)))
    if 1.0 <= t < 5.5:
        out = Image.alpha_composite(out, Image.fromarray(card_open(lang)))
    if t >= 51.8:
        out = Image.alpha_composite(out, Image.fromarray(card_end(lang)))
    out.convert("RGB").save(os.path.join(ROOT, "prev", f"ov_{lang}_{t:05.2f}.jpg"), quality=88)


if __name__ == "__main__":
    if sys.argv[1] == "build":
        build()
    else:
        preview(sys.argv[2], float(sys.argv[3]))
