"""Запекает карту Гхарна для игры: арт плана (gharn_art.png, 264×264 м с центром в 0, 0) + названия улиц вдоль дорог
(streets.py) и мелкие подписи дворов. Значки мест, герой, враги и подсказки игра рисует сама (city_map.gd, hud2.gd).
    python3 pax_rpg/dev/map/bake_gharn_map.py
Пишет mods/pax_rpg/textures/map/:
    gharn_map_<ru|en>.jpg  — большая карта (M), 7 px/м
    gharn_mini_<ru|en>.jpg — миникарта, 4.34 px/м (вдвое крупнее показа в 1080p), подписи под её масштаб и значки мест
    glyphs.png             — значки мест (5×4 по 96 px), номер — config/gharn_map.json → art.markers"""
import json
import os
import sys
import importlib.util
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
MOD = os.path.join(ROOT, 'mods', 'pax_rpg')
OUT = os.path.join(MOD, 'textures', 'map')
sp = importlib.util.spec_from_file_location('streets', os.path.join(HERE, 'streets.py'))
ST = importlib.util.module_from_spec(sp)
sp.loader.exec_module(ST)
A = 132.0                                      # арт — квадрат ±132 м
# значок места → номер картинки в gl/ (те же, что на утверждённой карте v5)
MARKERS = {'pax_rpg_lm_gate': 0, 'pax_rpg_lm_khan': 1, 'pax_rpg_lm_arena': 2, 'pax_rpg_lm_guild': 4, 'pax_rpg_lm_tavern': 5,
           'pax_rpg_lm_bazaar': 6, 'pax_rpg_lm_shamans': 8, 'pax_rpg_lm_forge': 15}
BIG = ('pax_rpg_lm_gate', 'pax_rpg_lm_khan', 'pax_rpg_lm_arena')
KCOL = {'gate': (120, 170, 200), 'fight': (196, 40, 52), 'trade': (200, 150, 60), 'rest': (200, 150, 60), 'craft': (170, 110, 70),
        'power': (140, 80, 160), 'nature': (90, 140, 90), 'beast': (150, 120, 80), 'home': (130, 110, 90), 'road': (160, 120, 100)}
GOLD = (214, 172, 98, 255)
# мелкие подписи: якорь (x, z) и радиус поиска места вдоль проезда, м
SMALL = {'pax_rpg_lm_kurgans': (-62, -80, 16), 'pax_rpg_lm_garden': (0, -86, 16), 'pax_rpg_lm_kennels': (35, -84, 14),
         'pax_rpg_lm_goblins': (48, -40, 16), 'pax_rpg_lm_barracks': (-50, -45, 16), 'pax_rpg_lm_bazaar': (-54, 24, 14),
         'pax_rpg_lm_clans': (-54, 62, 14), 'pax_rpg_lm_buffalo': (32, 36, 12), 'pax_rpg_lm_stable': (72, 28, 14),
         'pax_rpg_lm_fountain': (28, 20, 12), 'pax_rpg_lm_shamans': (62, -50, 14), 'pax_rpg_lm_forge': (-32, -23, 7)}
GL = [Image.open(os.path.join(HERE, 'gl', '%02d.png' % i)).convert('RGBA') for i in range(20)]


def marker(cv, q, idx, kind, s):
    """ромб места: тень, тёмная заливка, золотой кант, внутренний кант цвета вида, значок"""
    d = ImageDraw.Draw(cv)
    r = s * 0.62
    k = s / 28.0
    c = KCOL.get(kind, (120, 40, 40))
    sh = Image.new('RGBA', (int(r * 4), int(r * 4)))
    ImageDraw.Draw(sh).ellipse((r * 0.6, r * 0.9, r * 3.4, r * 3.6), fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(5 * k))
    cv.alpha_composite(sh, (int(q[0] - r * 2), int(q[1] - r * 2)))
    P = [(q[0], q[1] - r), (q[0] + r, q[1]), (q[0], q[1] + r), (q[0] - r, q[1])]
    d.polygon(P, fill=(24, 8, 10, 235))
    d.line(P + [P[0]], fill=GOLD, width=max(2, round(2 * k)))
    i = 5 * k
    d.polygon([(q[0], q[1] - r + i), (q[0] + r - i, q[1]), (q[0], q[1] + r - i), (q[0] - r + i, q[1])], outline=c + (200,))
    g = GL[idx].resize((int(s * 0.74),) * 2, Image.LANCZOS)
    cv.alpha_composite(g, (int(q[0] - g.width / 2), int(q[1] - g.height / 2)))


def bake(lang_id, mp):
    lang = json.load(open(os.path.join(MOD, 'data', 'lang', lang_id + '.json'), encoding='utf-8'))
    art = Image.open(os.path.join(HERE, 'gharn_art.png')).convert('RGBA')
    pois = {p['key']: p for p in mp['pois']}
    # --- большая карта
    ppm = 7.0
    k = ppm / 5.2                               # подписи подобраны на 5.2 px/м (карта v5)
    side = int(2 * A * ppm)
    cv = art.resize((side, side), Image.LANCZOS)
    to = lambda x, z: ((x + A) * ppm, (z + A) * ppm)
    sl = Image.new('RGBA', cv.size)
    rep = []
    ST.draw(sl, to, ppm, lang, max_fs=int(34 * k), min_fs=int(7 * k), report=rep)
    cv.alpha_composite(sl)
    om = sl.getchannel('A').point(lambda v: 255 if v > 16 else 0).filter(ImageFilter.MaxFilter(11))
    dm = ImageDraw.Draw(om)
    for key in MARKERS:
        q = to(pois[key]['x'], pois[key]['z'])
        r = 28 * k * (34 / 28 if key in BIG else 1)
        dm.ellipse((q[0] - r, q[1] - r, q[0] + r, q[1] + r), fill=255)
    occ = np.asarray(om) > 0
    rs = []
    ST.draw_small(cv, to, ppm, lang, SMALL, occ, max_fs=int(19 * k), min_fs=int(13 * k), report=rs)
    print(lang_id, 'streets', rep)
    print(lang_id, 'small', rs)
    cv.convert('RGB').save(os.path.join(OUT, 'gharn_map_%s.jpg' % lang_id), quality=90)
    # --- миникарта: в 1080p круг 97.6 px на 45 м — 2.17 px/м; запекаем вдвое крупнее
    ppm = 4.34
    side = int(2 * A * ppm)
    cv = art.resize((side, side), Image.LANCZOS)
    to = lambda x, z: ((x + A) * ppm, (z + A) * ppm)
    sl = Image.new('RGBA', cv.size)
    rep = []
    ST.draw(sl, to, ppm, lang, max_fs=36, fill_h=0.9, min_fs=16, track=0.1, lfit=0.97, report=rep)
    cv.alpha_composite(sl)
    for key, idx in MARKERS.items():
        marker(cv, to(pois[key]['x'], pois[key]['z']), idx, pois[key]['kind'], s=44)
    print(lang_id, 'mini', rep)
    cv.convert('RGB').save(os.path.join(OUT, 'gharn_mini_%s.jpg' % lang_id), quality=90)


def atlas():
    at = Image.new('RGBA', (96 * 5, 96 * 4))
    for i, g in enumerate(GL):
        at.alpha_composite(g, ((i % 5) * 96, (i // 5) * 96))
    at.save(os.path.join(OUT, 'glyphs.png'), optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    mp = json.load(open(os.path.join(MOD, 'config', 'gharn_map.json'), encoding='utf-8'))
    atlas()
    for lg in sys.argv[1:] or ['ru', 'en']:
        bake(lg, mp)
