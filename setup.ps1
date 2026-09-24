param(
    [ValidateSet('qwen21', 'flux1-schnell', 'lustify-v2')]
    [string]$ModelFamily = 'qwen21',

    [ValidateSet('Q4_0', 'Q4_K_M', 'Q5_K_M', 'Q6_K', 'Q8_0')]
    [string]$DiffusionQuantization = 'Q4_K_M',

    [switch]$IncludeVision
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$EngineDir = Join-Path $Root 'engine'
$ModelsDir = Join-Path $Root 'models'
$OutputDir = Join-Path $Root 'output'
$DownloadsDir = Join-Path $Root 'downloads'

New-Item -ItemType Directory -Force -Path $EngineDir,$ModelsDir,$OutputDir,$DownloadsDir | Out-Null

function Download-File([string]$Url, [string]$Destination) {
    if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
        Write-Host "Already exists: $Destination" -ForegroundColor DarkGray
        return
    }
    $partial = "$Destination.part"
    Write-Host "Downloading $([IO.Path]::GetFileName($Destination)) ..." -ForegroundColor Cyan
    & curl.exe -L --fail --retry 20 --retry-all-errors --retry-delay 3 -C - -o $partial $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    if ((Get-Item $partial).Length -eq 0) { throw "Downloaded file is empty: $Url" }
    Move-Item -Force $partial $Destination
}

Write-Host "Finding latest stable-diffusion.cpp release..." -ForegroundColor Cyan
$headers = @{ 'User-Agent' = 'aimage-installer' }
$installedExe = Join-Path $EngineDir 'sd-cli.exe'
try {
    $release = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/latest'
} catch {
    if (-not (Test-Path $installedExe)) { throw "Could not check for the engine release and no installed sd-cli.exe is available: $_" }
    Write-Warning 'Could not check the engine release; continuing with installed sd-cli.exe.'
    $release = $null
}

if ($release) {
    $engineAsset = $release.assets | Where-Object { $_.name -match '^sd-.*-bin-win-cuda12-x64\.zip$' } | Select-Object -First 1
    $cudartAsset = $release.assets | Where-Object { $_.name -match 'cudart.*win-cu12-x64\.zip$' } | Select-Object -First 1

    if (-not $engineAsset) { throw 'Could not find Windows CUDA12 x64 stable-diffusion.cpp asset in latest release.' }

    $engineZip = Join-Path $DownloadsDir $engineAsset.name
    $releaseCommit = [regex]::Match($engineAsset.name, '^sd-master-([a-f0-9]+)-').Groups[1].Value
    $installedVersion = if (Test-Path $installedExe) { (& $installedExe --version 2>&1 | Out-String) } else { '' }
    if ($releaseCommit -and $installedVersion -match "commit $releaseCommit") {
        Write-Host "Engine already current: $releaseCommit" -ForegroundColor DarkGray
    } else {
        Download-File $engineAsset.browser_download_url $engineZip
        Write-Host "Extracting engine..." -ForegroundColor Cyan
        Expand-Archive -Path $engineZip -DestinationPath $EngineDir -Force
    }

    if ($cudartAsset) {
        $cudartZip = Join-Path $DownloadsDir $cudartAsset.name
        if (-not (Test-Path (Join-Path $EngineDir 'cudart64_12.dll'))) {
            Download-File $cudartAsset.browser_download_url $cudartZip
            Write-Host "Extracting CUDA runtime DLLs..." -ForegroundColor Cyan
            Expand-Archive -Path $cudartZip -DestinationPath $EngineDir -Force
        } else {
            Write-Host 'CUDA runtime already present.' -ForegroundColor DarkGray
        }
    } else {
        Write-Warning 'Separate CUDA runtime asset was not found. This is okay if the runtime is bundled or installed system-wide.'
    }
}

if ($ModelFamily -eq 'qwen21') {
    $modelBase = 'https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/resolve/base'
    $vaeBase = 'https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/resolve/main'
    $encoderBase = 'https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/resolve/main'
    $diffusionName = "qwen-image-2.1-$DiffusionQuantization.gguf"
    Download-File "$modelBase/${diffusionName}?download=true" (Join-Path $ModelsDir $diffusionName)
    Download-File "$encoderBase/Qwen3-VL-8B-Instruct-Q4_K_M.gguf?download=true" (Join-Path $ModelsDir 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf')
    Download-File "$vaeBase/vae/qwen_image_2.1_vae_bf16.safetensors?download=true" (Join-Path $ModelsDir 'qwen_image_2.1_vae_bf16.safetensors')
    if ($IncludeVision) {
        $visionBase = 'https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main'
        Download-File "$visionBase/mmproj-Qwen3VL-8B-Instruct-F16.gguf?download=true" (Join-Path $ModelsDir 'mmproj-Qwen3VL-8B-Instruct-F16.gguf')
    }
} elseif ($ModelFamily -eq 'flux1-schnell') {
    if ($IncludeVision) { throw '-IncludeVision is for Qwen Image 2.1 only.' }
    $fluxBase = 'https://huggingface.co/leejet/FLUX.1-schnell-gguf/resolve/main'
    $fluxVaeBase = 'https://huggingface.co/unsloth/FLUX.1-schnell/resolve/main'
    $fluxTextBase = 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main'
    Download-File "$fluxBase/flux1-schnell-q3_k.gguf?download=true" (Join-Path $ModelsDir 'flux1-schnell-q3_k.gguf')
    Download-File "$fluxVaeBase/ae.safetensors?download=true" (Join-Path $ModelsDir 'ae.safetensors')
    Download-File "$fluxTextBase/clip_l.safetensors?download=true" (Join-Path $ModelsDir 'clip_l.safetensors')
    Download-File "$fluxTextBase/t5xxl_fp16.safetensors?download=true" (Join-Path $ModelsDir 't5xxl_fp16.safetensors')
} else {
    if ($IncludeVision) { throw '-IncludeVision is for Qwen Image 2.1 only.' }
    $lustifyBase = 'https://huggingface.co/shootstuff/LUSTIFY-v2.0/resolve/main'
    Download-File "$lustifyBase/lustifySDXLNSFWSFW_v20.safetensors?download=true" (Join-Path $ModelsDir 'lustifySDXLNSFWSFW_v20.safetensors')
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "Engine: $EngineDir"
Write-Host "Models: $ModelsDir"
Write-Host ''
if ($ModelFamily -ne 'qwen21') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'queue.ps1') model -Model $ModelFamily
    if ($LASTEXITCODE -ne 0) { throw "Model files downloaded, but selecting $ModelFamily failed." }
}
Write-Host 'Next run: queue.cmd add "A photograph of a sheep"' -ForegroundColor Green
