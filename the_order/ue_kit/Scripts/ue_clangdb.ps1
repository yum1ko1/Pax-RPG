# compile_commands.json для clangd (переход к определению, ошибки без полной сборки).
# Генерирует UnrealBuildTool; файл копируется в корень проекта. Пересоздаётся целиком — запускать после добавления файлов.
. "$PSScriptRoot\ue_env.ps1"

$t0 = Get-Date
& $UBT -mode=GenerateClangDatabase "-project=$UProject" CommandGameEditor Win64 Development 2>&1 | Out-File -Encoding utf8 (Join-Path $LogDir 'clangdb_last.log')
$db = @($ProjectRoot, $UERoot) | ForEach-Object { Get-ChildItem $_ -Filter 'compile_commands.json' -ErrorAction SilentlyContinue } |
    Where-Object { $_.LastWriteTime -ge $t0 } | Select-Object -First 1
if (-not $db) { Write-Output 'compile_commands.json не появился — см. Saved\Logs\clangdb_last.log'; exit 1 }
if ($db.DirectoryName -ne $ProjectRoot) { Copy-Item $db.FullName (Join-Path $ProjectRoot 'compile_commands.json') -Force }
Write-Output "OK: $(Join-Path $ProjectRoot 'compile_commands.json')"
