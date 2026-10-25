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
    "S15": "*Slow-motion_sound_design_a_thick*", "S16": "*Gigantic_magical_explosion*", "S17": "*tinnitus*",
    "S18": "*Two_heavy_objects_falling*", "S19": "*Two_magical_auras*", "S20": "*Smooth_low_whoosh*",
    "S21": "*vortex_in_the_sky_collapsing*", "S22": "*Two_heavy_swords_swinging*", "S23": "*Huge_close_sword_clash*",
    "S24": "*Burning_city*",
}
VO = {"l1": "*21_24_57_Celune*", "l2": "*21_27_26_Iru*", "l3": "*21_30_13_Iru*", "l4": "*21_32_10_Celune*",
      "fs": "*21_33_17_Celune*", "fi": "*21_34_02_Iru*"}

ST = "aformat=sample_rates=48000:channel_layouts=stereo"
MO = "aformat=sample_rates=48000:channel_layouts=mono"
DUCK = ("volume='1-0.5*clip((t-21.9)/0.3,0,1)*clip((34.0-t)/0.08,0,1)-0.2*clip((t-28.5)/0.1,0,1)*clip((29.6-t)/0.2,0,1)"
        "-0.55*clip((t-46.2)/0.3,0,1)*clip((51.3-t)/0.5,0,1)':eval=frame")
GATE = "volume='1-clip((t-33.86)/0.03,0,1)*clip((34.09-t)/0.01,0,1)':eval=frame"   # 0,23 с тишины перед взрывом
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
    a, b = find("Final Assault.mp3", "*Final_Assault.mp3"), find("Final Assault (1).mp3", "*Final_Assault_1.mp3")
    parts = [f"[0:a]{ST},atrim=9.65:36.742,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=1.0,afade=t=out:st=27.03:d=0.06",
             f"[0:a]{ST},atrim=108.5:115.5,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.06,afade=t=out:st=6.4:d=0.6,adelay=27092|27092",
             f"[0:a]{ST},atrim=131.43:141.43,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.3,afade=t=out:st=7.7:d=2.3,adelay=38133|38133",
             f"[1:a]{ST},atrim=0:9.55,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.8,afade=t=out:st=8.3:d=1.25,adelay=46200|46200"]
    mixdown(parts, [a, b], out, f"{DUCK},{GATE}")


# (ключ, задержка с, громкость dB, доп. фильтр)
SFX = [("S02", 2.6, -3, ""), ("S04", 4.9, -4, "afade=t=in:st=0:d=0.4"), ("S05", 6.95, -2, ""),
       ("S06", 6.75, -10, "afade=t=out:st=4.2:d=0.8"), ("S07", 11.8, -9, ""), ("S08", 12.9, -3, "afade=t=out:st=1.9:d=0.5"),
       ("S09", 14.9, -3, ""), ("S11", 20.3, 1, ""), ("S12", 23.79, -5, "afade=t=out:st=2.8:d=0.5"),
       ("S13a", 27.09, 4, "atrim=0:1.5,asetpts=PTS-STARTPTS,afade=t=out:st=1.4:d=0.1"),
       ("S13b", 28.59, -5, "atrim=1.5,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.05,afade=t=out:st=0.8:d=0.4"),
       ("S14", 29.59, 20, "afade=t=in:st=0:d=0.1"), ("S15", 31.09, 26, "afade=t=out:st=2.6:d=0.4"),
       ("S16", 34.09, -1, "afade=t=out:st=2.6:d=1.4"), ("S17", 35.1, 24, "afade=t=in:st=0:d=0.6,afade=t=out:st=1.8:d=1.2"),
       ("S18", 38.55, -3, ""), ("S19", 39.3, 22, "afade=t=in:st=0:d=0.2,afade=t=out:st=1.4:d=0.6"), ("S20", 40.6, 0, ""),
       ("S21", 41.8, -4, "afade=t=out:st=2.4:d=0.6"), ("S22", 43.9, -4, "afade=t=out:st=1.6:d=0.15"),
       ("S23", 45.65, 8, ""), ("S21", 51.8, -12, "afade=t=out:st=2.0:d=1.0")]          # кристаллы под титр
AMB = [("S01", 0.0, 0, ""), ("S03", 4.6, -8, "afade=t=in:st=0:d=0.3"),
       ("S10", 15.25, -8, "afade=t=in:st=0:d=0.4,afade=t=out:st=11.3:d=0.5"),
       ("S10", 38.9, -14, "atrim=2:9.5,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.6,afade=t=out:st=6.2:d=0.6"),
       ("S24", 45.9, 4, "atrim=0:9.85,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=1.0,afade=t=out:st=8.6:d=1.25")]


def bank(lst, out, duck=True):
    files, parts = [], []
    for k, t, db, f in lst:
        key = k[:3]
        files.append(find(S[key]))
        idx = len(files) - 1
        chain = f"[{idx}:a]{ST}" + (f",{f}" if f else "") + f",volume={db}dB,adelay={ms(t)}|{ms(t)}"
        parts.append(chain)
    mixdown(parts, files, out, f"{DUCK},{GATE}" if duck else GATE)


def voices(out):
    f = {k: find(p) for k, p in VO.items()}
    ins = [f["l1"], f["l2"], f["l3"], f["l4"], f["fi"], f["fs"]]
    V = lambda db, t: f"volume={db}dB,alimiter=limit=0.7:level=false,{ST},adelay={ms(t)}|{ms(t)}"
    parts = [
        f"[0:a]{MO},{VFX},{V(20.5, 22.25)}",
        f"[1:a]{MO},asplit[x][y];[x]atrim=0.15:2.3,asetpts=PTS-STARTPTS[x2];[y]atrim=3.05:4.36,asetpts=PTS-STARTPTS[y2];"
        f"[x2][y2]concat=n=2:v=0:a=1,{VFX},{V(13.5, 24.4)}",
        f"[2:a]{MO},atrim=0.05:3.0,asetpts=PTS-STARTPTS,atempo=1.1,{VFX},{V(11.5, 27.85)}",
        f"[3:a]{MO},asplit[vp][vq];[vp]atrim=0.05:2.3,asetpts=PTS-STARTPTS[vp2];[vq]atrim=2.55:4.2,asetpts=PTS-STARTPTS[vq2];"
        f"[vp2][vq2]concat=n=2:v=0:a=1,atempo=1.1,{VFX},{V(13.5, 30.55)}",
        f"[4:a]{MO},asplit[ia][ib];[ia]atrim=0.2:2.75,asetpts=PTS-STARTPTS,volume='1-0.65*t/2.5':eval=frame[ia2];"
        f"[ib]atrim=3.05:3.97,asetpts=PTS-STARTPTS,volume=0.7,adelay=2900[ib2];[ia2][ib2]amix=inputs=2:normalize=0:duration=longest[iru];"
        f"[5:a]{MO},asplit[sa][sb];[sa]atrim=0.2:2.65,asetpts=PTS-STARTPTS,volume='0.35+0.65*t/2.4':eval=frame[sa2];"
        f"[sb]atrim=3.3:4.44,asetpts=PTS-STARTPTS,volume=0.7,adelay=2900[sb2];[sa2][sb2]amix=inputs=2:normalize=0:duration=longest[sel];"
        f"[iru][sel]amix=inputs=2:normalize=0,{VFX},{V(21, 46.35)}",
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

    boom(6.95, 0.55); boom(12.45, 0.40); boom(21.0, 0.22, 1.0); boom(27.09, 0.60, 1.6)
    boom(34.09, 0.95, 3.2, 64, 22); boom(38.75, 0.60, 1.6); boom(42.1, 0.25, 2.0, 46, 26)
    boom(45.65, 0.80, 2.4); boom(51.8, 0.45, 2.6, 50, 24)
    riser(26.0, 27.06, 0.22); riser(32.55, 33.86, 0.42, 120, 1400); riser(44.3, 45.63, 0.35, 150, 1200)
    buf *= 0.6
    buf[int(33.86 * SR):int(34.09 * SR)] = 0
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
