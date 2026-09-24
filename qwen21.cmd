@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0qwen21.ps1" %*
exit /b %errorlevel%