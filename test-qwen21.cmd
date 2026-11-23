@echo off
setlocal
cd /d "%~dp0"
set "ENGINE=engine\sd-cli.exe"
if not exist "%SystemRoot%\System32\nvcuda.dll" if exist "engine-vulkan\sd-cli.exe" (
  set "ENGINE=engine-vulkan\sd-cli.exe"
)

if not exist "%ENGINE%" (
  echo ERROR: engine\sd-cli.exe not found. Run setup.ps1 first.
  exit /b 1
)

echo === Devices ===
"%ENGINE%" --list-devices
if errorlevel 1 exit /b %errorlevel%

echo.
echo === Qwen Image 2.1 test ===
echo Output: your configured Pictures\AI\AImage folder
echo.

call "%~dp0qwen21.cmd" qwen21-test "A highly detailed photograph of a sheep" 1024 1024 40 42

set EXITCODE=%errorlevel%
echo.
if %EXITCODE% EQU 0 (
  echo SUCCESS. Check your configured Pictures\AI\AImage folder.
) else (
  echo FAILED with exit code %EXITCODE%.
  echo Copy the complete console output so we can tune backend placement or memory settings.
)
exit /b %EXITCODE%
