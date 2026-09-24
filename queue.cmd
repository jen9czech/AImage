@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0queue.ps1" %*
exit /b %errorlevel%
