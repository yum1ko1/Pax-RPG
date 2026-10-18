import sys
"""Планировка локации Гхарна → mods/pax_rpg/config/gharn.json (по заметке «Гхарн — планировка»).
Оси: центр Площади Круга (0, 0), север = −Z, метры. Детерминированно (seed): перезапуск даёт ту же карту.
    python pax_rpg/dev/gharn/gharn_layout.py
items: {"m": модель | "box": [sx,sy,sz] + "mat", "p": [x,y,z], "r": градусы вокруг Y, "s": масштаб, "c": коллизия}
"""
import json
import math
import os
import random

random.seed(1047)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
B, P = "models/gharn/", "models/gharn/props/"
items = []
occupied = []          # (x, z, радиус) — чтобы мелочь не вставала в здания


NO_COLLIDE = {"road_cobble", "road_dirt", "boardwalk", "lantern_string", "mana_flags_line", "stairs_stone"}
TRUNK = {"flame_tree": [0.9, 3.0, 0.9],
         # Врата Клыка: две башни, проход x −2.3…2.1 (по сетке модели) свободен
         "gate_fang": [[8.0, 14.0, 7.1, -6.3, 7.0, 0.0], [8.2, 14.0, 7.1, 6.2, 7.0, 0.0]]}          # у деревьев — только ствол: крона не мешает ходить


WIN_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "windows.json")
WINDOWS = json.load(open(WIN_FILE, encoding="utf-8")) if os.path.exists(WIN_FILE) else {}   # gharn_windows.py
YURTS = []                                      # (x, z, радиус) — дворы, костры, дрова


def add(m, x, z, r=0.0, s=1.0, c=None, y=0.0, rad=0.0):
    name = m.lstrip("@")
    if y == 0.0:
        y = 0.02                                 # основания, ковры, плиты — над землёй города: без мерцания (z-fighting)
    for wx, wy, wz, wyaw, ww, wh in WINDOWS.get(name, []):     # стёкла в нарисованные окна (в осях здания)
        a = math.radians(r)
        lx, lz = wx * s, wz * s
        items.append({"m": P + "window_glass.glb", "p": [round(x + lx * math.cos(a) + lz * math.sin(a), 3),
                      round(y + wy * s, 3), round(z - lx * math.sin(a) + lz * math.cos(a), 3)],
                      "r": round(r + wyaw, 1), "s": s, "c": False})
    it = {"m": (P if not m.startswith("@") else B) + name + ".glb", "p": [round(x, 2), round(y, 2), round(z, 2)],
          "r": round(r, 1), "s": s, "c": (name not in NO_COLLIDE) if c is None else c}
    if name in TRUNK:
        it["col"] = TRUNK[name]
    items.append(it)
    if rad:
        occupied.append((x, z, rad))


def box(size, x, y, z, mat="stone", r=0.0, c=True):
    items.append({"box": size, "mat": mat, "p": [x, y, z], "r": r, "c": c})


def free(x, z, rad):
    return all((x - a) ** 2 + (z - b) ** 2 > (rad + rr) ** 2 for a, b, rr in occupied)


# --- дороги: не плитки, а маска для шейдера земли (shaders/ground.gdshader): R — булыжник в грязи, G — утоптанные
# тропы. Тракт (x −4.5…4.5) идёт от ворот до самого Круга, Аллея (z −6.5…6.5) — насквозь, площадь — круг r 21.5.
GROUND = [190, 186, 0, -6]                     # ширина, глубина, центр X, центр Z
MASK_PX = 4                                    # пикселей на метр
ROADS = [("rect", -5.0, 5.0, 14, 90), ("rect", -78, 78, -8.5, 8.5), ("disc", 0, 0, 30.0), ("rect", -6.5, 6.5, -37, -14),
         ("disc", 34, 0, 8.5), ("rect", 40, 50, -14, -5), ("rect", 40, 48, 5, 16)]
TRAILS = [("rect", -72, -36, -4, 32)]          # базар — вытоптанная площадка

# --- ворота и стена# --- ворота и стена
add("@gate_fang", 0, 82, 0, c=True, rad=11)
W, N, S = 92, -96, 84
x = -W
while x < W:
    if abs(x + 2) > 12:
        add("palisade_segment", x + 2, S, 0, c=True)
    add("palisade_segment", x + 2, N, 180, c=True)
    x += 4
z = N
while z < S:
    add("palisade_segment", -W, z + 2, 90, c=True)
    add("palisade_segment", W, z + 2, -90, c=True)
    z += 4

# --- Ставка Хаана на террасе (+3 м) и пандус-лестница
box([52, 3, 36], 0, 1.5, -54, "stone_cut")
box([12, 0.5, 14], 0, 1.5, -30, "stone_cut", c=False)
items.append({"box": [10, 0.4, 15], "mat": "stone", "p": [0, 1.4, -29], "r": 0, "rx": 11.5, "c": True})   # пандус
for i in range(7):
    add("stairs_stone", -3.3 + 0, -24 - i * 0.0, 0, s=1.0) if False else None
add("@khan_palace", 0, -56, 0, c=True, y=3.0, rad=16)
for x in (-6, 6):
    add("tug_banner", x, -38, y=3.0)
for x in (-22, -14, 14, 22):
    add("@yurt_noble" if abs(x) > 18 else "banner_clan", x, -46, 180, c=True, y=3.0)

# --- Площадь Круга: Круг, фонари, Древо Клятв (пока — дерево Аллеи покрупнее), глашатай
for a in range(0, 360, 30):
    ra = math.radians(a)
    add("stone_lantern", math.sin(ra) * 29.0, math.cos(ra) * 29.0) if a % 60 and a % 180 != 90 else None   # по краю площади Круга (r 30)
box([2, 1, 2], -11, 0.5, -24.5, "stone_dark")                   # тумба глашатая — у северного входа Арены
add("@oath_tree", 25, -27, 30, s=0.85, rad=6)                    # Древо Клятв: баньян с лентами (Meshy v3)
add("ovoo_cairn", 18, -24)
add("trough", -22, 22.5, 45, c=True)
occupied.append((0, 0, 30))

# --- Арена на Площади Круга: песчаная яма r 13.5 за парапетом, три яруса трибун до r 17, стена позади (r 18.2).
# Входы — юг (к Тракту и воротам, главный: жаровни, вывеска) и север (к Ставке). Текстуры — CC0 4K (city.gd TEX_MATS).
ARENA = (0.0, 0.0)
AX, AZ = ARENA
PIT = 13.5
A_IN = 0.0                                               # главный вход — на юг (+Z), к Тракту
def _gap(a, w):
    return any(abs((a - g + 180) % 360 - 180) < w for g in (A_IN, A_IN + 180))
for k in range(6):                                       # песок ямы: шесть квадратов, повёрнутых — почти круг
    box([25.6, 0.06, 25.6], AX, 0.03, AZ, "arena_sand", r=k * 15, c=False)
for a in range(0, 360, 6):                               # парапет ямы
    if _gap(a, 9):
        continue
    ra = math.radians(a)
    box([0.7, 1.3, 2 * math.pi * (PIT + 0.35) / 60 + 0.12], round(AX + math.sin(ra) * (PIT + 0.35), 2), 0.65,
        round(AZ + math.cos(ra) * (PIT + 0.35), 2), "arena_wall", r=a + 90)
for rr, h in ((14.85, 0.7), (15.95, 1.4), (17.05, 2.1)):  # ярусы трибун
    for a in range(0, 360, 5):
        if _gap(a, 10):
            continue
        ra = math.radians(a)
        box([1.15, h, 2 * math.pi * rr / 72 + 0.1], round(AX + math.sin(ra) * rr, 2), h / 2, round(AZ + math.cos(ra) * rr, 2),
            "arena_seat", r=a + 90)
for a in range(0, 360, 5):                               # стена позади трибун
    if _gap(a, 10):
        continue
    ra = math.radians(a)
    box([0.8, 3.6, 2 * math.pi * 18.2 / 72 + 0.12], round(AX + math.sin(ra) * 18.2, 2), 1.8, round(AZ + math.cos(ra) * 18.2, 2),
        "arena_wall", r=a + 90)
for g in (A_IN, A_IN + 180):                             # входы: туги и жаровни по сторонам
    rg = math.radians(g)
    ex, ez = AX + math.sin(rg) * 18.9, AZ + math.cos(rg) * 18.9
    for side in (-1, 1):
        px, pz = ex + side * 3.0 * math.cos(rg), ez - side * 3.0 * math.sin(rg)
        add("tug_banner", px, pz)
        items.append({"brazier": True, "p": [round(px + math.sin(rg) * 1.3, 2), 0.0, round(pz + math.cos(rg) * 1.3, 2)],
                      "c": True})
rg = math.radians(A_IN)
items.append({"sign": ["闘", "Арена"], "p": [round(AX + math.sin(rg) * 20.6 - 4.4 * math.cos(rg), 2), 0.0,
              round(AZ + math.cos(rg) * 20.6 + 4.4 * math.sin(rg), 2)], "r": round(A_IN, 1), "c": True})
for a in (45, 135, 225, 315):                            # жаровни в яме по диагоналям — свет вечером
    ra = math.radians(a)
    items.append({"brazier": True, "p": [round(AX + math.sin(ra) * 12.4, 2), 0.0, round(AZ + math.cos(ra) * 12.4, 2)], "c": True})
occupied.append((AX, AZ, 19.0))

# --- Аллея Знамён: деревья, знамёна, скамьи, фонтан
for x in list(range(-70, -24, 9)) + list(range(26, 72, 9)):
    if abs(x) < 33:                                   # у площади Круга — без деревьев: проход к Арене
        continue
    for z in (-10.5, 10.5):
        if 30 < x < 40:
            continue
        add("@flame_tree", x, z, random.uniform(0, 360), s=random.uniform(0.85, 1.05), rad=1.5)
    if x % 18 < 9:
        add("banner_clan", x + 4.5, -9.8, 0)
        add("banner_clan", x + 4.5, 9.8, 180)
    add("bench_long", x + 4.5, -11.8, 0)
add("@fountain_dragon", 34, 0, 0, s=1.6, c=True, rad=5)
add("barrel_water", 39, 4.5)
add("trough", 38, -5, 0, c=True)

# --- Гильдия и таверна у фонтана
add("@guild_hall", 54, -22, 0, c=True, rad=10)
add("quest_board", 44, -13, 20, c=True)
add("weapon_rack", 62, -12, 0)
add("training_dummy", 47, -11)
add("training_dummy", 50, -11)
add("@tavern_hall", 54, 24, 180, c=True, rad=10)
for i in range(3):
    add("table_long", 41, 14 + i * 3.5, 90)
    add("bench_long", 40, 14 + i * 3.5, 90)
    add("bench_long", 42, 14 + i * 3.5, 90)
add("cauldron", 45, 12)
for i in range(5):
    add("barrel_kumis", 63 + (i % 2) * 0.9, 13 + i * 0.9, random.uniform(0, 360))
add("hitching_post", 66, 32, 90, c=True)

# --- Аллея Сакур (бывший Тракт Туменов): первое, что видит игрок за Вратами Клыка. Мостовая 10 м, по краям — сакуры,
# кроны наклонены к оси и смыкаются над дорогой (падают лепестки), между стволами — каменные фонари. За деревьями —
# сплошные фасады двухэтажных домов и лавок (фасадом к улице), через улицу между домами — гирлянды бумажных фонарей
# на высоте второго этажа. Переулок z 57.5 — к Куреням (запад) и Улице Мастеров (восток).
# по референсу автора: улица-«каньон» — сплошные двух-трёхэтажные фасады вплотную к тротуару, гирлянды красных
# фонарей через каждые 3.5 м на разной высоте уходят вдаль к Арене, вывески у дверей; деревьев на проезде нет.
# --- Вход в город, левел-дизайн (итерации по рендерам: pax_rpg/dev/gharn/render_scene.py). Идея: путь — три порога.
#   1) Внешняя арка из клыков в 24 м от ворот + церемониальная дорога: пары туг-знамён, статуи-стражи, жаровни,
#      у обочины — караван (повозки, буйволы): город живёт уже снаружи стены.
#   2) Врата Клыка — сразу за ними узкое «горло» улицы-каньона: сплошные фасады разных домов вплотную, лавки с навесами
#      и товаром на тротуарах, гирлянды фонарей ритмом (через 6 м, свет — у каждой второй), не облаком.
#   3) В конце аллеи — арка из клыков с жаровнями: рамка, через которую видна площадь Круга (точка притяжения взгляда).
ALLEY_ROWS = [(76.5, 61.0), (54.0, 31.5)]              # отрезки фасадов (между ними — переулок z 57.5)
ALLEY_MODELS = ["@house_two_b", "@house_shop_a", "@house_timber_a", "@house_shop_c", "@house_shop_b", "@house_timber_b"]
FOOT = {"house_two_b": (5.22, 4.92), "house_shop_a": (5.11, 4.13), "house_shop_b": (4.24, 4.06),
        "house_shop_c": (5.74, 4.29), "house_timber_a": (3.74, 4.51), "house_timber_b": (4.03, 3.71)}
ALLEY_HOUSES = []                                       # (z центра, сторона, модель) — для вывесок и лавок
for side in (-1, 1):                                    # ряд домов на отрезок: на один больше, чем влезает, и
    k = 0 if side < 0 else 3                            # весь ряд ужат до длины отрезка — фасад сплошной, без дыр
    for z0, z1 in ALLEY_ROWS:
        seg, row = z0 - z1, []
        while sum(2 * FOOT[m.lstrip("@")][0] + 0.3 for m in row) < seg:
            row.append(ALLEY_MODELS[k % len(ALLEY_MODELS)])
            k += 1
        tot = sum(2 * FOOT[m.lstrip("@")][0] + 0.3 for m in row)
        sc = max(0.72, seg / tot)
        z = z0
        for m in row:
            fx, fz = FOOT[m.lstrip("@")]
            zc = z - fx * sc
            add(m, side * (8.1 + fz * sc), zc, 90 if side < 0 else -90, s=round(sc, 3), c=True, rad=fx * sc + 0.2)
            ALLEY_HOUSES.append((zc, side, m))
            z -= (2 * fx + 0.3) * sc
for side in (-1, 1):                                    # тротуары по обе стороны; у переулка (z 57.5) — разрыв
    box([3.0, 0.06, 23.0], side * 6.5, 0.03, 43.0, "stone_cut", c=False)   # низкий, без коллизии — герой не спотыкается
    box([3.0, 0.06, 16.0], side * 6.5, 0.03, 69.0, "stone_cut", c=False)
    box([0.25, 0.14, 23.0], side * 5.05, 0.07, 43.0, "stone_dark", c=False)   # бордюр — тёмная кромка, читается линия
    box([0.25, 0.14, 16.0], side * 5.05, 0.07, 69.0, "stone_dark", c=False)
for z in (38, 50, 64, 74):                              # каменные фонари у бордюра — реже, ритмом 12 м
    for side in (-1, 1):
        add("stone_lantern", side * 5.6, z, 90 if side < 0 else -90, rad=0.6)
for k, z in enumerate(range(34, 77, 6)):                # гирлянды: через 6 м, под карнизами (4.0…4.6), на столбах
    h = (4.8, 5.1, 4.6, 5.0)[k % 4]                     # низ фонаря ≥ 3 м: голова и копьё в прыжке не задевают
    items.append({"lanterns": [-7.4, z, 7.4, z + 0.8, h, 1 if k % 2 == 0 else 0, 1], "seed": int(z * 13 + k), "p": [0, 0, z],
                  "c": False})
for i, (zc, side, m) in enumerate(ALLEY_HOUSES):        # у каждой второй лавки — прилавок под навесом и товар
    if i % 2:
        continue
    x = side * 7.15
    add("@market_stall_hide", x, zc + 1.2, 90 if side < 0 else -90, c=True, rad=1.6)
    for j, pm in enumerate(random.sample(["crate", "barrel_kumis", "sack_grain", "basket", "crate_saerith"], 3)):
        add(pm, x + side * 0.3, zc - 1.4 - j * 0.85, random.uniform(0, 360), s=0.85, c=True, rad=0.5)
for i in range(len(ALLEY_HOUSES) - 1):                   # знамёна кланов в стыках домов — вертикальный ритм
    (z1_, s1_, _), (z2_, s2_, _) = ALLEY_HOUSES[i], ALLEY_HOUSES[i + 1]
    if s1_ == s2_ and abs(z1_ - z2_) < 12 and i % 2 == 0:
        add("banner_clan", s1_ * 7.7, (z1_ + z2_) / 2, 90 if s1_ < 0 else -90, s=1.2, c=True, rad=0.4)
for side in (-1, 1):                                     # карман у переулка (z 57.5): скамьи и кадка сакуры
    add("bench_long", side * 9.0, 55.6, 90 if side < 0 else -90, c=True)
    box([2.4, 0.9, 2.4], side * 9.6, 0.45, 59.6, "stone_cut", c=True)        # кадка сакуры (как planter ниже)
    add("@flame_tree", side * 9.6, 59.6, random.uniform(0, 360), s=0.42, c=False, y=0.9)
    occupied.append((side * 9.6, 59.6, 1.8))
add("hitching_post", -5.6, 79.5, 0, c=True)             # у ворот: коновязь и поилка для всадников
add("trough", 5.6, 79.5, 0, c=True)
for side in (-1, 1):                                     # конец аллеи: жаровни у арки
    add("@brazier_tusk", side * 4.4, 30.5, 0, c=True, rad=1.0)
    items.append({"brazier": True, "p": [side * 4.4, 0.0, 30.5], "c": False})
add("@tusk_arch", 0, 29.2, 0, s=1.75, c=False)          # рамка-портал на площадь Круга

# --- концепт (заглушки proxy — рисует только превью Blender, в игре пока нет; потом — настоящие модели)
def proxy(kind, x, y, z, r=0.0, **kw):
    it = {"proxy": kind, "p": [round(x, 2), round(y, 2), round(z, 2)], "r": round(r, 1), "c": False}
    it.update(kw)
    items.append(it)


# итерация 4: ворота изнутри, жилые окна и дым, колеи подхода
for side in (-1, 1):                                    # тоннель ворот: факелы на внутренних стенах башен
    for z in (79.6, 84.4):
        proxy("torch", side * 2.45, 2.3, z)
proxy("portcullis", 0, 4.1, 85.7, 0, w=4.6, h=1.6)       # решётка-герса, поднятая над проходом
proxy("ruts", 0, 0, 99.0, 0, len=26)                     # колеи повозок по мостовой подхода
# итерация 5: люди группами, с действием (концепт — потом жители с анимациями)
for side in (-1, 1):
    proxy("guard", side * 3.2, 0, 87.0, 0)               # стража снаружи ворот
    proxy("guard", side * 3.0, 0, 77.6, 180)             # и изнутри
    proxy("guard", side * 3.6, 0, 30.8, 180)             # у арки на площадь
for k, (dx, dz) in enumerate(((1.4, 0.4), (-1.2, 1.1), (0.3, -1.5), (-0.6, -1.3))):   # караванщики у костра
    proxy("person", -15.5 + dx, 0, 92.0 + dz, math.degrees(math.atan2(-dx, -dz)))
proxy("person", 12.2, 0, 95.0, 110)                       # погонщик у буйволов
for i, (zc, side, m) in enumerate(ALLEY_HOUSES[::2]):    # зазывалы у прилавков и покупатели
    proxy("crier", side * 5.9, 0, zc + 0.4, 90 if side > 0 else -90)
    proxy("person", side * 4.4, 0, zc - 0.8, 90 if side > 0 else -90)
for z, x in ((70, -1.6), (66, 2.2), (61, 0.4), (51, -2.4), (46, 1.2), (40, -0.4), (36, 2.6)):   # прохожие
    proxy("person", x, 0, z, random.uniform(0, 360))
for k, z in enumerate(range(37, 77, 12)):                  # полотнища поперёк улицы — между гирляндами
    for x in (-3.0, 3.0):
        proxy("banner_x", x, 4.6, z, 0, ln=1.4, c2=(0, 1, 3, 2)[(k + (x > 0)) % 4])
# итерация 6: контровой свет (тянет вперёд), лепестки у сакур
proxy("glow", 0, 0, 24.0, w=2200, h=5.0)                  # зарево площади за аркой — силуэт арки, цель пути
proxy("glow", 0, 0, 74.0, w=900, h=6.0)                   # тёплый свет улицы за воротами — виден с подхода
for x, z in ((-7.6, 106.5), (7.6, 106.5), (-9.6, 59.6), (9.6, 59.6)):
    proxy("petals", x, 0, z, random.uniform(0, 180), w=random.uniform(2.6, 3.6))
for x, z, w_ in ((-2.5, 63, 2.2), (2.8, 44, 1.6), (1.0, 96, 2.6)):   # лужи — в них отражаются фонари
    proxy("puddle", x, 0, z, random.uniform(0, 180), w=w_, d=w_ * 0.55)
for i, (zc, side, m) in enumerate(ALLEY_HOUSES):
    yaw = 90 if side < 0 else -90
    for dz in (-1.5, 1.5):                               # тёплые окна второго этажа
        if (i + (dz > 0)) % 3:
            proxy("window", side * 8.12, 3.6, zc + dz, yaw)
    proxy("noren", side * 8.0, 0.0, zc, yaw, c2=(0, 1, 0, 2, 3, 0, 4)[i % 7])  # занавес над дверью лавки
    proxy("hang_sign", side * 7.6, 0.0, zc - 2.4, yaw)    # вывеска на кронштейне — над тротуаром
    if i % 2 == 0:                                        # дым из трубы
        proxy("smoke", side * 11.5, 6.4, zc + 1.0)

# --- снаружи: церемониальная дорога к Вратам Клыка
box([9.0, 0.05, 26.0], 0, 0.025, 99.0, "stone_cut", c=False)              # мощёный подход
box([0.3, 0.16, 26.0], -4.6, 0.08, 99.0, "stone_dark", c=False)
box([0.3, 0.16, 26.0], 4.6, 0.08, 99.0, "stone_dark", c=False)
for z in (90.0, 95.5, 101.0):                            # пары туг-знамён вдоль дороги
    for side in (-1, 1):
        add("tug_banner", side * 5.6, z, 0, s=1.25, c=True, rad=0.6)
for side in (-1, 1):
    add("@guardian_statue", side * 7.4, 88.6, 0, s=1.6, c=True, rad=1.4)   # стражи у ворот — лицом к идущему (+Z)
    add("@brazier_tusk", side * 5.4, 87.4, 0, c=True, rad=1.0)
    items.append({"brazier": True, "p": [side * 5.4, 0.0, 87.4], "c": False})
add("@tusk_arch", 0, 108.0, 180, s=1.75, c=False)       # внешний порог — первая арка, видна издалека
for side in (-1, 1):                                     # сакуры у внешней арки и фонари вдоль дороги
    add("@flame_tree", side * 7.6, 106.5, random.uniform(0, 360), s=0.95, rad=1.5)
    for z in (92.8, 98.3, 103.8):
        add("stone_lantern", side * 4.1, z, 90 if side < 0 else -90, rad=0.6)
for k in range(26):                                       # степь у дороги: камни, кусты, трава — не голая земля
    side = -1 if k % 2 else 1
    x, z = side * random.uniform(7.0, 24.0), random.uniform(86.0, 114.0)
    if free(x, z, 1.2):
        add(random.choice(["rock_small", "bush_dry", "grass_tuft", "grass_tuft"]), x, z, random.uniform(0, 360),
            s=random.uniform(0.8, 1.4), c=False)
add("@hay_wagon", 13.5, 97.0, 20, c=True, rad=2.2)       # караван у обочины
add("@buffalo", 16.8, 93.5, -70, s=0.9, c=True, rad=2.0)
add("@buffalo", 15.2, 101.5, 110, s=0.85, c=True, rad=2.0)
add("hitching_post", 11.0, 93.0, 90, c=True)
add("merchant_cart", -13.0, 98.0, -15, c=True, rad=2.0)
for k in range(4):
    add(random.choice(["crate", "sack_grain", "barrel_kumis"]), -10.6 + random.uniform(-0.6, 0.6), 95.5 + k * 1.1,
        random.uniform(0, 360), c=True, rad=0.5)
add("firepit", -15.5, 92.0, 0, c=True, rad=1.0)          # стоянка караванщиков
items.append({"brazier": True, "p": [-15.5, 0.0, 92.0], "c": False})

# --- Базар Добычи (запад)
for i in range(4):
    for j in range(3):
        x, z = -66 + i * 9, -2 + j * 9 + 6
        add("stall_frame", x, z, random.choice([0, 180]), c=True, rad=2)
        add(random.choice(["crate_saerith", "crate", "barrel_kumis"]), x + 2.2, z + 1.4, random.uniform(0, 360))
        add("basket", x - 1.8, z - 1.4)
add("cauldron", -48, 30)
add("weapon_rack", -70, 30, 90)
# по концепту рынка: гирлянды больших оранжевых фонарей над рядами, торговцы за прилавками, тележки с добычей
for z in (8.5, 17.5):
    for x0 in (-70.5, -61.5, -52.5, -43.5):
        items.append({"lanterns": [x0, z, x0 + 9.0, z, 4.4], "seed": int(x0 * 10 + z), "p": [x0, 0, z], "c": False})
for x, z, r in ((-57.5, 1.5, 30), (-39.5, 23.5, 200), (-71.0, 19.0, 100)):   # тележки торговцев с добычей (Meshy)
    add("merchant_cart", x, z, r, c=True, rad=2.0)
for x in (-66, -48):
    items.append({"lanterns": [x - 4.5, 0.5, x - 4.5, 26.0, 4.6], "seed": int(x), "p": [x, 0, 0], "c": False})
for i in range(4):
    for j in range(3):
        if (i + j) % 3 == 2:
            continue
        x, z = -66 + i * 9, -2 + j * 9 + 6
        items.append({"merchant": True, "p": [x + random.uniform(-0.6, 0.6), 0.0, z - 1.3], "r": 180.0, "seed": i * 7 + j,
                      "c": False})

# --- Счётный двор (северо-запад): казармы из тёсаного камня, плац
for k in range(3):
    for i in range(5):
        add("wall_hob", -66 + i * 4.1, -36 - k * 10, 0, c=True)
        add("wall_hob", -66 + i * 4.1, -32 - k * 10, 180, c=True)
for i in range(6):
    add("training_dummy", -36 + (i % 3) * 3, -56 + (i // 3) * 3)
add("weapon_rack", -30, -48, 90)
add("weapon_rack", -30, -52, 90)
occupied.append((-55, -45, 16))

# --- Склон шаманов (северо-восток): холм, кристаллы, туры, флажки
box([24, 4, 20], 66, 2, -66, "stone_dark")
# подъём на склон: каменный пандус с юга (от гоблинского закоулка), туги по краям
items.append({"box": [7, 0.4, 12.8], "mat": "stone", "p": [62, 2.0, -50.0], "r": 0, "rx": 18.2, "c": True})
add("tug_banner", 58, -44.5)
add("tug_banner", 66, -44.5)
occupied.append((62, -50, 5))
ROADS.append(("rect", 58.5, 65.5, -56, -43))
for i in range(6):
    add("mana_crystal", 58 + random.uniform(0, 16), -72 + random.uniform(0, 12), random.uniform(0, 360), y=4.0)
    add("ovoo_cairn", 58 + random.uniform(0, 16), -72 + random.uniform(0, 12), y=4.0)
for i in range(3):
    add("mana_flags_line", 60 + i * 5, -62 - i * 3, 20 * i, y=4.0)
occupied.append((66, -66, 14))

# --- Буйволиный двор (юго-восток от Круга, по концепту улицы): загон из плетня, демонические буйволы (модель Meshy,
# свой скелет и анимации — pax_rpg/dev/blender/gharn/buffalo_rig.py), корыта и сено; снаружи вдоль каменной стены —
# стол и скамьи, где пастухи пьют кумыс
X0, X1, Z0, Z1 = 23.0, 41.0, 27.0, 40.0
x = X0
while x < X1 - 0.1:                                      # плетень: север и юг
    add("fence_wood", x + 2, Z0, 0, c=True)
    add("fence_wood", x + 2, Z1, 0, c=True)
    x += 4
z = Z0
while z < Z1 - 0.1:                                      # восток глухой, на западе — ворота (проход 4 м посередине)
    add("fence_wood", X1, z + 2, 90, c=True)
    if abs(z + 2 - (Z0 + Z1) / 2) > 2.5:
        add("fence_wood", X0, z + 2, 90, c=True)
    z += 4
for i in range(5):                                       # каменная стена за двором
    add("wall_rubble", X0 + 2 + i * 4.1, Z1 + 2.2, 0, c=True)
for bx, bz, br, clip in ((29, 31, 150, ["Idle", "Graze"]), (35, 35.5, 220, ["Graze", "Idle"]), (36.5, 30, 300, ["Idle"])):
    items.append({"m": B + "buffalo.glb", "p": [bx, 0.0, bz], "r": br, "s": 0.85, "anim": clip, "c": True,
                  "col": [1.4, 1.8, 3.0]})
add("trough", 39.5, 33.5, 90, c=True)
add("trough", 26, 38.6, 0, c=True)
for hx, hz in ((24.6, 28.6), (25.4, 30.2), (39.2, 38.4)):
    add("hay_bale", hx, hz, random.uniform(0, 360), c=True)
add("barrel_water", 24.4, 38.3)
add("table_long", 31, 44.4, 0, c=True)
add("bench_long", 31, 43.5, 0)
add("bench_long", 31, 45.3, 0)
add("barrel_kumis", 34.2, 44.2, 0)
add("lantern_post", 22.2, 33.5, 0)
occupied.append(((X0 + X1) / 2, (Z0 + Z1) / 2 + 2, 12.5))
TRAILS.append(("rect", X0, X1, Z0, Z1))                  # в загоне — вытоптанная земля

# --- Юрточные кварталы (юг)
def quarter(x0, x1, z0, z1, n):
    placed = 0
    tries = 0
    while placed < n and tries < 2000:
        tries += 1
        big = random.random() < 0.3
        rad = 4.6 if big else 3.0
        x, z = random.uniform(x0, x1), random.uniform(z0, z1)
        if not free(x, z, rad):
            continue
        kind = random.random()
        if kind < 0.28:                                  # оседлые кланы: бревенчатые дома на цоколе (Meshy v3)
            add(random.choice(["@house_timber_a", "@house_timber_b"]), x, z, random.choice([0, 90, 180, 270]) +
                random.uniform(-8, 8), c=True, rad=rad + 0.8)
        else:
            add("yurt_large" if big else "yurt_small", x, z, random.uniform(0, 360), c=True, rad=rad)
        YURTS.append((x, z, rad))
        placed += 1
        for _ in range(random.randint(1, 3)):         # быт у юрты
            a = random.uniform(0, 2 * math.pi)
            px, pz = x + math.cos(a) * (rad + 1.2), z + math.sin(a) * (rad + 1.2)
            if free(px, pz, 0.6):
                add(random.choice(["barrel_water", "crate", "sack_grain", "basket", "cauldron", "hitching_post"]),
                    px, pz, random.uniform(0, 360), rad=0.6)


# --- Жилые слободы: запад — кочевые курени кланов, восток — оседлая Улица Мастеров (districts() ниже)



# ===================== жилые слободы =====================
FOOT = {"yurt_large": (4.2, 4.2), "yurt_small": (2.7, 2.7), "house_timber_a": (3.8, 4.6), "house_timber_b": (4.1, 3.8),
        "house_shop_a": (5.2, 4.2), "house_shop_b": (4.3, 4.1), "house_shop_c": (5.8, 4.3),
        "house_two_a": (4.0, 3.6), "house_two_b": (5.2, 4.9)}
RECTS = []                                       # (x0, x1, z0, z1) занятых построек слобод — без самопересечений


def fits(x0, x1, z0, z1):
    return all(x1 <= a0 or x0 >= a1 or z1 <= b0 or z0 >= b1 for a0, a1, b0, b1 in RECTS) and \
        all(not (x0 - rr < a < x1 + rr and z0 - rr < b < z1 + rr) for a, b, rr in occupied)


def place(m, x, z, r, pad=0.4, **kw):
    """Постройка по габариту модели (r кратен 90°): не ставится, если задевает уже стоящее."""
    hx, hz = FOOT[m.lstrip("@")]
    if int(round(r / 90.0)) % 2:
        hx, hz = hz, hx
    box_ = (x - hx - pad, x + hx + pad, z - hz - pad, z + hz + pad)
    if not fits(*box_):
        return False
    RECTS.append(box_)
    add(m, x, z, r, c=True, **kw)
    return True


TWO = os.path.exists(os.path.join(ROOT, "mods", "pax_rpg", "models", "gharn", "house_two_a.glb"))


def clan_camp(cx, cz, k):
    """Курень кочевого клана: большая юрта главы на севере, три юрты родни кольцом — двери к общему очагу; у очага
    вертел и котёл, у входа (юг) туг клана и коновязь, бельё между юртами, гирлянда над очагом."""
    place("yurt_large", cx, cz - 6.8, 0)
    for a in (150, 210, 90) if k % 2 else (150, 210, 270):
        ra = math.radians(a)
        place("yurt_small", cx + math.sin(ra) * 6.8, cz - math.cos(ra) * 6.8, 0)
    add("firepit", cx, cz, 0, c=False, rad=1.2)
    add("@spit_roast" if k % 2 == 0 else "cauldron", cx + 1.9, cz + 0.6, 90, c=True)
    add("bench_long", cx - 2.2, cz + 1.2, 70)
    add("bench_long", cx + 0.3, cz - 2.4, 0)
    add("tug_banner", cx - 1.6, cz + 7.6)
    add("hitching_post", cx + 2.4, cz + 8.0, 0, c=True)
    add("hay_bale", cx + 4.4, cz + 8.2, random.uniform(0, 360), c=True)
    add(random.choice(["barrel_kumis", "barrel_water"]), cx - 5.6, cz - 1.4)
    add("basket", cx - 5.0, cz - 0.4)
    add("wood_pile", cx + 5.6, cz - 2.0, 60, c=True)
    items.append({"lanterns": [cx - 3.6, cz - 4.4, cx + 3.6, cz + 4.4, 3.6], "seed": int(cx * 3 + cz), "p": [cx, 0, cz],
                  "c": False})
    sx, sz = cx - 7.2, cz + 3.4
    items.append({"laundry": [sx, sz, sx + 1.6, sz + 4.2], "seed": k, "p": [sx, 0, sz], "c": False})
    TRAILS.append(("disc", cx, cz, 4.5))
    occupied.append((cx, cz, 4.0))


def craft_lot(x, z, side, k):
    """Участок мастера на Улице Мастеров: дом фасадом к улице (двухэтажный, где есть модель), за домом — свой двор:
    у гончара кувшины и корзины, у кожевника рамы со шкурой, у плотника дрова и телега, у пивовара бочки кумыса."""
    r = 0 if side < 0 else 180
    if TWO and k % 3 != 2:
        m = "@house_two_a" if k % 2 else "@house_two_b"
    else:
        m = ["@house_timber_a", "@house_shop_b", "@house_timber_b", "@house_shop_a"][k % 4]
    if not place(m, x, z, r):
        return
    by = z + side * 9.0                              # задний двор
    craft = k % 4
    if craft == 0:
        add("@hide_frame", x - 1.5, by, 0, c=True)
        add("barrel_water", x + 2.0, by)
    elif craft == 1:
        add("wood_pile", x - 2.0, by, 0, c=True)
        add("cart", x + 2.2, by, 90, c=True)
    elif craft == 2:
        for i in range(4):
            add("barrel_kumis", x - 2.0 + i * 1.0, by)
    else:
        add("basket", x - 1.6, by)
        add("@bucket_set", x + 1.2, by, 0, c=False)
        add("sack_grain", x + 2.6, by)
    for i in (-1, 1):                                # плетень вокруг двора
        add("fence_wood", x + i * 4.6, by, 90, c=True)
    add("fence_wood", x - 2.4, by + side * 2.4, 0, c=True)
    add("fence_wood", x + 2.4, by + side * 2.4, 0, c=True)
    if k % 3 == 0:                                   # огород: сакура и травы
        add("@flame_tree", x, by + side * 4.8, random.uniform(0, 360), s=0.7, rad=1.5)
    TRAILS.append(("rect", x - 4.4, x + 4.4, min(by, by + side * 2.2) - 1.2, max(by, by + side * 2.2) + 1.2))


def districts():
    # запад: шесть куреней, между ними переулки к Тракту (z 57.5 — проход между лавками) и к Аллее
    k = 0
    for cz in (46.5, 70.0):
        for cx in (-76.0, -54.0, -32.0):
            clan_camp(cx, cz, k)
            k += 1
    TRAILS.extend([("rect", -88, -5, 56.6, 59.4), ("rect", -66.4, -63.6, 30, 82), ("rect", -44.4, -41.6, 30, 82)])
    # восток: Улица Мастеров (мостовая z 57.5 от Тракта до стены), переулок к таверне (x 55), колодец на перекрёстке
    ROADS.append(("rect", 5, 88, 55.8, 59.2))
    TRAILS.append(("rect", 53.4, 56.6, 33, 82))
    k = 0
    for x in (25.0, 35.0, 45.0, 63.0, 74.0, 85.0):
        for side in (-1, 1):
            craft_lot(x, 57.5 + side * 6.8, side, k)
            k += 1
    add("trough", 55, 57.5, 0, c=True)
    add("barrel_water", 56.6, 56.4)
    for sx in (-1, 1):
        add("stone_lantern", 55 + sx * 3.2, 54.6, 0)
        add("stone_lantern", 55 + sx * 3.2, 60.4, 0)
    add("@totem_pole", 52.2, 61.0, 0, c=True)
    for x in (25.0, 63.0, 74.0):                     # гирлянды через улицу между фасадами — на высоте второго этажа
        items.append({"lanterns": [x + 5.5, 52.4, x + 5.5, 62.6, 5.6], "seed": int(x), "p": [x, 0, 57.5], "c": False})
    for x in (19.0, 38.0, 71.0):
        add("tug_banner", x, 55.2)


districts()


def north_zones():
    # Курганы Предков (северо-запад): аллея героев от Счётного двора — по обе стороны каменные волки-стражи и туги,
    # в конце — великий тур (обо) с костяными знамёнами; по сторонам курганы павших ханов (тур + тотем + жаровня)
    ax = -62.0
    for z in range(-62, -86, -6):
        add("@guardian_statue", ax - 3.2, z, 90, c=True)
        add("@guardian_statue", ax + 3.2, z, -90, c=True)
        add("tug_banner", ax - 4.6, z - 3)
        add("tug_banner", ax + 4.6, z - 3)
    TRAILS.append(("rect", ax - 2.0, ax + 2.0, -88, -55))
    add("ovoo_cairn", ax, -89, 0, s=2.2, c=True, rad=3)
    for x in (ax - 4.5, ax + 4.5):
        add("@bone_banner", x, -89, 0, c=True)
    for cx, cz in ((-80, -66), (-80, -80), (-44, -68), (-44, -82)):
        add("ovoo_cairn", cx, cz, random.uniform(0, 360), s=1.5, c=True, rad=2)
        add("@totem_pole", cx + 2.4, cz, 0, c=True)
        add("@brazier_tusk", cx - 2.4, cz + 1.0, 0, c=True)
        add("stone_lantern", cx, cz + 3.0, 0)
    # Сад Хаана (за дворцом): ряды сакуры вдоль дорожки, каменные фонари, скамьи, Камень Клятвы в центре
    TRAILS.append(("rect", -26, 26, -86, -80))           # дорожка 6 м — жители гуляют парами
    for x in range(-22, 24, 8):
        add("@flame_tree", x, -75.5, random.uniform(0, 360), s=0.9, rad=1.5)
        add("@flame_tree", x + 4, -91.0, random.uniform(0, 360), s=0.9, rad=1.5)
    for i, x in enumerate(range(-18, 24, 16)):           # фонари редко и по очереди: тёплые пятна, не световая стена
        add("stone_lantern", x, -79.2 if i % 2 else -86.8, 0 if i % 2 else 180)
    for x in (-10, 10):
        add("bench_long", x, -87.4, 0)
    add("ovoo_cairn", 0, -88.5, 0, s=1.4, c=True)
    # Волчьи Псарни (северо-восток, у склона шаманов): загоны из плетня, клетки, вертел с мясом, стойки для сбруи
    for px, pz in ((28, -66), (42, -66), (28, -82), (42, -82)):
        for i in range(3):
            add("fence_wood", px - 4 + i * 4, pz - 5, 0, c=True)
            add("fence_wood", px - 4 + i * 4, pz + 5, 0, c=True) if i != 1 else None
        add("fence_wood", px - 6, pz - 3, 90, c=True)
        add("fence_wood", px - 6, pz + 3, 90, c=True)
        add("fence_wood", px + 6, pz - 3, 90, c=True)
        add("fence_wood", px + 6, pz + 3, 90, c=True)
        add("@beast_cage", px, pz - 2, 0, c=True)
        add("trough", px + 3, pz + 2, 0, c=True)
        add("hay_bale", px - 3.5, pz + 2.5, random.uniform(0, 360), c=True)
        TRAILS.append(("rect", px - 6, px + 6, pz - 5, pz + 5))
    add("@spit_roast", 35, -74, 0, c=True)
    add("@spear_rack", 35, -88, 0, c=True)
    add("wood_pile", 50, -74, 90, c=True)
    TRAILS.append(("rect", 33, 37, -90, -60))


north_zones()

# --- деталь столицы: дворы у юрт, быт, телеги, навесы у лавок, фонари Аллеи, зелень
def on_road(x, z, m=1.5):
    for sh in ROADS:
        if sh[0] == "rect" and sh[1] - m < x < sh[2] + m and sh[3] - m < z < sh[4] + m:
            return True
        if sh[0] == "disc" and (x - sh[1]) ** 2 + (z - sh[2]) ** 2 < (sh[3] + m) ** 2:
            return True
        if sh[0] == "line" and _seg_d(x, z, sh[1]) < sh[2] / 2 + m:
            return True
    return False


def _seg_d(x, z, pts):
    best = 1e9
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        dx, dz = bx - ax, bz - az
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / max(dx * dx + dz * dz, 1e-6)))
        best = min(best, math.hypot(x - ax - dx * t, z - az - dz * t))
    return best


for i, (x, z, rad) in enumerate(YURTS):
    a0 = random.uniform(0, 2 * math.pi)
    if i % 3 == 0:                                   # двор: дуга плетня
        for k in range(4):
            a = a0 + k * 0.62
            fx, fz = x + math.cos(a) * (rad + 3.2), z + math.sin(a) * (rad + 3.2)
            if not on_road(fx, fz, 1.0):
                add("fence_wood", fx, fz, math.degrees(-a) + 90, c=True)
    a = a0 + math.pi
    fx, fz = x + math.cos(a) * (rad + 2.4), z + math.sin(a) * (rad + 2.4)
    if i % 2 == 0 and free(fx, fz, 1.0) and not on_road(fx, fz):
        add("firepit", fx, fz, random.uniform(0, 360), c=False, rad=1.0)
    a = a0 + math.pi / 2
    fx, fz = x + math.cos(a) * (rad + 1.4), z + math.sin(a) * (rad + 1.4)
    if i % 3 != 2 and free(fx, fz, 0.9) and not on_road(fx, fz):
        add(random.choice(["wood_pile", "hay_bale", "hay_bale"]), fx, fz, math.degrees(-a), c=True, rad=0.9)

SIGNS = [("酒", "Кумыс и брага"), ("武", "Оружие"), ("薬", "Зелья и травы"), ("肉", "Мясо"), ("布", "Ткани"),
         ("鉄", "Кузня"), ("革", "Кожа и сёдла"), ("茶", "Чайная"), ("宝", "Добыча"), ("骨", "Обереги")]
for i, (zc, side, m) in enumerate(ALLEY_HOUSES):      # вывески лавок Аллеи — у дверей, лицом к улице
    items.append({"sign": list(SIGNS[i % len(SIGNS)]), "p": [side * 7.7, 0.0, zc - 2.6 * side], "r": 90.0 * -side,
                  "c": True})
for i, (x, z, rad) in enumerate(YURTS):                 # верёвки с бельём и шкурами у юрт
    if i % 3 != 1:
        continue
    a = random.uniform(0, 2 * math.pi)
    sx, sz = x + math.cos(a) * (rad + 1.3), z + math.sin(a) * (rad + 1.3)
    ex, ez = sx - math.sin(a) * 4.6, sz + math.cos(a) * 4.6
    if all(free(px, pz, 0.6) and not on_road(px, pz) for px, pz in ((sx, sz), (ex, ez), ((sx + ex) / 2, (sz + ez) / 2))):
        items.append({"laundry": [round(sx, 2), round(sz, 2), round(ex, 2), round(ez, 2)], "seed": i, "p": [sx, 0, sz],
                      "c": False})
        occupied.append(((sx + ex) / 2, (sz + ez) / 2, 2.6))

for x, z, r in ((-58, 34, 90),
                (-30, -40, 90)):
    add("cart", x, z, r, c=True, rad=2.0)
for x in range(-70, 74, 18):                         # каменные фонари вдоль Аллеи — свет вечером
    if abs(x) > 24 and not 28 < x < 40:
        add("stone_lantern", x + 9, -12.5, 0)
        add("stone_lantern", x + 9, 12.5, 180)
for x, z in ((60, 14), (62, 30), (44, -16), (-46, 30), (-26, 18)):
    add("hay_bale", x, z, random.uniform(0, 360), c=True)
for i in range(4):
    add("crate", 64 + i * 0.85, -14, random.uniform(-8, 8))
    add("barrel_water", 46 + i * 0.9, 33, 0)

# ===================== версия 3: облик Орды — кость, клыки, шкуры, алые знамёна; точки интереса =====================
# Склон шаманов: башня шаманки на вершине, мановые тотемы, бубен (звук)
add("@shaman_tower", 68, -68, 200, c=True, y=4.0, rad=5)
for x, z in ((59, -60), (74, -59), (61, -73)):
    add("@mana_totem", x, z, random.uniform(0, 360), c=True, y=4.0)
add("@bone_banner", 56, -57, 160, c=True, y=4.0)
# гоблинский закоулок под склоном: хижины на сваях, плетни, вёдра, верёвки с тряпками
for x, z, r in ((44, -44, 30), (52, -47, -20), (40, -54, 80), (48, -56, 140)):
    if free(x, z, 3.0):
        add("@stilt_hut", x, z, r, c=True, rad=3.2)
for x, z in ((46, -40), (43, -50), (51, -52)):
    add("@bucket_set", x, z, random.uniform(0, 360), c=False)
add("@tusk_arch", 40, -37, 90, c=True)                     # вход в гоблинский закоулок
add("@mana_totem", 47, -50, 0, c=True)
# Кузнечный двор (между базаром и Счётным двором): кузня, жаровни, стойки, сохнущие шкуры
add("@forge_smithy", -32, -24, 90, s=0.62, c=True, rad=6.5)   # модель 9 м (крыша на столбах) — до 5.6 м
add("@spear_rack", -24.5, -19.5, 90, c=True)
add("@spear_rack", -24.5, -28.5, 90, c=True)
add("@brazier_tusk", -25, -16.5, 0, c=True)
add("@hide_frame", -40, -18, 60, c=True)
add("@hide_frame", -42, -30, 110, c=True)
add("barrel_water", -26.5, -24, 0)
add("wood_pile", -38.5, -27, 90, c=True)
# Конюшня у таверны: сено, телега, коновязь
add("@stable_hay", 76, 21, -90, c=True, rad=7)
add("@hay_wagon", 70, 33, 200, c=True, rad=2.2)
add("hay_bale", 71, 12, 30, c=True)
add("hay_bale", 72.2, 13.4, 70, c=True)
# Ставка Хаана: каменные волки у лестницы, жаровни с клыками, трофеи, барабаны
add("@guardian_statue", -8.6, -25.5, 0, c=True)          # волки-стражи по краям лестницы, лицом к городу
add("@guardian_statue", 8.6, -25.5, 0, c=True)
for x in (-20, 20):
    add("@brazier_tusk", x, -37.5, 0, c=True, y=3.0)
add("@loot_pile", -9, -38, 20, c=True, y=3.0)
add("@loot_pile", 9.5, -38.5, -30, c=True, y=3.0)
add("@war_drum", -13, -36.5, 10, c=True, y=3.0)
add("@war_drum", 13, -36.5, -10, c=True, y=3.0)
# Арена: барабаны у южного входа
add("@war_drum", -6.6, 32.0, 20, c=True)
add("@war_drum", 6.6, 32.0, -20, c=True)
# Базар Добычи: клетки зверей, лавки со шкурами, груда трофеев, вход — арка клыков
add("@beast_cage", -75, 12, 90, c=True)
add("@beast_cage", -75, 18.5, 80, c=True)
add("@market_stall_hide", -62, 30.5, 180, c=True)
add("@market_stall_hide", -54, 30.5, 180, c=True)
add("@loot_pile", -52, 13, 0, c=True)
add("@tusk_arch", -37.5, 9.5, 90, c=True)
# Врата и стена: дозорные вышки на углах и у ворот, знамёна-туги из костей у въезда
for x, z in ((-86, -90), (86, -90), (-86, 78), (86, 78)):
    add("@watch_tower", x, z, random.uniform(0, 360), c=True, rad=3)
for x in (-7.5, 7.5):
    add("@bone_banner", x, 75, 180 if x < 0 else 0, c=True)
# тотемы по Аллее у арены и вертела в кварталах
for x, z in ((-24, -11), (24, 11), (-24, 11)):
    if free(x, z, 0.8):
        add("@totem_pole", x, z, random.uniform(0, 360), c=True)
# буйволиный двор: вход — арка клыков
add("@tusk_arch", 22.6, 33.5, 90, c=True)

# гирлянды фонарей между домами Тракта (через улицу, на высоте вторых этажей) и между юртами кварталов
for i in range(0, len(YURTS) - 1, 2):
    (ax, az, ar), (bx, bz, br) = YURTS[i], YURTS[i + 1]
    dist = math.hypot(bx - ax, bz - az)
    if 7 < dist < 16:
        items.append({"lanterns": [round(ax, 2), round(az, 2), round(bx, 2), round(bz, 2), 3.6], "seed": i, "p": [ax, 0, az],
                      "c": False})

# 3D-звуки мест (заглушки sounds/amb/*.ogg — pax_rpg/dev/sfx/gharn_amb.py)
SOUNDS = [("forge", -32, 2.0, -22, -2.0, 38), ("market", -54, 2.0, 14, -4.0, 46), ("tavern", 54, 2.0, 22, -3.0, 34),
          ("shaman_drum", 68, 7.0, -66, -3.0, 55), ("water", 34, 1.0, 0, -6.0, 18), ("stable", 76, 1.5, 21, -6.0, 24),
          ("flags", 64, 6.0, -62, -10.0, 26), ("fire", -20, 4.0, -37.5, -8.0, 14),
          ("fire", 20, 4.0, -37.5, -8.0, 14), ("fire", -25, 1.0, -16.5, -8.0, 12), ("market", 0, 2.0, 50, -10.0, 34)]
for name, x, y, z, db, rng_ in SOUNDS:
    items.append({"sound": "sounds/amb/%s.ogg" % name, "p": [x, y, z], "db": db, "range": rng_, "c": False})

# вытоптанная земля дворов v3 — без травы, грязь и тропы (маска G)
YARDS = [("rect", -44, -22, -34, -14), ("rect", 36, 62, -60, -36), ("rect", 66, 84, 12, 32), ("rect", -12, 12, 64, 80)]
TRAILS.extend(YARDS)
# гоблинский закоулок: верёвки с тряпьём между хижинами, плетни, костёр, дрова, флажки маны
for (ax_, az_), (bx_, bz_) in (((44, -44), (52, -47)), ((40, -54), (48, -56)), ((44, -44), (40, -54))):
    items.append({"laundry": [ax_ + 1.5, az_ + 1.0, bx_ - 1.5, bz_ + 1.0], "seed": int(ax_ * az_), "p": [ax_, 0, az_],
                  "c": False})
for fx, fz, fr in ((36.5, -46, 90), (36.5, -50, 90), (36.5, -54, 90), (55, -40, 0), (59, -40, 0)):
    add("fence_wood", fx, fz, fr, c=True)
add("firepit", 46.5, -49.5, 0, c=False)
add("wood_pile", 54, -52, 30, c=True)
add("crate", 42.5, -47.5, 15)
add("sack_grain", 43.3, -47.2)
add("mana_flags_line", 44, -42, 75, c=False)
add("mana_flags_line", 50, -53, -20, c=False)
add("ovoo_cairn", 39, -41)
# кузнечный двор: телега с углём, ящики заготовок, бочки для закалки, стойки
add("cart", -40.5, -21.5, 20, c=True)
for i in range(3):
    add("crate", -28 + i * 0.9, -30.5, random.uniform(-8, 8))
add("barrel_water", -26.5, -22.6, 0)
add("weapon_rack", -31, -16.6, 0, c=True)
add("wood_pile", -39, -31.5, 0, c=True)
items.append({"lanterns": [-24.5, -15.5, -24.5, -32.5, 3.8], "seed": 77, "p": [-24.5, 0, -24], "c": False})
# конюшня: коновязи, поилки, сено, мешки
add("hitching_post", 69, 16, 90, c=True)
add("hitching_post", 69, 26, 90, c=True)
add("trough", 70.5, 21, 90, c=True)
for hx, hz in ((80.5, 13.5), (81.2, 15), (80.6, 29)):
    add("hay_bale", hx, hz, random.uniform(0, 360), c=True)
add("sack_grain", 71.5, 29.5)

LANDMARKS_V3 = [["pax_rpg_lm_kurgans", -62, -76], ["pax_rpg_lm_garden", 0, -83], ["pax_rpg_lm_kennels", 35, -74],
                ["pax_rpg_lm_masters", 55, 57], ["pax_rpg_lm_clans", -54, 58], ["pax_rpg_lm_forge", -32, -24], ["pax_rpg_lm_stable", 76, 21], ["pax_rpg_lm_goblins", 46, -48]]

grass, rocks, bushes = 0, 0, 0
tries = 0
while (grass < 900 or rocks < 120 or bushes < 70) and tries < 60000:
    tries += 1
    x, z = random.uniform(-91, 91), random.uniform(-94, 82)
    if on_road(x, z, 0.6) or not free(x, z, 0.4) or (-70 < x < 70 and -96 < z < -40 and abs(x) < 28) \
            or any(sh[1] < x < sh[2] and sh[3] < z < sh[4] for sh in YARDS):
        continue
    edge = abs(x) > 80 or z > 76 or z < -84            # у частокола — гуще
    if any((sh[0] == "rect" and sh[1] - 0.8 < x < sh[2] + 0.8 and sh[3] - 0.8 < z < sh[4] + 0.8) or
           (sh[0] == "line" and _seg_d(x, z, sh[1]) < sh[2] / 2 + 0.8) or
           (sh[0] == "disc" and math.hypot(x - sh[1], z - sh[2]) < sh[3] + 0.8) for sh in TRAILS):
        continue                                     # на тропах и дорожках — без травы: по ним ходят
    if not edge and random.random() < 0.85:          # в городе трава — лишь редкими кустами, не полями
        continue
    if any(a0 - 0.6 < x < a1 + 0.6 and b0 - 0.6 < z < b1 + 0.6 for a0, a1, b0, b1 in RECTS):
        continue
    k = random.random()
    if grass < 900 and k < (0.9 if edge else 0.8):
        add("grass_tuft", x, z, random.uniform(0, 360), s=round(random.uniform(0.7, 1.4), 2), c=False)
        grass += 1
        if random.random() < 0.6:                    # пучки кучками
            for _ in range(random.randint(1, 4)):
                gx, gz = x + random.uniform(-0.8, 0.8), z + random.uniform(-0.8, 0.8)
                add("grass_tuft", gx, gz, random.uniform(0, 360), s=round(random.uniform(0.6, 1.2), 2), c=False)
                grass += 1
    elif rocks < 140 and k < 0.92:
        add("rock_small", x, z, random.uniform(0, 360), s=round(random.uniform(0.6, 1.6), 2), c=False)
        rocks += 1
    elif bushes < 90:
        add("bush_dry", x, z, random.uniform(0, 360), s=round(random.uniform(0.8, 1.5), 2), c=False)
        bushes += 1


# ===================== дорожная сеть: все точки интереса связаны =====================
# Мощёные (R маски): Тракт и Аллея были; новые — к Кузне и Счётному двору, к Курганам, вокруг Ставки к Саду Хаана,
# к гоблинам и склону шаманов, к Псарням, от таверны к Улице Мастеров, мимо конюшни, к Буйволиному двору.
PAVED = [
    [(-21.5, -8.5), (-21.5, -34), (-45, -34), (-45, -58), (-62, -58)],          # Аллея → Кузня → Счётный двор → Курганы
    [(-45, -58), (-36, -72), (-30, -83), (-24, -83)],                            # → Сад Хаана (в обход Ставки, запад)
    [(36, -8.5), (36, -37), (44, -38.5), (62, -42.5)],                           # Аллея → гоблины → пандус шаманов
    [(36, -37), (35, -60)],                                                      # → Псарни
    [(66, 8.5), (66, 40), (55, 44)],                                                       # Аллея → конюшня → Улица Мастеров
    [(55, 33), (55, 56)],                                                        # таверна → колодец Мастеров
    [(30, 8.5), (20, 26), (20, 33.5), (22.5, 33.5)],                             # Аллея → Буйволиный двор (ворота)
]
DIRT = [
    [(35, -60), (35, -88)],                                                      # проход между загонами
    [(24, -83), (20, -83), (20, -74), (35, -74)],                                           # Сад Хаана → Псарни (восток)
]
for pl in PAVED:
    ROADS.append(("line", pl, 4.0))
for pl in DIRT:
    TRAILS.append(("line", pl, 3.0))
ALL_LINES = [(pl, 4.0) for pl in PAVED] + [(pl, 3.0) for pl in DIRT]

# с проезда убрать всё, что не постройка и не дерево: бочки, ящики, плетни, сено, мелочь
KEEP = ("palisade", "gate_fang", "khan_palace", "guild_hall", "tavern_hall", "house_", "forge_smithy", "stable_hay",
        "shaman_tower", "watch_tower", "yurt", "stilt_hut", "oath_tree", "fountain", "arena")
def _on_lines(x, z, m):
    return any(_seg_d(x, z, pl) < w / 2 + m for pl, w in ALL_LINES)
kept = []
removed = 0
for it in items:
    pnt = it.get("p")
    if pnt and not any(k in it.get("m", "") for k in KEEP) and "sound" not in it and "box" not in it \
            and _on_lines(pnt[0], pnt[2], 0.9):
        removed += 1
        continue
    kept.append(it)
items[:] = kept
print("с дорог убрано:", removed)
for it in items:                                   # постройка на дороге — ошибка планировки, видно сразу
    if "m" in it and any(k in it["m"] for k in KEEP[:13]) and _on_lines(it["p"][0], it["p"][2], 0.0):
        print("  ВНИМАНИЕ: постройка на дороге", it["m"], it["p"])

# --- благоустройство вдоль мощёных дорог: скамья + урна каждые ~16 м (сторона чередуется), лицом к дороге;
# на перекрёстках и поворотах — большие каменные кадки с сакурой (по углам, не на проходе); клумбы на Аллее.
def _clear(x, z, r):
    if on_road(x, z, 0.3):
        return False
    if any(a0 - r < x < a1 + r and b0 - r < z < b1 + r for a0, a1, b0, b1 in RECTS):
        return False
    return all((x - a) ** 2 + (z - b) ** 2 > (r + rr) ** 2 for a, b, rr in occupied) and \
        all((it["p"][0] - x) ** 2 + (it["p"][2] - z) ** 2 > (r + 0.9) ** 2 for it in items
            if "m" in it and "grass" not in it["m"] and "window" not in it["m"])


def bench_set(x, z, yaw):
    add("bench_long", x, z, yaw, c=True, rad=1.2)
    a = math.radians(yaw)
    add("barrel_kumis", x + math.cos(a) * 1.6, z - math.sin(a) * 1.6, 0, s=0.5, c=True)   # урна у скамьи


def planter(x, z):
    box([2.4, 0.9, 2.4], x, 0.45, z, "stone_cut", c=True)
    add("@flame_tree", x, z, random.uniform(0, 360), s=0.42, c=False, y=0.9)
    add("models/nature/plant_flower", x + 0.7, z - 0.6, 0, s=0.9, c=False, y=0.9) if False else None
    occupied.append((x, z, 1.8))


def road_furniture(pl, w, step=16.0):
    acc, side = 8.0, 1
    for (ax, az), (bx, bz) in zip(pl, pl[1:]):
        L = math.hypot(bx - ax, bz - az)
        ux, uz = (bx - ax) / L, (bz - az) / L
        nx, nz = -uz, ux
        t = acc
        while t < L - 2:
            off = w / 2 + 1.3
            x, z = ax + ux * t + nx * off * side, az + uz * t + nz * off * side
            yaw = math.degrees(math.atan2(-nx * side, -nz * side))   # спинкой от дороги
            if _clear(x, z, 1.6):
                bench_set(x, z, yaw)
            side = -side
            t += step
        acc = t - L
    for (x, z) in pl[1:-1]:                        # повороты: кадки снаружи угла
        for dx, dz in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
            px_, pz_ = x + dx * (w / 2 + 2.2), z + dz * (w / 2 + 2.2)
            if _clear(px_, pz_, 1.8):
                planter(px_, pz_)
                break


for pl in PAVED:
    road_furniture(pl, 4.0)
for x0, x1 in ((-74, -26), (26, 74)):             # Аллея: скамьи у деревьев
    road_furniture([(x0, 0), (x1, 0)], 13.0, 18.0)
# клумбы по оси Аллеи — каменный бордюр, цветы и травы; проход по обе стороны 5 м
for x in list(range(-66, -28, 12)) + list(range(46, 72, 12)):
    if any(abs(x - sx) < 4 for sx in (-54, -42)):  # у рядов базара — без клумб
        continue
    box([5.0, 0.35, 1.8], x, 0.175, 0, "stone_cut", c=True)
    for k in range(5):
        add("grass_tuft", x - 2.0 + k, random.uniform(-0.5, 0.5), random.uniform(0, 360), s=0.8, c=False, y=0.35)
        add("bush_dry", x - 1.6 + k * 0.8, random.uniform(-0.3, 0.3), random.uniform(0, 360), s=0.6, c=False, y=0.35) \
            if k % 2 else None
# у начала и конца каждой дороги (вход к месту) — пара кадок по сторонам
for pl in PAVED:
    for (x, z), (x2, z2) in ((pl[0], pl[1]), (pl[-1], pl[-2])):
        L = math.hypot(x2 - x, z2 - z)
        ux, uz = (x2 - x) / L, (z2 - z) / L
        for sd in (-1, 1):
            px_, pz_ = x + ux * 4.5 - uz * sd * 4.6, z + uz * 4.5 + ux * sd * 4.6
            if _clear(px_, pz_, 1.8):
                planter(px_, pz_)
# вход в город: кадки у ворот и у площади Круга (по сторонам Тракта)
for x in (-6.8, 6.8):                                # кадки по сторонам выхода Аллеи на площадь
    if _clear(x, 31.0, 1.8):
        planter(x, 31.0)

# подписи на карте (M): ключ перевода, x, z
LANDMARKS = [["pax_rpg_lm_gate", 0, 80], ["pax_rpg_lm_trakt", 0, 52], ["pax_rpg_lm_circle", 15, 21],
             ["pax_rpg_lm_khan", 0, -56], ["pax_rpg_lm_arena", AX, AZ], ["pax_rpg_lm_alley", -52, 0],
             ["pax_rpg_lm_fountain", 34, 0], ["pax_rpg_lm_guild", 54, -22], ["pax_rpg_lm_tavern", 54, 24],
             ["pax_rpg_lm_bazaar", -54, 14], ["pax_rpg_lm_barracks", -55, -45], ["pax_rpg_lm_shamans", 66, -66],
             ["pax_rpg_lm_buffalo", 32, 33], ] + LANDMARKS_V3
# маршруты мирных жителей (ломаные по улицам), сколько их
paths = [
    [[0, 80], [0, 50], [0, 24]],                                        # Тракт
    [[-1.5, 78], [-1.5, 30], [-8, 19.5], [-17, 13.5], [-22, 2]],                       # Тракт → базар
    [[-74, -3], [-40, -3], [-22, -3]],                                     # Аллея, запад
    [[22, -2], [34, -6], [50, -2], [74, -2]],                           # Аллея, восток мимо фонтана
    [[44, 8], [36, 6], [26, 12], [14, 18], [2, 22]],                    # таверна → площадь
    [[0, 24], [17, 17], [24, 0], [17, -17], [7, -20.5], [-7, -20.5], [-17, -17], [-24, 0], [-17, 17], [0, 24]],  # вокруг Арены
    [[-52.3, -3], [-52.3, 26], [-43.3, 26], [-43.3, -3]],                         # по базару
    [[-43.3, 8.5], [-43.3, 30], [-45, 34], [-45, 58], [-65, 58], [-65, 80]],                      # переулки куреней
    [[30, 6.5], [20, 24], [20, 33.5], [22.5, 33.5]],                    # к Буйволиному двору
    [[66, 8.5], [66, 40], [55, 44], [55, 57.5], [44, 57.5]],                                  # мимо конюшни на Улицу Мастеров
    [[-21.5, -6.5], [-21.5, -34], [-45, -34], [-45, -58], [-62, -58]],  # к Кузне, Счётному двору и Курганам
    [[34, -6.5], [34, -37], [44, -38.5], [62, -42.5]],                  # к гоблинам и шаманам
    [[-45, -58], [-30, -83], [20, -83], [20, -74], [35, -74], [35, -60]],          # Сад Хаана и Псарни
    [[30, -12], [36, -12], [36, -30], [44, -38.5]],                                   # к гильдии
    [[6, 57.5], [55, 57.5], [84, 57.5]],                                # Улица Мастеров
    [[55, 34], [55, 57.5], [55, 80]],                                   # переулок к таверне
    [[-6, 58], [-43, 58], [-65, 58], [-86, 58]],                        # переулок куреней
    [[-62, -58], [-62, -86]],                                           # аллея Курганов
    [[-20, -83], [20, -83]],                                            # Сад Хаана
]
npcs = 40
# ракурсы для превью: [камера xyz, куда смотрит xyz] — консоль rpg_cam N
shots = [
    [[0, 9, 96], [0, 6, 20]],            # 1 через Врата Клыка на Тракт и Ставку
    [[-3, 2.2, 60], [4, 4, 20]],         # 2 по Тракту на уровне глаз
    [[22, 14, 22], [0, 2, -8]],          # 3 площадь Круга сверху
    [[22, 3, 8], [40, 3, -10]],          # 4 Аллея, фонтан и гильдия
    [[30, 4, 2], [54, 6, 24]],           # 5 таверна от фонтана
    [[-110, 70, 120], [0, 0, -10]],      # 6 весь город с высоты
    [[-14, 6, -10], [-32, 3, -24]],      # 7 кузнечный двор
    [[30, 7, -30], [60, 6, -62]],        # 8 гоблинский закоулок и башня шаманки
    [[60, 4, 8], [76, 3, 21]],           # 9 конюшня у таверны
    [[0, 8, -14], [0, 5, -46]],          # 10 лестница к Ставке: волки, жаровни, трофеи
    [[0, 5, 66], [0, 7, 84]],            # 11 Врата Клыка изнутри: вышки, костяные туги
    [[-30, 5, 20], [-60, 3, 14]],        # 12 Базар Добычи
]

def draw_mask(path):
    """Маска дорог и троп в PNG: R — кладка, G — тропы (по маршрутам жителей и TRAILS), чуть размыто."""
    from PIL import Image, ImageDraw, ImageFilter
    w, d = GROUND[0] * MASK_PX, GROUND[1] * MASK_PX
    x0, z0 = GROUND[2] - GROUND[0] / 2, GROUND[3] - GROUND[1] / 2
    px = lambda x, z: ((x - x0) * MASK_PX, (z - z0) * MASK_PX)
    r = Image.new("L", (w, d), 0)
    g = Image.new("L", (w, d), 0)
    for layer, shapes in ((r, ROADS), (g, TRAILS)):
        dr = ImageDraw.Draw(layer)
        for sh in shapes:
            if sh[0] == "rect":
                dr.rectangle([px(sh[1], sh[3]), px(sh[2], sh[4])], fill=255)
            elif sh[0] == "line":
                dr.line([px(x, z) for x, z in sh[1]], fill=255, width=int(sh[2] * MASK_PX), joint="curve")
                for x, z in sh[1]:
                    cx, cz = px(x, z)
                    rr = sh[2] * MASK_PX / 2
                    dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=255)
            else:
                cx, cz = px(sh[1], sh[2])
                rr = sh[3] * MASK_PX
                dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=255)
    dg = ImageDraw.Draw(g)
    for pth in paths:
        dg.line([px(x, z) for x, z in pth], fill=255, width=int(2.6 * MASK_PX), joint="curve")
    r = r.filter(ImageFilter.GaussianBlur(MASK_PX * 0.6))
    g = g.filter(ImageFilter.GaussianBlur(MASK_PX * 0.9))
    Image.merge("RGB", (r, g, Image.new("L", (w, d), 0))).save(path)
    return [x0, z0, GROUND[0], GROUND[1]]


# --- дворики в пустотах: где на 9 м вокруг ничего крупного нет — свой маленький быт, чтобы город был плотным:
# юртовый двор с котлом, сруб с садом сакуры, пятачок с фонарями и скамьями, мастерская с дровами и телегой.
SMALL = ("grass_tuft", "rock_small", "bush_dry", "window_glass", "palisade_segment")
def _big_pts():
    out = []
    for it in items:
        if "m" in it and not any(k in it["m"] for k in SMALL):
            out.append((it["p"][0], it["p"][2]))
        elif "box" in it or "brazier" in it or "sign" in it:
            out.append((it["p"][0], it["p"][2]))
    return out


def _near_path(x, z, m):
    for pth in paths:
        for (ax, az), (bx, bz) in zip(pth, pth[1:]):
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / max(dx * dx + dz * dz, 1e-6)))
            if (x - ax - dx * t) ** 2 + (z - az - dz * t) ** 2 < m * m:
                return True
    return False


def fill_voids():
    pts = _big_pts()
    gx0, gx1 = GROUND[2] - GROUND[0] / 2 + 8, GROUND[2] + GROUND[0] / 2 - 8
    gz0, gz1 = GROUND[3] - GROUND[1] / 2 + 8, GROUND[3] + GROUND[1] / 2 - 8
    cells = [(x, z) for x in range(int(gx0), int(gx1), 5) for z in range(int(gz0), int(gz1), 5)]
    random.shuffle(cells)
    n = 0
    for cx, cz in cells:
        x, z = cx + random.uniform(-2, 2), cz + random.uniform(-2, 2)
        if on_road(x, z, 3.0) or (x - AX) ** 2 + (z - AZ) ** 2 < 30 ** 2 or (abs(x) < 16 and z < -24):
            continue
        if any((x - a) ** 2 + (z - b) ** 2 < 9.0 ** 2 for a, b in pts) or _near_path(x, z, 6.0):
            continue
        kind = n % 4
        r0 = random.uniform(0, 360)
        if kind == 0:                                   # юртовый двор
            add("yurt_large", x, z, r0, c=True, rad=4.6)
            for k in range(3):
                a = math.radians(r0 + 120 * k)
                add(random.choice(["barrel_water", "cauldron", "sack_grain", "basket", "hay_bale"]),
                    x + math.cos(a) * 5.8, z + math.sin(a) * 5.8, random.uniform(0, 360), rad=0.6)
            add("firepit", x + 6.5, z, 0, c=False)
        elif kind == 1:                                 # сруб с садом
            add(random.choice(["@house_timber_a", "@house_timber_b"]), x, z, random.choice([0, 90, 180, 270]), c=True, rad=5.4)
            for k in range(2):
                a = random.uniform(0, 2 * math.pi)
                add("@flame_tree", x + math.cos(a) * 7.0, z + math.sin(a) * 7.0, random.uniform(0, 360),
                    s=round(random.uniform(0.7, 0.95), 2), rad=1.5)
            add("@bucket_set", x + 4.0, z + 4.0, r0, c=False)
        elif kind == 2:                                 # пятачок: фонари, скамьи, тотем
            add("stone_lantern", x - 2.5, z, r0, rad=0.6)
            add("stone_lantern", x + 2.5, z, r0, rad=0.6)
            add("bench_long", x, z + 2.2, r0, rad=1.0)
            add(random.choice(["@totem_pole", "ovoo_cairn", "@mana_totem"]), x, z - 1.5, r0, rad=1.0)
            items.append({"lanterns": [x - 2.5, z, x + 2.5, z, 3.2], "seed": int(x * 7 + z), "p": [x, 0, z], "c": False})
        else:                                           # мастерская
            add("yurt_small", x, z, r0, c=True, rad=3.0)
            add("wood_pile", x + 4.0, z, r0, rad=1.0)
            add(random.choice(["cart", "@hay_wagon"]), x - 4.5, z + 1.0, r0, rad=1.5)
            add(random.choice(["@hide_frame", "@spear_rack", "training_dummy"]), x, z + 4.5, r0, rad=0.8)
        pts.append((x, z))
        n += 1
    print("дворики:", n)




# --- внешний город: слобода за стеной — юрты кочевников, срубы, вышки и туги. Земля там ровная (data "outer"),
# без коллизии (игрок туда не выходит), дым не идёт — только силуэт, чтобы столица не стояла коробкой в пустыне.
OUTER = 34.0
def outer_belt():
    gx0, gx1 = GROUND[2] - GROUND[0] / 2, GROUND[2] + GROUND[0] / 2
    gz0, gz1 = GROUND[3] - GROUND[1] / 2, GROUND[3] + GROUND[1] / 2
    step = 9.0
    x = gx0 - OUTER + 4
    while x < gx1 + OUTER - 4:
        z = gz0 - OUTER + 4
        while z < gz1 + OUTER - 4:
            px, pz = x + random.uniform(-0.6, 0.6), z + random.uniform(-0.6, 0.6)   # слобода — рядами вдоль стены
            inside = gx0 - 5 < px < gx1 + 5 and gz0 - 5 < pz < gz1 + 5
            in_field = any(abs(px - fx) < w / 2 + 6 and abs(pz - fz) < d / 2 + 6 for fx, fz, w, d, _m in FIELDS) or \
                (abs(px) < 70 and pz > gz1 + 4)               # юг у ворот — поля и дорога, без юрт
            if not inside and not in_field and not (abs(px) < 9 and pz > gz1 - 6) and random.random() < 0.9:
                k = random.random()
                if k < 0.55:
                    add(random.choice(["yurt_large", "yurt_small", "yurt_small"]), px, pz, random.uniform(0, 360), c=False, y=-0.4)
                elif k < 0.8:
                    face = 0 if pz < gz0 else 180 if pz > gz1 else (90 if px < gx0 else -90)   # фасадом к стене столицы
                    add("yurt_large", px, pz, face, c=False, y=-0.4)   # дома по 100k — только в столице
                elif k < 0.95:
                    add("@bone_banner", px, pz, random.uniform(0, 360), c=False, y=-0.4)
                else:
                    add("@hay_wagon", px, pz, random.uniform(0, 360), c=False, y=-0.4)
            z += step
        x += step



# --- Поля за стеной (юг, по сторонам дороги от Врат): гряды проса, зелени и риса, межи, стога, пугала, сарай.
# Кормят столицу; видны с дороги к воротам — первое, что игрок видит у города.
FIELDS = [(-48, 104, 26, 14, "field_millet"), (-20, 104, 18, 14, "field_green"), (20, 104, 18, 14, "field_rice"),
          (48, 104, 26, 14, "field_millet"), (-34, 117.5, 30, 9, "field_green"), (34, 117.5, 30, 9, "field_millet")]
def fields():
    for fx, fz, w, d, mat in FIELDS:
        box([w, 0.06, d], fx, -0.37, fz, "furrow", c=False)
        rows = int(d / 1.2)
        for i in range(rows):
            z = fz - d / 2 + 0.6 + i * 1.2
            box([w - 1.0, 0.32, 0.55], fx, -0.2, round(z, 2), mat, c=False)
        add("hay_bale", fx + w / 2 + 1.2, fz - 2, 20, c=False, y=-0.4)
        add("hay_bale", fx + w / 2 + 1.4, fz + 0.2, 80, c=False, y=-0.4)
        add("training_dummy", fx - w / 4, fz, random.uniform(0, 360), c=False, y=-0.4)   # пугало
    for x in (-70, 70):
        add("@stable_hay", x, 106, 0, s=0.7, c=False, y=-0.4)   # сарай для снопов


fields()

outer_belt()


mask_rect = draw_mask(os.path.join(ROOT, "mods", "pax_rpg", "models", "gharn", "tex", "roads_mask.png"))
data = {"_note": "Сгенерировано pax_rpg/dev/gharn/gharn_layout.py — правки вносить там.",
        "start": [0, 1.2, 74], "exit": [0, 86], "exit_radius": 5.0, "ground": GROUND, "ground_mask": {"tex": "models/gharn/tex/roads_mask.png", "rect": mask_rect}, "goblins": 0, "landmarks": LANDMARKS, "map": "config/gharn_map.json", "arena": [AX, AZ, PIT, A_IN], "paths": paths, "npcs": npcs, "shots": shots, "outer": OUTER,
        "items": items}
out = os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn.json")
json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(items), "объектов →", out)

# чертёж для Obsidian (совпадает с городом): obsidian/Pax RPG Vault/03 Мир/Города/Гхарн/Гхарн — план.svg
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plan_map import draw_plan  # noqa: E402
from check_overlaps import foot  # noqa: E402
draw_plan(os.path.join(ROOT, "obsidian", "Pax RPG Vault", "03 Мир", "Города", "Гхарн", "Гхарн — план.svg"), items, ROADS,
          TRAILS, foot, GROUND, OUTER)
print("чертёж обновлён")
