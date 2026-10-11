"""Фоновый гул города (петля 40 с) → mods/pax_rpg/sounds/city_bed.ogg. Синтез: «толпа» — много голосов из шума
через форманты гласных с ритмом слогов, далёкий ветер. Без чужих записей — лицензия чистая.
    python pax_rpg/dev/sfx/city_ambience.py   (нужны numpy, scipy, ffmpeg)
"""
import os
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt

SR, DUR, FADE = 32000, 40.0, 3.0
rng = np.random.default_rng(7)
n = int(SR * (DUR + FADE))
t = np.arange(n) / SR
VOWELS = [(730, 1090), (530, 1840), (270, 2290), (570, 840), (440, 1020), (300, 870)]


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def lp(x, f):
    return sosfilt(butter(2, f, "lowpass", fs=SR, output="sos"), x)


out = np.zeros(n)
for v in range(46):                                   # голоса: далёкие тише и глуше
    dist = rng.uniform(0.2, 1.0)
    pitch = rng.uniform(95, 230)
    src = np.sin(2 * np.pi * pitch * (1 + 0.03 * np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * t)) * t)
    src = np.sign(src) * np.abs(src) ** 0.3 + 0.4 * rng.standard_normal(n)
    voice = np.zeros(n)
    f1, f2 = VOWELS[rng.integers(len(VOWELS))]
    voice = bp(src, f1 * 0.8, f1 * 1.25) + 0.6 * bp(src, f2 * 0.85, f2 * 1.2)
    syl = np.clip(np.sin(2 * np.pi * rng.uniform(3.0, 5.5) * t + rng.uniform(0, 6)), 0, 1) ** 2
    talk = np.zeros(n)                                 # фразы с паузами
    pos = int(rng.uniform(0, 4) * SR)
    while pos < n:
        ln = int(rng.uniform(1.0, 4.0) * SR)
        talk[pos:pos + ln] = 1.0
        pos += ln + int(rng.uniform(1.5, 7.0) * SR)
    talk = lp(talk, 3.0)
    out += lp(voice * syl * talk, 2600 - 1600 * dist) * (1.1 - dist) * 0.5
wind = lp(rng.standard_normal(n), 400) * (0.6 + 0.4 * lp(rng.standard_normal(n), 0.2) * 30)
out = lp(out, 3200) + 0.25 * wind
f = int(FADE * SR)                                     # петля: хвост вплетается в начало
m = int(DUR * SR)
loop = out[:m].copy()
w = np.linspace(0, 1, f)
loop[:f] = loop[:f] * w + out[m:m + f] * (1 - w)
loop = loop / np.max(np.abs(loop)) * 0.5
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
dst = os.path.join(root, "mods", "pax_rpg", "sounds", "city_bed.ogg")
pcm = (loop * 32767).astype("<i2").tobytes()
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                "-c:a", "libvorbis", "-q:a", "4", dst], input=pcm, check=True)
print(dst, os.path.getsize(dst))
