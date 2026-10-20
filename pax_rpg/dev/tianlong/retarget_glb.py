"""Перенос клипа с одного скелета на другой — без Blender, по мировым поворотам костей (как npc_variant.py):
  • таз, позвоночник, шея, голова, кисти, пальцы — разница поворота от покоя исходника переносится на покой цели;
  • руки и ноги — так же, плюс доворот: кость цели смотрит туда же, куда кость исходника (позы покоя у ригов разные:
    T, A — без доворота руки торчали бы в стороны);
  • таз — по высоте бёдер (рост другой), ход по земле — в anim.json (root motion героя) или вынут (враги — на месте).
Исходник — glb (движение Meshy: FBX → fbx2glb, скелет SMPL: Pelvis, L_Hip…; или клип нашей модели: те же имена).

    python3 retarget_glb.py <цель.glb> <имя клипа> <исходник.glb>[#клип] [--meta anim.json] [--inplace]
        [--fingers <клип цели>] [--trim a-b] [--speed k] [--out <файл.glb>] [--only] [--mirror]
  --out — записать в другой файл (цель — образец узлов); --only — в нём только этот клип (клипы гоблина — по файлу).
  --fingers — пальцы цели — поза первого кадра этого её клипа (хват копья, топора), а не исходника.
  --trim — кадры исходника a…b (30 к/с); --speed — клип быстрее (k > 1) / медленнее.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_casc import load, save, read, write, trs, m2q, q2m, smooth, FK  # noqa: E402

FPS = 30
SMPL = {"Pelvis": "Hips", "Spine1": "Spine02", "Spine2": "Spine01", "Spine3": "Spine", "Neck": "neck", "Head": "Head"}
for s, t in (("L_", "Left"), ("R_", "Right")):
    SMPL.update({s + "Hip": t + "UpLeg", s + "Knee": t + "Leg", s + "Ankle": t + "Foot", s + "Foot": t + "ToeBase",
                 s + "Collar": t + "Shoulder", s + "Shoulder": t + "Arm", s + "Elbow": t + "ForeArm", s + "Wrist": t + "Hand"})
    for f in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
        for k in (1, 2, 3):
            SMPL[s + f + str(k)] = t + "Hand" + f + str(k)
# кость → ребёнок, по которому видно направление (руки, ноги)
DIRS = {}
for t in ("Left", "Right"):
    DIRS.update({t + "UpLeg": t + "Leg", t + "Leg": t + "Foot", t + "Shoulder": t + "Arm", t + "Arm": t + "ForeArm",
                 t + "ForeArm": t + "Hand"})


def arg(name, d=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else d


def rest_world(j):
    """Мировые матрицы узлов в покое (TRS узлов)."""
    N = j["nodes"]
    par = {c: i for i, n in enumerate(N) for c in n.get("children", [])}
    memo = {}

    def w(i):
        if i not in memo:
            n = N[i]
            m = trs(n.get("translation"), n.get("rotation"), n.get("scale"))
            memo[i] = w(par[i]) @ m if i in par else m
        return memo[i]
    return {i: w(i) for i in range(len(N))}, par


def nrm3(M):
    R = M[:3, :3].copy()
    return R / np.linalg.norm(R, axis=0)


def rot_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.9999:
        ax = np.cross(a, [1.0, 0.0, 0.0])
        if np.linalg.norm(ax) < 1e-3:
            ax = np.cross(a, [0.0, 1.0, 0.0])
        ax /= np.linalg.norm(ax)
        return 2.0 * np.outer(ax, ax) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx / (1.0 + c)


def facing(pos, left, right, hips):
    """Вперёд персонажа (по земле): лево × верх."""
    lv = pos[left] - pos[right]
    f = np.cross(lv, [0.0, 1.0, 0.0])
    f[1] = 0.0
    return f / np.linalg.norm(f)


def main():
    tgt_p, clip, src_arg = sys.argv[1], sys.argv[2], sys.argv[3]
    src_p, src_clip = (src_arg.split("#", 1) + [None])[:2]
    meta_p = arg("--meta")
    out_p = arg("--out", tgt_p)
    inplace = "--inplace" in sys.argv
    rm_scale = float(arg("--root", "1"))          # доля хода по земле в root motion (0 — на месте)
    mirror = "--mirror" in sys.argv
    speed = float(arg("--speed", "1"))
    j, jb = load(tgt_p)
    s, sb = load(src_p)
    TN = {n.get("name"): i for i, n in enumerate(j["nodes"])}
    SN = {n.get("name"): i for i, n in enumerate(s["nodes"])}
    ai = 0
    if src_clip:
        ai = next(k for k, a in enumerate(s["animations"]) if a["name"] == src_clip)
    sa = s["animations"][ai]
    smap = {}                                     # кость цели → кость исходника
    for sn in SN:
        tn = SMPL.get(sn, sn)
        if mirror:
            tn = tn.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right")
        if tn in TN and sn:
            smap[tn] = sn
    joints = [j["nodes"][i].get("name") for i in j["skins"][0]["joints"]]
    tw, tpar = rest_world(j)
    sw, spar = rest_world(s)
    fk = FK(s, sb, ai)
    t_all = sorted({float(x) for c in sa["channels"] for x in read(s, sb, sa["samplers"][c["sampler"]]["input"])[:, 0]})
    t0, t1 = t_all[0], t_all[-1]
    tr = arg("--trim")
    if tr:
        a_, b_ = (int(x) for x in tr.split("-"))
        t0, t1 = a_ / FPS, b_ / FPS
    n = int(round((t1 - t0) * FPS / speed)) + 1
    tt = np.linspace(0.0, (t1 - t0) / speed, n)          # время клипа цели
    ts = t0 + tt * speed                                  # время исходника
    # поворот исходника вокруг Y: лицом туда же, куда цель
    sp_rest = {k: sw[SN[v]][:3, 3] for k, v in smap.items()}
    tp_rest = {k: tw[TN[k]][:3, 3] for k in smap}
    fs = facing(sp_rest, "LeftUpLeg", "RightUpLeg", "Hips")
    ft = facing(tp_rest, "LeftUpLeg", "RightUpLeg", "Hips")
    if mirror:
        fs = -fs if False else fs
    yaw = np.arctan2(np.cross(fs, ft)[1], float(np.dot(fs, ft)))
    Y = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    # рост: высота таза над носками в покое
    def floor(pos):
        return min(pos[k][1] for k in ("LeftToeBase", "RightToeBase") if k in pos)
    s_floor_rest, t_floor = floor(sp_rest), floor(tp_rest)
    ratio = (tp_rest["Hips"][1] - t_floor) / max(1e-4, sp_rest["Hips"][1] - s_floor_rest)
    # пол исходника — по самой анимации (у скелета Meshy покой стоит ниже нуля, а движение — на полу): нижние точки
    # носков за клип
    toes = [smap[k] for k in ("LeftToeBase", "RightToeBase") if k in smap]
    lows = [min(float((Y @ fk.world(SN[sn], t)[:3, 3])[1]) for sn in toes) for t in np.linspace(t0, t1, 24)]
    s_floor = float(np.percentile(lows, 10)) - 0.02
    print("retarget %s ← %s: %d bones, yaw %.0f°, height ×%.3f, %d frames" % (clip, os.path.basename(src_p), len(smap),
          np.degrees(yaw), ratio, n))
    # пальцы из клипа цели (хват оружия)
    keep = {}                                     # кости цели с позой из её клипа (руки в хвате оружия, пальцы)
    aclip = arg("--arms")
    if aclip:
        aa = next(a for a in j["animations"] if a["name"] == aclip)
        for c in aa["channels"]:
            nm = j["nodes"][c["target"]["node"]].get("name", "")
            if c["target"]["path"] == "rotation" and any(x in nm for x in ("Shoulder", "Arm", "Hand")):
                keep[nm] = read(j, jb, aa["samplers"][c["sampler"]]["output"])[0]
    fingers = {}
    fclip = arg("--fingers")
    if fclip:
        fa = next(a for a in j["animations"] if a["name"] == fclip)
        for c in fa["channels"]:
            nm = j["nodes"][c["target"]["node"]].get("name", "")
            if "Hand" in nm and any(f in nm for f in ("Index", "Middle", "Ring", "Pinky", "Thumb")) and c["target"]["path"] == "rotation":
                fingers[nm] = read(j, jb, fa["samplers"][c["sampler"]]["output"])[0]
    # порядок: родители раньше детей
    order = []

    def visit(i):
        order.append(i)
        for c in j["nodes"][i].get("children", []):
            visit(c)
    for r in j["scenes"][0]["nodes"]:
        visit(r)
    jset = set(joints)
    rot_out = {nm: [] for nm in joints}
    hips_world = []
    mirror_m = np.diag([-1.0, 1.0, 1.0])
    for k in range(n):
        t = ts[k]
        Sw = {}
        for tn, sn in smap.items():
            M = fk.world(SN[sn], t)
            R = Y @ nrm3(M)
            P = Y @ M[:3, 3]
            if mirror:                                   # отражение мира по X; лево ↔ право уже в smap
                R = mirror_m @ R @ mirror_m
                P = mirror_m @ P
            Sw[tn] = (R, P)
        Sr = {}
        for tn, sn in smap.items():
            R = Y @ nrm3(sw[SN[sn]])
            P = Y @ sw[SN[sn]][:3, 3]
            if mirror:
                R = mirror_m @ R @ mirror_m
                P = mirror_m @ P
            Sr[tn] = (R, P)
        Wt = {}                                          # мир цели в этот кадр (повороты и положения)
        for i in order:
            nd = j["nodes"][i]
            nm = nd.get("name", "")
            L = trs(nd.get("translation"), nd.get("rotation"), nd.get("scale"))
            pr = tpar.get(i)
            PW = Wt[pr] if pr is not None else np.eye(4)
            Rr = nrm3(tw[i])
            if nm in keep:
                fingers[nm] = keep[nm]
            if nm in smap and nm in jset and not (nm in fingers):
                Rs, _ = Sw[nm]
                Rs0, _ = Sr[nm]
                R = Rs @ Rs0.T @ Rr                      # разница от покоя исходника → на покой цели
                ch = DIRS.get(nm)
                if ch and ch in smap:                    # доворот по направлению кости
                    sd = Sw[ch][1] - Sw[nm][1]
                    ci = TN[ch]
                    td0 = tw[ci][:3, 3] - tw[i][:3, 3]
                    td = R @ Rr.T @ td0                  # куда смотрит кость цели после переноса разницы
                    R = rot_between(td, sd) @ R
                W = np.eye(4)
                W[:3, :3] = R
                W[:3, 3] = (PW @ L)[:3, 3]
                if nm == "Hips":
                    sp0 = Sr["Hips"][1]
                    spt = Sw["Hips"][1]
                    tp0 = tw[i][:3, 3]
                    hp = np.array([tp0[0] + (spt[0] - sp0[0]) * ratio, t_floor + (spt[1] - s_floor) * ratio,
                                   tp0[2] + (spt[2] - sp0[2]) * ratio])
                    W[:3, 3] = hp
                Wt[i] = W
            else:
                if nm in fingers:
                    L = trs(nd.get("translation"), fingers[nm], nd.get("scale"))
                M = PW @ L
                Wt[i] = M
            if nm in jset:
                PWr = nrm3(PW) if pr is not None else np.eye(3)
                Rl = PWr.T @ nrm3(Wt[i])
                q = m2q(Rl)
                prev = rot_out[nm]
                if prev and np.dot(q, prev[-1]) < 0:
                    q = -q
                prev.append(q)
            if nm == "Hips":
                PWm = PW
                hips_world.append(np.linalg.inv(PWm) @ Wt[i])
    # таз: положение в осях родителя; ход по земле — root motion (герой) или вынут (враг)
    hv = np.array([m[:3, 3] for m in hips_world])
    hi = TN["Hips"]
    home = np.array(j["nodes"][hi].get("translation", [0.0, 0.0, 0.0]), float)
    d = hv - hv[0]
    road = smooth(d[:, [0, 2]], 4.0)
    road -= road[0]
    road += np.linspace(0.0, 1.0, n)[:, None] * (d[-1, [0, 2]] - road[-1])
    hv[:, 0] = home[0] + d[:, 0] - road[:, 0]
    hv[:, 2] = home[2] + d[:, 2] - road[:, 1]
    hv[:, 1] = hv[:, 1]
    off = [[round(float(road[i, 0]) * rm_scale, 4), round(float(road[i, 1]) * rm_scale, 4)] for i in range(n)]
    ch, samp = [], []
    ti = write(j, jb, tt.astype(np.float32), "SCALAR")
    for nm in joints:
        v = np.array(rot_out[nm], np.float32)
        if len(v) != n:
            continue
        v = smooth(v, 0.8)
        v /= np.linalg.norm(v, axis=1, keepdims=True)
        samp.append({"input": ti, "output": write(j, jb, v, "VEC4"), "interpolation": "LINEAR"})
        ch.append({"sampler": len(samp) - 1, "target": {"node": TN[nm], "path": "rotation"}})
    samp.append({"input": ti, "output": write(j, jb, hv.astype(np.float32), "VEC3"), "interpolation": "LINEAR"})
    ch.append({"sampler": len(samp) - 1, "target": {"node": hi, "path": "translation"}})
    if "Spear" in TN:                                # копьё в руке — как в покое модели (хват)
        gs = j["nodes"][TN["Spear"]]
        for path, v, typ in (("translation", gs.get("translation", [0, 0, 0]), "VEC3"),
                             ("rotation", gs.get("rotation", [0, 0, 0, 1]), "VEC4")):
            samp.append({"input": ti, "output": write(j, jb, np.array([v] * n, np.float32), typ), "interpolation": "LINEAR"})
            ch.append({"sampler": len(samp) - 1, "target": {"node": TN["Spear"], "path": path}})
    anim = {"name": clip, "channels": ch, "samplers": samp}
    if "--only" in sys.argv:
        j["animations"] = [anim]
    else:
        j["animations"] = [a for a in j["animations"] if a.get("name") != clip] + [anim]
    save(out_p, j, jb)
    if meta_p:
        meta = json.load(open(meta_p, encoding="utf-8"))
        meta.setdefault("root_motion", {})[clip] = {"fps": FPS, "frames": n, "offset": [[0.0, 0.0]] * n if inplace else off}
        meta.setdefault("clips", {})[clip] = {"frames": n}
        json.dump(meta, open(meta_p, "w", encoding="utf-8"), ensure_ascii=False)
    print("  %.2f s, path %.2f m%s" % (tt[-1], float(np.hypot(*off[-1])), " (in place)" if inplace else ""))


if __name__ == "__main__":
    main()
