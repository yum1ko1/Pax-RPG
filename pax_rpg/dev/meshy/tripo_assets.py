"""Модели Гхарна через Tripo API (ключ — переменная окружения TRIPO_API_KEY, в репозитории его нет).
По готовым референсам Meshy (W\\gharn\\<id>\\ref.png) — Image to Model с плотной сеткой и PBR:
дома 100k граней, средние постройки 40k, мелочь 15k (категории — ниже).
    python tripo_assets.py balance
    python tripo_assets.py [--only house_shop_a,crate]   → W\\gharn\\<id>\\model.glb (прежняя — model_lo.glb)
Состояние — W\\gharn\\tripo_state.json: перезапуск продолжает, не платит дважды.
"""
import json
import os
import sys
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gharn_assets as G  # noqa: E402

API = "https://api.tripo3d.ai/v2/openapi"
HOUSES = {"house_shop_a", "house_shop_b", "house_shop_c", "house_timber_a", "house_timber_b", "house_two_a",
          "house_two_b", "guild_hall", "tavern_hall", "khan_palace"}
MEDIUM = {"forge_smithy", "shaman_tower", "watch_tower", "yurt_noble", "stilt_hut", "stable_hay", "gate_fang",
          "fountain_dragon", "oath_tree", "flame_tree", "guardian_statue", "tusk_arch", "market_stall_hide"}


def faces(k):
    return 100000 if k in HOUSES else 40000 if k in MEDIUM else 15000


def key():
    k = os.environ.get("TRIPO_API_KEY", "")
    if not k:
        sys.exit("нет TRIPO_API_KEY")
    return k


def call(method, path, body=None, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + key(), "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            out = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:600]}")
    if out.get("code") != 0:
        sys.exit(f"Tripo: {out}")
    return out["data"]


def upload(path):
    b = "----pax" + uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ref.png\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + open(path, "rb").read() + f"\r\n--{b}--\r\n".encode()
    return call("POST", "/upload", raw=body, ctype="multipart/form-data; boundary=" + b)["image_token"]


def main():
    a = sys.argv[1:]
    if a and a[0] == "balance":
        print(call("GET", "/user/balance"))
        return
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else set(G.ASSETS)
    sf = os.path.join(G.OUT, "tripo_state.json")
    st = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    print("баланс:", call("GET", "/user/balance"), flush=True)
    while True:
        busy = False
        for k in sorted(only):
            d = os.path.join(G.OUT, k)
            ref = os.path.join(d, "ref.png")
            if not os.path.exists(ref):
                continue
            s = st.setdefault(k, {"stage": "new"})
            if s["stage"] == "new":
                tok = upload(ref)
                tid = call("POST", "/task", {"type": "image_to_model", "file": {"type": "png", "file_token": tok},
                                             "face_limit": faces(k), "texture": True, "pbr": True,
                                             "texture_quality": "detailed", "auto_size": True})["task_id"]
                s.update(stage="model", task=tid)
                print(k, "→", tid, faces(k), flush=True)
            elif s["stage"] == "model":
                r = call("GET", "/task/" + s["task"])
                if r.get("status") == "success":
                    out = r.get("output", {})
                    url = out.get("pbr_model") or out.get("model")
                    old = os.path.join(d, "model.glb")
                    if os.path.exists(old) and not os.path.exists(os.path.join(d, "model_lo.glb")):
                        os.rename(old, os.path.join(d, "model_lo.glb"))
                    urllib.request.urlretrieve(url, old)
                    s.update(stage="done")
                    print(k, "готово", os.path.getsize(old), flush=True)
                elif r.get("status") in ("failed", "cancelled", "banned", "expired", "unknown"):
                    s.update(stage="failed", error=r.get("status"))
                    print(k, "ошибка", r.get("status"), flush=True)
            if s["stage"] not in ("done", "failed"):
                busy = True
            json.dump(st, open(sf, "w", encoding="utf-8"), indent=1)
        if not busy:
            break
        time.sleep(10)
    print("баланс:", call("GET", "/user/balance"), flush=True)


if __name__ == "__main__":
    main()
