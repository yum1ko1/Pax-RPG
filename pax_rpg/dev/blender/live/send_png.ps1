# Отправить картинки проверки в облако: коммит в служебную ветку pax-rpg-renders (рабочий каталог и индекс не трогаются).
#   & .\pax_corporations_dev\send_png.ps1 C:\...\a.png C:\...\b.png
$files = @($args | Where-Object { Test-Path $_ })
if ($files.Count -eq 0) { "no files"; exit 1 }
$lines = foreach ($f in $files) { $h = git hash-object -w $f; "100644 blob $h`t$([IO.Path]::GetFileName($f))" }
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"))
$tree = cmd /c "git mktree < `"$tmp`""
Remove-Item $tmp
if (-not $tree) { "no tree"; exit 1 }
$parent = git rev-parse -q --verify refs/remotes/pax-corpinc/pax-rpg-renders 2>$null
if ($parent) { $c = git commit-tree $tree -p $parent -m "renders" } else { $c = git commit-tree $tree -m "renders" }
if (-not $c) { "no commit"; exit 1 }
git push -q pax-corpinc "${c}:refs/heads/pax-rpg-renders" 2>&1 | Out-Null
git fetch -q pax-corpinc pax-rpg-renders 2>&1 | Out-Null
"pushed $c"
