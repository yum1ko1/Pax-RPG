# Цветокоррекция по актам: кривые плёнки, раздельное тонирование, насыщенность. Пишет .cube для Resolve.
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import LUTS

# contrast, black, shadows tint, highlights tint, saturation, red_keep, exposure
LOOKS = {
    "dawn":   dict(c=1.10, black=0.018, sh=(-0.010, 0.008, 0.030), hi=(0.040, 0.018, -0.030), sat=1.04, red=0.0, exp=0.00),
    "rift":   dict(c=1.18, black=0.020, sh=(-0.005, -0.010, 0.040), hi=(0.035, -0.010, 0.005), sat=1.00, red=0.0, exp=-0.02),
    "war":    dict(c=1.22, black=0.022, sh=(-0.025, 0.012, 0.035), hi=(0.045, 0.010, -0.035), sat=0.90, red=0.6, exp=-0.03),
    "iru":    dict(c=1.08, black=0.020, sh=(0.012, -0.005, 0.045), hi=(0.020, 0.008, 0.020), sat=0.96, red=0.0, exp=0.00),
    "selune": dict(c=1.16, black=0.016, sh=(-0.010, 0.004, 0.030), hi=(0.000, 0.012, 0.030), sat=0.78, red=0.9, exp=-0.03),
    "blast":  dict(c=1.06, black=0.020, sh=(-0.010, 0.000, 0.030), hi=(0.030, 0.015, -0.010), sat=0.92, red=0.3, exp=0.00),
    "menu":   dict(c=1.06, black=0.016, sh=(-0.006, 0.000, 0.022), hi=(0.015, 0.006, -0.010), sat=1.00, red=0.0, exp=0.00),
}


def _scurve(x, c):
    # мягкая S-кривая вокруг 0.45 с плёночным носком и плечом, 0→0, 1→1
    p = 0.45
    y = np.where(x < p, p * (x / p) ** c, 1 - (1 - p) * ((1 - x) / (1 - p)) ** c)
    return y


def apply(rgb, look):
    """rgb float32 0..1, (...,3)"""
    L = LOOKS[look]
    x = np.clip(rgb * (2.0 ** L["exp"]), 0, 1)
    x = _scurve(x, L["c"])
    luma = (x * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1, keepdims=True)
    ws = np.clip(1 - luma / 0.5, 0, 1) ** 1.5
    wh = np.clip((luma - 0.45) / 0.55, 0, 1) ** 1.2
    x = x + ws * np.array(L["sh"], np.float32) + wh * np.array(L["hi"], np.float32)
    luma = (x * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1, keepdims=True)
    r, g, b = x[..., 0:1], x[..., 1:2], x[..., 2:3]
    redness = np.clip((r - np.maximum(g, b)) * 3.0, 0, 1) * L["red"]
    s = L["sat"] + (1 - L["sat"]) * redness if L["sat"] < 1 else L["sat"]
    x = luma + (x - luma) * s
    x = L["black"] + x * (1 - L["black"])          # плёночный подъём чёрного
    return np.clip(x, 0, 1)


def write_cube(look, path, n=33):
    t = np.linspace(0, 1, n, dtype=np.float32)
    b, g, r = np.meshgrid(t, t, t, indexing="ij")   # в .cube быстрее всего меняется R
    grid = np.stack([r, g, b], -1).reshape(-1, 3)
    out = apply(grid, look)
    with open(path, "w", newline="\n") as f:
        f.write(f'TITLE "Pax Intro {look}"\nLUT_3D_SIZE {n}\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n')
        for v in out:
            f.write(f"{v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")


if __name__ == "__main__":
    os.makedirs(LUTS, exist_ok=True)
    for k in LOOKS:
        write_cube(k, os.path.join(LUTS, f"PaxIntro_{k}.cube"))
        print("lut", k)
