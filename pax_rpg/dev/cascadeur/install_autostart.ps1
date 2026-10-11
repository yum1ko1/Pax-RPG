# Автозапуск сервера скриптов Cascadeur (для cascadeur_live.ps1) — чтобы не включать его руками каждый раз.
# Запускать ОДИН РАЗ от администратора (папка Cascadeur в Program Files защищена от записи):
#   правый клик по PowerShell → «Запуск от имени администратора» → .\install_autostart.ps1
# Кладёт обработчики событий scene_created / scene_opened: при первой сцене сервер стартует сам.
# Удалить: .\install_autostart.ps1 -Remove. После обновления Cascadeur — запустить снова.
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$events = 'C:\Program Files\Cascadeur\resources\scripts\python\events'
$handler = @'
"""Pax RPG: сервер скриптов Cascadeur (MCP, 127.0.0.1:8765) стартует сам при первой сцене."""
import scripts.mcp.script_server.server as script_server


def run(scene):
    if not script_server.is_running():
        script_server.start(scene)
'@
foreach ($e in 'scene_created', 'scene_opened') {
    $f = Join-Path $events "$e\pax_mcp_autostart.py"
    if ($Remove) { Remove-Item -Force $f -ErrorAction SilentlyContinue; Write-Output "убран: $f" }
    else { [IO.File]::WriteAllText($f, $handler, (New-Object Text.UTF8Encoding $false)); Write-Output "поставлен: $f" }
}
Write-Output 'Готово. Перезапусти Cascadeur.'
