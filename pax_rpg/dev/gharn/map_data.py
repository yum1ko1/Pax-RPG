"""Данные карты города (M) для игры: районы (из ZONES чертежа plan_map.py) и значки мест (landmarks gharn.json).
Пишет mods/pax_rpg/config/gharn_map.json; city_map.gd рисует по нему районы, значки и легенду.
    python3 pax_rpg/dev/gharn/map_data.py"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from plan_map import ZONES  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
# ключ места → (иероглиф-значок, вид для легенды: gate/fight/trade/rest/craft/power/nature/beast/home/road)
GLYPH = {
    "gate": ("門", "gate"), "trakt": ("道", "road"), "circle": ("円", "road"), "khan": ("宮", "power"),
    "arena": ("闘", "fight"), "alley": ("桜", "road"), "fountain": ("泉", "nature"), "guild": ("会", "fight"),
    "tavern": ("酒", "rest"), "bazaar": ("市", "trade"), "barracks": ("兵", "fight"), "shamans": ("巫", "power"),
    "buffalo": ("牛", "beast"), "kurgans": ("墓", "power"), "garden": ("庭", "nature"), "kennels": ("犬", "beast"),
    "masters": ("匠", "craft"), "clans": ("族", "home"), "forge": ("鍛", "craft"), "stable": ("馬", "beast"),
    "goblins": ("鬼", "home"),
}
KIND_COL = {"gate": "#7cc8ff", "fight": "#ff3a4a", "trade": "#ffb547", "rest": "#ffd27a", "craft": "#e8916b",
            "power": "#c98cff", "nature": "#7fdca0", "beast": "#d9b98a", "home": "#e8dcc8", "road": "#ff8cc6"}
lay = json.load(open(os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn.json"), encoding="utf-8"))
pois = []
for key, x, z in lay["landmarks"]:
    g, kind = GLYPH.get(key.replace("pax_rpg_lm_", ""), ("・", "road"))
    pois.append({"key": key, "x": x, "z": z, "glyph": g, "kind": kind})
data = {"_note": "Сгенерировано pax_rpg/dev/gharn/map_data.py.",
        "zones": [{"r": [x0, z0, x1, z1], "name": n, "col": c} for x0, z0, x1, z1, n, c in ZONES],
        "pois": pois, "kinds": KIND_COL}
out = os.path.join(ROOT, "mods", "pax_rpg", "config", "gharn_map.json")
json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(out, len(pois), "pois", len(ZONES), "zones")
