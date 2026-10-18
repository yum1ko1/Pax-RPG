"""Плотная сетка для готовых моделей Гхарна: Meshy Remesh по уже сделанной задаче Image to 3D (без новой генерации).
    python gharn_remesh.py house_two_a,house_two_b [100000]   → W\\gharn\\<id>\\model.glb (прежняя — model_lo.glb)
"""
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_api as M  # noqa: E402
import gharn_assets as G  # noqa: E402


def main():
    ids = sys.argv[1].split(",")
    poly = int(sys.argv[2]) if len(sys.argv) > 2 else 100000
    st = G.load()
    print("баланс:", M.call("GET", "/v1/balance"), flush=True)
    jobs = {}
    for k in ids:
        tid = st[k]["model_task"]
        r = M.call("POST", "/v1/remesh", {"input_task_id": tid, "target_formats": ["glb"], "topology": "triangle",
                                          "target_polycount": poly})
        jobs[k] = r["result"]
        print(k, "ремеш →", jobs[k], flush=True)
    while jobs:
        time.sleep(10)
        for k in list(jobs):
            r = M.call("GET", "/v1/remesh/" + jobs[k])
            if r.get("status") == "SUCCEEDED":
                d = os.path.join(G.OUT, k)
                old = os.path.join(d, "model.glb")
                if os.path.exists(old) and not os.path.exists(os.path.join(d, "model_lo.glb")):
                    os.rename(old, os.path.join(d, "model_lo.glb"))
                urllib.request.urlretrieve(r["model_urls"]["glb"], old)
                print(k, "готово", os.path.getsize(old), flush=True)
                del jobs[k]
            elif r.get("status") in ("FAILED", "CANCELED", "EXPIRED"):
                print(k, "ошибка", r.get("task_error"), flush=True)
                del jobs[k]
    print("баланс:", M.call("GET", "/v1/balance"), flush=True)


if __name__ == "__main__":
    main()
