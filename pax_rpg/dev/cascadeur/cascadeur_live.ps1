# Мост к Cascadeur: выполнить Python внутри открытого Cascadeur через его встроенный сервер скриптов
# (http://127.0.0.1:8765, Cascadeur 2026.2+). Как blender_live.ps1, только для Cascadeur.
#
# Один раз за сессию Cascadeur: меню Commands → «MCP.Start script server» (или install_autostart.ps1 от админа).
#
#   .\cascadeur_live.ps1 -Health                  — сервер жив?
#   .\cascadeur_live.ps1 -Launch                  — запустить Cascadeur
#   .\cascadeur_live.ps1 -Code "scene.name()"     — выражение → его значение (repr)
#   .\cascadeur_live.ps1 -B64 <base64 utf-8>      — код в base64 (так шлёт Claude через мост — без кавычек)
#   .\cascadeur_live.ps1 -File script.py          — код из файла
# В коде доступны scene (csc.domain.Scene), csc, app. print() уходит в журнал Cascadeur и в messages ответа.
# Ответ — JSON: ok, value, messages (журнал), error (traceback). Изменения сцены (scene.modify…) возвращают
# False при ошибке, хотя ok: true — проверять возврат; журнал: %LOCALAPPDATA%\Nekki Limited\Cascadeur\logs.
param([string]$Code = '', [string]$B64 = '', [string]$File = '', [switch]$Health, [switch]$Launch,
      [int]$TimeoutSec = 120, [int]$Port = 8765)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$base = "http://127.0.0.1:$Port"

if ($Launch) {
    $exe = 'C:\Program Files\Cascadeur\cascadeur.exe'
    if (Get-Process cascadeur -ErrorAction SilentlyContinue) { Write-Output 'Cascadeur уже запущен' }
    else { Start-Process $exe; Write-Output 'Cascadeur запускается. Включи сервер: Commands → MCP.Start script server' }
    exit 0
}
try {
    if ($Health) {
        Invoke-RestMethod -TimeoutSec 5 "$base/health" | ConvertTo-Json -Depth 5
        exit 0
    }
    if ($B64 -ne '') { $Code = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64)) }
    elseif ($File -ne '') { $Code = [IO.File]::ReadAllText((Resolve-Path $File).Path, [Text.Encoding]::UTF8) }
    if ($Code -eq '') { Write-Output 'Нет кода: -Code, -B64 или -File'; exit 2 }
    $body = [Text.Encoding]::UTF8.GetBytes((@{ code = $Code } | ConvertTo-Json -Compress))
    $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$base/run" -Body $body `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
    $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    Write-Output $text
    if ($text -match '"ok":\s*false') { exit 1 }
} catch {
    $running = [bool](Get-Process cascadeur -ErrorAction SilentlyContinue)
    Write-Output ('{"ok": false, "error": ' + (($_.Exception.Message) | ConvertTo-Json) + ', "cascadeur_running": ' +
        $running.ToString().ToLower() + ', "hint": "Cascadeur открыт? Commands → MCP.Start script server"}')
    exit 1
}
