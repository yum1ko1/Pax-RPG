"""Правка поворотов костей в клипах glb прямо в бинарнике (размер не меняется).
Операции (повторять можно):
  --damp Clip Bone k        — повороты кости ближе к позе покоя: q = slerp(q, rest, k) (0..1)
  --tilt Clip Bone ax deg   — добавить поворот вокруг локальной оси ax (x|y|z) на deg градусов
  --noyaw Clip Bone         — убрать поворот вокруг вертикали (Y родителя) относительно первого ключа
python3 edit_clip_rot.py in.glb out.glb ops..."""
import json, math, struct, sys

def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz)

def qinv(q): return (-q[0], -q[1], -q[2], q[3])

def qnorm(q):
    l = math.sqrt(sum(c*c for c in q)) or 1.0
    return tuple(c / l for c in q)

def slerp(a, b, t):
    d = sum(x*y for x, y in zip(a, b))
    if d < 0: b = tuple(-c for c in b); d = -d
    if d > 0.9995: return qnorm(tuple(x + (y - x) * t for x, y in zip(a, b)))
    th = math.acos(d); s = math.sin(th)
    return tuple((math.sin((1-t)*th) * x + math.sin(t*th) * y) / s for x, y in zip(a, b))

def axis_q(ax, deg):
    h = math.radians(deg) / 2; v = [0.0, 0.0, 0.0]; v["xyz".index(ax)] = math.sin(h)
    return (v[0], v[1], v[2], math.cos(h))

def main():
    a = sys.argv[1:]; src, dst, ops = a[0], a[1], a[2:]
    raw = bytearray(open(src, "rb").read())
    jl = struct.unpack_from("<I", raw, 12)[0]; g = json.loads(raw[20:20 + jl]); bo = 20 + jl + 8
    names = {n.get("name"): i for i, n in enumerate(g["nodes"])}

    def keys(clip, bone):
        an = next(x for x in g["animations"] if x["name"] == clip)
        ch = next(c for c in an["channels"] if c["target"].get("node") == names[bone] and c["target"]["path"] == "rotation")
        acc = g["accessors"][an["samplers"][ch["sampler"]]["output"]]; bv = g["bufferViews"][acc["bufferView"]]
        off = bo + bv.get("byteOffset", 0) + acc.get("byteOffset", 0); st = bv.get("byteStride", 16)
        return off, st, acc["count"]

    i = 0
    while i < len(ops):
        op = ops[i]
        if op == "--damp":
            clip, bone, k = ops[i+1], ops[i+2], float(ops[i+3]); i += 4
            rest = tuple(g["nodes"][names[bone]].get("rotation", [0, 0, 0, 1]))
            off, st, n = keys(clip, bone)
            for j in range(n):
                q = struct.unpack_from("<4f", raw, off + j*st)
                struct.pack_into("<4f", raw, off + j*st, *slerp(q, rest, k))
        elif op == "--tilt":
            clip, bone, ax, deg = ops[i+1], ops[i+2], ops[i+3], float(ops[i+4]); i += 5
            r = axis_q(ax, deg); off, st, n = keys(clip, bone)
            for j in range(n):
                q = struct.unpack_from("<4f", raw, off + j*st)
                struct.pack_into("<4f", raw, off + j*st, *qnorm(qmul(q, r)))
        elif op == "--noyaw":
            clip, bone = ops[i+1], ops[i+2]; i += 3
            off, st, n = keys(clip, bone)
            q0 = struct.unpack_from("<4f", raw, off)
            for j in range(n):
                q = struct.unpack_from("<4f", raw, off + j*st)
                d = qmul(q, qinv(q0))                     # поворот относительно первого ключа (в пространстве родителя)
                tw = qnorm((0.0, d[1], 0.0, d[3]))        # его часть вокруг вертикали
                struct.pack_into("<4f", raw, off + j*st, *qnorm(qmul(qinv(tw), q)))
        else:
            raise SystemExit("unknown op " + op)
        print("ok", ops[i-1] if False else op)
    open(dst, "wb").write(raw)

main()
