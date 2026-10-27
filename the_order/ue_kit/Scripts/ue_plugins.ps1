# Сверяет плагины из CommandGame.uproject с тем, что реально есть в движке и в Plugins проекта,
# и показывает кандидатов по ключевым словам. Запускать до первого открытия редактора:
# включённый, но не найденный плагин не даст открыть проект.
#   powershell -ExecutionPolicy Bypass -File Scripts\ue_plugins.ps1 [-Find Fracture,Toolset]
param([string[]]$Find = @('ModelContextProtocol', 'Toolset', 'Fracture', 'GeometryCollection', 'Chaos', 'Significance', 'Python', 'EditorScripting', 'Terminal', 'Llama'))
. "$PSScriptRoot\ue_env.ps1"

$all = @()
foreach ($root in @((Join-Path $UERoot 'Engine\Plugins'), (Join-Path $ProjectRoot 'Plugins'))) {
    if (Test-Path $root) {
        $all += Get-ChildItem $root -Recurse -Filter '*.uplugin' -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Name = $_.BaseName; Path = $_.DirectoryName } }
    }
}
Write-Output "Найдено плагинов: $($all.Count)"

$proj = Get-Content $UProject -Raw | ConvertFrom-Json
Write-Output '--- Плагины из .uproject'
foreach ($p in $proj.Plugins) {
    $hit = $all | Where-Object Name -eq $p.Name | Select-Object -First 1
    if ($hit) { Write-Output ("OK   {0,-28} {1}" -f $p.Name, $hit.Path) }
    else { Write-Output ("НЕТ  {0,-28} — исправьте имя в CommandGame.uproject или уберите строку" -f $p.Name) }
}
Write-Output '--- Кандидаты по ключевым словам'
foreach ($k in $Find) {
    $all | Where-Object Name -like "*$k*" | Select-Object -First 8 | ForEach-Object { "{0,-18} {1,-36} {2}" -f $k, $_.Name, $_.Path }
}
