"""Движения боевой системы «Концентрация» через Meshy (текст → движение, prime): парирование, отдача в блоке, слом
(шатание), Кровожадная атака героя с копьём; слом, парирование, падение и подъём орка; слом, парирование, блок гоблина.
Клипы — FBX скелета Meshy (имена костей как у наших моделей: Hips, Spine02…), перенос — retarget_glb.py.

    MESHY_KEY=… python combat_motions.py <папка>          → создаёт задачи (раз), ждёт, качает <папка>/<имя>.fbx
    MESHY_KEY=… python combat_motions.py <папка> --status
Состояние — <папка>/combat_motions.json: перезапуск ничего не оплачивает дважды. Ключ — только из окружения.
"""
import json
import os
import sys
import time
import urllib.request

API = "https://api.meshy.ai/openapi/v1/text-to-motion"
KEY = os.environ["MESHY_KEY"]
SPEAR = ("A lean martial artist holding a long spear with both hands near the middle of the shaft, tip forward, "
         "in a low guard stance")
ORC = "A huge heavy muscular orc warrior holding a massive battle axe in his right hand"
GOB = "A small hunched goblin warrior holding a short crude blade in his right hand"
JOBS = {
    "TL_Parry": (SPEAR + ". He sharply deflects an incoming sword strike with the spear shaft: a quick strong twist "
                 "of the spear sideways and up, knocking the blade away, a small step back, then returns to the same "
                 "guard stance.", 2.0),
    "TL_BlockHit": (SPEAR + " holding the spear horizontally in front of his chest blocks a heavy blow: the impact "
                    "pushes him one step back, arms recoil toward the body, then he steadies back into the guard.", 2.0),
    "TL_Stagger": (SPEAR + ". His guard is broken and he is exhausted: he staggers backward off balance, sags down "
                   "onto one knee leaning on the spear, breathes heavily with head down, then pushes himself up back "
                   "into the guard stance.", 3.0),
    "TL_Bloodthirsty": (SPEAR + " performs a brutal finishing move: lunges forward and drives the spear deep into an "
                        "enemy's chest, pushes it further in with both hands, twists it, then rips it out with a pull, "
                        "steps back and flicks the spear down into the guard stance.", 3.0),
    "TL_GetUp": ("A lean martial artist lying flat on his back on the ground holding a long spear in his right hand quickly "
                 "rolls to his side, pushes himself up with his free hand and springs back to his feet into a low spear "
                 "guard stance.", 2.5),
    "Orc_Stagger": (ORC + ". His guard is broken: he staggers backward dazed, drops heavily onto one knee with the axe "
                    "head on the ground, head hanging, breathing hard, then slowly gets back up into a fighting stance.",
                    3.0),
    "Orc_Parry": (ORC + " parries an incoming strike: swings the axe sideways with force to knock the attacker's "
                  "weapon away, leans into it, then returns to a fighting stance.", 2.0),
    "Orc_Fall": (ORC + " is hit very hard and knocked off his feet: he falls backward heavily onto his back and lies "
                 "still on the ground.", 2.5),
    "Orc_GetUp": (ORC + " lying on his back on the ground rolls to his side, pushes himself up with his free hand and "
                  "gets back on his feet into a fighting stance.", 3.0),
    "Gob_Stagger": (GOB + ". His guard is broken: he staggers back dazed, drops onto his knees swaying, shakes his head, "
                    "then gets back up into a crouched fighting stance.", 3.0),
    "Gob_Parry": (GOB + " quickly parries an incoming sword strike with his short blade, knocking it aside with a "
                  "snap of the wrist, then hops back into a crouched fighting stance.", 2.0),
    "Gob_Block": (GOB + " raises his short blade horizontally above his head with both hands to block a heavy strike, "
                  "crouches under the impact and holds the block braced.", 2.0),
}


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=120) as f:
        return json.loads(f.read().decode())


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    sp = os.path.join(out, "combat_motions.json")
    st = json.load(open(sp)) if os.path.exists(sp) else {}
    if "--status" in sys.argv:
        print({k: st.get(k, {}).get("stage", "-") for k in JOBS})
        return
    for k, (prompt, dur) in JOBS.items():
        s = st.setdefault(k, {})
        if "task" not in s:
            assert len(prompt) <= 400, (k, len(prompt))
            r = call("POST", API, {"prompt": prompt, "mode": "prime", "duration": dur})
            s["task"] = r.get("result") or r.get("id")
            s["stage"] = "motion"
            json.dump(st, open(sp, "w"), indent=1)
            print(k, "task", s["task"], flush=True)
    t0 = time.time()
    while time.time() - t0 < 1500:
        left = 0
        for k in JOBS:
            s = st[k]
            if s.get("stage") in ("done", "failed"):
                continue
            r = call("GET", API + "/" + s["task"])
            stt = r.get("status")
            if stt == "SUCCEEDED":
                if "result_keys" not in s:
                    s["result_keys"] = sorted(r.keys())
                urls = {}
                for kk, v in r.items():
                    if isinstance(v, str) and v.startswith("http"):
                        urls[kk] = v
                    elif isinstance(v, dict):
                        for k2, v2 in v.items():
                            if isinstance(v2, str) and v2.startswith("http"):
                                urls[kk + "." + k2] = v2
                s["urls"] = list(urls.keys())
                for name, u in urls.items():
                    ext = ".fbx" if ".fbx" in u.split("?")[0].lower() else os.path.splitext(u.split("?")[0])[1]
                    if ext.lower() in (".fbx", ".bvh", ".glb", ".gif", ".mp4"):
                        urllib.request.urlretrieve(u, os.path.join(out, k + "_" + name.replace(".", "_") + ext))
                s["stage"] = "done"
                print(k, "done", s["urls"], flush=True)
            elif stt in ("FAILED", "CANCELED", "EXPIRED"):
                s["stage"] = "failed"
                s["error"] = str(r.get("task_error"))
                print(k, "FAILED", s["error"], flush=True)
            else:
                left += 1
            json.dump(st, open(sp, "w"), indent=1)
        if not left:
            break
        time.sleep(15)
    print({k: st[k].get("stage") for k in JOBS})


if __name__ == "__main__":
    main()
