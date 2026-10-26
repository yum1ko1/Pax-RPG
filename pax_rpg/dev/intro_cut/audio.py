# Звук ролика: стемы (музыка, голоса, эффекты, атмосфера, удары) + финальный микс −14 LUFS.
import os, sys, glob, json, subprocess, re
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
SRC = os.environ.get("PAX_SRC", os.path.expanduser(r"~\Downloads"))
DUR = TOTAL / FPS
SR = 48000


def find(*pats):
    for p in pats:
        g = sorted(glob.glob(os.path.join(SRC, p)))
        if g:
            return g[0]
    raise FileNotFoundError(pats)


S = {
    "S01": "*High_altitude_wind*", "S02": "*Soft_long_whoosh_of_a_camera_flying_down*", "S03": "*Distant_huge_army*",
    "S04": "*Powerful_deep_ground_rumble*", "S05": "*Huge_loud_explosion_of_a_giant_stone_gate*",
    "S06": "*Colossal_pillar*", "S07": "*whole_sky_cracking*", "S08": "*Huge_vortex_swirling*",
    "S09": "*Fast_whoosh_of_a_camera_diving*", "S10": "*Large_fantasy_battle*", "S11": "*Close_heavy_katana*",
    "S12": "*Two_magical_streaks*", "S13": "*Close_massive_clash*", "S14": "*Small_golden_rings*",
    "S15": "*Slow-motion_sound_design_a_thick*", "S16": "*Gigantic_magical_explosion*", "S17": "*piercing_high-pitched_ringing*",
    "S18": "*Two_heavy_objects_falling*", "S19": "*Two_magical_auras*", "S20": "*Smooth_low_whoosh*",
    "S21": "*vortex_in_the_sky_collapsing*", "S22": "*Two_heavy_swords_swinging*", "S23": "*Huge_close_sword_clash*",
    "S24": "*Burning_city*",
    "N1": "*Giant_iron_chains_straining*", "N2": "*Rocks_and_debris_violently_sucked*",
    "N3": "*Massive_shockwave_blast*", "N4": "*huge_flaming_boulder*", "N5": "*Two_powerful_magical_energies*",
    "N6": "*earth_heaving_up*",
}
VO = {"l1": "*21_24_57_Celune*", "l2": "*21_27_26_Iru*", "l3": "*21_30_13_Iru*", "l4": "*21_32_10_Celune*",
      "fs": "*21_33_17_Celune*", "fi": "*21_34_02_Iru*"}

ST = "aformat=sample_rates=48000:channel_layouts=stereo"
MO = "aformat=sample_rates=48000:channel_layouts=mono"
DUCK = "volume='1-0.5*clip((t-18.7)/0.3,0,1)*clip((37.69-t)/0.08,0,1)':eval=frame"   # под диалогом сестёр
GATE = "volume='1-clip((t-37.69)/0.03,0,1)*clip((37.917-t)/0.01,0,1)':eval=frame"   # 0,23 с тишины перед взрывом
VFX = ("highpass=f=110,acompressor=threshold=-30dB:ratio=3:attack=5:release=120:makeup=2,"
       "aecho=1.0:0.9:45|140:0.22|0.10,aecho=1.0:0.95:420|780:0.12|0.07")


def ms(t):
    return int(round(t * 1000))


def run(inputs, graph, out):
    cmd = [FFMPEG, "-v", "error", "-y"]
    for i in inputs:
        cmd += ["-i", i]
    cmd += ["-filter_complex", graph, "-map", "[o]", "-ar", "48000", "-c:a", "pcm_f32le", out]
    subprocess.run(cmd, check=True)


def mixdown(parts, inputs, out, extra=""):
    labels = "".join(f"[part{i}]" for i in range(len(parts)))
    g = ";".join(f"{p}[part{i}]" for i, p in enumerate(parts))
    g += f";anullsrc=r=48000:cl=stereo,atrim=0:{DUR}[z];[z]{labels}amix=inputs={len(parts) + 1}:normalize=0:duration=first"
    g += (("," + extra) if extra else "") + "[o]"
    run(inputs, g, out)


def music(out):
    # Темп ~146 BPM. Замедления удлиняют картинку ровно на такт: такт повторяется, шов спрятан под ударами.
    a, b = find("Final Assault.mp3", "*Final_Assault.mp3"), find("Final Assault (1).mp3", "*Final_Assault_1.mp3")
    parts = [f"[0:a]{ST},atrim=9.65:34.975,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=1.0,afade=t=out:st=25.30:d=0.025",
             f"[0:a]{ST},atrim=33.30:36.742,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.025,afade=t=out:st=3.382:d=0.06,"
             f"adelay=25300|25300",
             f"[0:a]{ST},atrim=108.5:117.45,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.06,afade=t=out:st=8.90:d=0.05,"
             f"adelay=28759|28759",
             f"[0:a]{ST},atrim=131.43:136.875,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.3,afade=t=out:st=5.42:d=0.025,"
             f"adelay=41967|41967",
             f"[0:a]{ST},atrim=135.13:139.013,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.025,afade=t=out:st=3.833:d=0.05,"
             f"adelay=47387|47387",
             # меню: бочка дропа (23,35 с во втором файле) бьёт ровно в кадр появления меню
             f"[1:a]{ST},atrim=23.345:33.385,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.004,afade=t=out:st=8.6:d=1.44,"
             f"adelay={ms(MENU_AT)}|{ms(MENU_AT)}"]
    mixdown(parts, [a, b], out, f"{DUCK},{GATE}")


FAR = "apad=pad_dur=1.6,lowpass=f=1400,highpass=f=90,aecho=0.8:0.7:190|430|780:0.42|0.30|0.18"   # звук вдали
# (ключ, задержка с, громкость dB, доп. фильтр[, без приглушения под диалогом])
SFX = [("S02", 2.6, -3, ""), ("N1", 4.2, -9, "afade=t=in:st=0:d=0.3,afade=t=out:st=2.5:d=0.3," + FAR),
       ("S04", 4.9, -7, "afade=t=in:st=0:d=0.4"), ("S05", 6.95, -2, ""),
       ("S06", 6.75, -10, "afade=t=out:st=4.2:d=0.8"), ("N2", 9.4, -5, "afade=t=in:st=0:d=0.4"),
       ("S07", 11.8, -9, ""), ("S08", 12.9, -3, "afade=t=out:st=1.7:d=0.4"),
       ("N3", 14.9, -1, ""), ("N4", 16.8, -5, ""),
       ("S11", 22.88, 5, "asetrate=36000,aresample=48000", True),                  # нодати в слоу-мо — ниже и тяжелее
       ("S12", 25.458, -5, "afade=t=out:st=2.8:d=0.5"),
       ("S13a", 26.217, -9, "atrim=0:0.8,asetpts=PTS-STARTPTS," + FAR, True),
       ("S13a", 27.017, -10, "atrim=0:0.8,asetpts=PTS-STARTPTS," + FAR, True),
       ("S13b", 28.757, -3, "atrim=1.55,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.03,afade=t=out:st=0.85:d=0.4", True),
       ("N5", 28.667, -7, "afade=t=out:st=2.2:d=0.6", True),
       ("S14", 31.257, 18, "afade=t=in:st=0:d=0.1"), ("S15", 32.76, 6, "afade=t=out:st=2.6:d=0.4"),
       ("S16", 37.92, -1, "afade=t=out:st=2.6:d=1.4"), ("S17", 38.932, -24, "afade=t=in:st=0:d=0.5,afade=t=out:st=2.0:d=1.4"),
       ("S18", 42.382, -3, ""), ("S19", 43.132, 0, "afade=t=in:st=0:d=0.2,afade=t=out:st=1.4:d=0.6"), ("S20", 44.432, 0, ""),
       ("S21", 45.632, -4, "afade=t=out:st=2.4:d=0.6"), ("N6", 45.592, -3, "afade=t=out:st=2.4:d=0.6"),
       ("S22", 48.013, -4, "asetrate=29800,aresample=48000,afade=t=out:st=2.58:d=0.24"),   # замах в слоу-мо
       ("S23", 50.833, 8, "afade=t=out:st=0.4:d=0.8"), ("S21", MENU_AT, -12, "afade=t=out:st=2.0:d=1.0")]
AMB = [("S01", 0.0, 0, ""), ("S03", 4.6, -8, "afade=t=in:st=0:d=0.3"),
       ("S10", 15.25, -8, "afade=t=in:st=0:d=0.4,afade=t=out:st=11.3:d=0.7"),
       ("S10", 42.732, -14, "atrim=2:8.7,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=6.1:d=0.6"),
       ("S24", MENU_AT, 4, "atrim=0:10.04,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.5,afade=t=out:st=8.6:d=1.4")]


def bank(lst, out, duck=True):
    files, parts = [], []
    for item in lst:
        k, t, db, f = item[:4]
        free = len(item) > 4 and item[4]
        key = k.rstrip("ab")
        files.append(find(S[key]))
        idx = len(files) - 1
        chain = f"[{idx}:a]{ST}" + (f",{f}" if f else "") + f",volume={db}dB,adelay={ms(t)}|{ms(t)}"
        if duck and not free:
            chain += "," + DUCK
        parts.append(chain)
    mixdown(parts, files, out, GATE)


def voices(out):
    f = {k: find(p) for k, p in VO.items()}
    ins = [f["l1"], f["l2"], f["l2"], f["l3"], f["l4"], f["l4"], f["fi"], f["fs"], f["fi"], f["fs"]]
    V = lambda db, t: f"volume={db}dB,alimiter=limit=0.7:level=false,{ST},adelay={ms(t)}|{ms(t)}"
    parts = [
        f"[0:a]{MO},{VFX},{V(20.5, 19.0)}",                                             # «Остановись, сестра.»
        f"[1:a]{MO},atrim=0.15:2.3,asetpts=PTS-STARTPTS,{VFX},{V(13.5, 21.88)}",          # «Небо не вечно…»
        f"[2:a]{MO},atrim=3.05:4.36,asetpts=PTS-STARTPTS,{VFX},{V(13.5, 26.40)}",         # «Как и мы.»
        f"[3:a]{MO},atrim=0.05:3.0,asetpts=PTS-STARTPTS,{VFX},{V(11.5, 30.717)}",         # смех и «Я не исчезну.»
        f"[4:a]{MO},atrim=0.05:2.3,asetpts=PTS-STARTPTS,{VFX},{V(13.5, 33.667)}",         # «Мир не заплатит…»
        f"[5:a]{MO},atrim=2.55:4.2,asetpts=PTS-STARTPTS,{VFX},{V(13.5, 36.34)}",          # «…за твой страх.»
        # финал на чёрном: фраза (голос Иру перетекает в голос Селунэ), долгая пауза, «Arise» обеими голосами разом — тихо
        f"[6:a]{MO},atrim=0.2:2.75,asetpts=PTS-STARTPTS,volume='1-0.65*t/2.5':eval=frame[ia2];"
        f"[7:a]{MO},atrim=0.2:2.65,asetpts=PTS-STARTPTS,volume='0.35+0.65*t/2.4':eval=frame[sa2];"
        f"[ia2][sa2]amix=inputs=2:normalize=0,{VFX},{V(13, 51.5)}",
        f"[8:a]{MO},atrim=3.05:3.97,asetpts=PTS-STARTPTS[ib2];[9:a]{MO},atrim=3.3:4.44,asetpts=PTS-STARTPTS[sb2];"
        f"[ib2][sb2]amix=inputs=2:normalize=0,volume=0.75,{VFX},{V(13, 56.30)}",
    ]
    mixdown(parts, ins, out, GATE)


def synth_impacts(out):
    # низкие удары (саб-бум с хлопком), обратные нарастания перед кульминациями
    n = int(DUR * SR)
    buf = np.zeros(n, np.float32)
    rng = np.random.default_rng(3)

    def boom(t0, gain, length=1.8, f0=58, f1=27):
        m = int(length * SR)
        tt = np.arange(m) / SR
        f = f1 + (f0 - f1) * np.exp(-tt / 0.25)
        ph = 2 * np.pi * np.cumsum(f) / SR
        env = np.exp(-tt / (length / 3.2)) * np.clip(tt / 0.004, 0, 1)
        thump = rng.normal(0, 1, m) * np.exp(-tt / 0.03)
        thump = np.convolve(thump, np.ones(24) / 24, mode="same")
        s = (np.sin(ph) * 0.9 + np.sin(ph * 2) * 0.12 + thump * 0.5) * env * gain
        i = int(t0 * SR)
        buf[i:i + m] += s[:max(0, n - i)]

    def riser(t0, t1, gain, f0=180, f1=900):
        m = int((t1 - t0) * SR)
        tt = np.arange(m) / SR
        noise = rng.normal(0, 1, m)
        k = np.clip(tt / (t1 - t0), 0, 1)
        out_ = np.zeros(m)
        # фильтр с растущей частотой — однополюсный, коэффициент по частоте
        y = 0.0
        fc = f0 + (f1 - f0) * k ** 2
        a = np.exp(-2 * np.pi * fc / SR)
        for j in range(m):
            y = a[j] * y + (1 - a[j]) * noise[j]
            out_[j] = y
        env = k ** 2.2 * gain
        i = int(t0 * SR)
        buf[i:i + m] += (out_ * env * 3.0).astype(np.float32)

    boom(6.95, 0.55); boom(12.45, 0.40); boom(15.22, 0.50, 2.0); boom(23.679, 0.25, 1.0)
    boom(26.267, 0.05, 1.2, 70, 40); boom(27.067, 0.05, 1.2, 70, 40); boom(28.757, 0.60, 1.6)
    boom(37.932, 0.95, 3.2, 64, 22); boom(42.582, 0.60, 1.6); boom(45.692, 0.35, 2.4, 46, 24)
    boom(50.833, 0.80, 1.6); boom(MENU_AT, 0.60, 2.8, 50, 24)
    riser(27.667, 28.727, 0.22); riser(36.45, 37.69, 0.42, 120, 1400); riser(49.55, 50.80, 0.35, 150, 1200)
    buf *= 0.6
    buf[int(37.69 * SR):int(37.917 * SR)] = 0
    st = np.stack([buf, buf], -1)
    st = np.clip(st, -1, 1)
    import wave
    with wave.open(out, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype(np.int16).tobytes())


def master(stems, out):
    ins = list(stems)
    g = "".join(f"[{i}:a]" for i in range(len(ins))) + f"amix=inputs={len(ins)}:normalize=0,alimiter=limit=0.93:level=false[m]"
    tmp = out + ".tmp.wav"
    run(ins, g.replace("[m]", "[o]"), tmp)
    r = subprocess.run([FFMPEG, "-i", tmp, "-af", "loudnorm=I=-14:TP=-1:LRA=18:print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    js = json.loads(r[r.rindex("{"):r.rindex("}") + 1])
    ln = (f"loudnorm=I=-14:TP=-1:LRA=18:measured_I={js['input_i']}:measured_TP={js['input_tp']}:"
          f"measured_LRA={js['input_lra']}:measured_thresh={js['input_thresh']}:offset={js['target_offset']}:linear=true")
    run([tmp], f"[0:a]{ln},aresample=48000[o]", out)
    os.remove(tmp)
    print("master", js["input_i"], "->", "-14", flush=True)


if __name__ == "__main__":
    os.makedirs(AUDIO, exist_ok=True)
    p = lambda n: os.path.join(AUDIO, n)
    music(p("A_music.wav")); print("music", flush=True)
    voices(p("A_voice.wav")); print("voice", flush=True)
    bank(SFX, p("A_sfx.wav")); print("sfx", flush=True)
    bank(AMB, p("A_amb.wav")); print("amb", flush=True)
    synth_impacts(p("A_impacts.wav")); print("impacts", flush=True)
    master([p(x) for x in ("A_music.wav", "A_voice.wav", "A_sfx.wav", "A_amb.wav", "A_impacts.wav")], p("A_master.wav"))
