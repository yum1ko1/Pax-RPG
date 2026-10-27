# Проверка окружения «Приказа» (Спринт 0). Ничего не меняет, только смотрит и пишет, чего не хватает.
#   powershell -ExecutionPolicy Bypass -File setup_check.ps1 [-ProjectRoot E:\CommandGame]
# Работает и до установки движка/создания проекта. Итог — таблица OK / НЕТ и что делать.
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$rows = New-Object System.Collections.Generic.List[object]
function Row($name, $ok, $info, $fix) { $rows.Add([pscustomobject]@{ Check = $name; State = $(if ($ok) { 'OK' } else { 'НЕТ' }); Info = $info; Fix = $(if ($ok) { '' } else { $fix }) }) }

# Диски
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and ($_.Used + $_.Free) -gt 0 } | ForEach-Object {
    Row "Диск $($_.Name):" $true ("свободно {0} ГБ" -f [math]::Round($_.Free / 1GB)) ''
}

# Visual Studio: версия ≥ 17.14 (минимум UE 5.8) и нагрузки C++
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = $null
if (Test-Path $vswhere) { $vs = & $vswhere -latest -products * -format json | ConvertFrom-Json | Select-Object -First 1 }
if ($vs) {
    $ver = [version]($vs.installationVersion)
    Row 'Visual Studio ≥ 17.14' ($ver -ge [version]'17.14') "$($vs.displayName) $($vs.catalog.productDisplayVersion)" 'Обновить Visual Studio через Visual Studio Installer'
    foreach ($w in 'Microsoft.VisualStudio.Workload.NativeGame', 'Microsoft.VisualStudio.Workload.NativeDesktop') {
        $has = [bool](& $vswhere -latest -products * -requires $w -property installationPath)
        Row "VS: $($w.Split('.')[-1])" $has '' 'Scripts\install_vs_workloads.ps1 (нужно подтвердить окно UAC)'
    }
    $msvc = Get-ChildItem (Join-Path $vs.installationPath 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    $okMsvc = [bool]($msvc | Where-Object { [version]$_.Name -ge [version]'14.38' })
    Row 'MSVC ≥ 14.38' $okMsvc (($msvc | ForEach-Object Name) -join ', ') 'Ставится вместе с нагрузкой C++ (install_vs_workloads.ps1)'
} else {
    Row 'Visual Studio' $false 'не найдена' 'Установить Visual Studio 2022 Community (17.14+) или 2026'
}
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Include" -Directory -ErrorAction SilentlyContinue | Sort-Object Name
$okSdk = [bool]($sdk | Where-Object { $_.Name -match '^10\.0\.(\d+)' -and [int]$Matches[1] -ge 22621 })
Row 'Windows SDK ≥ 10.0.22621' $okSdk (($sdk | ForEach-Object Name) -join ', ') 'Ставится вместе с нагрузкой Desktop C++ (install_vs_workloads.ps1)'

# Unreal Engine 5.8
$ue = $env:UE_ROOT
$dat = 'C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat'
if (-not $ue -and (Test-Path $dat)) {
    $e = (Get-Content $dat -Raw | ConvertFrom-Json).InstallationList | Where-Object { $_.AppName -eq 'UE_5.8' } | Select-Object -First 1
    if ($e) { $ue = $e.InstallLocation }
}
Row 'Unreal Engine 5.8' ([bool]$ue -and (Test-Path "$ue\Engine\Binaries\Win64\UnrealEditor.exe")) "$ue" 'Автор: Epic Games Launcher → Unreal Engine → Library → «+» → 5.8 → Install (шаг А3 в НАСТРОЙКА_СПРИНТ0.md)'

# Инструменты
foreach ($t in @(@('git', 'Git for Windows'), @('git-lfs', 'git lfs install (идёт с Git for Windows)'), @('claude', 'npm i -g @anthropic-ai/claude-code'), @('tar', 'встроен в Windows 10/11'))) {
    $c = Get-Command $t[0] -ErrorAction SilentlyContinue
    Row "Инструмент $($t[0])" ([bool]$c) "$(if ($c) { $c.Source })" $t[1]
}

# Проект
$up = Join-Path $ProjectRoot 'CommandGame.uproject'
Row 'Проект CommandGame' (Test-Path $up) $ProjectRoot 'Оркестратор копирует ue_kit в папку проекта (шаг О4)'
if (Test-Path $up) {
    Row 'Git-репозиторий' (Test-Path (Join-Path $ProjectRoot '.git')) '' 'git init + git lfs install (шаг О5)'
    Row 'Бинарники проекта' (Test-Path (Join-Path $ProjectRoot 'Binaries\Win64')) '' 'Scripts\ue_build.ps1 (шаг О7)'
    Row 'Плагин Llama-Unreal' (Test-Path (Join-Path $ProjectRoot 'Plugins\Llama*')) '' 'Scripts\get_deps.ps1 -Plugin (шаг О9)'
    $m = Get-ChildItem (Join-Path $ProjectRoot 'Saved\Models') -Filter '*.gguf' -ErrorAction SilentlyContinue | Select-Object -First 1
    Row 'Модель GGUF' ([bool]$m) "$(if ($m) { '{0} ({1:N1} ГБ)' -f $m.Name, ($m.Length / 1GB) })" 'Scripts\get_deps.ps1 -Model (шаг О9)'
    Row '.mcp.json (Unreal MCP)' (Test-Path (Join-Path $ProjectRoot '.mcp.json')) '' 'Лежит в ue_kit; иначе в редакторе: ModelContextProtocol.GenerateClientConfig ClaudeCode'
}

# Codex для картинок (необязательно)
$codex = Get-Command codex -ErrorAction SilentlyContinue
Row 'Codex (картинки, необязательно)' ([bool]$codex) "$(if ($codex) { $codex.Source })" 'npm i -g @openai/codex, затем codex login'

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 220
$bad = @($rows | Where-Object State -eq 'НЕТ')
Write-Output ("ИТОГО: {0} проверок, не готово: {1}" -f $rows.Count, $bad.Count)
