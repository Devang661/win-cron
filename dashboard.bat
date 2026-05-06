@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_dashboard.ps1"
start "" "%~dp0dashboard.html"
exit /b %errorlevel%
