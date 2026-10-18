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
# не здания (деревья, фонтаны, статуи): без архитектурного блока — иначе генератор пририсует дом
STYLE_PROP = ("East Asian fantasy, orc horde capital city prop, stylized realism game asset, weathered and heavy. ")
PROPS = {"flame_tree", "fountain_dragon"}
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
    "fountain_dragon": ("Only a fountain, no buildings, no walls, no roofs behind it: an octagonal rough stone fountain basin with copper plaques, in the center a stone pedestal holding "
                        "a looted gilded golden dragon head from an enemy temple, mouth open, elegant scales, contrasting "
                        "the crude stonework; the basin holds pink glowing water.", 25000),
    "gate_fang": ("City gate: two square timber watch towers on stone bases with curved roofs, joined by a gatehouse "
                  "with a tiered roof over a wide passage, massive wooden doors with iron bands and spikes, a giant "
                  "curved beast tusk mounted above the passage wrapped in red ribbons, red banners on the towers.", 35000),
    "khan_palace": ("Palace of the Great Khan: an enormous ceremonial yurt with three tiered roofs of white felt, red "
                    "lacquer and gold plates, a nine-tail horsetail standard on top, on a low stone platform with "
                    "wide stairs, red pillared porch.", 40000),
    "flame_tree": ("Only a single tree, no buildings, no walls: a flame tree (royal poinciana): an umbrella-shaped tree with a broad flat crown of scarlet red blossoms "
                   "and fine green leaves, a twisted dark trunk, standing in a small square stone planter.", 12000),
    "house_shop_a": ("Two-storey orc shop house: rough stone ground floor with an open wooden shopfront and awning, upper "
                     "floor of dark timber with a red balcony, curved tiled roof, hanging paper lanterns, barrels and "
                     "crates at the entrance, a horsetail standard by the door.", 15000),
    "house_shop_b": ("Narrow two-storey orc butcher and leatherworker house: stone plinth, timber upper floor with "
                     "stretched hides drying on a frame, meat hooks under a canopy, curved roof with a beast skull at "
                     "the ridge end, red door.", 15000),
    "house_shop_c": ("Wide orc smithy house: stone ground floor with a big open forge bay and anvil, chimney, timber "
                     "loft with red shutters, curved tiled roof, weapons on racks under an awning.", 15000),
    # --- версия 3: облик Орды по референсам (кость, клыки, шкуры, рваные алые знамёна) поверх азиатской крыши
    "shaman_tower": ("Goblin shaman tower: a tall leaning tower of dark logs and patched hides on a rubble base, "
                     "crooked balconies, a small curved roof on top crowned with a beast skull and long horns, ropes "
                     "with colorful cloth mana flags and dangling charms, a glowing pink crystal in a cage at the top.", 25000),
    "forge_smithy": ("Orc forge: an open stone smithy with a huge rubble-stone chimney and a glowing furnace mouth, "
                     "a thatched and hide roof on log posts with giant curved tusks at the corners, an anvil on a stump, "
                     "a quenching barrel, racks of axes and spears, tattered red banner on a pole.", 20000),
    "watch_tower": ("Orc wooden watchtower: tall log tower on four slanted legs braced with ropes, a covered lookout "
                    "platform with a small curved roof, sharpened stakes and tusks around the platform, a ladder, hides "
                    "and a torn red banner hanging down.", 12000),
    "yurt_noble": ("Large clan chieftain yurt: round felt walls in cream and red, a red conical roof with curved "
                   "horns at the edge and a big horned beast skull above the wooden door, a wooden porch with two spears "
                   "and a round clan shield, ropes and horsetail tassels.", 12000),
    "stilt_hut": ("Goblin stilt hut: a round woven wicker hut with a red cloth roof and horns on top, raised on wooden "
                  "stilts, a rickety ladder, a wooden platform with railings, strings of small skulls and red rags, "
                  "clay pots below.", 10000),
    "stable_hay": ("Orc horse stable: a long open shed with a thick hay roof on rough log posts, wooden stalls with "
                   "half doors, hay bales, saddles and bridles hanging on pegs, a water trough in front.", 14000),
    "oath_tree": ("Only a single giant tree, no buildings: an ancient banyan tree with many aerial roots and a wide "
                  "crown, hundreds of red and white cloth ribbons tied to its branches, small iron bells, a ring of "
                  "rough stones around the trunk.", 25000),
    "house_timber_a": ("Orc dwelling house: one and a half storeys, rough rubble-stone plinth, dark log walls, a "
                       "steep curved roof with a horn ornament, small shuttered windows, a red door, firewood stacked "
                       "under the eaves, a hide stretched on the wall.", 12000),
    "house_timber_b": ("Orc family house with a courtyard wall: low stone walls, timber upper part with a red wooden "
                       "gallery, curved tiled roof with a skull at the ridge, laundry rope with cloth, clay jars by the door.", 12000),
    "house_two_a": ("Two-storey capital townhouse of an orc clan, narrow and tall: rubble-stone ground floor with a "
                    "workshop opening and a red door, upper floor of dark timber with a red-railed wooden balcony, "
                    "paper lanterns hanging under the eaves, a steep two-tier curved roof with horn ornaments.", 12000),
    "house_two_b": ("Wide two-storey merchant house of the orc capital: stone ground floor with a shop counter and "
                    "cloth awning, timber upper floor with lattice windows and a gallery, a corner tower-like bay, "
                    "curved tiled roof with a bone ridge ornament, red banners with a fang emblem.", 12000),
    # --- версия 4: дома аллеи у входа — двухэтажные, с нависающими балконами над улицей (левел-дизайн входа)
    "house_bal_a": ("Narrow tall two-storey townhouse of the orc capital facing a street: solid rubble-stone ground "
                    "floor with a wide shop opening and red noren cloth curtains over the door, a deep overhanging "
                    "upper floor of dark timber on carved brackets with a long red-railed wooden balcony running the "
                    "whole facade, lattice windows, paper lanterns under the eaves, steep curved tiled roof with "
                    "upturned corners and a horn ridge ornament, all walls solid and closed.", 60000),
    "house_bal_b": ("Two-storey corner tea house of the orc capital: stone plinth, ground floor with sliding wooden "
                    "screens and a narrow veranda, upper floor of dark timber with a wrap-around balcony on two sides "
                    "with red railings, a hanging wooden signboard on an iron bracket, round red lanterns, two-tier "
                    "curved roof with dark tiles and gold ridge tips, all walls solid and closed.", 60000),
    "house_bal_c": ("Three-storey narrow merchant house of the orc capital squeezed into a street: rubble-stone ground "
                    "floor with an open stall counter under a hide awning, two upper floors of dark timber stepping "
                    "outward over the street, a small enclosed bay balcony on the second floor, drying cloth on a pole, "
                    "steep curved roof with a beast skull at the gable, all walls solid and closed.", 60000),
    "totem_pole": ("A tall carved wooden totem pole with three stacked snarling orc faces painted red and black, a "
                   "horned skull at the top, tusks sticking out, red ribbons and feathers tied around it.", 4000),
    "bone_banner": ("War standard: a wooden pole with a crossbar, a horned ram skull on top, a long torn dark-red banner "
                    "with a pale fang symbol, curved tusks bound with rope around the base of piled stones, hanging chains.", 4000),
    "guardian_statue": ("A rough carved stone statue of a sitting great wolf guardian on a square plinth, red cloth "
                        "scarf around its neck, weathered and mossy.", 6000),
    "loot_pile": ("A pile of war loot: golden temple bowls, jade figurines, a cracked golden dragon mask, coins, an "
                  "ornate chest and silk, heaped on a hide rug.", 5000),
    "war_drum": ("A huge orc war drum: a wooden barrel drum with stretched hide, laced with rope, on a wooden frame "
                 "with tusks, two heavy bone drumsticks.", 4000),
    "beast_cage": ("A heavy wooden beast cage with iron bands on wooden wheels, thick bars, a chained door, straw "
                   "inside, a bone hanging from the top.", 4000),
    "spit_roast": ("Campfire with a roasting spit: a whole beast leg on an iron spit over glowing coals, wooden "
                   "forked posts, a ring of stones, a cauldron beside it.", 3000),
    "hay_wagon": ("A rough orc hay wagon: big wooden wheels with iron rims, loaded with hay and sacks, a tarp tied with "
                  "ropes, a horn charm on the front.", 5000),
    "tusk_arch": ("Two giant curved beast tusks planted in the ground crossing above to form an arch, bound together "
                  "with rope and red cloth at the top, a hanging skull charm, stone base.", 3000),
    "brazier_tusk": ("A large iron fire brazier on three legs with curved tusks rising around the bowl, glowing coals "
                     "inside, a ring of rough stones at the base.", 3000),
    "spear_rack": ("A wooden weapon rack with orc spears, axes and round hide shields, a horned skull on top, rope lashings.", 3000),
    "market_stall_hide": ("A market stall: log frame with a patched hide awning, a plank counter with clay jars, "
                          "baskets of fruit and dried fish, hanging meat and garlic, a small paper lantern.", 5000),
    "mana_totem": ("A goblin shaman mana totem: a tripod of bound wooden poles holding a large glowing pink crystal "
                   "wrapped in cloth strips, colorful rag flags and bone charms hanging on strings.", 4000),
    "hide_frame": ("A wooden frame of crossed poles with a large beast hide stretched by ropes for drying, a scraping "
                   "knife and bucket beside it.", 2500),
    "bucket_set": ("A small group of household items: two wooden buckets with rope handles, a woven wicker basket "
                   "with vegetables, a clay water jar.", 2000),
}
PROPS |= {"oath_tree", "totem_pole", "bone_banner", "guardian_statue", "loot_pile", "war_drum", "beast_cage",
          "spit_roast", "hay_wagon", "tusk_arch", "brazier_tusk", "spear_rack", "market_stall_hide", "mana_totem",
          "hide_frame", "bucket_set"}


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
                tid = try_post("text-to-image", {"ai_model": "nano-banana-pro", "prompt": (STYLE_PROP if k in PROPS else STYLE) + desc + ISO,
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
