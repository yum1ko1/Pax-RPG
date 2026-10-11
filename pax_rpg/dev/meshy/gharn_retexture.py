"""Текстуры уровня Meshy для простых моделей Гхарна (геометрия — наша из Blender): Meshy Retexture.
    python gharn_retexture.py [--only barrel_kumis,...]  → W\\gharn\\retex\\<id>\\model.glb
Состояние — W\\gharn\\retex\\state.json; очередь Meshy ждёт сама.
"""
import json, os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402

SRC = os.path.join(os.path.dirname(M.W), "gharn", "props")
OUT = os.path.join(os.path.dirname(M.W), "gharn", "retex")
STYLE = "East Asian fantasy orc horde city prop, realistic hand-painted PBR, weathered, worn, dirt in crevices. "
P = {
 "barrel_kumis": "dark oak barrel with black iron hoops, cracked leather lid tied with rope",
 "barrel_water": "old grey weathered wooden water barrel, rusty iron hoops, wet stains",
 "crate": "rough wooden crate, dark timber frame, light pine planks, scratches",
 "crate_saerith": "wooden crate with a gilded golden dragon medallion, red lacquer strip",
 "sack_grain": "coarse burlap grain sack tied with rope, patched",
 "basket": "woven wicker basket, straw, worn",
 "lantern_post": "dark timber lantern post with iron bracket, red paper lantern glowing, stone base",
 "stone_lantern": "crude grey granite stone lantern, moss, glowing warm light inside",
 "road_cobble": "uneven grey sandstone flagstones with earth and grass in joints, hoof marks",
 "road_dirt": "packed ochre earth road with cart ruts, straw and small stones",
 "boardwalk": "weathered wooden plank boardwalk, nails, mud",
 "wall_rubble": "rough rubble stone wall, mortar of clay, soot stains",
 "wall_hob": "neat cut grey stone block wall with carved numbers, iron plaque",
 "stairs_stone": "worn stone steps, chipped edges, earth",
 "palisade_segment": "sharpened dark log palisade, bark, rope lashing, stone base",
 "yurt_small": "grey felt yurt with patches, ropes, red painted wooden door",
 "yurt_large": "white felt noble yurt with red embroidered fang patterns, red lacquered door",
 "tug_banner": "wooden pole with black horsehair tails and iron spearhead",
 "banner_clan": "red cloth war banner with a single black curved fang emblem, wooden pole",
 "hitching_post": "weathered wooden hitching post with iron ring",
 "trough": "old wooden water trough with water",
 "bench_long": "worn wooden bench",
 "table_long": "heavy wooden tavern table with stains",
 "weapon_rack": "wooden weapon rack with iron spears",
 "training_dummy": "burlap training dummy on wooden pole, rope",
 "cauldron": "black iron cauldron on wooden tripod over campfire stones",
 "ovoo_cairn": "stacked stone cairn with colorful prayer ribbons",
 "mana_crystal": "glowing pink mana crystals on dark rock",
 "mana_flags_line": "rope line with glowing pink and colored prayer flags on poles",
 "stall_frame": "market stall, wooden counter, colorful cloth awning, goods",
 "quest_board": "wooden notice board with pinned paper notes and daggers, small roof",
 "lantern_string": "rope with red paper lanterns between wooden poles",
 "cart": "old two-wheeled wooden steppe cart, iron-rimmed spoked wheels, burlap sacks in the bed, mud on wheels",
 "fence_wood": "woven wattle fence of thin branches between rough stakes, bark, dry",
 "hay_bale": "rectangular bale of golden dry hay tied with twine",
 "wood_pile": "stacked split firewood logs between two posts, bark and pale cut ends",
 "firepit": "campfire ring of blackened stones, charred logs, glowing embers and flames, ash",
 "awning": "market awning of faded red and cream striped canvas on four wooden poles",
 "rock_small": "weathered grey steppe boulders with lichen and dirt",
 "bush_dry": "dry steppe shrub, thin twisted brown branches, sparse olive leaves",
}

def main():
    os.makedirs(OUT, exist_ok=True)
    a = sys.argv[1:]
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else set(P)
    sf = os.path.join(OUT, "state.json")
    st = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    t0 = time.time()
    while time.time() - t0 < 5400:
        busy = False
        for k, desc in P.items():
            if k not in only:
                continue
            s = st.setdefault(k, {"stage": "new"})
            if s["stage"] == "new":
                try:
                    r = M.call("POST", M.ep("retexture"), {"model_url": M.data_uri(os.path.join(SRC, k + ".glb")),
                               "text_style_prompt": STYLE + desc, "enable_pbr": True, "enable_original_uv": False})
                    s.update(stage="run", id=r.get("result")); print(k, "→", s["id"], flush=True)
                except SystemExit as e:
                    print(k, "очередь:", str(e)[:60], flush=True)
            elif s["stage"] == "run":
                r = M.call("GET", f"{M.ep('retexture')}/{s['id']}")
                if r.get("status") == "SUCCEEDED":
                    d = os.path.join(OUT, k); os.makedirs(d, exist_ok=True)
                    urllib.request.urlretrieve(r["model_urls"]["glb"], os.path.join(d, "model.glb"))
                    s["stage"] = "done"; print(k, "готово", flush=True)
                elif r.get("status") in ("FAILED", "CANCELED", "EXPIRED"):
                    s.update(stage="failed", error=str(r.get("task_error"))); print(k, "ошибка", s["error"], flush=True)
            if s["stage"] not in ("done", "failed"):
                busy = True
            json.dump(st, open(sf, "w", encoding="utf-8"), indent=1)
        if not busy:
            break
        time.sleep(10)
    print("итог:", {k: v["stage"] for k, v in st.items()})

if __name__ == "__main__":
    main()
