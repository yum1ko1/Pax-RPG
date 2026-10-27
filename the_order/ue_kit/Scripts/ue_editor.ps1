# Запуск редактора с MCP-сервером Unreal (http://127.0.0.1:8000/mcp) и ожидание, пока сервер ответит.
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_editor.ps1            — запустить и дождаться MCP
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_editor.ps1 -Stop      — закрыть редактор с этим проектом
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_editor.ps1 -Map L_Blockout -Game   — сразу играть карту
param(
    [switch]$Stop,
    [string]$Map = '',
    [switch]$Game,
    [int]$Port = 8000,
    [int]$TimeoutSec = 1800
)
. "$PSScriptRoot\ue_env.ps1"

if ($Stop) {
    Get-CimInstance Win32_Process -Filter "Name='UnrealEditor.exe'" |
        Where-Object { $_.CommandLine -like '*CommandGame.uproject*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId; "Закрыт редактор PID $($_.ProcessId)" }
    exit 0
}
if (Test-EditorRunning) { Write-Output 'Редактор с проектом уже открыт.'; exit 0 }

$a = @("`"$UProject`"")
if ($Map) { $a += $Map }
if ($Game) { $a += '-game', '-windowed', '-ResX=1600', '-ResY=900' } else { $a += '-ModelContextProtocolStartServer', "-ModelContextProtocolPort=$Port" }
Start-Process -FilePath $Editor -ArgumentList $a | Out-Null
if ($Game) { Write-Output 'Игра запущена.'; exit 0 }

Write-Output "Редактор запускается. Первый запуск компилирует шейдеры — это может занять 20–60 минут."
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $Port); $c.Close()
        Write-Output "MCP готов: http://127.0.0.1:$Port/mcp (через $([int]((Get-Date) - $t0).TotalSeconds) с)"
        exit 0
    } catch { Start-Sleep -Seconds 10 }
}
Write-Output "MCP не ответил за $TimeoutSec с. Проверьте, что плагин Unreal MCP включён; лог: Scripts\ue_log.ps1 -Pattern ModelContextProtocol"
exit 1
