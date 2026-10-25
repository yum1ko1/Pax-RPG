# Эталонный рендер без Resolve: плёнки + LUT по актам + кинорамка + титры + микс. python ref.py ru|en
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *
import overlays

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")


def esc(p):
    return p.replace("\\", "/").replace(":", "\\:")


def main(lang):
    ins, g = [], []
    for i, c in enumerate(CLIPS):
        ins += ["-i", os.path.join(PLATES, c[0] + ".mov")]
        g.append(f"[{i}:v]lut3d=file='{esc(os.path.join(LUTS, 'PaxIntro_' + c[6] + '.cube'))}':interp=tetrahedral,format=yuv444p10le[v{i}]")
    g.append("".join(f"[v{i}]" for i in range(len(CLIPS))) + f"concat=n={len(CLIPS)}:v=1:a=0[base]")
    n = len(CLIPS)
    ins += ["-i", os.path.join(OV, "frame_239.mov")]
    g.append(f"[base][{n}:v]overlay=0:0:format=auto[b0]")
    k = n + 1
    last = "b0"
    lays = [(f"sub_{lang}_{j + 1:02d}.mov", a) for j, (_, a, _, _) in enumerate(overlays.SUBS[lang])]
    lays += [(f"card_open_{lang}.mov", 1.0), (f"card_end_{lang}.mov", CARD_END[0] / FPS)]
    for j, (fn, a) in enumerate(lays):
        ins += ["-itsoffset", f"{a:.4f}", "-i", os.path.join(OV, fn)]
        g.append(f"[{last}][{k}:v]overlay=0:0:eof_action=pass:format=auto[o{j}]")
        last = f"o{j}"
        k += 1
    ins += ["-i", os.path.join(AUDIO, "A_master.wav")]
    g.append(f"[{last}]format=yuv420p[vout]")
    out = os.path.join(RENDER, f"Pax_RPG_Intro_reference_{lang}.mp4")
    os.makedirs(RENDER, exist_ok=True)
    cmd = [FFMPEG, "-v", "error", "-y"] + ins + ["-filter_complex", ";".join(g), "-map", "[vout]", "-map", f"{k}:a",
           "-c:v", "libx264", "-crf", "16", "-preset", "slow", "-c:a", "aac", "-b:a", "320k", "-movflags", "+faststart",
           "-t", f"{TOTAL / FPS:.3f}", out]
    subprocess.run(cmd, check=True)
    print("ref", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "ru")
