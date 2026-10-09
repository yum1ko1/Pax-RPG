# Отправить Python-код (base64) в открытый Blender: расширение Blender MCP слушает localhost:9876.
# Код кладёт ответ в dict `result`. Через мост: & .\pax_corporations_dev\blender_live.ps1 '<base64>'
param([string]$B64)
$code = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($B64))
$req = @{type = 'execute'; code = $code; strict_json = $false} | ConvertTo-Json -Compress
$c = New-Object Net.Sockets.TcpClient('127.0.0.1', 9876)
$s = $c.GetStream()
$b = [Text.Encoding]::UTF8.GetBytes($req + [char]0)
$s.Write($b, 0, $b.Length)
$ms = New-Object IO.MemoryStream
$buf = New-Object byte[] 65536
do { $n = $s.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $ms.Write($buf, 0, $n) } while ($buf[$n - 1] -ne 0)
$c.Close()
[Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimEnd([char]0)
