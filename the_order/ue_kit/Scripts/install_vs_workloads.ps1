# Добавляет в установленную Visual Studio нагрузки, нужные UE 5.8: «Game development with C++» и «Desktop development with C++»
# (MSVC, Windows SDK входят в рекомендуемые компоненты). Windows покажет окно UAC — его подтверждает автор.
# Перед запуском закройте Visual Studio. Объём ≈ 8–15 ГБ на диске C:.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
$path = & $vswhere -latest -products * -property installationPath
if (-not $path) { Write-Output 'Visual Studio не найдена — сначала установите VS 2022 Community (17.14+) или VS 2026.'; exit 1 }
Write-Output "Visual Studio: $path"
Write-Output 'Сейчас появится окно UAC «Разрешить этому приложению вносить изменения?» — нажмите «Да». Установка идёт в фоне 10–30 минут.'
$p = Start-Process -FilePath $setup -Verb RunAs -Wait -PassThru -ArgumentList @(
    'modify', '--installPath', "`"$path`"",
    '--add', 'Microsoft.VisualStudio.Workload.NativeGame',
    '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop',
    '--includeRecommended', '--passive', '--norestart')
Write-Output "Visual Studio Installer завершился с кодом $($p.ExitCode) (0 или 3010 — успех; 3010 — нужна перезагрузка)."
