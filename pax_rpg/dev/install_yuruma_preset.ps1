# Ставит пресет «Юрума» из ветки мода в папку пресетов игры (user://presets = %APPDATA%\Pax Universe\presets).
# Пресет делает pax_rpg/dev/yuruma_scenario.py. Запуск из папки игры:  & .\pax_corporations_dev\install_yuruma_preset.ps1
$ref = 'pax-corpinc/claude/blissful-lovelace-v7ir3o'
git fetch -q pax-corpinc claude/blissful-lovelace-v7ir3o
$dst = Join-Path $env:APPDATA 'Pax Universe\presets\Юрума'
New-Item -ItemType Directory -Force $dst | Out-Null
foreach ($f in 'meta.json', 'Земля.png', 'обложка.jpg') {
    cmd /c "git show ${ref}:mods/pax_rpg/presets/Юрума/$f > `"$dst\$f`""
}
Get-ChildItem $dst | Select-Object Name, Length | Format-Table -AutoSize | Out-String
