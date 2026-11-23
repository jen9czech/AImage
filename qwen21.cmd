@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0qwen21.ps1" %*
exit /b %errorlevel%
