# Подключить команды Pax к Cascadeur без прав администратора: пакет pax_cascadeur копируется в
# Документы\PaxCascadeur, в настройки Cascadeur (%LOCALAPPDATA%\Nekki Limited\Cascadeur\settings.json)
# добавляются эта папка (Python.Path) и пакет команд (Python.Commands). После этого сервер скриптов
# (порт 8766) стартует сам при запуске Cascadeur — cascadeur_live.ps1 работает без кликов.
#   .\install.ps1            — если Cascadeur открыт, ждёт, пока его закроют, ставит и открывает снова
#   .\install.ps1 -Remove    — убрать
# Cascadeur при выходе пишет свои настройки, поэтому правим их только при закрытом Cascadeur.
param([switch]$Remove, [switch]$NoRelaunch)
$ErrorActionPreference = 'Stop'
$dst = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PaxCascadeur'
$settings = Join-Path $env:LOCALAPPDATA 'Nekki Limited\Cascadeur\settings.json'
$exe = 'C:\Program Files\Cascadeur\cascadeur.exe'
$wasOpen = $false
while (Get-Process cascadeur -ErrorAction SilentlyContinue) {
    if (-not $wasOpen) { Write-Output 'Cascadeur открыт — жду, пока его закроют (сохрани сцену и закрой)…' }
    $wasOpen = $true
    Start-Sleep 2
}
Start-Sleep 2
$j = Get-Content -Raw -Encoding UTF8 $settings | ConvertFrom-Json
if (-not $j.Python) { $j | Add-Member -Force Python ([pscustomobject]@{ Path = @(); Commands = @('commands'); Scripts = @('scripts') }) }
$paths = @($j.Python.Path | Where-Object { $_ -and $_ -ne $dst })
$cmds = @($j.Python.Commands | Where-Object { $_ -and $_ -ne 'pax_cascadeur' })
if ($Remove) {
    Remove-Item -Recurse -Force $dst -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item -Recurse -Force (Join-Path $PSScriptRoot 'pax_cascadeur') $dst
    $paths += $dst
    $cmds += 'pax_cascadeur'
}
$j.Python.Path = $paths
$j.Python.Commands = $cmds
[IO.File]::WriteAllText($settings, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Write-Output ($(if ($Remove) { 'Команды Pax убраны из Cascadeur' } else { "Готово: $dst, settings.json обновлён" }))
if ($wasOpen -and -not $NoRelaunch -and -not $Remove) { Start-Process $exe; Write-Output 'Cascadeur открывается снова' }
