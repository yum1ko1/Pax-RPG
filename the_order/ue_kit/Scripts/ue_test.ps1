# Автотесты без окна (-nullrhi). Отчёт → Saved\Automation\Reports\index.json, лог → Saved\Logs\test_last.log.
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_test.ps1 [-Filter CommandGame] [-Render]
# -Render — с настоящим рендером (для тестов, которым нужна графика/FPS); без него — быстрее и без окна.
param(
    [string]$Filter = 'CommandGame',
    [switch]$Render
)
. "$PSScriptRoot\ue_env.ps1"

$report = Join-Path $ProjectRoot 'Saved\Automation\Reports'
$log = Join-Path $LogDir 'test_last.log'
Remove-Item -Recurse -Force $report -ErrorAction SilentlyContinue
$a = @("`"$UProject`"", "-ExecCmds=`"Automation RunTests $Filter; Quit`"", '-TestExit="Automation Test Queue Empty"',
          '-unattended', '-nopause', '-nosplash', "-ReportExportPath=`"$report`"", "-abslog=`"$log`"")
if (-not $Render) { $a += '-nullrhi' }

$t0 = Get-Date
$p = Start-Process -FilePath $EditorCmd -ArgumentList $a -Wait -PassThru -NoNewWindow
$sec = [int]((Get-Date) - $t0).TotalSeconds

$results = Select-String -Path $log -Pattern 'Test Completed\. Result=\{(\w+)\}.*Name=\{([^}]*)\}' -ErrorAction SilentlyContinue
$failed = $results | Where-Object { $_.Matches[0].Groups[1].Value -notin @('Success', 'Passed') }
Write-Output ("TESTS: всего {0}, провалено {1}, за {2} с (код процесса {3})" -f $results.Count, $failed.Count, $sec, $p.ExitCode)
$failed | ForEach-Object { '  FAIL ' + $_.Matches[0].Groups[2].Value }
if ($failed) {
    Write-Output 'Ошибки в логе тестов:'
    Select-String -Path $log -Pattern 'Error:', 'Expected ', 'Ensure condition failed' | Select-Object -First 30 | ForEach-Object { '  ' + $_.Line.Trim() }
}
if (-not $results) { Write-Output "Результатов нет — смотрите $log (тесты не найдены по фильтру или редактор упал)."; Get-Content $log -Tail 25 }
if (Test-Path (Join-Path $report 'index.json')) { Write-Output "Отчёт JSON: $report\index.json" }
Write-Output "Лог: $log"
if ($failed -or -not $results) { exit 1 } else { exit 0 }
