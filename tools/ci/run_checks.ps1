# Проверка мода вне игры на Windows — то же, что run_checks.sh в CI:
#   1. static_checks.py — JSON, CodeGuard, переводы, файлы из конфигов;
#   2. компиляция всех .gd мода в Godot с заглушками API Pax — ошибки с файлом и номером строки;
#   3. прогон арены (бот жмёт клавиши) — ошибки выполнения; с -Shot — окно на 10 с и скриншот out\arena.png.
#   .\run_checks.ps1 [-ModDir <папка мода>] [-NoSmoke] [-Shot]
# Godot скачивается один раз в %LOCALAPPDATA%\pax_rpg_ci. Код выхода 1 — есть ошибки.
param([string]$ModDir = '', [switch]$NoSmoke, [switch]$Shot, [string]$Version = '4.5.1-stable')
$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$CI = $PSScriptRoot
$Root = (Resolve-Path (Join-Path $CI '..\..')).Path
if ($ModDir -eq '') { $ModDir = Join-Path $Root 'mods\pax_rpg' }
$ModDir = (Resolve-Path $ModDir).Path
$Proj = Join-Path $CI 'project'
$Out = Join-Path $CI 'out'
$Cache = Join-Path $env:LOCALAPPDATA 'pax_rpg_ci'
$Godot = Join-Path $Cache "Godot_v${Version}_win64_console.exe"
if (-not (Test-Path $Godot)) {
    New-Item -ItemType Directory -Force $Cache | Out-Null
    $zip = Join-Path $Cache 'godot.zip'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip "https://github.com/godotengine/godot/releases/download/$Version/Godot_v${Version}_win64.exe.zip"
    Expand-Archive -Force $zip $Cache
    Remove-Item $zip
}
Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out | Out-Null
$fail = $false
$pat = 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Invalid call|Invalid access|Invalid assignment|Invalid operands|Nonexistent function|Attempt to call|GDScript backtrace|smoke: FAIL|check: FAIL'

# статика смотрит на <корень>\mods\pax_rpg — даём ей временный корень со ссылкой на мод
$tmpRoot = Join-Path $Out 'root'
New-Item -ItemType Directory -Force (Join-Path $tmpRoot 'mods') | Out-Null
Copy-Item -Recurse $ModDir (Join-Path $tmpRoot 'mods\pax_rpg')

Write-Output '== 1. статические проверки'
$static = & python (Join-Path $CI 'static_checks.py') $tmpRoot 2>&1 | Out-String
$static | Set-Content -Encoding UTF8 (Join-Path $Out 'static.log')
Write-Output $static.TrimEnd()
if ($static -notmatch 'ошибок: 0') { $fail = $true }

Write-Output '== 2. компиляция'
foreach ($d in 'mods', 'stubs', '.godot') { Remove-Item -Recurse -Force (Join-Path $Proj $d) -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force (Join-Path $Proj 'mods'), (Join-Path $Proj 'stubs') | Out-Null
Copy-Item -Recurse $ModDir (Join-Path $Proj 'mods\pax_rpg')
& python (Join-Path $CI 'gen_stubs.py') (Join-Path $CI 'pax_api\api-reference.md') (Join-Path $Proj 'stubs') (Join-Path $CI 'stub_overrides') | Out-Null
& $Godot --headless --path $Proj --import *> (Join-Path $Out 'import.log')
$compile = & $Godot --headless --path $Proj -s res://ci/check_scripts.gd 2>&1 | Out-String
$compile | Set-Content -Encoding UTF8 (Join-Path $Out 'compile.log')
$compile -split "`n" | Select-String -Pattern 'SCRIPT ERROR|Parse Error|at: GDScript::reload|check: FAIL|check: \d' | ForEach-Object { $_.Line.TrimEnd() }
if ($compile -match $pat) { $fail = $true }

if (-not $NoSmoke) {
    Write-Output '== 3. прогон арены'
    if ($Shot) {
        $smoke = & $Godot --path $Proj --resolution 1920x1080 --fixed-fps 60 -s res://ci/smoke.gd -- "--out=$Out" 2>&1 | Out-String
    } else {
        $smoke = & $Godot --headless --path $Proj --fixed-fps 60 -s res://ci/smoke.gd 2>&1 | Out-String
    }
    $smoke | Set-Content -Encoding UTF8 (Join-Path $Out 'smoke.log')
    $smoke -split "`n" | Select-String -Pattern 'smoke:|SCRIPT ERROR|at: ' | Select-Object -First 40 | ForEach-Object { $_.Line.TrimEnd() }
    if ($smoke -match $pat -or $smoke -notmatch 'smoke: ok') { $fail = $true }
}
if ($fail) { Write-Output "== ИТОГ: есть ошибки (логи — $Out)"; exit 1 }
Write-Output '== ИТОГ: всё чисто'
exit 0
