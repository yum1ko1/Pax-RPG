"""Синтез звука взмаха тяжёлого двуручного меча: 6 вариантов → mods/pax_rpg/sounds/swing_1..6.wav.

    python pax_rpg/dev/audio/sword_swing.py [--preview спектрограмма.png]

Из чего звук (всё — numpy, без сэмплов):
  - свист: розовый шум через полосовой фильтр, центр которого ползёт вверх и обратно (клинок подходит и уходит),
    громкость медленно нарастает и быстро срывается — тяжёлый меч разгоняется долго;
  - гул: тот же шум через низкочастотный фильтр 70–160 Гц — масса клинка;
  - звон: несколько негармонических затухающих частот — металл в начале движения;
  - бряцание доспеха: короткие щелчки высокочастотного шума в первые 0,15 с.
Варианты отличаются случайностью шума, высотой (−3…+2 полутона), длительностью и тембром.
"""
import argparse
import math
import wave
from pathlib import Path

import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parents[3] / "mods/pax_rpg/sounds"
VARIANTS = [  # (полутоны, длительность с, сила гула, сила звона, сид)
    (0.0, 1.00, 1.0, 1.0, 11),
    (-1.0, 1.05, 1.15, 0.9, 23),
    (-2.0, 1.10, 1.3, 0.8, 37),
    (-3.0, 1.15, 1.45, 0.7, 41),
    (1.0, 0.95, 0.9, 1.1, 53),
    (2.0, 0.90, 0.8, 1.2, 67),
]


def pink(n: int, rng) -> np.ndarray:
    """Розовый шум (1/f) — гуще белого, звучит как воздух."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    x = np.fft.irfft(spec / np.sqrt(f), n)
    return x / np.max(np.abs(x))


def biquad_bp(x: np.ndarray, fc: np.ndarray, q: float) -> np.ndarray:
    """Полосовой фильтр с меняющейся частотой (коэффициенты — каждые 32 отсчёта)."""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for s in range(0, len(x), 32):
        w = 2 * math.pi * float(fc[s]) / SR
        al = math.sin(w) / (2 * q)
        a0 = 1 + al
        b0, b2 = al / a0, -al / a0
        a1, a2 = -2 * math.cos(w) / a0, (1 - al) / a0
        for i in range(s, min(s + 32, len(x))):
            v = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1 = x1, x[i]
            y2, y1 = y1, v
            y[i] = v
    return y


def lowpass(x: np.ndarray, fc: float) -> np.ndarray:
    a = math.exp(-2 * math.pi * fc / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for _ in range(2):                         # два прохода — круче срез
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y.copy()
    return y


def swing(semi: float, dur: float, body: float, ring: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(SR * dur)
    t = np.arange(n) / SR
    k = 2 ** (semi / 12)                       # высота: выше — светлее и быстрее
    peak = 0.58 * dur + rng.uniform(-0.03, 0.03)
    # огибающая: долгий разгон (тяжесть), быстрый срыв
    rise = np.clip(t / peak, 0, 1) ** 2.6
    fall = np.exp(-np.clip(t - peak, 0, None) / (0.10 * dur))
    env = rise * fall
    # свист: центр полосы 260 → 950 → 320 Гц (×k)
    u = t / peak
    fc = np.where(u < 1, 260 + 690 * u ** 1.8, 320 + 630 * np.exp(-(t - peak) / 0.09)) * k
    air = biquad_bp(pink(n, rng), fc, 1.4)
    air2 = biquad_bp(pink(n, rng), fc * 2.3, 2.5) * 0.35   # верхний «шелест» рассекаемого воздуха
    whoosh = (air + air2) * env
    # гул массы клинка
    rumble = lowpass(pink(n, rng), 150 * k) * env ** 0.8 * 2.2 * body
    # металлический звон в начале движения (негармонические частоты)
    ring_sig = np.zeros(n)
    for f, a, d in ((1187, 1.0, 0.35), (1733, 0.6, 0.25), (2519, 0.4, 0.18), (3361, 0.25, 0.12)):
        ff = f * k * rng.uniform(0.98, 1.02)
        ring_sig += a * np.sin(2 * math.pi * ff * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    ring_sig *= np.clip(t / 0.01, 0, 1) * 0.05 * ring
    # бряцание доспеха: 3–4 щелчка
    rattle = np.zeros(n)
    hp = pink(n, rng)
    hp = hp - lowpass(hp, 2500)
    for _ in range(rng.integers(3, 5)):
        c = rng.uniform(0.02, 0.16)
        rattle += hp * np.exp(-((t - c) / 0.004) ** 2) * rng.uniform(0.3, 0.6)
    x = whoosh + rumble + ring_sig + rattle * 0.22
    fade = int(0.005 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.max(np.abs(x)) * 10 ** (-1 / 20)       # пик −1 дБ


def write_wav(path: Path, x: np.ndarray) -> None:
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def spectrogram(sounds: list, path: str) -> None:
    from PIL import Image
    rows = []
    for x in sounds:
        win, hop = 1024, 256
        frames = [np.abs(np.fft.rfft(x[i:i + win] * np.hanning(win)))[:400]
                  for i in range(0, len(x) - win, hop)]
        s = 20 * np.log10(np.array(frames).T + 1e-6)
        s = np.clip((s - s.max() + 70) / 70, 0, 1)[::-1]
        img = Image.fromarray((s * 255).astype(np.uint8)).resize((600, 160))
        rows.append(img)
    out = Image.new("L", (600, 165 * len(rows)))
    for i, r in enumerate(rows):
        out.paste(r, (0, i * 165))
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    sounds = []
    for i, v in enumerate(VARIANTS, 1):
        x = swing(*v)
        write_wav(OUT / f"swing_{i}.wav", x)
        sounds.append(x)
        print(f"swing_{i}.wav  {len(x) / SR:.2f} c  тон {v[0]:+.0f}")
    if a.preview:
        spectrogram(sounds, a.preview)


if __name__ == "__main__":
    main()
