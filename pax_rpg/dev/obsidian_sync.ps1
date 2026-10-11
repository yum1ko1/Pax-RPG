# Разложить дерево Obsidian «Pax RPG» из репозитория в хранилище на ПК (C:\MODS\Моды\Pax RPG).
# Берёт последнюю версию ветки pax-rpg/main (git в папке игры). Заметки, которые автор создал в этой папке
# руками и которых нет в репозитории, не удаляются; одноимённые — перезаписываются версией из репозитория.
#   .\obsidian_sync.ps1 [-Vault 'C:\MODS\Моды']
param([string]$Vault = '')
$ErrorActionPreference = 'Stop'
if ($Vault -eq '') {
    $cfg = Get-Content -Raw -Encoding UTF8 "$env:APPDATA\obsidian\obsidian.json" | ConvertFrom-Json
    $Vault = ($cfg.vaults.PSObject.Properties | ForEach-Object { $_.Value.path } | Select-Object -First 1)
}
git fetch -q pax-rpg main
$zip = Join-Path $env:TEMP 'pax_rpg_obsidian.zip'
$tmp = Join-Path $env:TEMP 'pax_rpg_obsidian'
git archive --format=zip -o $zip pax-rpg/main obsidian
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Expand-Archive -Force $zip $tmp
$src = Join-Path $tmp 'obsidian\Pax RPG'
$dst = Join-Path $Vault 'Pax RPG'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Recurse -Force (Join-Path $src '*') $dst
$n = (Get-ChildItem -Recurse -File $dst).Count
Write-Output "Pax RPG → $dst ($n файлов)"
