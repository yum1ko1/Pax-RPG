#!/usr/bin/env bash
# Проверка мода вне игры (Linux, CI). Шаги:
#   1. static_checks.py — JSON, CodeGuard, переводы, файлы из конфигов;
#   2. компиляция всех .gd мода в Godot с заглушками API Pax (из pax_api/api-reference.md);
#   3. дымовой прогон арены: бот жмёт клавиши, ловятся ошибки выполнения; с экраном (xvfb) — скриншот.
# Итог и логи — в tools/ci/out/. Код выхода 1 — есть ошибки.
#   GODOT=<путь к godot> — свой бинарник (иначе скачивается Godot $GODOT_VERSION в .cache/godot)
#   NO_SMOKE=1 — без прогона арены
set -uo pipefail
CI="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CI/../.." && pwd)"
PROJ="$CI/project"
OUT="$CI/out"
VER="${GODOT_VERSION:-4.5.1-stable}"
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  CACHE="$ROOT/.cache/godot"
  GODOT="$CACHE/Godot_v${VER}_linux.x86_64"
  if [ ! -x "$GODOT" ]; then
    mkdir -p "$CACHE"
    curl -sSL -o "$CACHE/godot.zip" \
      "https://github.com/godotengine/godot/releases/download/${VER}/Godot_v${VER}_linux.x86_64.zip" \
      && unzip -oq "$CACHE/godot.zip" -d "$CACHE" && rm -f "$CACHE/godot.zip"
  fi
fi
rm -rf "$OUT" && mkdir -p "$OUT"
fail=0
# ошибки выполнения и компиляции в выводе Godot
PAT='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Invalid call|Invalid access|Invalid assignment|Invalid operands|Nonexistent function|Attempt to call|smoke: FAIL|check: FAIL'

echo "== 1. статические проверки"
python3 "$CI/static_checks.py" "$ROOT" | tee "$OUT/static.log" || true
grep -q "ошибок: 0" "$OUT/static.log" || fail=1

echo "== 2. компиляция (Godot $("$GODOT" --version 2>/dev/null | head -1))"
rm -rf "$PROJ/mods" "$PROJ/stubs" "$PROJ/.godot"
mkdir -p "$PROJ/mods" "$PROJ/stubs"
cp -r "$ROOT/mods/pax_rpg" "$PROJ/mods/pax_rpg"
python3 "$CI/gen_stubs.py" "$CI/pax_api/api-reference.md" "$PROJ/stubs" "$CI/stub_overrides" > "$OUT/stubs.log"
"$GODOT" --headless --path "$PROJ" --import > "$OUT/import.log" 2>&1
"$GODOT" --headless --path "$PROJ" -s res://ci/check_scripts.gd > "$OUT/compile.log" 2>&1
grep -E "check:|SCRIPT ERROR|Parse Error|res://mods" "$OUT/compile.log" | grep -v "check: ok" || true
if grep -qE "$PAT" "$OUT/compile.log"; then fail=1; fi

if [ "${NO_SMOKE:-0}" != "1" ]; then
  echo "== 3. прогон арены"
  if command -v xvfb-run > /dev/null; then
    xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$PROJ" --rendering-driver opengl3 \
      --resolution 1920x1080 --fixed-fps 60 -s res://ci/smoke.gd -- "--out=$OUT" > "$OUT/smoke.log" 2>&1
  else
    "$GODOT" --headless --path "$PROJ" --fixed-fps 60 -s res://ci/smoke.gd > "$OUT/smoke.log" 2>&1
  fi
  grep -E -A3 "smoke:|SCRIPT ERROR" "$OUT/smoke.log" | head -60
  if grep -qE "$PAT" "$OUT/smoke.log" || ! grep -q "smoke: ok" "$OUT/smoke.log"; then fail=1; fi
fi

if [ "$fail" = 0 ]; then echo "== ИТОГ: всё чисто"; else echo "== ИТОГ: есть ошибки (логи — $OUT)"; fi
exit $fail
