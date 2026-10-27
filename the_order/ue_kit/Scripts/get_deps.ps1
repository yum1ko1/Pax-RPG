# Скачивает зависимости проекта (только с согласия автора):
#   -Plugin — Llama-Unreal v1.4.0 для UE 5.8 (≈25 МБ) → Plugins\
#   -Model  — Qwen3-4B-RPG-Roleplay-V2 Q4_K_M (≈2.5 ГБ, лицензия MIT) → Saved\Models\
#   powershell -ExecutionPolicy Bypass -File Scripts\get_deps.ps1 -Plugin -Model
param([switch]$Plugin, [switch]$Model)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $env:TEMP 'order_deps'
New-Item -ItemType Directory -Force $tmp | Out-Null

if ($Plugin) {
    $url = 'https://github.com/getnamo/Llama-Unreal/releases/download/v1.4.0/Llama-Unreal-UE5.8-v1.4.0-Vulkan.7z'
    $arc = Join-Path $tmp 'Llama-Unreal.7z'
    Write-Output "Скачиваю $url"
    curl.exe -L --fail -o $arc $url
    if ($LASTEXITCODE) { Write-Output 'Не скачалось.'; exit 1 }
    $x = Join-Path $tmp 'llama_x'
    Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $x | Out-Null
    tar -xf $arc -C $x
    if ($LASTEXITCODE) {
        $7z = 'C:\Program Files\7-Zip\7z.exe'
        if (-not (Test-Path $7z)) { Write-Output 'tar не распаковал 7z. Поставьте 7-Zip: winget install 7zip.7zip — и повторите.'; exit 1 }
        & $7z x $arc "-o$x" -y | Out-Null
    }
    # В архиве лежит папка Plugins — её содержимое копируем в Plugins проекта (так в README плагина).
    $src = Get-ChildItem $x -Recurse -Directory -Filter 'Plugins' | Select-Object -First 1
    if (-not $src) { Write-Output "В архиве нет папки Plugins — смотрите $x"; exit 1 }
    New-Item -ItemType Directory -Force (Join-Path $ProjectRoot 'Plugins') | Out-Null
    Copy-Item (Join-Path $src.FullName '*') (Join-Path $ProjectRoot 'Plugins') -Recurse -Force
    Get-ChildItem (Join-Path $ProjectRoot 'Plugins') -Recurse -Filter '*.uplugin' | ForEach-Object { "Плагин: $($_.FullName)" }
}

if ($Model) {
    $url = 'https://huggingface.co/Chun121/Qwen3-4B-RPG-Roleplay-V2/resolve/main/unsloth.Q4_K_M.gguf'
    $dir = Join-Path $ProjectRoot 'Saved\Models'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dst = Join-Path $dir 'Qwen3-4B-RPG-Roleplay-V2.Q4_K_M.gguf'
    Write-Output "Скачиваю модель (≈2.5 ГБ) → $dst"
    curl.exe -L --fail -C - -o $dst $url
    if ($LASTEXITCODE) { Write-Output 'Не скачалось (повторный запуск докачает).'; exit 1 }
    $len = (Get-Item $dst).Length
    Write-Output ("Модель: {0:N2} ГБ (ожидается 2 497 276 416 байт, сейчас {1})" -f ($len / 1GB), $len)
}
if (-not $Plugin -and -not $Model) { Write-Output 'Укажите -Plugin и/или -Model.' }
