"""Клипы-позы из одного ключа (длина 0 с) → два одинаковых ключа на 0 и LEN с: дерево анимаций Godot не вплетает
клип нулевой длины — поза застревала на последнем кадре шага.
    python3 pose_len.py <model.glb> Idle IdleArmed [...]"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read, write  # noqa: E402

LEN = 1.0
path = sys.argv[1]
j, bin_ = load(path)
for an in j["animations"]:
    if an["name"] not in sys.argv[2:]:
        continue
    ti = write(j, bin_, np.array([0.0, LEN], np.float32), "SCALAR")
    fixed = 0
    for sp in an["samplers"]:
        if len(read(j, bin_, sp["input"])) != 1:
            continue
        v = read(j, bin_, sp["output"])
        typ = j["accessors"][sp["output"]]["type"]
        sp["output"] = write(j, bin_, np.repeat(v[:1], 2, axis=0).astype(np.float32), typ)
        sp["input"] = ti
        fixed += 1
    print(an["name"], "ключей-поз:", fixed)
save(path, j, bin_)
