"""Ключевые модели Гхарна через Meshy: Text to Image (объект отдельно, белый фон, вид 3/4) → Image to 3D (PBR).
Список и размеры — заметка «Гхарн — ассеты» (Obsidian). Стиль — как в концепт-арте.

    python gharn_assets.py [--only guild_hall,tavern_hall]   → W\\gharn\\<id>\\{ref.png, model.glb}
Состояние — W\\gharn\\state.json: перезапуск продолжает, не платит дважды; очередь Meshy (≤ 10) ждёт сама.
"""
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402

OUT = os.path.join(os.path.dirname(M.W), "gharn")
STYLE = ("East Asian fantasy orc horde capital architecture, heavy rough orc-built: dark timber logs on rough "
         "rubble-stone plinths, curved upturned East Asian roofs with dark tiles, red lacquered pillars with peeling "
         "paint, black iron bands and rivets, bone and tusk ornaments, red cloth banners with a single curved black "
         "fang emblem (original, not any existing logo). Stylized realism game asset. ")
ISO = (" Single isolated object, full object visible, three-quarter view from slightly above, plain white background, "
       "soft even studio light, no people, no surrounding buildings, no ground clutter, no text.")
ASSETS = {
    # id: (описание, полигоны)
    "guild_hall": ("Adventurers' guild hall: a fortified former caravanserai, massive square stone ground floor with an "
                   "arched gate, two upper floors of dark timber with red-railed wooden galleries, tiered curved roof, "
                   "an emblem of a crossed sword and fang hanging on iron chains above the gate, a wooden quest board "
                   "with pinned papers beside the gate.", 40000),
    "tavern_hall": ("Huge round timber tavern shaped like a giant yurt grown into a stone base, two-tier conical wooden "
                    "roof with a smoke lantern on top, red lacquered door frame with a beast skull above it, wide stone "
                    "stairs, an open terrace with a canopy and long wooden tables, stacked barrels by the wall.", 35000),
    "fountain_dragon": ("Octagonal rough stone fountain basin with copper plaques, in the center a stone pedestal holding "
                        "a looted gilded golden dragon head from an enemy temple, mouth open, elegant scales, contrasting "
                        "the crude stonework; the basin holds pink glowing water.", 25000),
    "gate_fang": ("City gate: two square timber watch towers on stone bases with curved roofs, joined by a gatehouse "
                  "with a tiered roof over a wide passage, massive wooden doors with iron bands and spikes, a giant "
                  "curved beast tusk mounted above the passage wrapped in red ribbons, red banners on the towers.", 35000),
    "khan_palace": ("Palace of the Great Khan: an enormous ceremonial yurt with three tiered roofs of white felt, red "
                    "lacquer and gold plates, a nine-tail horsetail standard on top, on a low stone platform with "
                    "wide stairs, red pillared porch.", 40000),
    "flame_tree": ("Flame tree (royal poinciana): an umbrella-shaped tree with a broad flat crown of scarlet red blossoms "
                   "and fine green leaves, a twisted dark trunk, standing in a small square stone planter.", 12000),
    "house_shop_a": ("Two-storey orc shop house: rough stone ground floor with an open wooden shopfront and awning, upper "
                     "floor of dark timber with a red balcony, curved tiled roof, hanging paper lanterns, barrels and "
                     "crates at the entrance, a horsetail standard by the door.", 15000),
    "house_shop_b": ("Narrow two-storey orc butcher and leatherworker house: stone plinth, timber upper floor with "
                     "stretched hides drying on a frame, meat hooks under a canopy, curved roof with a beast skull at "
                     "the ridge end, red door.", 15000),
    "house_shop_c": ("Wide orc smithy house: stone ground floor with a big open forge bay and anvil, chimney, timber "
                     "loft with red shutters, curved tiled roof, weapons on racks under an awning.", 15000),
}


def load():
    f = os.path.join(OUT, "state.json")
    return json.load(open(f, encoding="utf-8")) if os.path.exists(f) else {}


def save(st):
    json.dump(st, open(os.path.join(OUT, "state.json"), "w", encoding="utf-8"), indent=1)


def try_post(endpoint, body):
    try:
        return M.call("POST", M.ep(endpoint), body).get("result")
    except SystemExit as e:                       # 429 — очередь полна
        print("  очередь:", str(e)[:70], flush=True)
        return None


def main():
    os.makedirs(OUT, exist_ok=True)
    a = sys.argv[1:]
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else set(ASSETS)
    st = load()
    t0 = time.time()
    while time.time() - t0 < 3600:
        busy = False
        for k, (desc, poly) in ASSETS.items():
            if k not in only:
                continue
            s = st.setdefault(k, {"stage": "new"})
            d = os.path.join(OUT, k)
            os.makedirs(d, exist_ok=True)
            if s["stage"] == "new":
                tid = try_post("text-to-image", {"ai_model": "nano-banana-pro", "prompt": STYLE + desc + ISO,
                                                 "aspect_ratio": "1:1"})
                if tid:
                    s.update(stage="image", image_task=tid)
                    print(k, "картинка →", tid, flush=True)
            elif s["stage"] == "image":
                r = M.call("GET", f"{M.ep('text-to-image')}/{s['image_task']}")
                if r.get("status") == "SUCCEEDED":
                    url = (r.get("image_urls") or [""])[0]
                    urllib.request.urlretrieve(url, os.path.join(d, "ref.png"))
                    s.update(stage="image_done", image_url=url)
                    print(k, "картинка готова", flush=True)
                elif r.get("status") in ("FAILED", "CANCELED", "EXPIRED"):
                    s.update(stage="failed", error=str(r.get("task_error")))
            elif s["stage"] == "image_done":
                tid = try_post("image-to-3d", {"image_url": s["image_url"], "ai_model": "latest", "should_texture": True,
                                               "enable_pbr": True, "should_remesh": True, "target_polycount": poly,
                                               "topology": "triangle"})
                if tid:
                    s.update(stage="model", model_task=tid)
                    print(k, "модель →", tid, flush=True)
            elif s["stage"] == "model":
                r = M.call("GET", f"{M.ep('image-to-3d')}/{s['model_task']}")
                if r.get("status") == "SUCCEEDED":
                    urllib.request.urlretrieve(r["model_urls"]["glb"], os.path.join(d, "model.glb"))
                    if r.get("thumbnail_url"):
                        urllib.request.urlretrieve(r["thumbnail_url"], os.path.join(d, "thumb.png"))
                    s.update(stage="done")
                    print(k, "модель готова", flush=True)
                elif r.get("status") in ("FAILED", "CANCELED", "EXPIRED"):
                    s.update(stage="failed", error=str(r.get("task_error")))
                    print(k, "ошибка", s["error"], flush=True)
            if s["stage"] not in ("done", "failed"):
                busy = True
            save(st)
        if not busy:
            break
        time.sleep(10)
    print("итог:", {k: v["stage"] for k, v in st.items()})


if __name__ == "__main__":
    main()
