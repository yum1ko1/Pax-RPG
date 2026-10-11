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
TRUNK = {"flame_tree": [0.9, 3.0, 0.9]}          # у деревьев — только ствол: крона не мешает ходить


def add(m, x, z, r=0.0, s=1.0, c=None, y=0.0, rad=0.0):
    name = m.lstrip("@")
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


# --- дороги: Тракт (x −4…4, z 22…80), Аллея (z −6…6), площадь (r 22)
def tile(x, z):
    add("road_cobble", x, z, random.choice([0, 90, 180, 270]), y=0.02)


for z in range(24, 84, 4):
    for x in (-2, 2):
        tile(x, z)
for x in range(-74, 78, 4):
    if abs(x) < 22:
        continue
    for z in (-4, 0, 4):
        tile(x, z)
for x in range(-22, 24, 4):
    for z in range(-22, 24, 4):
        if x * x + z * z < 21 ** 2:
            tile(x, z)
for z in range(-34, -21, 4):                                  # к лестнице Ставки
    for x in (-4, 0, 4):
        tile(x, z)

# --- ворота и стена
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
    add("yurt_large" if abs(x) > 18 else "banner_clan", x, -46, 0, c=True, y=3.0)

# --- Площадь Круга: Круг, фонари, Древо Клятв (пока — дерево Аллеи покрупнее), глашатай
for a in range(0, 360, 30):
    ra = math.radians(a)
    add("stone_lantern", math.sin(ra) * 20.5, math.cos(ra) * 20.5) if a % 60 else None
# Круг поединков: каменное кольцо-трибуна (две ступени-скамьи), проходы на север и юг
for a in range(0, 360, 12):
    if a % 180 in (0, 12, 168) or a in (348, 192):
        continue
    ra = math.radians(a)
    for rr, h in ((9.0, 0.5), (10.2, 1.0)):
        box([1.25, h, 2.0 * math.pi * rr / 30 + 0.1], round(math.sin(ra) * rr, 2), h / 2, round(math.cos(ra) * rr, 2),
            "stone_cut", r=a + 90)
for a in (0, 180):                                     # столбы у проходов
    ra = math.radians(a)
    for side in (-1, 1):
        add("tug_banner", math.sin(ra) * 10 + side * 1.6 * math.cos(ra), math.cos(ra) * 10 + side * 1.6 * math.sin(ra))
box([2, 1, 2], 0, 0.5, -16, "stone_dark")                     # тумба глашатая
add("@flame_tree", 14, -14, 30, s=1.8, rad=4)                  # Древо Клятв (заглушка)
add("ovoo_cairn", 12, -10)
add("well_square" if False else "trough", -14, 12, 45, c=True)
occupied.append((0, 0, 21))

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
        add("yurt_large" if big else "yurt_small", x, z, random.uniform(0, 360), c=True, rad=rad)
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

# маршруты мирных жителей (ломаные по улицам), сколько их
paths = [
    [[0, 80], [0, 50], [0, 24]],                                        # Тракт
    [[-1.5, 78], [-1.5, 30], [-8, 18], [-20, 2]],                       # Тракт → базар
    [[-74, 2], [-40, 2], [-22, 2]],                                     # Аллея, запад
    [[22, -2], [34, -6], [50, -2], [74, -2]],                           # Аллея, восток мимо фонтана
    [[44, 8], [36, 6], [26, 12], [14, 18], [2, 22]],                    # таверна → площадь
    [[-15, 15], [15, 15], [15, -15], [-15, -15], [-15, 15]],            # вокруг Круга
    [[0, -20], [0, -32]],                                               # к лестнице Ставки
    [[-60, 2], [-60, 26], [-42, 26], [-42, 2]],                         # по базару
    [[-30, 30], [-50, 44], [-70, 60], [-50, 74]],                       # западный квартал
    [[30, 30], [50, 46], [70, 62], [44, 74]],                           # восточный квартал
    [[-24, -10], [-34, -28], [-40, -54]],                               # к Счётному двору
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
]
data = {"_note": "Сгенерировано pax_rpg/dev/gharn/gharn_layout.py — правки вносить там.",
        "start": [0, 1.2, 74], "exit": [0, 86], "exit_radius": 5.0, "ground": [190, 186, 0, -6], "goblins": 0, "paths": paths, "npcs": npcs, "shots": shots,
        "items": items}
out = os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn.json")
json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(items), "объектов →", out)
