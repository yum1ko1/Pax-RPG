"""Концепт-арт через Meshy Text to Image: промпты берутся из заметки Obsidian
(«Гхарн — промпты концепт-арта.md»: первый блок кода — стиль, дальше — кадры «### N. …» и листы объектов).

    python concept_images.py <заметка.md> <папка вывода> [--only 1,4] [--model nano-banana-pro]

Состояние — в <папка>/state.json: перезапуск докачивает готовое и не платит дважды.
"""
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402


def shots(md):
    blocks = re.findall(r"```\n(.*?)```", md, flags=re.S)
    style = " ".join(blocks[0].split())
    out = {}
    for m in re.finditer(r"### (\d+)\. ([^\n]+)\n```\n(.*?)```", md, flags=re.S):
        out[f"shot{m.group(1)}"] = style + " " + " ".join(m.group(3).split())
    sheet = re.search(r"Блок для листов:\n```\n(.*?)```", md, flags=re.S)
    if sheet:
        base = " ".join(sheet.group(1).split())
        for i, m in enumerate(re.finditer(r"- \*\*([^*]+):\*\* `([^`]+)`", md, flags=re.S), 1):
            out[f"sheet{i}"] = base + " Props: " + " ".join(m.group(2).split())
    return out


def main():
    md = open(sys.argv[1], encoding="utf-8-sig").read()
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    only = None
    model = "nano-banana-pro"
    a = sys.argv[3:]
    if "--only" in a:
        only = set(a[a.index("--only") + 1].split(","))
    if "--model" in a:
        model = a[a.index("--model") + 1]
    state_f = os.path.join(out, "state.json")
    st = json.load(open(state_f, encoding="utf-8")) if os.path.exists(state_f) else {}
    jobs = shots(md)
    todo = [k for k in jobs if not (only and k not in only and k.replace("shot", "") not in only)]
    t0 = time.time()
    while time.time() - t0 < 1800:
        for k in todo:                         # отправить, пока очередь Meshy принимает (на тарифе ≤ 10 задач)
            if k in st:
                continue
            try:
                r = M.call("POST", M.ep("text-to-image"), {"ai_model": model, "prompt": jobs[k][:2000],
                                                           "aspect_ratio": "16:9" if k.startswith("shot") else "1:1"})
            except SystemExit as e:              # 429 — очередь полна: ждём готовых и пробуем снова
                print(k, "ждёт очереди:", str(e)[:60], flush=True)
                break
            st[k] = {"id": r.get("result"), "done": False}
            json.dump(st, open(state_f, "w", encoding="utf-8"), indent=1)
            print(k, "→", st[k]["id"], f"({len(jobs[k])} симв.)", flush=True)
        pending = [k for k, v in st.items() if not v["done"]]
        if not pending and all(k in st for k in todo):
            break
        for k in pending:
            v = st[k]
            r = M.call("GET", f"{M.ep('text-to-image')}/{v['id']}")
            s = r.get("status")
            if s == "SUCCEEDED":
                for i, u in enumerate(r.get("image_urls") or []):
                    urllib.request.urlretrieve(u, os.path.join(out, f"{k}_{i}.png"))
                v["done"] = True
                print(k, "готово", flush=True)
            elif s in ("FAILED", "CANCELED", "EXPIRED"):
                v["done"] = True
                v["error"] = str(r.get("task_error"))
                print(k, "ошибка", v["error"], flush=True)
            json.dump(st, open(state_f, "w", encoding="utf-8"), indent=1)
        time.sleep(6)
    print("итог:", {k: ("ok" if not v.get("error") else "fail") for k, v in st.items()})


if __name__ == "__main__":
    main()
