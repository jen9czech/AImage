@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0benchmark-qwen.ps1" %*
exit /b %errorlevel%
