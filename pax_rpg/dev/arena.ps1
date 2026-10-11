# Запуск Pax Universe сразу в тестовую арену Pax RPG (без кликов по меню и планете).
# Мод не может читать командную строку (песочница CodeGuard), поэтому скрипт ставит одноразовую настройку мода
# autostart_arena в %APPDATA%\Pax Universe\mod_settings\pax_rpg.json; мод при старте открывает арену и сбрасывает её.
#   .\arena.ps1            — поставить флаг и запустить игру
#   .\arena.ps1 -NoStart   — только флаг (игру запустит мост: game_start)
#   .\arena.ps1 -City gharn — сразу в город
# Лежит в <папка игры>\pax_corporations_dev\ (копия из репозитория Pax-RPG: pax_rpg/dev/arena.ps1).
param([switch]$NoStart, [string]$City = '')
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:APPDATA 'Pax Universe\mod_settings'
$file = Join-Path $dir 'pax_rpg.json'
New-Item -ItemType Directory -Force $dir | Out-Null
$data = [ordered]@{}
if (Test-Path $file) {
    $old = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
    if ($old) { foreach ($p in $old.PSObject.Properties) { $data[$p.Name] = $p.Value } }
}
if ($City -ne '') { $data['autostart_city'] = $City } else { $data['autostart_arena'] = $true }
[IO.File]::WriteAllText($file, ($data | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Write-Output "autostart_arena = true -> $file"
if (-not $NoStart) {
    $game = Split-Path -Parent $PSScriptRoot
    Start-Process (Join-Path $game 'PaxUniverse.exe') -WorkingDirectory $game
    Write-Output 'Pax Universe starting -> test arena'
}
