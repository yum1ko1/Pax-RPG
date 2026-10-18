# Рендер входа в Гхарн в Blender на ПК (без игры) → ветка xfer-render (забрать и удалить).
#   powershell -File render_entrance.ps1 [-Tag it1]
param([string]$Tag = "it")
$ErrorActionPreference = "Continue"
git fetch -q pax-rpg main
$w = "$env:TEMP\gharn_render"; Remove-Item -Recurse -Force $w -ErrorAction SilentlyContinue
git archive -o "$env:TEMP\gr.zip" pax-rpg/main pax_rpg/dev/gharn/render_scene.py mods/pax_rpg/config/gharn.json
Expand-Archive "$env:TEMP\gr.zip" $w
$out = "$w\out"
$mg = "C:\Users\mbkli\Desktop\pax_rpg_work\models_graded\gharn"
$shots = @(
  "${Tag}_1_approach:0,2.0,104:0,5,70:28",
  "${Tag}_2_gate_in:0,1.7,77:0,3.5,30:24",
  "${Tag}_3_alley:0,1.7,55:0,3,10:24",
  "${Tag}_4_bird:22,16,100:0,2,55:24",
  "${Tag}_5_side:-9,2.2,62:6,3,44:24"
)
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b -P "$w\pax_rpg\dev\gharn\render_scene.py" -- "$w\mods\pax_rpg\config\gharn.json" $mg $out "-32,8,32,112" @shots 2>&1 | Select-String "Traceback|Error:|shot " | % Line
Push-Location $out; git init -q; git add .; git -c user.email=x@x -c user.name=x commit -qm r; git push -q -f https://github.com/yum1ko1/Pax-RPG HEAD:refs/heads/xfer-render 2>&1 | Out-Null; Pop-Location
"rendered: " + (Get-ChildItem $out -Filter *.png).Count
