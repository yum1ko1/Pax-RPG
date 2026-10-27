# Чтение логов и крэшей без открытия редактора.
#   Scripts\ue_log.ps1                       — ошибки/предупреждения из последнего лога игры/редактора
#   Scripts\ue_log.ps1 -Pattern LogLLM       — строки по категории или тексту
#   Scripts\ue_log.ps1 -Tail 80              — последние 80 строк
#   Scripts\ue_log.ps1 -Crash                — последний крэш: сообщение и стек
param(
    [string]$Pattern = '',
    [int]$Tail = 0,
    [switch]$Crash
)
. "$PSScriptRoot\ue_env.ps1"

if ($Crash) {
    $dir = Get-ChildItem (Join-Path $ProjectRoot 'Saved\Crashes') -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $dir) { Write-Output 'Крэшей нет.'; exit 0 }
    Write-Output "Крэш: $($dir.FullName) ($($dir.LastWriteTime))"
    $ctx = Get-ChildItem $dir.FullName -Filter 'CrashContext.runtime-xml' | Select-Object -First 1
    if ($ctx) {
        $x = Get-Content $ctx.FullName -Raw
        foreach ($tag in 'ErrorMessage', 'CallStack') {
            if ($x -match "(?s)<$tag>(.*?)</$tag>") { Write-Output "--- $tag"; ($Matches[1] -split "`n" | Select-Object -First 40) }
        }
    }
    $clog = Get-ChildItem $dir.FullName -Filter '*.log' | Select-Object -First 1
    if ($clog) { Write-Output '--- конец лога'; Get-Content $clog.FullName -Tail 40 }
    exit 0
}

$log = Get-ChildItem $LogDir -Filter 'CommandGame*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $log) { Write-Output "Логов нет в $LogDir"; exit 0 }
Write-Output "Лог: $($log.FullName) ($($log.LastWriteTime))"
if ($Tail -gt 0) { Get-Content $log.FullName -Tail $Tail; exit 0 }
if (-not $Pattern) { $Pattern = 'Error:|Fatal|Assertion failed|Ensure condition failed|Warning: .*(LogOrder|LogOfficerAI|LogLLM|LogDestructionPool|LogRagdollPool|LogMission)' }
Select-String -Path $log.FullName -Pattern $Pattern | Select-Object -Last 60 | ForEach-Object { $_.Line }
