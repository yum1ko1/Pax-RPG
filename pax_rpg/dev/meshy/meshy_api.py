"""Мини-клиент Meshy API для моста: ключ берётся из переменной пользователя MESHY_API_KEY (реестр Windows),
в вывод не попадает. Файлы задач — в W\\meshy\\<имя>.

    python meshy_api.py balance
    python meshy_api.py library                       → W\\meshy\\animation_library.json
    python meshy_api.py create <endpoint> <body.json> → id задачи (в body: "@file:<путь>" → data URI картинки/модели)
    python meshy_api.py status <endpoint> <id>         → статус, прогресс, ссылки
    python meshy_api.py wait <endpoint> <id> [сек]     → ждёт SUCCEEDED/FAILED (до N сек, по умолчанию 50)
    python meshy_api.py fetch <endpoint> <id> <имя>    → скачивает все ссылки результата в W\\meshy\\<имя>\\
endpoint — как в API: image-to-image, image-to-3d, rigging, animations, text-to-motion, remesh.
"""
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai/openapi"
W = r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy"
VERSION = {"text-to-3d": "v2"}


def key() -> str:
    k = os.environ.get("MESHY_API_KEY", "")
    if not k:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
            k = winreg.QueryValueEx(h, "MESHY_API_KEY")[0]
    return k


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:800]}")


def ep(name: str) -> str:
    return f"/{VERSION.get(name, 'v1')}/{name}"


def data_uri(path: str) -> str:
    mime = mimetypes.guess_type(path)[0] or ("model/gltf-binary" if path.endswith(".glb") else "application/octet-stream")
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()


def expand(v):
    if isinstance(v, str) and v.startswith("@file:"):
        return data_uri(v[6:])
    if isinstance(v, list):
        return [expand(x) for x in v]
    if isinstance(v, dict):
        return {k: expand(x) for k, x in v.items()}
    return v


def urls(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(urls(v, f"{prefix}{k}."))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out.update(urls(v, f"{prefix}{i}."))
    elif isinstance(obj, str) and obj.startswith("https://"):
        out[prefix.rstrip(".")] = obj
    return out


def short(t: dict) -> dict:
    return {"status": t.get("status"), "progress": t.get("progress"), "error": (t.get("task_error") or {}).get("message"),
            "credits": t.get("consumed_credits"), "files": sorted(urls(t).keys())}


def main():
    a = sys.argv[1:]
    os.makedirs(W, exist_ok=True)
    if a[0] == "balance":
        print(call("GET", "/v1/balance"))
    elif a[0] == "library":
        lib = call("GET", "/v1/animations/library")
        open(os.path.join(W, "animation_library.json"), "w", encoding="utf-8").write(json.dumps(lib, ensure_ascii=False, indent=1))
        print("saved", len(lib) if isinstance(lib, list) else type(lib).__name__)
    elif a[0] == "create":
        body = expand(json.load(open(a[2], encoding="utf-8")))
        print(call("POST", ep(a[1]), body).get("result"))
    elif a[0] == "status":
        print(json.dumps(short(call("GET", f"{ep(a[1])}/{a[2]}")), ensure_ascii=False))
    elif a[0] == "wait":
        end = time.time() + float(a[3] if len(a) > 3 else 50)
        while True:
            t = call("GET", f"{ep(a[1])}/{a[2]}")
            if t.get("status") in ("SUCCEEDED", "FAILED", "CANCELED") or time.time() > end:
                print(json.dumps(short(t), ensure_ascii=False))
                return
            time.sleep(5)
    elif a[0] == "fetch":
        t = call("GET", f"{ep(a[1])}/{a[2]}")
        d = os.path.join(W, a[3])
        os.makedirs(d, exist_ok=True)
        json.dump(t, open(os.path.join(d, "task.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        for name, u in urls(t).items():
            ext = os.path.splitext(u.split("?")[0])[1] or ".bin"
            path = os.path.join(d, name.replace("result.", "") + ext)
            urllib.request.urlretrieve(u, path)
            print(os.path.basename(path), os.path.getsize(path))


if __name__ == "__main__":
    main()
