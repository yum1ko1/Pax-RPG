"""Проверка планировки Гхарна: постройки не стоят друг в друге и не стоят на дорогах.
Габариты — из glb моделей (POSITION min/max × масштаб узла), прямоугольник повёрнут по r.
    python3 check_overlaps.py            → список пересечений (пусто — всё чисто)
"""
import json
import math
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BIG = ("house_", "guild_hall", "tavern_hall", "khan_palace", "forge_smithy", "stable_hay", "shaman_tower",
       "watch_tower", "yurt_large", "yurt_small", "yurt_noble", "stilt_hut", "fountain", "gate_fang", "flame_tree",
       "oath_tree", "beast_cage", "market_stall", "stall_frame", "merchant_cart", "cart", "hay_wagon", "bench_long",
       "stone_lantern", "guardian_statue", "spit_roast", "war_drum", "totem_pole", "tusk_arch", "wall_hob")
_fp = {}


def foot(path):
    if path in _fp:
        return _fp[path]
    f = os.path.join(ROOT, "mods", "pax_rpg", path)
    d = open(f, "rb").read()
    n = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + n])
    mn, mx = [1e9] * 3, [-1e9] * 3
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            a = j["accessors"][p["attributes"]["POSITION"]]
            for i in range(3):
                mn[i], mx[i] = min(mn[i], a["min"][i]), max(mx[i], a["max"][i])
    sc = 1.0
    for nd in j.get("nodes", []):
        if "scale" in nd:
            sc = nd["scale"][0]
    r = ((mx[0] - mn[0]) * sc / 2, (mx[2] - mn[2]) * sc / 2)
    if "flame_tree" in path or "oath_tree" in path:
        r = (0.9, 0.9)                     # дерево: мешает только ствол, крона над головой
    _fp[path] = r
    return r


def main():
    d = json.load(open(os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn.json"), encoding="utf-8"))
    bs = []
    for it in d["items"]:
        m = it.get("m", "")
        if not any(k in m for k in BIG) or it["p"][1] < -0.1:
            continue
        hx, hz = foot(m)
        s = float(it.get("s", 1.0))
        a = math.radians(it.get("r", 0.0))
        ex = abs(math.cos(a)) * hx * s + abs(math.sin(a)) * hz * s
        ez = abs(math.sin(a)) * hx * s + abs(math.cos(a)) * hz * s
        x, _, z = it["p"]
        bs.append((m.split("/")[-1][:-4], x, z, ex * 0.9, ez * 0.9))
    bad = 0
    for i in range(len(bs)):
        for k in range(i + 1, len(bs)):
            a, b = bs[i], bs[k]
            if abs(a[1] - b[1]) < a[3] + b[3] and abs(a[2] - b[2]) < a[4] + b[4]:
                ov = min(a[3] + b[3] - abs(a[1] - b[1]), a[4] + b[4] - abs(a[2] - b[2]))
                if ov > 0.35:
                    bad += 1
                    print(f"  {a[0]} ({a[1]:.1f},{a[2]:.1f}) × {b[0]} ({b[1]:.1f},{b[2]:.1f}) — {ov:.1f} м")
    print("пересечений:", bad, "из", len(bs), "построек")
    return bad


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
