# Тест мультиплеера на одном ПК: две копии игры. В первой — «Мультиплеер» → создать игру (хост),
# во второй — «Мультиплеер» → найти игру / по приглашению. Обе зайдите в один город — герои видят друг друга.
# Окна — половинки экрана. Запуск: powershell -ExecutionPolicy Bypass -File pax_rpg\dev\mp_two.ps1
$game = "$env:LOCALAPPDATA\Programs\Pax Universe\PaxUniverse.exe"
if (-not (Test-Path $game)) { Write-Error "Нет $game"; exit 1 }
Start-Process $game -ArgumentList "--windowed --resolution 960x1040 --position 0,0"
Start-Sleep -Seconds 4
Start-Process $game -ArgumentList "--windowed --resolution 960x1040 --position 960,0"
