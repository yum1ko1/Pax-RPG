# Медиа ролика для игры: трейлер без вшитых титров (до кадра меню), петля фона нового меню, бочка меню.
# Субтитры и карточки игра рисует сама, на языке игры (src/ui/intro.gd). Нужны плёнки, LUT и мастер-звук
# (run_all.py). python game_media.py <папка мода>
import os, sys, subprocess
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edl import *
from ref import esc
import audio

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
LOOP_FADE = 12                       # кадров перекрёстного затухания на шве петли меню


def trailer(out):
    # всё до меню: плёнки с LUT по актам, кинорамка, мастер-звук; последний кадр — чёрный перед бочкой меню
    clips = [c for c in CLIPS if c[5] < MENU_AT * FPS]
    ins, g = [], []
    for i, c in enumerate(clips):
        ins += ["-i", os.path.join(PLATES, c[0] + ".mov")]
        g.append(f"[{i}:v]lut3d=file='{esc(os.path.join(LUTS, 'PaxIntro_' + c[6] + '.cube'))}':interp=tetrahedral[v{i}]")
    n = len(clips)
    g.append("".join(f"[v{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[base]")
    ins += ["-i", os.path.join(OV, "frame_239.mov"), "-i", os.path.join(AUDIO, "A_master.wav")]
    g.append(f"[base][{n}:v]overlay=0:0:format=auto,hqdn3d=4:3:7:5,format=yuv420p[vout]")
    g.append(f"[{n + 1}:a]atrim=0:{MENU_AT:.4f},afade=t=out:st={MENU_AT - 0.05:.4f}:d=0.05[aout]")
    subprocess.run([FFMPEG, "-v", "error", "-y"] + ins + ["-filter_complex", ";".join(g), "-map", "[vout]", "-map", "[aout]",
                    "-frames:v", str(int(round(MENU_AT * FPS))), "-c:v", "libtheora", "-b:v", "7M", "-maxrate", "9M", "-bufsize", "14M", "-g", "48",
                    "-c:a", "libvorbis", "-q:a", "6", "-ar", "48000", out], check=True)


def menu_loop(out):
    # c13 в луке меню; шов петли — перекрёстное затухание хвоста в начало
    vf = (f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},setsar=1,fps={FPS},"
          f"lut3d=file='{esc(os.path.join(LUTS, 'PaxIntro_menu.cube'))}':interp=tetrahedral")
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", os.path.join(MEDIA, "c13.mp4"), "-vf", vf, "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    fr = np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3)
    n = len(fr) - 1                                  # последний кадр совпадает с первым
    k = LOOP_FADE
    enc = subprocess.Popen([FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-c:v", "libtheora", "-q:v", "8", "-g", "24", "-pix_fmt",
                            "yuv420p", out], stdin=subprocess.PIPE)
    for j in range(n - k):                           # петля: кадры k…n-1, хвост n-k…n-1 тает в 0…k-1
        f = fr[j + k].astype(np.float32)
        if j >= n - 2 * k:
            a = (j - (n - 2 * k) + 1) / (k + 1)
            f = f * (1 - a) + fr[j + k - (n - k)].astype(np.float32) * a
        enc.stdin.write((f + 0.5).astype(np.uint8).tobytes())
    enc.stdin.close()
    enc.wait()


def menu_drop(out):
    # дроп из второго файла саундтрека: бочка с басом — в кадр появления меню, дальше трек сам доходит до конца
    src = audio.find("Final Assault (1).mp3", "*Final_Assault_1.mp3")
    subprocess.run([FFMPEG, "-v", "error", "-y", "-i", src, "-af",
                    "atrim=23.345:33.77,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.004,afade=t=out:st=8.9:d=1.5",
                    "-ar", "48000", "-c:a", "libvorbis", "-q:a", "6", out], check=True)


if __name__ == "__main__":
    mod = sys.argv[1]
    os.makedirs(os.path.join(mod, "video"), exist_ok=True)
    trailer(os.path.join(mod, "video", "intro.ogv")); print("trailer", flush=True)
    menu_loop(os.path.join(mod, "video", "menu_loop.ogv")); print("menu loop", flush=True)
    menu_drop(os.path.join(mod, "sounds", "music", "menu_drop.ogg")); print("menu drop", flush=True)
