"""Звуковая дорожка видео Иай: wav-звуки приёма по моментам из лога («iai_sound имя с тон»), время от кадра 10."""
import sys, wave
import numpy as np

log, snd, out = sys.argv[1:4]
SR = 44100
OFF = 10 / 30.0                       # видео начинается за 10 кадров до нажатия V
track = np.zeros(SR * 14)
for line in open(log, encoding="utf-8", errors="ignore"):
    if not line.startswith("iai_sound"):
        continue
    _, name, t, pitch = line.split()
    w = wave.open(f"{snd}/iai_{name}.wav")
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32767
    p = float(pitch)
    if abs(p - 1.0) > 1e-3:
        x = np.interp(np.arange(0, len(x), p), np.arange(len(x)), x)
    i = int((float(t) + OFF) * SR)
    track[i:i + len(x)] += x[: max(0, len(track) - i)]
track /= max(1.0, np.abs(track).max())
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((track * 32767).astype(np.int16).tobytes())
print("audio ok")
