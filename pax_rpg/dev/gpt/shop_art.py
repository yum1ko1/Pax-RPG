"""Картинки лавки через GPT (OpenAI Images, модель gpt-image-1): значки товаров, монета-награда, фон окна.
Сначала — НА ПРОСМОТР, в мод не попадают; ставятся в игру отдельной командой после согласования.

    python shop_art.py gen <папка просмотра> [--only stat_scroll,shop_bg] [--model gpt-image-1] [--quality high]
    python shop_art.py install <папка просмотра> <mods/pax_rpg> [--only …]   → textures/shop/ (после «да» автора)

Ключ — переменная OPENAI_API_KEY (Windows: и из реестра пользователя), в вывод не попадает. Состояние —
<папка>/state.json: перезапуск не платит дважды за готовое. Удалить файл из папки — сгенерируется заново.
Что ждёт окно лавки (src/location/shop_view.gd): textures/shop/<id товара>.png (значок 200 px на карточке),
fx_gold.png (золото на карточке рулетки; остальные награды берут значок товара того же действия), shop_bg.jpg (фон,
приглушён). При установке значки ужимаются до 256 px, фон — до 1920 px (если есть Pillow): мод не пухнет.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.openai.com/v1/images/generations"

STYLE = ("Game UI item icon for a dark East Asian fantasy action RPG (steppe horde city of Gharn, world of Yuruma). "
         "Painterly, semi-realistic, rich detail, crimson lacquer, antique gold and dark bronze palette with soft "
         "pink mana glow accents. Single object centered, three-quarter view, soft rim light, no text, no letters, "
         "no frame, no border, transparent background, clean silhouette readable at 128 px.")

ICONS = {
    "elixir_refill": "A small round glass vial of glowing pink mana draught with a red lacquered stopper and a gold "
                     "wire collar, tiny bubbles inside, a silk tag tied to the neck.",
    "xp_scroll": "A rolled paper scroll tied with a crimson cord and a jade bead, edge slightly open showing ink "
                 "brush drawings of sword stances.",
    "xp_tome": "A thick stitched-bound martial arts treatise with dark leather covers, gold corner plates and a "
               "red silk bookmark, faint golden glow from the pages.",
    "fate_token": "A bronze coin-like token with a square hole in the center, engraved with a stylised wheel and "
                  "eight spokes, violet mana glint on the rim, hanging on a short red cord.",
    "flask_vessel": "A dried calabash gourd flask for a warrior's belt, lacquered deep red with gold bands, a cork "
                    "stopper and a braided strap, faint pink glow at the mouth.",
    "stat_scroll": "A sacred scroll of the Way on a dark wooden rod with gold end caps, sealed with a red wax seal, "
                   "radiant golden light leaking from the seam, legendary feel.",
    "fx_gold": "A small heap of thick antique gold coins with square holes, stamped with a horned samurai helmet "
               "emblem, warm highlights.",
}

BG = ("Interior of a cramped, cosy bazaar shop in a steppe horde city of a dark East Asian fantasy world at dusk: "
      "wooden shelves with vials, gourds, scrolls and bronze tokens, hanging paper lanterns with warm light, red "
      "lacquer and antique gold accents, a large ornate wooden wheel of fortune with eight coloured segments on the "
      "back wall, carpets, sacks of spice. No people, no text. Painterly cinematic matte painting, shallow depth, "
      "darker at the edges and the center left calm for UI panels, wide 3:2 composition.")

def jobs():
    out = {k: {"prompt": STYLE + " Object: " + v, "size": "1024x1024", "background": "transparent", "ext": "png"}
           for k, v in ICONS.items()}
    out["shop_bg"] = {"prompt": BG, "size": "1536x1024", "background": "opaque", "ext": "jpg"}
    return out


def key():
    k = os.environ.get("OPENAI_API_KEY", "")
    if not k and os.name == "nt":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
                k = winreg.QueryValueEx(h, "OPENAI_API_KEY")[0]
        except OSError:
            pass
    if not k:
        sys.exit("нет OPENAI_API_KEY (переменная окружения или пользователя Windows)")
    return k


def generate(job, model, quality):
    fmt = "jpeg" if job["ext"] == "jpg" else "png"
    body = {"model": model, "prompt": job["prompt"], "size": job["size"], "quality": quality, "n": 1,
            "background": job["background"], "output_format": fmt}
    req = urllib.request.Request(API, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit("OpenAI %d: %s" % (e.code, e.read().decode("utf-8", "replace")[:400]))
    return base64.b64decode(data["data"][0]["b64_json"])


def opt(a, name, default):
    return a[a.index(name) + 1] if name in a else default


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("gen", "install"):
        sys.exit(__doc__)
    a = sys.argv[2:]
    out = a[0]
    only = set(opt(a, "--only", "").split(",")) - {""}
    todo = {k: v for k, v in jobs().items() if not only or k in only}
    if sys.argv[1] == "gen":
        os.makedirs(out, exist_ok=True)
        state_f = os.path.join(out, "state.json")
        st = json.load(open(state_f, encoding="utf-8")) if os.path.exists(state_f) else {}
        for k, job in todo.items():
            f = os.path.join(out, k + "." + job["ext"])
            if os.path.exists(f):
                print(k, "готово")
                continue
            print(k, "…", flush=True)
            open(f, "wb").write(generate(job, opt(a, "--model", "gpt-image-1"), opt(a, "--quality", "high")))
            st[k] = {"prompt": job["prompt"], "size": job["size"]}
            json.dump(st, open(state_f, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("на просмотр:", os.path.abspath(out))
    else:
        mod = a[1]
        dst = os.path.join(mod, "textures", "shop")
        os.makedirs(dst, exist_ok=True)
        import shutil
        try:
            from PIL import Image
        except ImportError:
            Image = None
        for k, job in todo.items():
            src = os.path.join(out, k + "." + job["ext"])
            if not os.path.exists(src):
                continue
            to = os.path.join(dst, k + "." + job["ext"])
            if Image is None:
                shutil.copy(src, to)
            else:
                im = Image.open(src)
                im.thumbnail((1920, 1280) if k == "shop_bg" else (256, 256), Image.LANCZOS)
                im.save(to, quality=90) if job["ext"] == "jpg" else im.save(to, optimize=True)
            print("поставлено:", k)


if __name__ == "__main__":
    main()
