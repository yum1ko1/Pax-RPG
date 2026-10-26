"""Картинки с ПК → ветка gpt-refs репозитория Pax-RPG (remote pax-rpg в папке игры), чтобы облачная сессия их
увидела: `git fetch origin gpt-refs` → `git show origin/gpt-refs:<путь> > файл`. Рабочая папка и индекс игры
не трогаются (временный индекс + commit-tree), push — без force, поверх текущей ветки.

    python send_refs.py <папка или файлы…> [--to gpt/<имя>] [--max 1536] [--msg "…"]
--max N — уменьшить длинную сторону до N (PNG с альфой остаются PNG), 0 — как есть.
"""
import os
import subprocess
import sys
import tempfile

REMOTE, BRANCH = "pax-rpg", "gpt-refs"
EXT = (".png", ".jpg", ".jpeg", ".webp", ".json", ".txt", ".md")


def git(*a, inp=None, env=None):
    r = subprocess.run(["git", *a], input=inp, capture_output=True, env=env)
    if r.returncode:
        sys.exit(f"git {' '.join(a[:2])}: {r.stderr.decode('utf-8', 'replace')[:600]}")
    return r.stdout.decode().strip()


def shrink(path: str, m: int) -> bytes:
    data = open(path, "rb").read()
    if not m or not path.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
        return data
    from io import BytesIO
    from PIL import Image
    im = Image.open(BytesIO(data))
    if max(im.size) <= m:
        return data
    im.thumbnail((m, m), Image.LANCZOS)
    b = BytesIO()
    im.save(b, format=im.format or "PNG")
    return b.getvalue()


def main():
    a = sys.argv[1:]
    to, mx, msg, src = None, 1536, None, []
    i = 0
    while i < len(a):
        if a[i] in ("--to", "--max", "--msg"):
            v = a[i + 1]
            to, mx, msg = (v, mx, msg) if a[i] == "--to" else (to, int(v), msg) if a[i] == "--max" else (to, mx, v)
            i += 2
        else:
            src.append(a[i])
            i += 1
    files = []
    for s in src:
        if os.path.isdir(s):
            files += [os.path.join(s, f) for f in sorted(os.listdir(s)) if f.lower().endswith(EXT)]
        else:
            files.append(s)
    if not files:
        sys.exit(__doc__)
    to = (to or "gpt/" + os.path.basename(os.path.normpath(src[0] if os.path.isdir(src[0]) else os.path.dirname(src[0])))).strip("/")
    subprocess.run(["git", "fetch", "-q", REMOTE, BRANCH], capture_output=True)
    parent = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/remotes/{REMOTE}/{BRANCH}"],
                            capture_output=True).stdout.decode().strip()
    env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tempfile.mkdtemp(), "index"))
    if parent:
        git("read-tree", parent, env=env)
    for f in files:
        blob = git("hash-object", "-w", "--stdin", inp=shrink(f, mx))
        git("update-index", "--add", "--cacheinfo", f"100644,{blob},{to}/{os.path.basename(f)}", env=env)
    tree = git("write-tree", env=env)
    c = git("commit-tree", tree, *(["-p", parent] if parent else []), "-m", msg or f"refs: {to} ({len(files)} файлов)")
    git("push", "-q", REMOTE, f"{c}:refs/heads/{BRANCH}")
    print(f"→ {REMOTE}/{BRANCH} {c[:8]}: {to}/ ← {', '.join(os.path.basename(f) for f in files)}")


if __name__ == "__main__":
    main()
