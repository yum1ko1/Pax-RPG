# Полная сборка материалов на ПК: LUT → звук → слои → VFX-плёнки → эталон → Lua для Resolve.
import os, sys, time, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault("PAX_INTRO", os.path.dirname(HERE))
LOG = os.path.join(HERE, "run_log.txt")


def step(name, args):
    t = time.time()
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"--- {name} {time.strftime('%H:%M:%S')}\n")
    r = subprocess.run([sys.executable, "-u", os.path.join(HERE, args[0])] + args[1:], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(r.stdout[-3000:] + r.stderr[-3000:] + f"=== {name} rc={r.returncode} {time.time() - t:.0f}s\n")
    if r.returncode:
        raise SystemExit(f"{name} failed")


steps = sys.argv[1:] or ["lut", "audio", "overlays", "plates", "ref", "lua"]
for s in steps:
    {"lut": lambda: step("lut", ["grade.py"]),
     "audio": lambda: step("audio", ["audio.py"]),
     "overlays": lambda: step("overlays", ["overlays.py", "build"]),
     "plates": lambda: step("plates", ["vfx.py", "plates"]),
     "ref": lambda: step("ref", ["ref.py", "ru"]),
     "lua": lambda: step("lua", ["gen_lua.py"])}[s]()
with open(LOG, "a", encoding="utf-8") as f:
    f.write("ALL DONE " + time.strftime("%H:%M:%S") + "\n")
