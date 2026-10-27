# Общие пути проекта и движка. Подключается из других скриптов: . "$PSScriptRoot\ue_env.ps1"
# Движок ищется так: переменная окружения UE_ROOT → запись UE_5.8 в LauncherInstalled.dat Epic Launcher.
# ErrorActionPreference не ставим в Stop: в Windows PowerShell 5.1 stderr сборщика (2>&1) тогда обрывает скрипт.
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$UProject = Join-Path $ProjectRoot 'CommandGame.uproject'
$UEVersion = '5.8'

$UERoot = $env:UE_ROOT
if (-not $UERoot) {
    $dat = 'C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat'
    if (Test-Path $dat) {
        $entry = (Get-Content $dat -Raw | ConvertFrom-Json).InstallationList |
            Where-Object { $_.AppName -eq "UE_$UEVersion" } | Select-Object -First 1
        if ($entry) { $UERoot = $entry.InstallLocation }
    }
}
if (-not $UERoot -or -not (Test-Path (Join-Path $UERoot 'Engine'))) {
    throw "UE $UEVersion не найден. Установите его через Epic Launcher или задайте UE_ROOT (папка, где лежит Engine\)."
}

$BuildBat = Join-Path $UERoot 'Engine\Build\BatchFiles\Build.bat'
$Editor = Join-Path $UERoot 'Engine\Binaries\Win64\UnrealEditor.exe'
$EditorCmd = Join-Path $UERoot 'Engine\Binaries\Win64\UnrealEditor-Cmd.exe'
$UBT = Join-Path $UERoot 'Engine\Binaries\DotNET\UnrealBuildTool\UnrealBuildTool.exe'
$LogDir = Join-Path $ProjectRoot 'Saved\Logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null

function Test-EditorRunning {
    # Редактор с этим проектом открыт? Сборка при открытом редакторе с Live Coding падает.
    $p = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor.exe'" -ErrorAction SilentlyContinue
    return [bool]($p | Where-Object { $_.CommandLine -like "*CommandGame.uproject*" })
}
