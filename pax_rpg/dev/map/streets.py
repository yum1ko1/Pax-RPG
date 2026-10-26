"""Названия улиц вдоль дорог: размер шрифта подбирается по ширине дороги из маски (roads_mask, R — кладка),
текст не выходит за края дороги; круговая площадь — текст по дуге."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'mods', 'pax_rpg') + '/'
MASK = np.asarray(Image.open(T + 'models/gharn/tex/roads_mask.png').convert('RGB'))[:, :, 0] > 110
MR = (-95.0, -99.0, 190.0, 186.0)
# улица: (ключ, вид, параметры, ширина дороги м, отступ от краёв)
STREETS = [
    ('pax_rpg_lm_trakt', 'line', ((0, 76), (0, 33)), 10.0),      # главная: от ворот к площади (читается снизу вверх)
    ('pax_rpg_lm_alley', 'line', ((-77, 0), (-31, 0)), 17.0),
    ('pax_rpg_lm_alley', 'line', ((31, 0), (77, 0)), 17.0),
    ('pax_rpg_lm_masters', 'line', ((8, 57.5), (86, 57.5)), 4.2),  # кладка 3 м, на арте бордюр-бордюр ≈4.2 м
    ('pax_rpg_lm_circle', 'arc', (0, 0, 26.0, -150, -30), 8.0),   # дуга r 26 м по северной части кольца
]
def on_road(x, z):
    px = int((x - MR[0]) * MASK.shape[1] / MR[2]); pz = int((z - MR[1]) * MASK.shape[0] / MR[3])
    return 0 <= px < MASK.shape[1] and 0 <= pz < MASK.shape[0] and MASK[pz, px]
def _font(path, fs): return ImageFont.truetype(T + 'fonts/' + path, max(6, int(fs)))
def _render(txt, f, sp, fill, shadow=(12, 4, 6, 255), bold=0, glow=2):
    """строка текста; картинка обрезана симметрично вокруг середины прописных букв,
    чтобы центр картинки = ось улицы (хвосты Ц/Щ/Д и диакритика Ё не сдвигают подпись)"""
    w = int(sum(f.getlength(c) for c in txt) + sp * (len(txt) - 1)) + 12
    H = int(f.size * 2.2); im = Image.new('RGBA', (w, H))
    d = ImageDraw.Draw(im); x = 6
    for c in txt:
        d.text((x, H / 2), c, font=f, fill=fill, anchor='lm', stroke_width=bold, stroke_fill=fill); x += f.getlength(c) + sp
    bb = im.getbbox()
    if not bb: return im, 0
    cb = f.getbbox('Н', anchor='lm'); cy = H / 2 + (cb[1] + cb[3]) / 2
    half = int(max(cy - bb[1], bb[3] - cy)) + 4
    im = im.crop((bb[0] - 4, int(cy) - half, bb[2] + 4, int(cy) + half))
    sh = Image.new('RGBA', im.size, shadow); sh.putalpha(im.getchannel('A').filter(ImageFilter.GaussianBlur(1.6 + 0.3 * (glow - 2))))
    out = Image.new('RGBA', im.size)
    for _ in range(glow): out.alpha_composite(sh)
    out.alpha_composite(im)
    return out, bb[3] - bb[1]
FILL_H = {'pax_rpg_lm_masters': 0.7}
MAX_FS = {'pax_rpg_lm_alley': 0.85}  # иерархия: главная улица крупнее аллей
def _clip(p0, p1, c):
    """отрезок p0-p1 (мир) внутри круга c=(x, z, r) с полем; None если почти не виден"""
    (x0, z0), (x1, z1) = p0, p1; cx, cz, r = c
    dx, dz = x1 - x0, z1 - z0; A = dx * dx + dz * dz; B = 2 * ((x0 - cx) * dx + (z0 - cz) * dz)
    C = (x0 - cx) ** 2 + (z0 - cz) ** 2 - r * r; D = B * B - 4 * A * C
    if D <= 0: return None
    t0, t1 = max(0.0, (-B - D ** 0.5) / (2 * A)), min(1.0, (-B + D ** 0.5) / (2 * A))
    if t1 - t0 < 1e-3: return None
    return (x0 + dx * t0, z0 + dz * t0), (x0 + dx * t1, z0 + dz * t1)
def check(layer, to):
    """доля непрозрачных пикселей букв (без тени) вне дорожной маски"""
    a = np.asarray(layer)[:, :, 3]; ys, xs = np.nonzero(a > 200)
    o = np.array(to(0, 0)); ex = np.array(to(1, 0)) - o; ez = np.array(to(0, 1)) - o
    M = np.linalg.inv(np.array([ex, ez]).T)
    w = M @ (np.stack([xs, ys]).astype(float) - o[:, None])
    px = ((w[0] - MR[0]) * MASK.shape[1] / MR[2]).astype(int); pz = ((w[1] - MR[1]) * MASK.shape[0] / MR[3]).astype(int)
    ok = (px >= 0) & (px < MASK.shape[1]) & (pz >= 0) & (pz < MASK.shape[0])
    road = np.zeros(len(xs), bool); road[ok] = MASK[pz[ok], px[ok]]
    return 1 - road.mean() if len(xs) else 0.0
def draw(cv, to, ppm, lang, rot=0.0, font='cormorant_sc.ttf', fill=(244, 230, 202, 240), fill_h=0.55, max_fs=34, report=None, clip=None, min_fs=7, track=0.22, lfit=0.86):
    """to(x, z) → экранные px; ppm — px на метр; rot — поворот карты (миникарта), рад;
    clip=(x, z, r) мир — видимый круг миникарты (подписи режутся по нему)."""
    for key, kind, prm, wm in STREETS:
        lay = Image.new('RGBA', cv.size)
        _street(lay, to, ppm, lang, rot, font, fill, fill_h, max_fs, clip, min_fs, key, kind, prm, wm, track, lfit)
        if not lay.getbbox(): continue
        if clip:
            c = to(clip[0], clip[1]); r = clip[2] * ppm; m = Image.new('L', cv.size, 0)
            ImageDraw.Draw(m).ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=255)
            lay.putalpha(Image.fromarray(np.minimum(np.asarray(lay.getchannel('A')), np.asarray(m))))
        if report is not None: report.append((key, round(check(lay, to), 3)))
        cv.alpha_composite(lay)
def _street(cv, to, ppm, lang, rot, font, fill, fill_h, max_fs, clip, min_fs, key, kind, prm, wm, track, lfit):
        txt = lang[key].upper()
        hmax = wm * ppm * (FILL_H.get(key, fill_h) if fill_h < 0.8 else fill_h)
        if kind == 'line':
            (x0, z0), (x1, z1) = prm
            if clip:
                cs = _clip((x0, z0), (x1, z1), clip)
                if not cs: return
                (x0, z0), (x1, z1) = cs
            L = math.hypot((x1 - x0), (z1 - z0)) * ppm * lfit
            fs = int(max_fs * MAX_FS.get(key, 1))
            while fs >= min_fs:
                f = _font(font, fs); sp = fs * track
                im, h = _render(txt, f, sp, fill)
                if h <= hmax and im.width <= L: break
                fs -= 1
            if fs < min_fs: return
            a = math.degrees(math.atan2(-(to(x1, z1)[1] - to(x0, z0)[1]), to(x1, z1)[0] - to(x0, z0)[0]))
            r = im.rotate(a, expand=True, resample=Image.BICUBIC)
            c = to((x0 + x1) / 2, (z0 + z1) / 2)
            cv.alpha_composite(r, (int(c[0] - r.width / 2), int(c[1] - r.height / 2)))
        else:
            cx, cz, R, a0, a1 = prm
            fs = max_fs
            if clip and math.hypot(cx + R * math.cos(math.radians((a0 + a1) / 2)) - clip[0],
                                   cz + R * math.sin(math.radians((a0 + a1) / 2)) - clip[1]) > clip[2] * 0.8: return
            while fs >= min_fs:
                f = _font(font, fs); sp = fs * 0.3
                tw = sum(f.getlength(c) for c in txt) + sp * (len(txt) - 1)
                _, h = _render(txt, f, sp, fill)
                if h <= hmax and tw <= math.radians(a1 - a0) * R * ppm: break
                fs -= 1
            if fs < min_fs: return
            f = _font(font, fs); sp = fs * 0.3
            tw = sum(f.getlength(c) for c in txt) + sp * (len(txt) - 1)
            ang = math.radians((a0 + a1) / 2) - tw / 2 / (R * ppm)
            for ch in txt:
                cw = f.getlength(ch)
                am = ang + (cw / 2) / (R * ppm)
                x, z = cx + R * math.cos(am), cz + R * math.sin(am)
                im, _ = _render(ch, f, 0, fill)
                deg = -math.degrees(am) - 90 - math.degrees(rot)
                r = im.rotate(deg, expand=True, resample=Image.BICUBIC)
                p = to(x, z); cv.alpha_composite(r, (int(p[0] - r.width / 2), int(p[1] - r.height / 2)))
                ang += (cw + sp) / (R * ppm)

# ---- мелкие подписи (дворы, закоулки, кварталы): ищем ближайший прямой участок дороги/двора по маске
# (R кладка | G тропы и дворы), куда строка целиком влезает с запасом от краёв, и кладём её вдоль него
ROAD = MASK | (np.asarray(Image.open(T + 'models/gharn/tex/roads_mask.png').convert('RGB'))[:, :, 1] > 110)
def _on(x, z, m=ROAD):
    px = ((x - MR[0]) * m.shape[1] / MR[2]).astype(int); pz = ((z - MR[1]) * m.shape[0] / MR[3]).astype(int)
    ok = (px >= 0) & (px < m.shape[1]) & (pz >= 0) & (pz < m.shape[0])
    r = np.zeros(x.shape, bool); r[ok] = m[pz[ok], px[ok]]; return r
def draw_small(cv, to, ppm, lang, labels, occ, font='cormorant_garamond_italic.ttf', fill=(240, 224, 196, 240),
               max_fs=19, min_fs=13, pad=0.2, report=None):
    """labels: {ключ: (x, z, радиус поиска м)}; occ — bool [H, W] занятые экранные пиксели (подписи, маркеры, панели)"""
    o = np.array(to(0, 0)); Hh, Ww = occ.shape
    for key, (ax, az, rad) in labels.items():
        txt = lang[key]; best = None
        gx, gz = np.meshgrid(np.arange(ax - rad, ax + rad + 0.1, 0.5), np.arange(az - rad, az + rad + 0.1, 0.5))
        sel = ((gx - ax) ** 2 + (gz - az) ** 2 <= rad * rad); gx, gz = gx[sel], gz[sel]
        sel = _on(gx, gz); gx, gz = gx[sel], gz[sel]
        for fs in range(max_fs, min_fs - 1, -1):
            f = _font(font, fs); im, h = _render(txt, f, fs * 0.04, fill, glow=4)
            wm, hm = (im.width - 8) / ppm + 2 * pad, (im.height - 8) / ppm + 2 * pad
            su, sv = np.meshgrid(np.linspace(-wm / 2, wm / 2, max(3, int(wm / 0.4))), np.linspace(-hm / 2, hm / 2, max(3, int(hm / 0.35))))
            su, sv = su.ravel(), sv.ravel()
            for a in range(-90, 90, 5):
                ux, uz = math.cos(math.radians(a)), math.sin(math.radians(a))
                X = gx[:, None] + su[None] * ux - sv[None] * uz; Z = gz[:, None] + su[None] * uz + sv[None] * ux
                good = _on(X.ravel(), Z.ravel()).reshape(X.shape).all(1)
                if a % 90:   # косо — только вдоль узкого проезда, не поперёк широкого двора
                    t = np.arange(-1.6 * hm, 1.6 * hm + 0.01, 0.3)
                    wide = _on(gx[:, None] - t[None] * uz, gz[:, None] + t[None] * ux).all(1)
                    good &= ~wide
                if not good.any(): continue
                PX = (o[0] + X * ppm).astype(int); PY = (o[1] + Z * ppm).astype(int)   # to() — равномерный масштаб без поворота
                ins = ((PX >= 0) & (PX < Ww) & (PY >= 0) & (PY < Hh)).all(1)
                good &= ins
                if not good.any(): continue
                idx = np.nonzero(good)[0]
                free = ~occ[np.clip(PY[idx], 0, Hh - 1), np.clip(PX[idx], 0, Ww - 1)].any(1)
                idx = idx[free]
                if not len(idx): continue
                sc = np.hypot(gx[idx] - ax, gz[idx] - az) + (abs(a) % 90 > 0) * 4.0
                i = idx[sc.argmin()]
                if best is None or sc.min() < best[0]: best = (sc.min(), gx[i], gz[i], a, im, PX[i], PY[i])
            if best: break
        if not best:
            if report is not None: report.append((key, None)); continue
        _, x, z, a, im, PX, PY = best
        r = im.rotate(-a, expand=True, resample=Image.BICUBIC); c = to(x, z)
        cv.alpha_composite(r, (int(c[0] - r.width / 2), int(c[1] - r.height / 2)))
        occ[np.clip(PY, 0, Hh - 1), np.clip(PX, 0, Ww - 1)] = True
        # подпись целиком занимает свой прямоугольник + поле
        if report is not None: report.append((key, fs, round(x, 1), round(z, 1), a))
