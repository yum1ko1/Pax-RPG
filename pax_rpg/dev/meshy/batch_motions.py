"""Пакет анимаций боя (стойка, шаги вбок и назад, парирование, добивание) для рыцаря и гоблина через Meshy API.

    python batch_motions.py            → создаёт задачи, ждёт, привязывает к ригам, качает в W\\meshy\\<папка>\\
    python batch_motions.py --status   → что уже готово

Текст → движение (Text to Motion, prime) → анимация на риге (animations, motion_task_id); из библиотеки — action_id.
Состояние — в W\\meshy\\batch_motions.json: перезапуск продолжает с того места, где остановился (ничего не платит дважды).
Ключ — как в meshy_api.py (переменная MESHY_API_KEY), в вывод не попадает.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402

W = M.W
STATE = os.path.join(W, "batch_motions.json")
RIG_KNIGHT = "01a12a14-0f1c-70b8-81b2-22ba751cdb2c"     # рыцарь 2 (без плаща)
RIG_GOBLIN = "01a12a07-dc3d-72b9-8c75-053798521c38"

KNIGHT = ("A heavily armored dark knight in full black plate armor holds a huge two-handed greatsword low in front of "
          "him with both hands on the grip, blade pointing forward and down, in a wary combat guard")
GOBLIN = "A small hunched goblin warrior holding a crude short blade in his right hand"
JOBS = {
    # папка: (риг, текст или action_id, длительность)
    "anim2_GuardStrafeL": (RIG_KNIGHT, KNIGHT + ". He steps sideways to HIS LEFT with slow heavy cautious side steps, "
                           "feet crossing carefully, body and face turned forward toward an enemy the whole time, "
                           "circling the enemy. Seamless loop.", 2.5),
    "anim2_GuardStrafeR": (RIG_KNIGHT, KNIGHT + ". He steps sideways to HIS RIGHT with slow heavy cautious side steps, "
                           "feet crossing carefully, body and face turned forward toward an enemy the whole time, "
                           "circling the enemy. Seamless loop.", 2.5),
    "anim2_GuardBack": (RIG_KNIGHT, KNIGHT + ". He walks slowly BACKWARD with heavy cautious steps, keeping the guard, "
                        "body and face turned forward toward an enemy the whole time. Seamless loop.", 2.5),
    "anim2_StrafeL": (RIG_KNIGHT, "A heavily armored knight with empty hands walks sideways to HIS LEFT with calm heavy "
                      "side steps, facing forward the whole time. Seamless loop.", 2.0),
    "anim2_StrafeR": (RIG_KNIGHT, "A heavily armored knight with empty hands walks sideways to HIS RIGHT with calm heavy "
                      "side steps, facing forward the whole time. Seamless loop.", 2.0),
    "anim2_Deathblow": (RIG_KNIGHT, "An armored knight with a huge two-handed greatsword delivers a finishing blow: "
                        "raises the sword high with both hands, drives it straight down with full weight into a "
                        "fallen enemy on the ground in front of him, holds, pulls it out and returns to guard.", 3.0),
    "anim2_WalkBack": (RIG_KNIGHT, 544, 0),                  # библиотека: Walk Backward
    "anim2_Parry": (RIG_KNIGHT, 149, 0),                     # библиотека: Two-handed Parry
    "gob_CombatIdle": (RIG_GOBLIN, GOBLIN + " crouches in a wary fighting stance, swaying slightly, blade ready, "
                       "watching an enemy in front of him. Seamless loop.", 2.5),
    "gob_StrafeL": (RIG_GOBLIN, GOBLIN + " side-steps to HIS LEFT in a low crouched fighting stance, facing an enemy in "
                    "front of him the whole time, circling him like a predator. Seamless loop.", 2.0),
    "gob_StrafeR": (RIG_GOBLIN, GOBLIN + " side-steps to HIS RIGHT in a low crouched fighting stance, facing an enemy in "
                    "front of him the whole time, circling him like a predator. Seamless loop.", 2.0),
    "gob_Back": (RIG_GOBLIN, GOBLIN + " backs away slowly in a low crouched fighting stance, facing an enemy in front of "
                 "him the whole time. Seamless loop.", 2.0),
    "gob_Deflected": (RIG_GOBLIN, GOBLIN + " swings his blade, it is violently knocked away by a parry: his arm is "
                      "thrown back, he staggers two steps backward off balance and recovers into a crouch.", 2.0),
    "gob_Knockdown": (RIG_GOBLIN, GOBLIN + " is hit in the chest by a huge heavy blow: he is thrown backward off his feet, "
                      "flies back, falls hard flat on his back and lies on the ground stunned.", 2.0),
    "gob_GetUp": (RIG_GOBLIN, GOBLIN + " lies flat on his back on the ground, then quickly rolls over, pushes up with his "
                  "free hand and gets back on his feet into a low crouched fighting stance, blade ready.", 2.0),
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
