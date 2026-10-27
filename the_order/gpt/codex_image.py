"""Картинки и референсы через подписку ChatGPT: Codex CLI на ПК (`codex exec`, вход «Sign in with ChatGPT»,
встроенный инструмент image_gen — без OPENAI_API_KEY). Результаты — в out\\<имя>\\ рядом со скриптом:
<имя>_N.png, request.json (история промптов).

    python codex_image.py gen <имя> "<промпт>" [--style order] [--img реф.png …] [--n 2] [--shape square|landscape|portrait]
                                              [--transparent] [--edit] [--avoid "…"]
    python codex_image.py check                                        → codex есть, вход через ChatGPT

--img — референсы (стиль, композиция, форма); с --edit первая картинка — цель правки (меняется только сказанное).
--style — файл или имя из styles/ (order, sheet3d, topdown), дописывается в начало промпта.
Промпт можно передать файлом: "@file:<путь>". Одна генерация ≈ 1–2 мин; мост вернёт job_id — дочитывать job_status.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
W = os.path.join(HERE, "out")
HOME = os.environ.get("CODEX_HOME", os.path.join(os.path.expanduser("~"), ".codex"))
SHAPE = {"square": "square 1:1", "landscape": "landscape 3:2", "portrait": "portrait 2:3"}


def codex() -> str:
    exe = shutil.which("codex.cmd") or shutil.which("codex")
    if not exe:
        sys.exit("нет codex: npm i -g @openai/codex, затем codex login (Sign in with ChatGPT)")
    return exe


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
        if k in ("--transparent", "--edit"):
            o[k[2:]] = True
            i += 1
        elif k.startswith("--") and i + 1 < len(a):
            o["img"].append(os.path.abspath(a[i + 1])) if k == "--img" else o.__setitem__(k[2:], a[i + 1])
            i += 2
        else:
            sys.exit(f"непонятный аргумент: {k}")
    for f in o["img"]:
        if not os.path.isfile(f):
            sys.exit(f"нет файла {f}")
    return o


def run(prompt: str, cwd: str, imgs: list, timeout=900):
    """codex exec → (thread_id, последнее сообщение, ошибки). Промпт — через stdin (без кавычек cmd.exe)."""
    os.makedirs(cwd, exist_ok=True)
    last = os.path.join(cwd, "answer.txt")
    cmd = [codex(), "exec", "--skip-git-repo-check", "--ignore-user-config", "--ephemeral", "-s", "read-only",
           "-C", cwd, "--json", "-o", last]
    for f in imgs:
        cmd += ["-i", f]
    cmd.append("-")
    r = subprocess.run(cmd, input=prompt.encode("utf-8"), capture_output=True, timeout=timeout)
    thread, errors = None, []
    for line in r.stdout.decode("utf-8", "replace").splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") == "thread.started":
            thread = e.get("thread_id")
        elif e.get("type") in ("error", "turn.failed") and "Reconnecting" not in str(e.get("message")):
            errors.append(str(e.get("message") or e.get("error"))[:300])
    msg = open(last, encoding="utf-8").read().strip() if os.path.exists(last) else ""
    if r.returncode and not msg:
        errors.append(r.stderr.decode("utf-8", "replace")[-600:])
    return thread, msg, errors


def gen_prompt(p: str, o: dict) -> str:
    n = int(o.get("n", 1))
    lines = [style(o["style"]) if "style" in o else "", p]
    if o["img"]:
        roles = [f"Image {i + 1}: " + ("edit target — change only what is asked, keep everything else identical"
                                       if o.get("edit") and i == 0 else "reference for style, shapes and composition")
                 for i in range(len(o["img"]))]
        lines.append("Input images: " + "; ".join(roles) + ".")
    if "shape" in o:
        lines.append("Aspect: " + SHAPE.get(o["shape"], o["shape"]) + ".")
    if o.get("transparent"):
        lines.append("Background: genuinely transparent (alpha), no backdrop, no shadow plate.")
    if "avoid" in o:
        lines.append("Avoid: " + o["avoid"] + ".")
    spec = "\n".join(x for x in lines if x)
    return (f"Use your built-in image_gen tool{' (edit mode on Image 1)' if o.get('edit') else ''} to make exactly {n} "
            f"separate image{'s' if n > 1 else ''} from this spec. Follow the spec literally, do not add text, "
            f"logos or watermarks unless the spec asks. Do not run shell commands or write files. When done, reply "
            f"with the absolute path of each generated image file, one per line, nothing else.\n\nSPEC:\n{spec}")


def cmd_gen(name: str, p: str, o: dict):
    d = os.path.join(W, name)
    t0 = time.time()
    prompt = gen_prompt(text(p), o)
    thread, msg, errors = run(prompt, d, o["img"])
    found = set(glob.glob(os.path.join(HOME, "generated_images", thread or "-", "*")))
    found |= {f.strip() for f in msg.splitlines() if os.path.isfile(f.strip())}
    found |= {f for f in glob.glob(os.path.join(HOME, "generated_images", "*", "*")) if os.path.getmtime(f) >= t0}
    out = []
    k = len(glob.glob(os.path.join(d, f"{name}_*.*")))
    for f in sorted(found, key=os.path.getmtime):
        dst = os.path.join(d, f"{name}_{k}{os.path.splitext(f)[1]}")
        shutil.copy2(f, dst)
        out.append(dst)
        k += 1
    log = os.path.join(d, "request.json")
    hist = json.load(open(log, encoding="utf-8")) if os.path.exists(log) else []
    hist.append({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "prompt": prompt, "refs": o["img"], "files": out,
                 "thread": thread, "seconds": round(time.time() - t0), "errors": errors})
    json.dump(hist, open(log, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps({"files": out, "seconds": round(time.time() - t0), "errors": errors}, ensure_ascii=False, indent=1))
    if not out:
        sys.exit("картинок нет: " + (msg[:400] or "; ".join(errors)))


def cmd_check():
    r = subprocess.run([codex(), "login", "status"], capture_output=True, stdin=subprocess.DEVNULL)
    print(codex(), "|", (r.stdout or r.stderr).decode("utf-8", "replace").strip())
    f = subprocess.run([codex(), "features", "list"], capture_output=True, stdin=subprocess.DEVNULL).stdout.decode()
    print("\n".join(x for x in f.splitlines() if x.startswith("image_generation")) or "image_generation: нет в списке")


def main():
    a = sys.argv[1:]
    if a[:1] == ["check"]:
        cmd_check()
    elif a[:1] == ["gen"] and len(a) >= 3:
        cmd_gen(a[1], a[2], opts(a[3:]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
