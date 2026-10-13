"""Звуки приёма «Иай: остановка времени» — синтез (своё, без чужих записей). → mods/pax_rpg/sounds/iai_*.wav
timestop — гулкий «дон» (негармонические обертоны), нисходящий свип «вжууум», шумовой удар, затухающие тики
часов, хвост реверберации; rewind — он же задом наперёд; draw / sheathe — щелчок цубы (металлический транзиент
+ звон) со скольжением стали; slash — свист клинка (полосовой шум со свипом) и звонкий хвост; heart — удары сердца.
    python3 pax_rpg/dev/sfx/make_iai_sounds.py"""
import os, wave
import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "sounds")
rng = np.random.default_rng(1047)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, a, d):
    x = np.arange(n) / SR
    return np.minimum(1.0, x / max(a, 1e-4)) * np.exp(-x / max(d, 1e-4))


def bandnoise(n, lo, hi):
    x = rng.standard_normal(n)
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    y = np.fft.irfft(f, n)
    return y / (np.abs(y).max() + 1e-9)


def sweepnoise(n, f0, f1, q=0.25):
    """Шум через скользящий резонатор (свист)."""
    x = rng.standard_normal(n)
    y = np.zeros(n)
    y1 = y2 = 0.0
    for i in range(n):
        fc = f0 * (f1 / f0) ** (i / n)
        w = 2 * np.pi * fc / SR
        r = 1 - q * w
        y0 = x[i] * (1 - r) + 2 * r * np.cos(w) * y1 - r * r * y2
        y[i] = y0
        y2, y1 = y1, y0
    return y / (np.abs(y).max() + 1e-9)


def reverb(x, mix=0.35, decay=0.82):
    out = x.copy()
    for d, g in ((1557, decay), (1617, decay * 0.97), (1491, decay * 0.95), (1422, decay * 0.93)):
        y = np.zeros(len(x) + SR * 2)
        y[:len(x)] += x
        for i in range(d, len(y)):
            y[i] += y[i - d] * g
        out = np.pad(out, (0, len(y) - len(out)))
        out += y * mix / 4
    return out


def ring(n, freqs, decay):
    x = np.arange(n) / SR
    y = sum(np.sin(2 * np.pi * f * x + rng.uniform(0, 6)) * a for f, a in freqs)
    return y * np.exp(-x / decay)


def save(name, y, peak=0.9):
    y = y / (np.abs(y).max() + 1e-9) * peak
    loud = np.nonzero(np.abs(y) > 0.004)[0]                    # хвост тишины — обрезать
    if len(loud):
        y = y[:min(len(y), loud[-1] + int(SR * 0.05))]
    fade = min(len(y), 800)
    y[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    print(name, round(len(y) / SR, 2), "с")
    return y


def timestop():
    n = int(SR * 1.8)
    x = np.arange(n) / SR
    dong = ring(n, [(146, 1.0), (219, 0.6), (311, 0.45), (437, 0.3), (622, 0.2), (877, 0.12)], 0.9)
    f = 520 * np.exp(-x * 3.2) + 55                            # «вжууум» вниз
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.02, 0.7) * 0.9
    sub = np.sin(2 * np.pi * 42 * x) * env(n, 0.005, 0.8) * 1.1
    hit = bandnoise(n, 300, 6000) * env(n, 0.001, 0.08) * 0.8
    ticks = np.zeros(n)
    for k, at in enumerate((0.55, 0.85, 1.12, 1.36)):           # тики часов — затухают и замедляются
        i = int(at * SR)
        m = min(int(0.03 * SR), n - i)
        ticks[i:i + m] += ring(m, [(3200, 1), (4700, 0.6)], 0.006) * (0.5 / (k + 1))
    y = dong * 0.8 + sweep + sub + hit + ticks
    return reverb(y, 0.4, 0.85)[:int(SR * 2.6)]


def click(deeper=False):
    n = int(SR * 0.5)
    tr = bandnoise(n, 1500, 9000) * env(n, 0.0005, 0.012)
    rn = ring(n, [(2850, 1), (4120, 0.7), (6310, 0.4)] if not deeper else [(2100, 1), (3350, 0.7), (5200, 0.4)], 0.09)
    thunk = np.sin(2 * np.pi * (180 if not deeper else 120) * np.arange(n) / SR) * env(n, 0.001, 0.05)
    slide = np.zeros(n)
    s = sweepnoise(int(SR * 0.16), 2500, 5500 if not deeper else 1800, 0.18) * 0.25
    pre = np.concatenate([s * np.hanning(len(s)), np.zeros(n)])[:n] if deeper else np.zeros(n)
    y = tr * 0.9 + rn * 0.5 + thunk * 0.7
    if deeper:                                                  # в ножны: сперва скольжение стали, потом щелчок
        y = np.concatenate([pre[:int(SR * 0.16)], y])[:n + int(SR * 0.16)]
    else:                                                       # из ножен: щелчок и короткий «шшинг»
        sh = np.zeros(n)
        m = min(len(s), n - int(SR * 0.01))
        sh[int(SR * 0.01):int(SR * 0.01) + m] = (s * np.hanning(len(s)))[:m] * 0.6
        y = y + sh
    return reverb(y, 0.18, 0.7)


def slash():
    n = int(SR * 0.42)
    w = sweepnoise(n, 700, 3400, 0.22) * np.hanning(n) ** 0.7
    sting = ring(n, [(3600, 1), (5100, 0.5)], 0.05) * 0.25
    sting = np.pad(sting, (int(SR * 0.17), 0))[:n]
    return reverb(w + sting, 0.2, 0.7)


def heart():
    n = int(SR * 0.9)
    x = np.arange(n) / SR
    y = np.zeros(n)
    for at, a in ((0.0, 1.0), (0.22, 0.7)):
        i = int(at * SR)
        m = n - i
        y[i:] += np.sin(2 * np.pi * 52 * x[:m]) * env(m, 0.005, 0.07) * a
    return y


os.makedirs(OUT, exist_ok=True)
ts = timestop()
tsc = save("iai_timestop.wav", ts)
save("iai_rewind.wav", tsc[::-1].copy())
save("iai_draw.wav", click(False))
save("iai_sheathe.wav", click(True))
save("iai_slash.wav", slash())
save("iai_heart.wav", heart(), 0.8)
