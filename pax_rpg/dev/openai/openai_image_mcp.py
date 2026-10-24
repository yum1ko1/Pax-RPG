"""MCP-мост к картинкам OpenAI: Claude генерирует референсы для Pax RPG (концепты, листы персонажей, предметы
для Meshy Image to 3D, иконки, текстуры). Только стандартная библиотека Python — ставить ничего не надо.

    python openai_image_mcp.py            → stdio MCP-сервер (его запускает Claude Code / Claude Desktop)
    python openai_image_mcp.py --selftest → проверка: пресеты, папка вывода, какой бэкенд и вошёл ли Codex

Два бэкенда (PAX_IMAGES_BACKEND, по умолчанию — api, если есть ключ, иначе codex):
  codex — подписка ChatGPT (Plus/Pro/Team): картинку рисует встроенный инструмент image_generation в Codex CLI
          (`npm i -g @openai/codex`, вход `codex login` через ChatGPT). Расходует лимиты подписки, ключ не нужен.
  api   — OpenAI Images API по ключу OPENAI_API_KEY (оплата отдельно, по токенам).
Настройки окружения:
  PAX_IMAGES_DIR         куда сохранять (по умолчанию pax_rpg/reference/openai в репозитории)
  PAX_IMAGES_INLINE_MAX  до скольки байт показывать картинку Claude прямо в ответе (по умолчанию 3 000 000)
  PAX_CODEX_BIN          путь к codex (по умолчанию ищется в PATH), PAX_CODEX_TIMEOUT — сек. на картинку (600)
  PAX_CODEX_SANDBOX      песочница codex exec (workspace-write; на Windows при сбоях — danger-full-access)
  OPENAI_IMAGE_MODEL     модель для api (gpt-image-2), OPENAI_BASE_URL — свой адрес API

Инструменты: generate_image, edit_image (по своим картинкам-образцам), list_images.
Рядом с каждой картинкой — <имя>.json: промпт, бэкенд, параметры (для api — ещё revised_prompt и расход).
"""
import base64
import glob
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
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
CODEX_TIMEOUT = int(os.environ.get("PAX_CODEX_TIMEOUT") or 600)
CODEX_SANDBOX = os.environ.get("PAX_CODEX_SANDBOX") or "workspace-write"
IMG_EXT = (".png", ".jpg", ".jpeg", ".webp")
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


def backend() -> str:
    b = (os.environ.get("PAX_IMAGES_BACKEND") or "").lower()
    return b if b in ("api", "codex") else ("api" if key() else "codex")


def codex_bin() -> str:
    return os.environ.get("PAX_CODEX_BIN") or shutil.which("codex") or ""


class ApiError(Exception):
    pass


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


# --- бэкенд api: OpenAI Images API по ключу ----------------------------------------------------------------

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
        hint = " (нет ключа: задайте OPENAI_API_KEY или PAX_IMAGES_BACKEND=codex)" if e.code == 401 and not k else ""
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


def via_api(prompt: str, params: dict, a: dict, images: list, mask: str) -> tuple:
    """→ ([(байты, расширение, доп. поля для JSON)], поля ответа)."""
    model = a.get("model") or MODEL
    if images:
        fields = dict(params, model=model, prompt=prompt)
        if a.get("input_fidelity"):
            fields["input_fidelity"] = a["input_fidelity"]
        files = [("image[]", p) for p in images] + ([("mask", mask)] if mask else [])
        body, ctype = multipart(fields, files)
        resp = post("/images/edits", body, ctype)
    else:
        resp = post("/images/generations", json.dumps(dict(params, model=model, prompt=prompt)).encode(),
                    "application/json")
    fmt = params.get("output_format") or resp.get("output_format") or "png"
    out = []
    for d in resp.get("data") or []:
        raw = base64.b64decode(d["b64_json"]) if d.get("b64_json") else urllib.request.urlopen(d["url"], timeout=120).read()
        out.append((raw, "jpg" if fmt == "jpeg" else fmt, {"revised_prompt": d.get("revised_prompt")}))
    return out, {"model": model, "usage": resp.get("usage")}


# --- бэкенд codex: подписка ChatGPT через Codex CLI ----------------------------------------------------------

CODEX_PROMPT = """Use your built-in image_generation tool to create {n} bitmap image(s). Do not write code, SVG, \
scripts or curl calls, and do not fabricate an image any other way.

Image size: {size}. Quality: {quality}.{bg}{refs}

PROMPT:
{prompt}

After generating, save the result(s) as PNG files in the current working directory, named variant-1.png, \
variant-2.png, ... (exactly {n} file(s)). Do not ask for confirmation. Reply with only the saved file names."""


def via_codex(prompt: str, params: dict, a: dict, images: list, mask: str) -> tuple:
    exe = codex_bin()
    if not exe:
        raise ApiError("Codex CLI не найден: `npm i -g @openai/codex`, потом `codex login` (вход через ChatGPT)")
    work = tempfile.mkdtemp(prefix="pax-images-")
    refs = ""
    attach = []
    if images or mask:
        os.makedirs(os.path.join(work, "references"))
        names = []
        for i, p in enumerate(images + ([mask] if mask else [])):
            dst = os.path.join(work, "references", f"{i + 1}_{os.path.basename(p)}")
            shutil.copy2(p, dst)
            attach.append(dst)
            names.append("references/" + os.path.basename(dst))
        refs = ("\n\nReference images (attached and copied to " + ", ".join(names) + "): base the new image on them"
                + (" — the last one is a mask, transparent areas are to be repainted" if mask else "")
                + ". Do not modify the reference files.")
    bg = "\nBackground: transparent (PNG with alpha)." if params.get("background") == "transparent" else ""
    text = CODEX_PROMPT.format(n=params["n"], size=params["size"], quality=params["quality"], bg=bg, refs=refs,
                               prompt=prompt)
    cmd = [exe, "exec", "--skip-git-repo-check", "--enable", "image_generation", "-s", CODEX_SANDBOX,
           "-c", 'model_reasoning_effort="low"', "-C", work, "-o", os.path.join(work, "last_message.txt")]
    cmd += [f"--image={p}" for p in attach]
    env = dict(os.environ)
    env.pop("OPENAI_API_KEY", None)          # чтобы Codex шёл через вход ChatGPT, а не по ключу
    home = os.environ.get("CODEX_HOME") or os.path.join(os.path.expanduser("~"), ".codex")
    gen = os.path.join(home, "generated_images", "**", "*")
    before = {f: os.path.getmtime(f) for f in glob.glob(gen, recursive=True)}
    try:
        r = subprocess.run(cmd, input=text.encode("utf-8"), capture_output=True, env=env, timeout=CODEX_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise ApiError(f"Codex не уложился в {CODEX_TIMEOUT} с (PAX_CODEX_TIMEOUT); папка: {work}")
    tail = (r.stdout + r.stderr).decode("utf-8", "replace")[-1500:]
    found = sorted((f for f in glob.glob(os.path.join(work, "*")) if f.lower().endswith(IMG_EXT)), key=os.path.getmtime)
    if not found and r.returncode == 0:   # Codex сам кладёт картинки в $CODEX_HOME/generated_images — берём новые
        fresh = [f for f in glob.glob(gen, recursive=True)
                 if f.lower().endswith(IMG_EXT) and before.get(f) != os.path.getmtime(f)]
        found = sorted(fresh, key=os.path.getmtime)[-params["n"]:]
    if not found:
        hint = " Войдите: `codex login`." if re.search(r"401|login|auth", tail, re.I) else ""
        raise ApiError(f"Codex не вернул картинку (код {r.returncode}).{hint}\n…{tail}")
    out = []
    for f in found[:params["n"]]:
        with open(f, "rb") as h:
            out.append((h.read(), os.path.splitext(f)[1].lstrip(".").lower(), {}))
    shutil.rmtree(work, ignore_errors=True)
    return out, {"model": "codex image_generation (подписка ChatGPT)"}


# --- общее: сохранить и ответить ---------------------------------------------------------------------------

def run(a: dict, images: list, mask: str) -> list:
    prompt, params = compose(a)
    b = backend()
    log(b, params, [os.path.basename(p) for p in images])
    results, extra = (via_codex if b == "codex" else via_api)(prompt, params, a, images, mask)
    os.makedirs(OUT, exist_ok=True)
    base = f"{stem(a.get('name'))}_{time.strftime('%Y%m%d-%H%M%S')}"
    paths, blocks = [], []
    for i, (raw, ext, more) in enumerate(results):
        name = base + (f"_{i + 1}" if len(results) > 1 else "")
        path = os.path.join(OUT, f"{name}.{ext}")
        with open(path, "wb") as f:
            f.write(raw)
        meta = dict(extra, backend=b, file=os.path.basename(path), prompt=prompt, user_prompt=a["prompt"],
                    style=a.get("style"), kind=a.get("kind"), params=params, images=images or None, mask=mask, **more)
        with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=1)
        paths.append(path)
        if len(raw) <= INLINE_MAX:
            blocks.append({"type": "image", "data": base64.b64encode(raw).decode(),
                           "mimeType": "image/jpeg" if ext == "jpg" else f"image/{ext}"})
    info = {"saved": paths, "backend": b, "usage": extra.get("usage"), "prompt_sent": prompt}
    if len(blocks) < len(paths):
        info["note"] = f"часть картинок больше {INLINE_MAX} байт — в ответ не вложены, открыть по пути"
    return [{"type": "text", "text": json.dumps(info, ensure_ascii=False, indent=1)}] + blocks


def generate_image(a: dict) -> list:
    return run(a, [], None)


def edit_image(a: dict) -> list:
    images = [resolve(p) for p in a.get("images") or []]
    if not images:
        raise ApiError("нужна хотя бы одна картинка в images")
    return run(a, images, resolve(a["mask"]) if a.get("mask") else None)


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
                     "style": d.get("style"), "kind": d.get("kind"), "backend": d.get("backend")})
    return [{"type": "text", "text": json.dumps({"dir": OUT, "images": rows}, ensure_ascii=False, indent=1)}]


def describe(group: str) -> str:
    return "; ".join(f"{k} — {v['about']}" for k, v in PRESETS[group].items())


COMMON = {
    "prompt": {"type": "string", "description": "Описание картинки, лучше по-английски. Стиль и тип добавятся сами."},
    "name": {"type": "string", "description": "Имя файла (латиница), напр. oni_hero_sheet. К нему добавится время."},
    "style": {"type": "string", "enum": list(PRESETS["styles"]), "description": "Блок стиля мира: " + describe("styles")},
    "kind": {"type": "string", "enum": list(PRESETS["kinds"]), "description": "Тип референса: " + describe("kinds")},
    "size": {"type": "string", "description": "1024x1024, 1536x1024, 1024x1536 или auto; по умолчанию — из kind, иначе auto"},
    "quality": {"type": "string", "enum": ["low", "medium", "high", "auto"], "description": "По умолчанию medium"},
    "n": {"type": "integer", "minimum": 1, "maximum": 4, "description": "Сколько вариантов (1–4); каждый тратит лимит"},
    "background": {"type": "string", "enum": ["auto", "transparent", "opaque"]},
    "output_format": {"type": "string", "enum": ["png", "jpeg", "webp"], "description": "Только для бэкенда api"},
    "model": {"type": "string", "description": f"Только для бэкенда api, по умолчанию {MODEL}"},
}

TOOLS = {
    "generate_image": (generate_image, {
        "description": "Сгенерировать референс-картинку для Pax RPG (OpenAI: через подписку ChatGPT в Codex или по "
                       "ключу API). Сохраняет файл и JSON с промптом в папку референсов и возвращает картинку. "
                       "Занимает от 30 с до нескольких минут.",
        "inputSchema": {"type": "object", "properties": COMMON, "required": ["prompt"]}}),
    "edit_image": (edit_image, {
        "description": "Новая картинка по своим образцам (1–16 файлов): перерисовать в стиле Юрумы, сделать лист "
                       "персонажа по концепту, поменять детали; с mask (PNG с прозрачной областью) — дорисовать часть.",
        "inputSchema": {"type": "object", "properties": dict(COMMON, **{
            "images": {"type": "array", "items": {"type": "string"},
                       "description": "Пути к картинкам: абсолютные, от корня репозитория или из папки референсов"},
            "mask": {"type": "string", "description": "PNG-маска: прозрачное — перерисовать"},
            "input_fidelity": {"type": "string", "enum": ["low", "high"],
                               "description": "Только api: high — точнее держать лицо/детали образца"},
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
                "serverInfo": {"name": "pax-images", "version": "1.1.0"},
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
    log("готов; бэкенд", backend(), "| вывод", OUT)
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
    b = backend()
    print("бэкенд:", b, "(PAX_IMAGES_BACKEND=api|codex)")
    print("вывод:", OUT)
    if b == "codex":
        exe = codex_bin()
        print("codex:", exe or "НЕ НАЙДЕН — npm i -g @openai/codex")
        if exe:
            r = subprocess.run([exe, "login", "status"], capture_output=True, text=True, stdin=subprocess.DEVNULL,
                               timeout=30)
            print("вход:", (r.stdout + r.stderr).strip() or f"код {r.returncode}", "(нужно «Logged in using ChatGPT»)")
    else:
        print("API:", API, "| модель:", MODEL, "| ключ:", "найден" if key() else "НЕТ")
    print("стили:", ", ".join(PRESETS["styles"]), "| типы:", ", ".join(PRESETS["kinds"]))


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else serve()
