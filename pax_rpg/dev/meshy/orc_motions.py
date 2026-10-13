"""Анимации орка-чемпиона и падения рыцаря через Meshy (текст → движение → риг), как batch_motions.py.
    python orc_motions.py / --status. Состояние — W\\meshy\\orc_motions.json.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402

W = M.W
STATE = os.path.join(W, "orc_motions.json")
RIG_KNIGHT = "01a12a14-0f1c-70b8-81b2-22ba751cdb2c"
RIG_ORC = "01a132a8-ea43-7559-bd8a-ca08e03afd0a"
KNIGHT = ("A heavily armored dark knight in full black plate armor holding a huge two-handed greatsword")
ORC = ("A huge muscular red-skinned orc champion, very heavy and powerful, holding a massive battle axe in his right "
       "hand")
JOBS = {
    "orc_ChargeStart": (RIG_ORC, ORC + " stops, lowers his head and shoulders, stamps one foot hard on the ground twice "
                        "like a bull, roars, then leans forward ready to charge.", 1.8),
    "orc_ChargeRun": (RIG_ORC, ORC + " charges forward running heavily like a raging bull, body leaning far forward, "
                      "left shoulder lowered in front as a battering ram, axe held back, huge powerful strides. "
                      "Seamless loop.", 1.2),
    "orc_ChargeHit": (RIG_ORC, ORC + " running forward slams his lowered shoulder into an enemy with full weight, "
                      "stops abruptly, stumbles one heavy step, straightens up and turns back into a fighting stance.",
                      1.8),
    "orc_Death": (RIG_ORC, ORC + " is mortally wounded: drops the axe, staggers back, falls heavily to his knees, "
                  "then collapses face down on the ground and lies still.", 3.0),
    "knight_Knocked": (RIG_KNIGHT, KNIGHT + " is rammed in the chest by a huge charging enemy: he is thrown backward "
                       "off his feet, flies back, lands hard flat on his back and lies stunned for a moment.", 1.8),
    "knight_GetUp": (RIG_KNIGHT, KNIGHT + " lying flat on his back on the ground quickly rolls to his side, pushes "
                     "himself up with one hand and gets back on his feet into a combat guard with the greatsword.", 2.2),
}


def load():
    return json.load(open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}


def save(st):
    json.dump(st, open(STATE, "w", encoding="utf-8"), indent=1)


def wait(endpoint, task_id, limit=900):
    t0 = time.time()
    while time.time() - t0 < limit:
        r = M.call("GET", f"{M.ep(endpoint)}/{task_id}")
        if r.get("status") in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            return r
        time.sleep(8)
    return {"status": "TIMEOUT"}


def main():
    st = load()
    if "--status" in sys.argv:
        for k in JOBS:
            print(k, st.get(k, {}).get("stage", "-"))
        return
    # 1) всё текст → движение сразу (идут параллельно)
    for k, (rig, what, dur) in JOBS.items():
        s = st.setdefault(k, {})
        if isinstance(what, str) and "motion" not in s:
            r = M.call("POST", M.ep("text-to-motion"), {"prompt": what, "mode": "prime", "duration": dur})
            s["motion"] = r.get("result") or r.get("id")
            s["stage"] = "motion"
            save(st)
            print(k, "motion", s["motion"], flush=True)
    # 2) по готовности — анимация на риге, скачать
    for k, (rig, what, dur) in JOBS.items():
        s = st[k]
        if s.get("stage") == "done":
            continue
        if "anim" not in s:
            if isinstance(what, str):
                r = wait("text-to-motion", s["motion"])
                if r.get("status") != "SUCCEEDED":
                    print(k, "motion failed", r.get("status"), r.get("task_error"), flush=True)
                    s["stage"] = "motion_failed"
                    save(st)
                    continue
                body = {"rig_task_id": rig, "motion_task_id": s["motion"]}
            else:
                body = {"rig_task_id": rig, "action_id": what}
            body["post_process"] = {"operation_type": "change_fps", "fps": 30}
            r = M.call("POST", M.ep("animations"), body)
            s["anim"] = r.get("result") or r.get("id")
            s["stage"] = "anim"
            save(st)
        r = wait("animations", s["anim"])
        if r.get("status") != "SUCCEEDED":
            print(k, "anim failed", r.get("status"), flush=True)
            s["stage"] = "anim_failed"
            save(st)
            continue
        url = (r.get("result") or {}).get("animation_glb_url")
        d = os.path.join(W, k)
        os.makedirs(d, exist_ok=True)
        import urllib.request
        urllib.request.urlretrieve(url, os.path.join(d, "animation_glb_url.glb"))
        s["stage"] = "done"
        save(st)
        print(k, "done", flush=True)
    print("all:", {k: st[k].get("stage") for k in JOBS})


if __name__ == "__main__":
    main()
