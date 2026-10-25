# VFX-плёнки для монтажа: движение камеры, тряска, вспышки, свечение, хроматика, зерно, переходы.
# python vfx.py plates            — все плёнки (ProRes 422 HQ) в plates/
# python vfx.py stills 6.9 27.1   — кадры-превью (с грейдом) в prev/
import os, sys, math, subprocess
import numpy as np
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *
import grade

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
RNG = np.random.default_rng(1047)
PH = RNG.uniform(0, 2 * math.pi, (8, 6))


def smooth_noise(t, k, freqs):
    # плавный шум из синусов: k — канал, freqs — частоты (Гц)
    v = 0.0
    for i, f in enumerate(freqs):
        v += math.sin(2 * math.pi * f * t + PH[k, i]) / (i + 1)
    return v / sum(1 / (i + 1) for i in range(len(freqs)))


def camera(t):
    """смещение (px), поворот (град), рывок зума, хроматика, вспышка (rgb), свечение"""
    dx = dy = rot = punch = 0.0
    ca = 1.0
    flash = np.zeros(3, np.float32)
    glow = 0.0
    for (t0, amp, tau, fl, col, cap, zp) in IMPACTS:
        d = t - t0
        if -0.05 < d < 0:                       # кадр-предвестник: лёгкий подсвет
            flash += np.array(col, np.float32) * fl * 0.15
        if d < 0 or d > tau * 4:
            continue
        e = math.exp(-d / tau)
        a = amp * e
        dx += a * smooth_noise(t, 0, (13.0, 19.0, 7.0))
        dy += a * smooth_noise(t, 1, (11.0, 17.0, 5.0))
        rot += amp / 30.0 * e * smooth_noise(t, 2, (9.0, 6.0))
        punch += zp * math.exp(-d / 0.22)
        ca += cap * math.exp(-d / 0.35)
        flash += np.array(col, np.float32) * fl * math.exp(-d / 0.10)
        glow += 0.6 * fl * math.exp(-d / 0.5)
    for (a0, a1, amp) in RUMBLES:
        if a0 <= t <= a1 + 0.6:
            k = min(1.0, (t - a0) / max(0.01, a1 - a0)) if t <= a1 else max(0.0, 1 - (t - a1) / 0.6)
            dx += amp * k * smooth_noise(t, 3, (8.0, 14.0, 21.0))
            dy += amp * k * smooth_noise(t, 4, (9.0, 15.0, 23.0))
    for (a0, a1, amp) in HANDHELD:
        if a0 <= t <= a1:
            dx += amp * smooth_noise(t, 5, (0.35, 0.8, 1.7))
            dy += amp * 0.8 * smooth_noise(t, 6, (0.3, 0.7, 1.5))
            rot += amp * 0.05 * smooth_noise(t, 7, (0.25, 0.6))
    return dx, dy, rot, punch, ca, flash, glow


def ease(x):
    return x * x * (3 - 2 * x)


def warp(img, zoom, dx, dy, rot):
    # аффинно: вход = R^-1 * (выход - центр - d) / zoom + центр
    margin = 1 + 2.2 * max(abs(dx) / W, abs(dy) / H) + abs(rot) * 0.012
    s = zoom * margin
    a = math.radians(rot)
    ca_, sa = math.cos(a) / s, math.sin(a) / s
    cx, cy = W / 2, H / 2
    ox, oy = cx + dx, cy + dy
    # x_in = ca*(x-ox) + sa*(y-oy) + cx ; y_in = -sa*(x-ox) + ca*(y-oy) + cy
    data = (ca_, sa, cx - ca_ * ox - sa * oy, -sa, ca_, cy + sa * ox - ca_ * oy)
    return img.transform((W, H), Image.AFFINE, data, resample=Image.BICUBIC)


def chroma(arr, px):
    # радиальная хроматика: R чуть больше, B чуть меньше от центра
    if px < 0.6:
        return arr
    k = px / (W / 2)
    out = arr.copy()
    for ch, sgn in ((0, 1), (2, -1)):
        s = 1 + sgn * k
        im = Image.fromarray(arr[..., ch])
        nw, nh = int(round(W * s)), int(round(H * s))
        im = im.resize((nw, nh), Image.BILINEAR)
        l, tp = (nw - W) // 2, (nh - H) // 2
        if s >= 1:
            im = im.crop((l, tp, l + W, tp + H))
            out[..., ch] = np.asarray(im)
        else:
            bg = Image.fromarray(arr[..., ch])
            bg.paste(im, (-l, -tp))
            out[..., ch] = np.asarray(bg)
    return out


GRAIN = None


def grain_frame(i):
    global GRAIN
    if GRAIN is None:
        g = np.random.default_rng(7).normal(0, 1, (12, H // 2, W // 2)).astype(np.float32)
        GRAIN = [np.asarray(Image.fromarray(((x * 32) + 128).clip(0, 255).astype(np.uint8))
                            .filter(ImageFilter.GaussianBlur(0.55)).resize((W, H), Image.BILINEAR), np.float32) / 255 - 0.5
                 for x in g]
    return GRAIN[i % len(GRAIN)]


def bloom(arr, glow_boost):
    # ореол (тёплое свечение светов) + анаморфный блик по горизонтали
    small = Image.fromarray(arr).resize((480, 270), Image.BILINEAR)
    s = np.asarray(small, np.float32) / 255
    lum = s.max(-1, keepdims=True)
    hi = np.clip((lum - 0.78) / 0.22, 0, 1) ** 2 * s
    hal = np.asarray(Image.fromarray((hi * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255
    hot = np.clip((lum - 0.88) / 0.12, 0, 1) ** 2 * s
    k = 90
    c = np.cumsum(np.pad(hot, ((0, 0), (k, k), (0, 0)), mode="edge"), axis=1)
    streak = (c[:, 2 * k:] - c[:, :-2 * k]) / (2 * k)
    streak = streak[:, :480] * np.array([0.55, 0.65, 1.0], np.float32)
    add = hal * np.array([1.0, 0.72, 0.55], np.float32) * (0.20 + glow_boost) + streak * (0.38 + glow_boost)
    add = np.asarray(Image.fromarray((np.clip(add, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR), np.float32) / 255
    return add


_SH = {}


def _shock_maps():
    if not _SH:
        a, b, c, (ox, oy) = SHOCK
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        d = np.sqrt((xx - ox * W) ** 2 + (yy - oy * H) ** 2)
        _SH["d"] = d
        _SH["rmax"] = float(d.max())
        rng = np.random.default_rng(15)
        lay = []
        for k, sz in ((0, 24), (1, 60)):
            n = rng.normal(0, 1, (H // sz + 2, W // sz + 2)).astype(np.float32)
            im = Image.fromarray(((n * 40) + 128).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
            lay.append(np.asarray(im.filter(ImageFilter.GaussianBlur(6)), np.float32) / 255)
        _SH["n"] = np.clip(lay[0] * 0.5 + lay[1] * 0.5, 0, 1)
    return _SH


def dust_frame(tl):
    # стена пыли, летящая на камеру: текстура растёт от центра волны
    m = _shock_maps()
    a, b, c, (ox, oy) = SHOCK
    s = 1 + (tl - a) * 0.05
    n = Image.fromarray((m["n"] * 255).astype(np.uint8))
    nw, nh = int(W * s), int(H * s)
    n = n.resize((nw, nh), Image.BILINEAR)
    l, t = int(ox * W * (s - 1)), int(oy * H * (s - 1))
    n = np.asarray(n.crop((l, t, l + W, t + H)), np.float32) / 255
    base = np.array([0.88, 0.74, 0.68], np.float32)
    return np.clip(base[None, None, :] * (0.60 + 0.75 * n[..., None]), 0, 1), n


def shockwave(f, tl):
    a, b, c, _ = SHOCK
    if not (a <= tl < c):
        return f
    m = _shock_maps()
    dust, n = dust_frame(tl)
    if tl < b:
        p = (tl - a + 1) / (b - a)
        r = (p ** 1.5) * 1.15 * m["rmax"]
        inside = np.clip((r - m["d"]) / 110, 0, 1) * 0.97
        edge = np.exp(-((m["d"] - r) / 60) ** 2)
        f = f * (1 - inside[..., None]) + dust * inside[..., None]
        f = f + edge[..., None] * np.array([1.0, 0.86, 0.80], np.float32) * 0.6
        f = f + p * p * 0.18
    else:
        q = (tl - b) / (c - b)
        val = 0.6 * n + 0.4 * (1 - m["d"] / m["rmax"])
        al = np.clip((val - (q * 1.4 - 0.25)) * 3.5, 0, 1) * (1 - q) ** 0.6
        f = f * (1 - al[..., None]) + dust * al[..., None]
    return f


def process(frame, tl_frame, clip, local_i):
    t = tl_frame / FPS
    name, _, _, n, _, _, look, (z0, z1) = clip
    p = local_i / max(1, n - 1)
    dx, dy, rot, punch, ca, flash, glow = camera(t)
    zoom = (z0 + (z1 - z0) * ease(p)) * (1 + punch)
    img = Image.fromarray(frame)
    img = warp(img, zoom, dx, dy, rot)
    arr = np.asarray(img)
    arr = chroma(arr, ca)
    f = arr.astype(np.float32) / 255
    f = 1 - (1 - f) * (1 - bloom(arr, glow))          # экран: свечение не пережигает
    f = f + flash[None, None, :] * (0.35 + 0.65 * f)  # вспышка ярче в светах
    f = shockwave(f, tl_frame)
    f = f + grain_frame(tl_frame)[..., None] * (0.085 * (1 - np.abs(f - 0.5) * 1.2)).clip(0.02, 1)
    for (a, b, col, mode) in FADES:
        if a <= tl_frame < b:
            k = (tl_frame - a + 1) / (b - a)
            k = {"out": k, "in": 1 - (tl_frame - a) / (b - a), "hold": 1.0}[mode]
            f = f * (1 - k) + np.array(col, np.float32) / 255 * k
    return (np.clip(f, 0, 1) * 255 + 0.5).astype(np.uint8)


def decode(clip):
    name, fn, ss, n, rev, *_ = clip
    if not fn:
        return np.zeros((n, H, W, 3), np.uint8)
    vf = f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},setsar=1,fps={FPS}"
    if rev:
        vf += ",reverse"
    cmd = [FFMPEG, "-v", "error", "-ss", f"{ss:.3f}", "-i", os.path.join(MEDIA, fn), "-frames:v" if not rev else "-t",
           str(n) if not rev else f"{n / FPS + 0.02:.3f}", "-vf", vf, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    fr = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    if len(fr) < n:
        fr = np.concatenate([fr, np.repeat(fr[-1:], n - len(fr), 0)])
    return fr[:n]


def make_c11():
    out = os.path.join(MEDIA, "c11.mp4")
    if os.path.exists(out):
        return
    src = os.path.join(MEDIA, "c11src.mp4")
    fc = ("[0:v]trim=0:0.5,setpts=PTS-STARTPTS[a];[0:v]trim=0.5:1.25,setpts=(PTS-STARTPTS)/3[b];"
          "[0:v]trim=1.25,setpts=PTS-STARTPTS[c];[a][b][c]concat=n=3:v=1:a=0,fps=24[v]")
    subprocess.run([FFMPEG, "-v", "error", "-y", "-i", src, "-filter_complex", fc, "-map", "[v]",
                    "-c:v", "libx264", "-crf", "10", "-preset", "slow", "-pix_fmt", "yuv420p", out], check=True)


def plates(only=None):
    os.makedirs(PLATES, exist_ok=True)
    make_c11()
    for clip in CLIPS:
        if only and clip[0] not in only:
            continue
        frames = decode(clip)
        out = os.path.join(PLATES, f"{clip[0]}.mov")
        enc = subprocess.Popen([FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                                "-r", str(FPS), "-i", "-", "-c:v", "prores_ks", "-profile:v", "3", "-vendor", "apl0",
                                "-pix_fmt", "yuv422p10le", out], stdin=subprocess.PIPE)
        for i, fr in enumerate(frames):
            enc.stdin.write(process(fr, clip[5] + i, clip, i).tobytes())
        enc.stdin.close()
        enc.wait()
        print("plate", clip[0], len(frames), flush=True)


def stills(times):
    os.makedirs(os.path.join(ROOT, "prev"), exist_ok=True)
    make_c11()
    for t in times:
        fr = int(round(float(t) * FPS))
        clip = clip_at(fr)
        frames = decode(clip)
        i = fr - clip[5]
        out = process(frames[i], fr, clip, i)
        g = grade.apply(out.astype(np.float32) / 255, clip[6])
        Image.fromarray((g * 255 + 0.5).astype(np.uint8)).save(os.path.join(ROOT, "prev", f"t{float(t):05.2f}.jpg"), quality=88)
        print("still", t, clip[0])


if __name__ == "__main__":
    if sys.argv[1] == "plates":
        plates(sys.argv[2:] or None)
    else:
        stills(sys.argv[2:])
