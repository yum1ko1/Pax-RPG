"""Синтез удара тяжёлого меча о землю: 3 варианта → mods/pax_rpg/sounds/impact_1..3.wav.

    python pax_rpg/dev/audio/ground_impact.py

Слои (numpy, без сэмплов): глухой «бум» — синус, падающий 95 → 38 Гц; хруст грунта — короткий всплеск
приглушённого шума; осыпь — мелкие камешки (щелчки шума) ещё ~0,5 с. Без металла и звона.
"""
import math
import wave
from pathlib import Path

import numpy as np

SR = 48000
OUT = Path(__file__).resolve().parents[3] / "mods/pax_rpg/sounds"
VARIANTS = [(0.0, 5), (-1.5, 17), (1.0, 29)]       # (полутоны, сид)


def lowpass(x: np.ndarray, fc: float, passes: int = 2) -> np.ndarray:
    a = math.exp(-2 * math.pi * fc / SR)
    for _ in range(passes):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y
    return x


def impact(semi: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    k = 2 ** (semi / 12)
    n = int(SR * 1.2)
    t = np.arange(n) / SR
    # бум: частота падает, фаза — интеграл частоты
    f = (38 + 57 * np.exp(-t / 0.07)) * k
    boom = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.32) * np.clip(t / 0.003, 0, 1)
    # хруст: всплеск шума, приглушённый
    crunch = lowpass(rng.standard_normal(n), 1400 * k) * np.exp(-t / 0.06) * 3.0
    # осыпь: камешки
    debris = np.zeros(n)
    src = lowpass(rng.standard_normal(n), 3000 * k, 1)
    for _ in range(40):
        c = rng.uniform(0.04, 0.6)
        debris += src * np.exp(-((t - c) / 0.003) ** 2) * rng.uniform(0.1, 0.5) * math.exp(-c / 0.25)
    x = boom * 1.0 + crunch * 0.55 + debris * 0.5
    fade = int(0.03 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.max(np.abs(x)) * 10 ** (-1 / 20)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (semi, seed) in enumerate(VARIANTS, 1):
        x = impact(semi, seed)
        pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
        with wave.open(str(OUT / f"impact_{i}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        print(f"impact_{i}.wav  тон {semi:+.1f}")


if __name__ == "__main__":
    main()
