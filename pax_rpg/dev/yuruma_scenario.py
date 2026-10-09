"""Сценарий «Юрума» для игры: пресет мира и своя карта провинций.

    python pax_rpg/dev/yuruma_scenario.py

Берёт:
    pax_rpg/scenario/yuruma.json              — текст сценария: империи, вожди, лор, год, календарь (правится руками)
    pax_rpg/reference/yuruma/yuruma_regions.png    — провинции цветами (pax_rpg/dev/yuruma_planet.py)
    pax_rpg/reference/yuruma/yuruma_provinces.json — цвет провинции → империя (тот же генератор)
    mods/pax_rpg/config/cities.json           — столицы (те же точки, что значки на глобусе)
Пишет:
    mods/pax_rpg/data/regions2.json, regions2.bin, regions2_grow.bin — карта провинций Юрумы вместо земной
        (тот же разбор, что «карта из картинки» игры — ImageMap.gd: номера по первому появлению цвета)
    mods/pax_rpg/presets/Юрума/meta.json, Земля.png (земли империй), обложка.jpg — пресет мира
"""
import gzip
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "pax_rpg/scenario/yuruma.json"
REF = ROOT / "pax_rpg/reference/yuruma"
MOD = ROOT / "mods/pax_rpg"
EARTH_RADIUS_KM = 6371.0          # как в игре (ImageMap.gd): площади провинций — в км² шара этого радиуса
SLICING = 2                        # data/regions2 — «нарезка 2», ключ пресета «провинции_зон_2»


def text(v):
    """Длинные тексты в источнике — списками строк."""
    if isinstance(v, list):
        return "\n".join(v)
    if isinstance(v, dict):
        return {k: text(x) for k, x in v.items()}
    return v


def hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- карта провинций (порт ImageMap.gd)

def province_map(png: Path):
    img = np.asarray(Image.open(png).convert("RGBA"))
    v, sh = img.shape[:2]
    assert sh == v * 2 and 256 <= v and sh <= 8192, "картинка должна быть 2:1"
    rgb = img[..., :3].astype(np.int64)
    key = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
    land = (img[..., 3] >= 128) & (key != 0)
    flat_key = key.ravel()
    flat_land = land.ravel()
    keys, first = np.unique(flat_key[flat_land], return_index=True)
    order = np.argsort(first)                                   # номер — по первому появлению цвета
    id_of = {int(keys[i]): n + 1 for n, i in enumerate(order)}
    colors = [""] + ["%06x" % int(keys[i]) for i in order]
    lut_keys = np.array(sorted(id_of), dtype=np.int64)
    lut_ids = np.array([id_of[k] for k in lut_keys], dtype=np.int32)
    m = np.zeros(sh * v, dtype=np.int32)
    m[flat_land] = lut_ids[np.searchsorted(lut_keys, flat_key[flat_land])]
    amount = np.bincount(m, minlength=len(colors))
    threshold = max(6, sh * v // 250000)
    small = [i for i in range(1, len(colors)) if amount[i] < threshold]
    assert not small, f"мелкие провинции {small}: игра слила бы их с соседями — поправь картинку"
    return m.reshape(v, sh), colors


def regions_data(m: np.ndarray, colors: list, names: dict, country: dict):
    v, sh = m.shape
    n = len(colors) - 1
    lat = np.radians(90.0 - (np.arange(v) + 0.5) * 180.0 / v)
    lon = np.radians((np.arange(sh) + 0.5) * 360.0 / sh - 180.0)
    cos_lat = np.cos(lat)[:, None] * np.ones((1, sh))
    pixel_km2 = (2 * math.pi * EARTH_RADIUS_KM / sh) * (math.pi * EARTH_RADIUS_KM / v)
    ids = m.ravel()
    on = ids > 0
    w = cos_lat.ravel()
    area = np.bincount(ids[on], weights=pixel_km2 * w[on], minlength=n + 1)
    cx = np.bincount(ids[on], weights=(cos_lat * np.cos(lon)[None, :]).ravel()[on], minlength=n + 1)
    cy = np.bincount(ids[on], weights=(cos_lat * np.sin(lon)[None, :]).ravel()[on], minlength=n + 1)
    cz = np.bincount(ids[on], weights=(np.sin(lat)[:, None] * np.ones((1, sh))).ravel()[on], minlength=n + 1)
    d = np.sqrt(cx * cx + cy * cy + cz * cz)
    d[d == 0] = 1
    lat_c = np.degrees(np.arcsin(np.clip(cz / d, -1, 1)))
    lon_c = np.degrees(np.arctan2(cy, cx))

    # берег и соседи — как в игре: справа (по кругу), снизу; слева и сверху — только берег
    right = np.roll(m, -1, axis=1)
    below = np.vstack([m[1:], m[-1:]])                         # последняя строка: «снизу» — она сама
    left = np.roll(m, 1, axis=1)
    left[:, 0] = 1                                              # x = 0: слева не смотрим
    above = np.vstack([np.ones((1, sh), dtype=m.dtype), m[:-1]])
    coast = np.zeros(n + 1, dtype=bool)
    for nb in (right, below, left, above):
        hit = (m > 0) & (nb == 0)
        coast[np.unique(m[hit])] = True
    pairs = set()
    for nb in (right, below):
        hit = (m > 0) & (nb > 0) & (nb != m)
        for a, b in zip(m[hit].tolist(), nb[hit].tolist()):
            pairs.add((a, b) if a < b else (b, a))
    neigh = {i: set() for i in range(1, n + 1)}
    for a, b in pairs:
        neigh[a].add(b)
        neigh[b].add(a)

    # подпись — пиксель провинции, ближайший к её центру
    tx = (lon_c + 180.0) / 360.0 * sh
    ty = (90.0 - lat_c) / 180.0 * v
    yy, xx = np.nonzero(m)
    pid = m[yy, xx]
    dx = np.abs(xx - tx[pid])
    dx = np.minimum(dx, sh - dx)
    d2 = dx * dx + (yy - ty[pid]) ** 2
    best = np.lexsort((d2, pid))                                # по провинции, внутри — по расстоянию
    first = np.ones(len(best), dtype=bool)
    first[1:] = pid[best][1:] != pid[best][:-1]
    caption = np.zeros((n + 1, 2), dtype=np.int64)
    caption[pid[best][first]] = np.stack([xx[best][first], yy[best][first]], axis=1)

    # очередь роста (как _growth_queue): полразмера, доля пути от подписи до края провинции
    sh2, v2 = sh // 2, v // 2
    half = m[0::2, 0::2][:v2, :sh2]
    hy, hx = np.nonzero(half)
    hid = half[hy, hx]
    ddx = np.abs(hx * 2 - caption[hid, 0])
    ddx = np.minimum(ddx, sh - ddx)
    far = np.sqrt(ddx * ddx + (hy * 2 - caption[hid, 1]) ** 2).astype(np.float32)
    mx = np.zeros(n + 1, dtype=np.float32)
    np.maximum.at(mx, hid, far)
    queue = np.zeros((v2, sh2), dtype=np.uint8)
    queue[hy, hx] = np.clip(far / np.maximum(mx[hid], 0.001) * 255.0, 0, 255).astype(np.uint8)

    regions = []
    for i in range(1, n + 1):
        regions.append({"id": i, "names": names[i], "country": country.get(i, ""), "colour": "#" + colors[i],
                        "slicing": SLICING, "area": int(round(area[i])),
                        "ш": round(float(lat_c[i]), 2), "д": round(float(lon_c[i]), 2),
                        "caption": [int(caption[i, 0]), int(caption[i, 1])],
                        "coast": bool(coast[i]), "on_water": bool(coast[i]), "neighbours": sorted(neigh[i])})
    meta = {"_manner_this_works": "Сделано из pax_rpg/reference/yuruma/yuruma_regions.png (pax_rpg/dev/yuruma_scenario.py,"
                                  " тот же разбор, что КартаИзКартинки.gd). Цвет провинции — поле «colour».",
            "width": sh, "height": v, "queue_width": sh2, "queue_height": v2, "regions": regions}
    return meta, queue, lat_c, lon_c


def write_regions(m: np.ndarray, meta: dict, queue: np.ndarray):
    out = MOD / "data"
    out.mkdir(parents=True, exist_ok=True)
    (out / "regions2.json").write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (out / "regions2.bin").write_bytes(gzip.compress(m.astype("<u2").tobytes(), mtime=0))
    (out / "regions2_grow.bin").write_bytes(gzip.compress(queue.tobytes(), mtime=0))


# ---------------------------------------------------------------- имена провинций

# слоги по культурам империй (азиатское фэнтези: Престол — Китай, Хаддур — Корея, Гхарн — степь,
# Саэрит — Индокитай, Цветение — Япония)
CULTURES = {
    "престол": (["Лань", "Шэн", "Юй", "Цзинь", "Мэй", "Хуа", "Лин", "Сюэ", "Тянь", "Бай", "Цин", "Ло", "Жун", "Вэнь"],
                ["чжоу", "шань", "хэ", "лин", "ань", "фэн", "цюань", "тай", "ся", "юань"],
                ["Lan", "Sheng", "Yu", "Jin", "Mei", "Hua", "Ling", "Xue", "Tian", "Bai", "Qing", "Luo", "Rong", "Wen"],
                ["zhou", "shan", "he", "ling", "an", "feng", "quan", "tai", "xia", "yuan"]),
    "хаддур": (["Хан", "Сон", "Дол", "Пак", "Гым", "Чон", "Баэк", "Мун", "Каль", "Тор", "Ыль", "Сок"],
               ["-дон", "-сан", "-гаре", "-рим", "-холь", "-бонг", "-дан", "-гок"],
               ["Han", "Son", "Dol", "Pak", "Geum", "Jeon", "Baek", "Mun", "Kal", "Tor", "Eul", "Sok"],
               ["-dong", "-san", "-gare", "-rim", "-hol", "-bong", "-dan", "-gok"]),
    "гхарн": (["Гхар", "Бат", "Ург", "Мун", "Тэм", "Хаан", "Дзу", "Орх", "Гур", "Шаг", "Кхул", "Нар"],
              ["-тал", "-ул", "-гол", "-хот", "-дуг", "-ар", "-баг", "-зур"],
              ["Ghar", "Bat", "Urg", "Mun", "Tem", "Khaan", "Dzu", "Orkh", "Gur", "Shag", "Khul", "Nar"],
              ["-tal", "-ul", "-gol", "-khot", "-dug", "-ar", "-bag", "-zur"]),
    "саэрит": (["Сае", "Анг", "Тха", "Вай", "Кор", "Пра", "Сур", "Лао", "Нгу", "Рат", "Сим", "Ваэт"],
               ["-рит", "-пур", "-тхам", "-ван", "-нга", "-кор", "-лай", "-сар"],
               ["Sae", "Ang", "Tha", "Vai", "Kor", "Pra", "Sur", "Lao", "Ngu", "Rat", "Sim", "Vaet"],
               ["-rith", "-pur", "-tham", "-van", "-nga", "-kor", "-lai", "-sar"]),
    "цветение": (["Са", "Ку", "Ми", "Ё", "Хи", "Ки", "Цу", "Ру", "Ха", "Ая", "Ока", "Сида"],
                 ["кура", "сато", "но", "сима", "мори", "кава", "ми", "юки", "дзава", "ми"],
                 ["Sa", "Ku", "Mi", "Yo", "Hi", "Ki", "Tsu", "Ru", "Ha", "Aya", "Oka", "Shida"],
                 ["kura", "sato", "no", "shima", "mori", "kawa", "mi", "yuki", "zawa", "mi"]),
}


def province_names(owner: dict, culture_of: dict, seed: int = 47):
    rng = random.Random(seed)
    used = set()
    names = {}
    for i in sorted(owner):
        a_ru, b_ru, a_en, b_en = CULTURES[culture_of[owner[i]]]
        for _ in range(200):
            ia, ib = rng.randrange(len(a_ru)), rng.randrange(len(b_ru))
            ru, en = a_ru[ia] + b_ru[ib], a_en[ia] + b_en[ib]
            if ru not in used:
                break
        used.add(ru)
        names[i] = {"ru": ru.replace("--", "-"), "en": en}
    return names


# ---------------------------------------------------------------- пресет

def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def zones_image(m: np.ndarray, owner: dict, color_of: dict) -> Image.Image:
    v, sh = m.shape
    lut = np.zeros((m.max() + 1, 4), dtype=np.uint8)
    for i, fac in owner.items():
        lut[i] = (*color_of[fac], 255)
    img = Image.fromarray(lut[m])
    return img.resize((1024, 512), Image.NEAREST)


def cover(src: dict, title_year: str) -> Image.Image:
    W, H = 1600, 900
    img = Image.new("RGB", (W, H), "#06051a")
    g = 640
    mask = Image.new("L", (g, g), 0)
    ImageDraw.Draw(mask).ellipse((g * 0.04, g * 0.04, g * 0.96, g * 0.96), fill=255)   # глобус без квадрата фона
    for k, name in enumerate(("lunniel", "sherraks", "vellamir")):                     # ближний — последним
        p = REF / f"yuruma_globe_{name}.png"
        if p.exists():
            gl = Image.open(p).convert("RGB").resize((g, g), Image.LANCZOS)
            img.paste(gl, (40 + k * 470, 230 + (k % 2) * 30), mask)
    d = ImageDraw.Draw(img)
    d.text((60, 50), src["имя"].upper(), font=font(84), fill="#ffd9f3")
    d.text((64, 150), title_year, font=font(34), fill="#c9b6ff")
    return img


def main():
    src = json.loads(SRC.read_text(encoding="utf-8"))
    table = json.loads((REF / "yuruma_provinces.json").read_text(encoding="utf-8"))
    cities = {c["id"]: c for c in json.loads((MOD / "config/cities.json").read_text(encoding="utf-8"))["cities"]}
    empire_of_color = {t["color"].lstrip("#"): t["empire"] for t in table}
    factions = src["фракции"]
    color_of = {}
    hues = {"Лазурный Престол": "#3d8bff", "Пиковый Доминион Хаддур": "#9a8cff", "Орда Гхарн": "#ff5a6a",
            "Империум Саэрит": "#ffb347", "Двор Вечного Цветения": "#ff7fd0"}   # как EMPIRES генератора
    for f in factions:
        color_of[f["имя"]] = hex_rgb(hues[f["имя"]])
    culture_of = {f["имя"]: f["культура"] for f in factions}

    m, colors = province_map(REF / "yuruma_regions.png")
    owner = {i: empire_of_color[colors[i]] for i in range(1, len(colors))}
    names = province_names(owner, culture_of)
    meta_r, queue, lat_c, lon_c = regions_data(m, colors, names, owner)
    write_regions(m, meta_r, queue)

    # фракции
    pairs = src["отношения_пар"]
    at_war = {("Орда Гхарн", "Империум Саэрит")}
    out_f = []
    for f in factions:
        name = f["имя"]
        people = int(f["людей"])
        cap = cities[f["столица_город"]]
        links = {}
        for bloc in src["блоки"].values():
            if name in bloc["члены"]:
                links.update({o: "союз" for o in bloc["члены"] if o != name})
        for a, b in at_war:
            if name in (a, b):
                links[b if name == a else a] = "война"
        out_f.append({
            "имя": name, "тип": "государство", "тело": "Земля", "зоны": [name],
            "столица": [cap["lat"], cap["lon"]], "людей": people, "уровень": f["уровень"],
            "цвет": [round(c / 255, 6) for c in color_of[name]],
            "где_живут": "", "откуда": "", "почему": f["почему"], "чем_заняты": f["чем_заняты"], "цель": f["цель"],
            "сторона": f["сторона"], "лор": text(f["лор"]), "откуда_ви": src["откуда_ви"],
            "запас": {"еда": int(people * 0.6), "вода": int(people * 0.5), "энергия": int(people * 0.2),
                      "стройматериалы": int(people * 0.4), "горючее": int(people * 0.05),
                      "лекарства": int(people * 0.03), "редкое": int(people * 0.012)},
            "ум": f["ум"], "обычаи": {}, "лидеры": f["лидеры"], "связи": links, "имена": f["имена"],
            "коррупция": f["коррупция"], "бюджет": int(people * 0.004), "деньги": int(people * 0.002),
            "бойцы": f["бойцы"],
        })
    zones = {str(i): owner[i] for i in sorted(owner)}
    year = src["старт"]["year"]
    era = src["календарь"]["эра"]["ru"]
    meta = {
        "имя": src["имя"], "версия": 1, "встроенный": False, "режим": "страны", "старт": src["старт"],
        "описание": src["описание"], "описание_en": src["описание_en"],
        "лор_системы": text(src["лор_системы"]), "лор_системы_en": text(src["лор_системы_en"]),
        "лор_тел": text(src["лор_тел"]), "лор_тел_en": text(src["лор_тел_en"]),
        "параметры_тел": src["параметры_тел"],
        "сюжет": {"места": src["сюжет"]["места"], "события": src["сюжет"]["события"],
                  "правила_для_ии": text(src["сюжет"]["правила_для_ии"]),
                  "правила_для_ии_en": text(src["сюжет"]["правила_для_ии_en"]),
                  "обучение": text(src["сюжет"]["обучение"]), "цели": src["сюжет"]["цели"]},
        "фракции": out_f,
        "местности": [{"имя": f["имя"], "тип": "", "цвет": [round(c / 255, 6) for c in color_of[f["имя"]]], "лор": "",
                       "описание": f["чем_заняты"], "тело": "Земля"} for f in factions],
        "океаны": [], "превью": "Земля", "обложка": "обложка.jpg",
        "откуда_ви_en": src["откуда_ви_en"], "завеса": "мифический",
        "рекомендуемые": [f["имя"] for f in factions],
        "блоки": src["блоки"], "тяга_блоков": [], "отношения_пар": pairs,
        "календарь": src["календарь"],
        "провинции_зон_2": zones, "источник": "pax_rpg",
    }
    folder = MOD / "presets" / src["имя"]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent="\t"), encoding="utf-8")
    zones_image(m, owner, color_of).save(folder / "Земля.png")
    cover(src, f"{year} год {era} · пять империй").save(folder / "обложка.jpg", quality=88)

    per = {}
    for fac in owner.values():
        per[fac] = per.get(fac, 0) + 1
    print(json.dumps({"provinces": len(colors) - 1, "per_faction": per, "preset": str(folder.relative_to(ROOT)),
                      "regions_kb": round((MOD / "data/regions2.json").stat().st_size / 1024)}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
