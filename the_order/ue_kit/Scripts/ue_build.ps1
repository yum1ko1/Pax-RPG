# Сборка C++ без IDE. Полный лог → Saved\Logs\build_last.log, в консоль — только ошибки и итог.
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_build.ps1 [-Target CommandGameEditor] [-Config Development]
param(
    [string]$Target = 'CommandGameEditor',
    [string]$Config = 'Development'
)
. "$PSScriptRoot\ue_env.ps1"

if ($Target -like '*Editor' -and (Test-EditorRunning)) {
    Write-Output 'ВНИМАНИЕ: редактор с проектом открыт. Сборка редакторской цели при открытом редакторе (Live Coding) не пройдёт.'
    Write-Output 'Закройте редактор (Scripts\ue_editor.ps1 -Stop) или для правок только в .cpp используйте Live Coding (Ctrl+Alt+F11 в редакторе).'
    exit 2
}

$log = Join-Path $LogDir 'build_last.log'
$t0 = Get-Date
& $BuildBat $Target Win64 $Config "-Project=$UProject" -WaitMutex -NoHotReloadFromIDE 2>&1 | Out-File -Encoding utf8 $log
$code = $LASTEXITCODE
$sec = [int]((Get-Date) - $t0).TotalSeconds

$errors = Select-String -Path $log -Pattern 'error C\d{4}', 'error LNK\d{4}', ': fatal error', ': error ', '^ERROR:', 'UnrealHeaderTool failed' |
    Select-Object -First 40
$warnings = (Select-String -Path $log -Pattern 'warning C\d{4}').Count

if ($code -eq 0) {
    Write-Output "BUILD OK: $Target $Config за $sec с, предупреждений C++: $warnings"
} else {
    Write-Output "BUILD FAILED (код $code): $Target $Config за $sec с. Первые ошибки:"
    $errors | ForEach-Object { $_.Line.Trim() }
    if (-not $errors) { Get-Content $log -Tail 30 }
    Write-Output "Полный лог: $log"
}
exit $code
