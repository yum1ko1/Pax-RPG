"""CC0-текстуры Poly Haven (4K: цвет, нормали GL, шероховатость, AO) для арены центра Гхарна (arena_central.py).
    python pbr_fetch.py <папка>"""
import json, os, sys, urllib.request

NAMES = ["monastery_stone_floor", "old_mosaic_floor", "stone_block_wall", "castle_wall_slates", "marble_01",
         "lacquered_cherry_wood", "roof_tiles_14", "patterned_paving"]
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
for t in NAMES:
    d = json.loads(urllib.request.urlopen(f"https://api.polyhaven.com/files/{t}").read())
    for k, s in {"Diffuse": "diff", "nor_gl": "nor", "Rough": "rough", "AO": "ao"}.items():
        if k in d and "4k" in d[k]:
            fmt = "jpg" if "jpg" in d[k]["4k"] else "png"
            out = os.path.join(OUT, f"{t}_{s}.{fmt}")
            if not os.path.exists(out):
                urllib.request.urlretrieve(d[k]["4k"][fmt]["url"], out)
    print(t, "ok")
