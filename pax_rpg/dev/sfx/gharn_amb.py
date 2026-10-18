"""Заглушки 3D-звуков Гхарна (синтез numpy): петли 20–30 с → mods/pax_rpg/sounds/amb/<имя>.ogg.
Автор потом заменит их на настоящие записи с теми же именами — расстановка в gharn.json («sound»).
    python3 pax_rpg/dev/sfx/gharn_amb.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "mods", "pax_rpg", "sounds", "amb")
rng = np.random.default_rng(1047)


def noise(n):
    return rng.standard_normal(n)


def lp(x, a):                      # однополюсный ФНЧ, a — 0..1 (больше — темнее)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = acc * a + v * (1 - a)
        y[i] = acc
    return y


def bp(x, f, q=4.0):               # резонатор (полосовой) на частоте f
    w = 2 * np.pi * f / SR
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    for i in range(2, len(x)):
        y[i] = x[i] - a1 * y[i - 1] - a2 * y[i - 2]
    return y * (1 - r)


def env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / d)


def place(buf, snd, t):
    i = int(t * SR)
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[:j - i]


def loopify(x, fade=1.0):          # петля без щелчка: хвост перекрёстно сводится с началом
    n = int(fade * SR)
    x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return x[:-n]


def save(name, x, gain=0.7):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    print(name, "%.1f s" % (len(x) / SR))


def anvil(f0=880.0):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    parts = [(1.0, 1.0, 0.5), (2.76, 0.6, 0.35), (5.4, 0.35, 0.2), (8.9, 0.2, 0.12)]
    s = sum(a * np.sin(2 * np.pi * f0 * k * t) * np.exp(-t / d) for k, a, d in parts)
    return s + noise(n) * np.exp(-t / 0.01) * 0.6


def forge(sec=24):
    n = sec * SR
    x = lp(noise(n), 0.985) * 0.35                          # гул горна
    x += lp(noise(n), 0.9) * (0.15 + 0.1 * np.sin(np.arange(n) / SR * 2 * np.pi * 0.3))
    t = 0.6
    while t < sec - 2:
        k = rng.integers(2, 5)
        for j in range(k):                                  # серия ударов молота
            place(x, anvil(rng.uniform(820, 960)) * rng.uniform(0.7, 1.0), t)
            t += rng.uniform(0.45, 0.6)
        t += rng.uniform(1.5, 3.5)
    return loopify(x)


def murmur(n, voices=10, base=180.0):
    x = np.zeros(n)
    for _ in range(voices):                                 # «голоса»: шум сквозь форманты, слогами
        v = noise(n)
        f = rng.uniform(base, base * 2.2)
        v = bp(v, f, 6) * 2 + bp(v, f * rng.uniform(2.5, 3.5), 8)
        syl = rng.uniform(3, 6)
        am = np.clip(np.sin(np.arange(n) / SR * 2 * np.pi * syl + rng.uniform(0, 6)), 0, None) ** 2
        talk = np.repeat(rng.random(n // SR + 2) < 0.6, SR)[:n]
        x += v * am * talk * rng.uniform(0.4, 1.0)
    return x


def market(sec=28):
    n = sec * SR
    x = murmur(n, 16) + lp(noise(n), 0.97) * 0.4
    for _ in range(10):                                     # выкрики зазывал
        t = rng.uniform(1, sec - 2)
        m = int(0.8 * SR)
        place(x, bp(noise(m), rng.uniform(300, 420), 10) * 6 * env(m, 0.05, 0.4), t)
    return loopify(x)


def tavern(sec=26):
    n = sec * SR
    x = murmur(n, 12, 160) + lp(noise(n), 0.97) * 0.3
    beat = 60 / 96
    t = 0.0
    while t < sec:                                          # барабан морин-хуура вдали
        m = int(0.4 * SR)
        tt = np.arange(m) / SR
        place(x, np.sin(2 * np.pi * 90 * tt) * np.exp(-tt / 0.12) * 1.2, t)
        t += beat * (1 if rng.random() < 0.7 else 0.5)
    for _ in range(6):                                      # «смех» — серии коротких слогов
        t = rng.uniform(1, sec - 3)
        for j in range(rng.integers(4, 8)):
            m = int(0.12 * SR)
            place(x, bp(noise(m), rng.uniform(500, 700), 8) * 5 * env(m, 0.01, 0.06), t + j * 0.16)
    return loopify(x)


def drum(sec=24):
    n = sec * SR
    x = lp(noise(n), 0.99) * 0.1
    pat = [0, 0.5, 1.0, 1.25, 1.5]
    t = 0.0
    while t < sec - 2:
        for p in pat:                                       # бубен шамана: низкий удар + бряцание
            m = int(0.6 * SR)
            tt = np.arange(m) / SR
            hit = np.sin(2 * np.pi * (70 + 40 * np.exp(-tt / 0.05)) * tt) * np.exp(-tt / 0.25)
            place(x, hit * 1.4, t + p)
            place(x, bp(noise(int(0.2 * SR)), 5200, 2) * env(int(0.2 * SR), 0.002, 0.08) * 0.8, t + p)
        t += 2.0 + (0.0 if rng.random() < 0.7 else 2.0)
    return loopify(x)


def fire(sec=20):
    n = sec * SR
    x = lp(noise(n), 0.995) * 0.6 + lp(noise(n), 0.94) * 0.15
    for _ in range(int(sec * 9)):                           # треск поленьев
        m = int(0.02 * SR)
        place(x, noise(m) * env(m, 0.0005, 0.004) * rng.uniform(0.5, 2.0), rng.uniform(0, sec - 0.1))
    return loopify(x)


def water(sec=20):
    n = sec * SR
    x = bp(noise(n), 900, 0.7) * 0.6 + lp(noise(n), 0.9) * 0.3
    for _ in range(int(sec * 25)):                          # бульканье
        m = int(0.05 * SR)
        tt = np.arange(m) / SR
        f = rng.uniform(400, 1200)
        place(x, np.sin(2 * np.pi * f * (1 + 2 * tt) * tt) * np.exp(-tt / 0.015) * 0.3, rng.uniform(0, sec - 0.1))
    return loopify(x)


def stable(sec=26):
    n = sec * SR
    x = lp(noise(n), 0.96) * 0.15
    for _ in range(int(sec * 1.5)):                         # шорох сена
        m = int(0.4 * SR)
        place(x, bp(noise(m), 3000, 1.5) * env(m, 0.05, 0.15) * 0.4, rng.uniform(0, sec - 0.5))
    for _ in range(4):                                      # фырканье
        m = int(0.7 * SR)
        place(x, bp(noise(m), rng.uniform(250, 400), 3) * 3 * env(m, 0.02, 0.2), rng.uniform(1, sec - 1))
    return loopify(x)


def flags(sec=20):
    n = sec * SR
    gust = lp(np.abs(noise(n)), 0.9995) * 3
    x = bp(noise(n), 260, 1.2) * gust
    flap = np.clip(np.sin(np.arange(n) / SR * 2 * np.pi * 7.0), 0, None) ** 6
    x += bp(noise(n), 1800, 2) * flap * gust * 0.5
    return loopify(x)


if __name__ == "__main__":
    for name, fn, g in (("forge", forge, 0.8), ("market", market, 0.7), ("tavern", tavern, 0.7), ("shaman_drum", drum, 0.8),
                        ("fire", fire, 0.6), ("water", water, 0.6), ("stable", stable, 0.6), ("flags", flags, 0.5)):
        save(name, fn(), g)
