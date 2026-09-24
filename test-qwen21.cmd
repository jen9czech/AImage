@echo off
setlocal
cd /d "%~dp0"

if not exist "engine\sd-cli.exe" (
  echo ERROR: engine\sd-cli.exe not found. Run setup.ps1 first.
  exit /b 1
)

if not exist "models\qwen-image-2.1-Q4_K_M.gguf" (
  echo ERROR: Q4_K_M model not found. Run setup.ps1 first.
  exit /b 1
)

if not exist "output" mkdir output

echo === Devices ===
engine\sd-cli.exe --list-devices
if errorlevel 1 exit /b %errorlevel%

echo.
echo === Qwen Image 2.1 test ===
echo Output: output\qwen21-test.png
echo.

engine\sd-cli.exe ^
  --diffusion-model "models\qwen-image-2.1-Q4_K_M.gguf" ^
  --llm "models\Qwen3-VL-8B-Instruct-Q4_K_M.gguf" ^
  --vae "models\qwen_image_2.1_vae_bf16.safetensors" ^
  --backend "diffusion=cuda0,te=cpu,vae=cpu" ^
  --diffusion-fa ^
  --sampling-method euler ^
  --cfg-scale 6.0 ^
  --steps 40 ^
  --seed 42 ^
  -W 1024 ^
  -H 1024 ^
  -p "A highly detailed photograph of a sheep" ^
  -o "output\qwen21-test.png" ^
  -v

set EXITCODE=%errorlevel%
echo.
if %EXITCODE% EQU 0 (
  echo SUCCESS. Check output\qwen21-test.png
) else (
  echo FAILED with exit code %EXITCODE%.
  echo Copy the complete console output so we can tune backend placement or memory settings.
)
exit /b %EXITCODE%
