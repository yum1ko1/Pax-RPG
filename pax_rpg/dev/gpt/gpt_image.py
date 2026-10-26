"""Запасной путь — платный OpenAI API (основной — codex_image.py, по подписке ChatGPT). Ключ — из переменной
пользователя OPENAI_API_KEY (реестр Windows),
в вывод не попадает. Результаты — в W\\<имя>\\: картинки, request.json (промпт, модель, параметры) для повтора.

    python gpt_image.py check                                   → есть ли ключ, отвечает ли API, доступные image-модели
    python gpt_image.py gen <имя> "<промпт>" [опции]            → W\\<имя>\\<имя>_0.png …
    python gpt_image.py edit <имя> "<промпт>" --img a.png [--img b.png …] [--mask m.png] [опции]
                                                                → правка / новая картинка по референсам (до 16 картинок)
    python gpt_image.py ask "<вопрос>" [--img a.png …] [--json] [--out файл] → ответ модели-зрения (разбор референса)

Опции картинок: --size 1024x1024|1536x1024|1024x1536|auto  --quality low|medium|high|auto  --n 1..4
  --bg transparent|opaque|auto  --style <файл.txt|имя из styles/> (дописывается перед промптом)  --model <id>
  --fidelity high|low (edit: насколько держать лицо/форму референса)  --format png|webp|jpeg
Модели по умолчанию: OPENAI_IMAGE_MODEL (иначе gpt-image-2; прозрачный фон — только gpt-image-1.5), OPENAI_TEXT_MODEL (иначе gpt-5).
Промпт можно передать файлом: "@file:<путь>".
"""
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "https://api.openai.com/v1"
W = r"C:\Users\mbkli\Desktop\pax_rpg_work\gpt"
HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE_MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-2")
TEXT_MODEL = os.environ.get("OPENAI_TEXT_MODEL", "gpt-5")


def key() -> str:
    k = os.environ.get("OPENAI_API_KEY", "")
    if not k and os.name == "nt":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
                k = winreg.QueryValueEx(h, "OPENAI_API_KEY")[0]
        except OSError:
            pass
    if not k:
        sys.exit("нет OPENAI_API_KEY: [Environment]::SetEnvironmentVariable('OPENAI_API_KEY','sk-…','User')")
    return k


def _send(req: urllib.request.Request, timeout=300):
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:800]}")


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    return _send(urllib.request.Request(API + path, data=data, method=method,
                                        headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"}))


def multipart(path: str, fields: dict, files: list):
    """files: [(поле, путь)] — для /images/edits (image[] можно повторять)."""
    b = uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        out += [f"--{b}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()]
    for k, p in files:
        mime = mimetypes.guess_type(p)[0] or "image/png"
        out += [f"--{b}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{os.path.basename(p)}\"\r\n"
                f"Content-Type: {mime}\r\n\r\n".encode(), open(p, "rb").read(), b"\r\n"]
    out.append(f"--{b}--\r\n".encode())
    return _send(urllib.request.Request(API + path, data=b"".join(out), method="POST", headers={
        "Authorization": "Bearer " + key(), "Content-Type": f"multipart/form-data; boundary={b}"}))


def text(v: str) -> str:
    return open(v[6:], encoding="utf-8-sig").read().strip() if v.startswith("@file:") else v


def style(v: str) -> str:
    for p in (v, os.path.join(HERE, "styles", v), os.path.join(HERE, "styles", v + ".txt")):
        if os.path.isfile(p):
            return " ".join(open(p, encoding="utf-8-sig").read().split())
    sys.exit(f"нет стиля {v} (есть: {', '.join(sorted(os.listdir(os.path.join(HERE, 'styles'))))})")


def opts(a: list):
    o = {"img": []}
    i = 0
    while i < len(a):
        k = a[i]
        if k == "--json":
            o["json"] = True
            i += 1
            continue
        if not k.startswith("--") or i + 1 >= len(a):
            sys.exit(f"непонятный аргумент: {k}")
        v = a[i + 1]
        if k == "--img":
            o["img"].append(v)
        else:
            o[k[2:]] = v
        i += 2
    return o


def image_params(o: dict, prompt: str) -> dict:
    if "style" in o:
        prompt = style(o["style"]) + "\n\n" + prompt
    p = {"model": o.get("model", IMAGE_MODEL), "prompt": prompt, "n": int(o.get("n", 1)),
         "size": o.get("size", "1024x1024"), "quality": o.get("quality", "high")}
    if "bg" in o:
        p["background"] = o["bg"]
    if "format" in o:
        p["output_format"] = o["format"]
    return p


def save(name: str, r: dict, params: dict, refs: list):
    d = os.path.join(W, name)
    os.makedirs(d, exist_ok=True)
    ext = params.get("output_format", "png")
    paths = []
    for i, it in enumerate(r.get("data") or []):
        f = os.path.join(d, f"{name}_{i}.{ext}")
        if it.get("b64_json"):
            open(f, "wb").write(base64.b64decode(it["b64_json"]))
        elif it.get("url"):
            urllib.request.urlretrieve(it["url"], f)
        paths.append(f)
    meta = {"params": params, "refs": refs, "usage": r.get("usage"), "revised": [it.get("revised_prompt") for it in r.get("data") or []],
            "time": time.strftime("%Y-%m-%d %H:%M:%S"), "files": paths}
    json.dump(meta, open(os.path.join(d, "request.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps({"files": paths, "usage": r.get("usage")}, ensure_ascii=False, indent=1))


def cmd_check():
    k = key()
    print("ключ: есть, длина", len(k))
    ids = sorted(m["id"] for m in call("GET", "/models").get("data", []))
    print("image-модели:", [m for m in ids if "image" in m or "dall" in m])
    print("по умолчанию:", IMAGE_MODEL, "/", TEXT_MODEL, "(text есть)" if TEXT_MODEL in ids else "(text-модели НЕТ в списке)")


def cmd_gen(name: str, prompt: str, o: dict):
    p = image_params(o, text(prompt))
    save(name, call("POST", "/images/generations", p), p, [])


def cmd_edit(name: str, prompt: str, o: dict):
    if not o["img"]:
        sys.exit("edit: нужен хотя бы один --img")
    p = image_params(o, text(prompt))
    if "fidelity" in o:
        p["input_fidelity"] = o["fidelity"]
    files = [("image[]", f) for f in o["img"]] + ([("mask", o["mask"])] if "mask" in o else [])
    save(name, multipart("/images/edits", {k: str(v) for k, v in p.items()}, files), p, o["img"])


def cmd_ask(q: str, o: dict):
    content = [{"type": "text", "text": text(q)}]
    for f in o["img"]:
        mime = mimetypes.guess_type(f)[0] or "image/png"
        content.append({"type": "image_url", "image_url": {
            "url": f"data:{mime};base64," + base64.b64encode(open(f, "rb").read()).decode(), "detail": "high"}})
    body = {"model": o.get("model", TEXT_MODEL), "messages": [{"role": "user", "content": content}]}
    if o.get("json"):
        body["response_format"] = {"type": "json_object"}
    ans = call("POST", "/chat/completions", body)["choices"][0]["message"]["content"]
    if "out" in o:
        os.makedirs(os.path.dirname(os.path.abspath(o["out"])), exist_ok=True)
        open(o["out"], "w", encoding="utf-8").write(ans)
        print("→", o["out"])
    print(ans)


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help", "help"):
        sys.exit(__doc__)
    c = a[0]
    if c == "check":
        cmd_check()
    elif c in ("gen", "edit") and len(a) >= 3:
        (cmd_gen if c == "gen" else cmd_edit)(a[1], a[2], opts(a[3:]))
    elif c == "ask" and len(a) >= 2:
        cmd_ask(a[1], opts(a[2:]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
