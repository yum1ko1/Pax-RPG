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
ROADS = [("rect", -4.5, 4.5, 14, 90), ("rect", -78, 78, -6.5, 6.5), ("disc", 0, 0, 21.5), ("rect", -6.5, 6.5, -37, -14),
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
add("stairs_stone", 0, -25, 180, s=3.0)
add("@khan_palace", 0, -56, 0, c=True, y=3.0, rad=16)
for x in (-6, 6):
    add("tug_banner", x, -38, y=3.0)
for x in (-22, -14, 14, 22):
    add("@yurt_noble" if abs(x) > 18 else "banner_clan", x, -46, 180, c=True, y=3.0)

# --- Площадь Круга: Круг, фонари, Древо Клятв (пока — дерево Аллеи покрупнее), глашатай
for a in range(0, 360, 30):
    ra = math.radians(a)
    add("stone_lantern", math.sin(ra) * 20.5, math.cos(ra) * 20.5) if a % 60 else None
box([2, 1, 2], 0, 0.5, -21.2, "stone_dark")                   # тумба глашатая — у северного входа Арены
add("@oath_tree", 21, -21, 30, s=1.0, rad=6)                    # Древо Клятв: баньян с лентами (Meshy v3)
add("ovoo_cairn", 17, -11)
add("trough", -16, 16, 45, c=True)
occupied.append((0, 0, 21))

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
    for z in (-8, 8):
        if 30 < x < 40:
            continue
        add("@flame_tree", x, z, random.uniform(0, 360), s=random.uniform(0.85, 1.05), rad=1.5)
    if x % 18 < 9:
        add("banner_clan", x + 4.5, -7.5, 0)
        add("banner_clan", x + 4.5, 7.5, 180)
    add("bench_long", x + 4.5, -9.5, 0)
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

# --- Тракт Туменов: лавки, фонари, туги, гирлянды, мелочь у входов
shops = ["@house_shop_a", "@house_shop_b", "@house_shop_c"]
for i, z in enumerate(range(30, 76, 11)):
    add(shops[i % 3], -12, z, 90, c=True, rad=5.5)
    add(shops[(i + 1) % 3], 12, z, -90, c=True, rad=5.5)
for z in range(28, 80, 10):
    add("lantern_post", -5.6, z, 0)
    add("lantern_post", 5.6, z, 180)
    add("tug_banner", -6.2, z + 5)
    add("tug_banner", 6.2, z + 5)
for z in range(33, 80, 12):
    add("lantern_string", 0, z, 0)
for z in range(27, 78, 5):
    for side in (-1, 1):
        k = random.random()
        x = side * random.uniform(6.6, 7.4)
        if k < 0.35:
            add("barrel_kumis", x, z, random.uniform(0, 360))
        elif k < 0.6:
            add("crate", x, z + 1, random.uniform(-10, 10))
            add("sack_grain", x + side * 0.2, z + 2)
        elif k < 0.8:
            add("basket", x, z)
            add("sack_grain", x, z + 0.8)
add("hitching_post", -5.5, 78, 0, c=True)
add("trough", 5.5, 78, 0, c=True)

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


quarter(-86, -20, 34, 80, 22)
quarter(20, 86, 40, 80, 20)
quarter(-86, -24, 14, 30, 5)


# --- деталь столицы: дворы у юрт, быт, телеги, навесы у лавок, фонари Аллеи, зелень
def on_road(x, z, m=1.5):
    for sh in ROADS:
        if sh[0] == "rect" and sh[1] - m < x < sh[2] + m and sh[3] - m < z < sh[4] + m:
            return True
        if sh[0] == "disc" and (x - sh[1]) ** 2 + (z - sh[2]) ** 2 < (sh[3] + m) ** 2:
            return True
    return False


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
for i, z in enumerate(range(30, 76, 11)):                # вывески лавок Тракта — лицом к дороге
    items.append({"sign": list(SIGNS[i * 2]), "p": [-7.9, 0.0, z + 2.8], "r": 90.0, "c": True})
    items.append({"sign": list(SIGNS[i * 2 + 1]), "p": [7.9, 0.0, z + 2.8], "r": -90.0, "c": True})
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

for x, z, r in ((-8.5, 66, 0), (8.5, 44, 180), (-9, 22, 20), (9, 84, 160), (-58, 34, 90), (-40, 14, 0), (46, 30, 200),
                (-30, -40, 90)):
    add("cart", x, z, r, c=True, rad=2.0)
for i, z in enumerate(range(30, 76, 11)):            # навесы перед лавками Тракта
    if i % 2 == 0:
        add("awning", -8.6, z, 90, c=False)
    else:
        add("awning", 8.6, z, -90, c=False)
for x in range(-70, 74, 18):                         # каменные фонари вдоль Аллеи — свет вечером
    if abs(x) > 24 and not 28 < x < 40:
        add("stone_lantern", x + 9, -10.5, 0)
        add("stone_lantern", x + 9, 10.5, 180)
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
add("@forge_smithy", -32, -24, 90, c=True, rad=6.5)
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
add("@guardian_statue", -6.8, -23.5, 180, c=True)
add("@guardian_statue", 6.8, -23.5, 180, c=True)
for x in (-20, 20):
    add("@brazier_tusk", x, -37.5, 0, c=True, y=3.0)
add("@loot_pile", -9, -38, 20, c=True, y=3.0)
add("@loot_pile", 9.5, -38.5, -30, c=True, y=3.0)
add("@war_drum", -13, -36.5, 10, c=True, y=3.0)
add("@war_drum", 13, -36.5, -10, c=True, y=3.0)
# Арена: барабаны у южного входа
add("@war_drum", -6.6, 23.5, 20, c=True)
add("@war_drum", 6.6, 23.5, -20, c=True)
# Базар Добычи: клетки зверей, лавки со шкурами, груда трофеев, вход — арка клыков
add("@beast_cage", -75, 12, 90, c=True)
add("@beast_cage", -75, 18.5, 80, c=True)
add("@market_stall_hide", -62, 30.5, 180, c=True)
add("@market_stall_hide", -54, 30.5, 180, c=True)
add("@loot_pile", -52, 13, 0, c=True)
add("@tusk_arch", -37.5, 9.5, 90, c=True)
# Врата и стена: дозорные вышки на углах и у ворот, знамёна-туги из костей у въезда
for x, z in ((-86, -90), (86, -90), (-86, 78), (86, 78), (-15, 79), (15, 79)):
    add("@watch_tower", x, z, random.uniform(0, 360), c=True, rad=3)
for x in (-7.5, 7.5):
    add("@bone_banner", x, 75, 180 if x < 0 else 0, c=True)
    add("@totem_pole", x * 1.25, 71, 0, c=True)
# тотемы по Аллее у арены и вертела в кварталах
for x, z in ((-24, -11), (24, 11), (-24, 11)):
    if free(x, z, 0.8):
        add("@totem_pole", x, z, random.uniform(0, 360), c=True)
for x, z in ((-36, 46), (30, 52), (-62, 66)):
    if free(x, z, 1.4):
        add("@spit_roast", x, z, random.uniform(0, 360), c=True, rad=1.4)
# буйволиный двор: вход — арка клыков
add("@tusk_arch", 22.6, 33.5, 90, c=True)

# гирлянды фонарей между домами Тракта (через улицу, на высоте вторых этажей) и между юртами кварталов
for z in range(36, 76, 11):
    items.append({"lanterns": [-8.6, z, 8.6, z + 1.5, 5.2], "seed": z * 3, "p": [0, 0, z], "c": False})
for i in range(0, len(YURTS) - 1, 2):
    (ax, az, ar), (bx, bz, br) = YURTS[i], YURTS[i + 1]
    dist = math.hypot(bx - ax, bz - az)
    if 7 < dist < 16:
        items.append({"lanterns": [round(ax, 2), round(az, 2), round(bx, 2), round(bz, 2), 3.6], "seed": i, "p": [ax, 0, az],
                      "c": False})

# 3D-звуки мест (заглушки sounds/amb/*.ogg — pax_rpg/dev/sfx/gharn_amb.py)
SOUNDS = [("forge", -32, 2.0, -22, -2.0, 38), ("market", -54, 2.0, 14, -4.0, 46), ("tavern", 54, 2.0, 22, -3.0, 34),
          ("shaman_drum", 68, 7.0, -66, -3.0, 55), ("water", 34, 1.0, 0, -6.0, 18), ("stable", 76, 1.5, 21, -6.0, 24),
          ("flags", 64, 6.0, -62, -10.0, 26), ("flags", 0, 4.0, 52, -12.0, 30), ("fire", -20, 4.0, -37.5, -8.0, 14),
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

LANDMARKS_V3 = [["pax_rpg_lm_forge", -32, -24], ["pax_rpg_lm_stable", 76, 21], ["pax_rpg_lm_goblins", 46, -48]]

grass, rocks, bushes = 0, 0, 0
tries = 0
while (grass < 1800 or rocks < 140 or bushes < 90) and tries < 60000:
    tries += 1
    x, z = random.uniform(-91, 91), random.uniform(-94, 82)
    if on_road(x, z, 0.6) or not free(x, z, 0.4) or (-70 < x < 70 and -96 < z < -40 and abs(x) < 28) \
            or any(sh[1] < x < sh[2] and sh[3] < z < sh[4] for sh in YARDS):
        continue
    edge = abs(x) > 80 or z > 74 or z < -84            # у частокола — гуще
    k = random.random()
    if grass < 1800 and k < (0.9 if edge else 0.8):
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

# подписи на карте (M): ключ перевода, x, z
LANDMARKS = [["pax_rpg_lm_gate", 0, 80], ["pax_rpg_lm_trakt", 0, 52], ["pax_rpg_lm_circle", 15, 21],
             ["pax_rpg_lm_khan", 0, -56], ["pax_rpg_lm_arena", AX, AZ], ["pax_rpg_lm_alley", -52, 0],
             ["pax_rpg_lm_fountain", 34, 0], ["pax_rpg_lm_guild", 54, -22], ["pax_rpg_lm_tavern", 54, 24],
             ["pax_rpg_lm_bazaar", -54, 14], ["pax_rpg_lm_barracks", -55, -45], ["pax_rpg_lm_shamans", 66, -66],
             ["pax_rpg_lm_buffalo", 32, 33], ["pax_rpg_lm_yurts", -52, 58]] + LANDMARKS_V3
# маршруты мирных жителей (ломаные по улицам), сколько их
paths = [
    [[0, 80], [0, 50], [0, 24]],                                        # Тракт
    [[-1.5, 78], [-1.5, 30], [-8, 19.5], [-17, 13.5], [-22, 2]],                       # Тракт → базар
    [[-74, 2], [-40, 2], [-22, 2]],                                     # Аллея, запад
    [[22, -2], [34, -6], [50, -2], [74, -2]],                           # Аллея, восток мимо фонтана
    [[44, 8], [36, 6], [26, 12], [14, 18], [2, 22]],                    # таверна → площадь
    [[0, 20.2], [14.3, 14.3], [20.2, 0], [14.3, -14.3], [0, -20.2], [-14.3, -14.3], [-20.2, 0], [-14.3, 14.3], [0, 20.2]],  # вокруг Арены
    [[0, -20], [0, -32]],                                               # к лестнице Ставки
    [[-60, 2], [-60, 26], [-42, 26], [-42, 2]],                         # по базару
    [[-30, 30], [-50, 44], [-70, 60], [-50, 74]],                       # западный квартал
    [[30, 30], [50, 46], [70, 62], [44, 74]],                           # восточный квартал
    [[-24, -10], [-46, -10], [-47, -26], [-42, -40], [-40, -54]],       # к Счётному двору (в обход Арены)
    [[0, 26], [0, 10]],                                                 # в Арену через южный вход
    [[24, -10], [44, -12], [54, -8]],                                   # к гильдии
]
npcs = 32
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
            px, pz = x + random.uniform(-3, 3), z + random.uniform(-3, 3)
            inside = gx0 - 5 < px < gx1 + 5 and gz0 - 5 < pz < gz1 + 5
            if not inside and not (abs(px) < 9 and pz > gz1 - 6) and random.random() < 0.9:
                k = random.random()
                if k < 0.55:
                    add(random.choice(["yurt_large", "yurt_small", "yurt_small"]), px, pz, random.uniform(0, 360), c=False, y=-0.4)
                elif k < 0.8:
                    add(random.choice(["@house_timber_a", "@house_timber_b"]), px, pz, random.choice([0, 90, 180, 270]), c=False, y=-0.4)
                elif k < 0.88:
                    add("@watch_tower", px, pz, random.uniform(0, 360), c=False, y=-0.4)
                elif k < 0.95:
                    add("@bone_banner", px, pz, random.uniform(0, 360), c=False, y=-0.4)
                else:
                    add("@hay_wagon", px, pz, random.uniform(0, 360), c=False, y=-0.4)
            z += step
        x += step


outer_belt()


mask_rect = draw_mask(os.path.join(ROOT, "mods", "pax_rpg", "models", "gharn", "tex", "roads_mask.png"))
data = {"_note": "Сгенерировано pax_rpg/dev/gharn/gharn_layout.py — правки вносить там.",
        "start": [0, 1.2, 74], "exit": [0, 86], "exit_radius": 5.0, "ground": GROUND, "ground_mask": {"tex": "models/gharn/tex/roads_mask.png", "rect": mask_rect}, "goblins": 0, "landmarks": LANDMARKS, "arena": [AX, AZ, PIT, A_IN], "paths": paths, "npcs": npcs, "shots": shots, "outer": OUTER,
        "items": items}
out = os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn.json")
json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(items), "объектов →", out)
