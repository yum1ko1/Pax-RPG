"""MCP-мост к OpenAI Images: Claude генерирует референсы для Pax RPG (концепты, листы персонажей, предметы
для Meshy Image to 3D, иконки, текстуры). Только стандартная библиотека Python — ставить ничего не надо.

    python openai_image_mcp.py            → stdio MCP-сервер (его запускает Claude Code / Claude Desktop)
    python openai_image_mcp.py --selftest → проверка без сети: пресеты, папка вывода, ключ найден или нет

Ключ — переменная OPENAI_API_KEY (или переменная пользователя Windows в реестре), в вывод не попадает.
Нет ключа — запрос уходит без заголовка (облачный прокси Claude может подставить ключ сам).
Настройки окружения:
  OPENAI_IMAGE_MODEL   модель по умолчанию (gpt-image-2)
  OPENAI_BASE_URL      свой адрес API (по умолчанию https://api.openai.com/v1)
  PAX_IMAGES_DIR       куда сохранять (по умолчанию pax_rpg/reference/openai в репозитории)
  PAX_IMAGES_INLINE_MAX  до скольки байт показывать картинку Claude прямо в ответе (по умолчанию 3 000 000)

Инструменты: generate_image, edit_image (по своим картинкам-образцам), list_images.
Рядом с каждой картинкой — <имя>.json: промпт, модель, параметры, revised_prompt, расход токенов.
"""
import base64
import json
import mimetypes
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT = os.environ.get("PAX_IMAGES_DIR") or os.path.join(REPO, "pax_rpg", "reference", "openai")
API = (os.environ.get("OPENAI_BASE_URL") or "https://api.openai.com/v1").rstrip("/")
MODEL = os.environ.get("OPENAI_IMAGE_MODEL") or "gpt-image-2"
INLINE_MAX = int(os.environ.get("PAX_IMAGES_INLINE_MAX") or 3_000_000)
PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
PRESETS = json.load(open(os.path.join(HERE, "presets.json"), encoding="utf-8"))


def log(*a):
    print("[pax-images]", *a, file=sys.stderr, flush=True)


def key() -> str:
    k = os.environ.get("OPENAI_API_KEY", "")
    if not k and sys.platform == "win32":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
                k = winreg.QueryValueEx(h, "OPENAI_API_KEY")[0]
        except OSError:
            pass
    return k


class ApiError(Exception):
    pass


def post(path: str, body: bytes, content_type: str) -> dict:
    headers = {"Content-Type": content_type}
    k = key()
    if k:
        headers["Authorization"] = "Bearer " + k
    req = urllib.request.Request(API + path, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            text = json.loads(text)["error"]["message"]
        except (ValueError, KeyError, TypeError):
            text = text[:800]
        hint = " (нет ключа: задайте OPENAI_API_KEY)" if e.code == 401 and not k else ""
        msg = f"OpenAI HTTP {e.code}: {text}{hint}"
        raise ApiError(msg.replace(k, "sk-***") if k else msg)
    except urllib.error.URLError as e:
        raise ApiError(f"OpenAI недоступен: {e.reason}")


def multipart(fields: dict, files: list) -> tuple:
    """files: [(поле, путь)] → (тело, content-type)."""
    b = uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out.append(f'--{b}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    for name, path in files:
        mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
        out.append(f'--{b}\r\nContent-Disposition: form-data; name="{name}"; filename="{os.path.basename(path)}"\r\n'
                   f"Content-Type: {mime}\r\n\r\n".encode())
        with open(path, "rb") as f:
            out.append(f.read())
        out.append(b"\r\n")
    out.append(f"--{b}--\r\n".encode())
    return b"".join(out), f"multipart/form-data; boundary={b}"


# --- сборка промпта и параметров ---------------------------------------------------------------------------

def compose(a: dict) -> tuple:
    kind = PRESETS["kinds"].get(a.get("kind") or "")
    style = PRESETS["styles"].get(a.get("style") or "")
    parts = [kind["text"]] if kind else []
    if style:
        parts.append(style["text"])
    parts.append(a["prompt"].strip())
    if style and style.get("avoid"):
        parts.append("Avoid: " + style["avoid"] + ".")
    params = {"size": a.get("size") or (kind or {}).get("size") or "auto",
              "quality": a.get("quality") or "medium",
              "n": max(1, min(int(a.get("n") or 1), 4))}
    bg = a.get("background") or (kind or {}).get("background")
    if bg:
        params["background"] = bg
    if a.get("output_format"):
        params["output_format"] = a["output_format"]
    return "\n\n".join(parts), params


def stem(name: str) -> str:
    s = re.sub(r"[^\w\-]+", "_", (name or "image").strip(), flags=re.U).strip("_")[:60]
    return s or "image"


def resolve(p: str) -> str:
    p = os.path.expanduser(p)
    for base in ("", REPO, OUT):
        q = os.path.join(base, p) if base else p
        if os.path.isfile(q):
            return os.path.abspath(q)
    raise ApiError(f"файл не найден: {p}")


def save(resp: dict, name: str, meta: dict) -> tuple:
    os.makedirs(OUT, exist_ok=True)
    fmt = meta["params"].get("output_format") or resp.get("output_format") or "png"
    ext = "jpg" if fmt == "jpeg" else fmt
    ts = time.strftime("%Y%m%d-%H%M%S")
    data = resp.get("data") or []
    paths, blocks = [], []
    for i, d in enumerate(data):
        raw = base64.b64decode(d["b64_json"]) if d.get("b64_json") else urllib.request.urlopen(d["url"], timeout=120).read()
        base = f"{stem(name)}_{ts}" + (f"_{i + 1}" if len(data) > 1 else "")
        path = os.path.join(OUT, f"{base}.{ext}")
        with open(path, "wb") as f:
            f.write(raw)
        side = dict(meta, file=os.path.basename(path), revised_prompt=d.get("revised_prompt"), usage=resp.get("usage"),
                    created=resp.get("created"))
        with open(os.path.join(OUT, base + ".json"), "w", encoding="utf-8") as f:
            json.dump(side, f, ensure_ascii=False, indent=1)
        paths.append(path)
        if len(raw) <= INLINE_MAX:
            blocks.append({"type": "image", "data": base64.b64encode(raw).decode(), "mimeType": f"image/{fmt}"})
    return paths, blocks


def summary(paths: list, blocks: list, resp: dict, prompt: str) -> list:
    info = {"saved": paths, "usage": resp.get("usage"), "prompt_sent": prompt}
    if len(blocks) < len(paths):
        info["note"] = f"часть картинок больше {INLINE_MAX} байт — в ответ не вложены, открыть по пути"
    return [{"type": "text", "text": json.dumps(info, ensure_ascii=False, indent=1)}] + blocks


# --- инструменты -------------------------------------------------------------------------------------------

def generate_image(a: dict) -> list:
    prompt, params = compose(a)
    model = a.get("model") or MODEL
    body = dict(params, model=model, prompt=prompt)
    log("generate", model, params)
    resp = post("/images/generations", json.dumps(body).encode(), "application/json")
    paths, blocks = save(resp, a.get("name"), {"tool": "generate_image", "model": model, "prompt": prompt,
                                               "user_prompt": a["prompt"], "style": a.get("style"),
                                               "kind": a.get("kind"), "params": params})
    return summary(paths, blocks, resp, prompt)


def edit_image(a: dict) -> list:
    images = [resolve(p) for p in a.get("images") or []]
    if not images:
        raise ApiError("нужна хотя бы одна картинка в images")
    prompt, params = compose(a)
    model = a.get("model") or MODEL
    fields = dict(params, model=model, prompt=prompt)
    if a.get("input_fidelity"):
        fields["input_fidelity"] = a["input_fidelity"]
    files = [("image[]", p) for p in images]
    if a.get("mask"):
        files.append(("mask", resolve(a["mask"])))
    log("edit", model, params, [os.path.basename(p) for p in images])
    body, ctype = multipart(fields, files)
    resp = post("/images/edits", body, ctype)
    paths, blocks = save(resp, a.get("name"), {"tool": "edit_image", "model": model, "prompt": prompt,
                                               "user_prompt": a["prompt"], "style": a.get("style"),
                                               "kind": a.get("kind"), "params": params, "images": images,
                                               "mask": a.get("mask")})
    return summary(paths, blocks, resp, prompt)


def list_images(a: dict) -> list:
    if not os.path.isdir(OUT):
        return [{"type": "text", "text": f"пока пусто: {OUT}"}]
    metas = sorted((f for f in os.listdir(OUT) if f.endswith(".json")), reverse=True)[:int(a.get("limit") or 20)]
    rows = []
    for m in metas:
        try:
            d = json.load(open(os.path.join(OUT, m), encoding="utf-8"))
        except ValueError:
            continue
        rows.append({"file": os.path.join(OUT, d.get("file", "")), "prompt": d.get("user_prompt"),
                     "style": d.get("style"), "kind": d.get("kind"), "model": d.get("model")})
    return [{"type": "text", "text": json.dumps({"dir": OUT, "images": rows}, ensure_ascii=False, indent=1)}]


def describe(group: str) -> str:
    return "; ".join(f"{k} — {v['about']}" for k, v in PRESETS[group].items())


COMMON = {
    "prompt": {"type": "string", "description": "Описание картинки, лучше по-английски. Стиль и тип добавятся сами."},
    "name": {"type": "string", "description": "Имя файла (латиница), напр. oni_hero_sheet. К нему добавится время."},
    "style": {"type": "string", "enum": list(PRESETS["styles"]), "description": "Блок стиля мира: " + describe("styles")},
    "kind": {"type": "string", "enum": list(PRESETS["kinds"]), "description": "Тип референса: " + describe("kinds")},
    "size": {"type": "string", "description": "1024x1024, 1536x1024, 1024x1536 или auto; по умолчанию — из kind, иначе auto"},
    "quality": {"type": "string", "enum": ["low", "medium", "high", "auto"], "description": "По умолчанию medium (high дороже)"},
    "n": {"type": "integer", "minimum": 1, "maximum": 4, "description": "Сколько вариантов (1–4)"},
    "background": {"type": "string", "enum": ["auto", "transparent", "opaque"]},
    "output_format": {"type": "string", "enum": ["png", "jpeg", "webp"]},
    "model": {"type": "string", "description": f"Модель OpenAI, по умолчанию {MODEL}"},
}

TOOLS = {
    "generate_image": (generate_image, {
        "description": "Сгенерировать референс-картинку для Pax RPG через OpenAI Images. Сохраняет PNG и JSON с "
                       "промптом в папку референсов и возвращает картинку для просмотра.",
        "inputSchema": {"type": "object", "properties": COMMON, "required": ["prompt"]}}),
    "edit_image": (edit_image, {
        "description": "Новая картинка по своим образцам (1–16 файлов): перерисовать в стиле Юрумы, сделать лист "
                       "персонажа по концепту, поменять детали; с mask (PNG с прозрачной областью) — дорисовать часть.",
        "inputSchema": {"type": "object", "properties": dict(COMMON, **{
            "images": {"type": "array", "items": {"type": "string"},
                       "description": "Пути к картинкам: абсолютные, от корня репозитория или из папки референсов"},
            "mask": {"type": "string", "description": "PNG-маска: прозрачное — перерисовать"},
            "input_fidelity": {"type": "string", "enum": ["low", "high"],
                               "description": "high — точнее держать лицо/детали образца (если модель умеет)"},
        }), "required": ["prompt", "images"]}}),
    "list_images": (list_images, {
        "description": "Последние сгенерированные референсы: пути и промпты.",
        "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "minimum": 1}}}}),
}


# --- MCP поверх stdio (JSON-RPC 2.0, по строке на сообщение) -----------------------------------------------

def handle(msg: dict):
    method, mid, p = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if method == "initialize":
        want = p.get("protocolVersion")
        return {"protocolVersion": want if want in PROTOCOLS else PROTOCOLS[0],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "pax-images", "version": "1.0.0"},
                "instructions": "Референсы для мода Pax RPG (Юрума, азиатское фэнтези). Для листов под 3D — "
                                "kind=character/object, для кадров — kind=concept, стиль style=yuruma или gharn."}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [dict(spec, name=n) for n, (_, spec) in TOOLS.items()]}
    if method == "tools/call":
        fn = TOOLS.get(p.get("name"), (None,))[0]
        if not fn:
            raise LookupError(f"нет инструмента {p.get('name')}")
        try:
            return {"content": fn(p.get("arguments") or {})}
        except (ApiError, KeyError, ValueError, OSError) as e:
            return {"content": [{"type": "text", "text": f"Ошибка: {e}"}], "isError": True}
    if mid is None:      # уведомления (initialized, cancelled) — без ответа
        return None
    raise LookupError(f"метод не поддерживается: {method}")


def serve():
    out = sys.stdout.buffer
    log("готов; модель", MODEL, "| вывод", OUT, "| ключ", "есть" if key() else "нет")
    for line in sys.stdin.buffer:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line.decode("utf-8"))
        except ValueError:
            continue
        mid = msg.get("id")
        try:
            res = handle(msg)
            if mid is None:      # уведомление или ответ клиента
                continue
            reply = {"jsonrpc": "2.0", "id": mid, "result": res}
        except LookupError as e:
            reply = {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": str(e)}}
        except Exception as e:  # noqa: BLE001 — сервер не должен падать
            log("сбой:", repr(e))
            reply = {"jsonrpc": "2.0", "id": mid, "error": {"code": -32603, "message": str(e)}}
        out.write(json.dumps(reply, ensure_ascii=False).encode("utf-8") + b"\n")
        out.flush()


def selftest():
    print("модель:", MODEL)
    print("API:", API)
    print("вывод:", OUT)
    print("ключ OPENAI_API_KEY:", "найден" if key() else "НЕТ (запрос пойдёт без ключа)")
    print("стили:", ", ".join(PRESETS["styles"]), "| типы:", ", ".join(PRESETS["kinds"]))
    print("пример промпта:\n" + compose({"prompt": "a young oni swordsman", "style": "yuruma", "kind": "character"})[0])


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else serve()
