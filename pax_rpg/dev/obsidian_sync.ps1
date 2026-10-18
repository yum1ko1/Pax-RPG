# Хранилище Obsidian «Pax RPG» — отдельное (не внутри общего хранилища модов): C:\MODS\Pax RPG.
# Берёт последнюю версию из репозитория (obsidian/Pax RPG Vault, ветка pax-rpg/main — git в папке игры),
# раскладывает в хранилище и регистрирует его в Obsidian (obsidian.json), если ещё не зарегистрировано.
# Заметки, созданные автором руками и которых нет в репозитории, не удаляются; одноимённые — обновляются.
#   .\obsidian_sync.ps1 [-Vault 'C:\MODS\Pax RPG']
param([string]$Vault = 'C:\MODS\Pax RPG')
$ErrorActionPreference = 'Stop'
git fetch -q pax-rpg main
$zip = Join-Path $env:TEMP 'pax_rpg_obsidian.zip'
$tmp = Join-Path $env:TEMP 'pax_rpg_obsidian'
git archive --format=zip -o $zip pax-rpg/main obsidian
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Expand-Archive -Force $zip $tmp
$src = Join-Path $tmp 'obsidian\Pax RPG Vault'
New-Item -ItemType Directory -Force $Vault | Out-Null
Copy-Item -Recurse -Force (Join-Path $src '*') $Vault
Copy-Item -Recurse -Force (Join-Path $src '.obsidian') $Vault
$cfgPath = "$env:APPDATA\obsidian\obsidian.json"
if (Test-Path $cfgPath) {
    $cfg = Get-Content -Raw -Encoding UTF8 $cfgPath | ConvertFrom-Json
    $known = $cfg.vaults.PSObject.Properties | Where-Object { $_.Value.path -eq $Vault }
    if (-not $known) {
        $id = -join ((48..57) + (97..102) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
        $cfg.vaults | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ path = $Vault; ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() })
        $cfg | ConvertTo-Json -Depth 5 -Compress | Set-Content -Encoding UTF8 $cfgPath
        Write-Output "зарегистрировано в Obsidian: $Vault"
    }
}
$n = (Get-ChildItem -Recurse -File $Vault).Count
Write-Output "Pax RPG → $Vault ($n файлов)"
