@echo off
chcp 65001 >nul
title Claude Cron
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude_cron.ps1" %*
exit /b %errorlevel%
