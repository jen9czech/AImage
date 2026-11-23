param(
    [ValidateSet('qwen21', 'flux1-schnell', 'lustify-v10-krea2-turbo', 'lustify-zenith-v9')]
    [string]$ModelFamily = 'qwen21',

    [ValidateSet('Q4_0', 'Q4_K_M', 'Q5_K_M', 'Q6_K', 'Q8_0')]
    [string]$DiffusionQuantization = 'Q4_K_M',

    [switch]$IncludeVision,
    [switch]$EngineOnly,
    [switch]$UpdateEngine,
    [switch]$KeepDownloads,

    [ValidateSet('cuda12', 'vulkan')]
    [string]$EngineBackend
)

$ErrorActionPreference = 'Stop'
if ($IncludeVision -and ($EngineOnly -or $ModelFamily -ne 'qwen21')) {
    throw '-IncludeVision requires a Qwen Image 2.1 model install.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'paths.ps1')
$Paths = Get-AImagePaths -Root $Root
if (-not $EngineBackend) {
    $nvidiaDriver = Join-Path ([Environment]::SystemDirectory) 'nvcuda.dll'
    $EngineBackend = if (Test-Path -LiteralPath $nvidiaDriver) { 'cuda12' } else { 'vulkan' }
}
$EngineDir = Join-Path $Root 'engine'
if ($EngineBackend -eq 'vulkan') { $EngineDir = Join-Path $Root 'engine-vulkan' }
$ModelsDir = $Paths.Models
$OutputDir = $Paths.Output
$DownloadsDir = Join-Path $Root 'downloads'

New-Item -ItemType Directory -Force -Path $EngineDir,$ModelsDir,$OutputDir,$DownloadsDir | Out-Null

function Test-InstalledFile([string]$Path) {
    return [IO.File]::Exists($Path) -and (Get-Item -LiteralPath $Path).Length -gt 0
}

function Confirm-DownloadHash([string]$Path, [string]$Sha256) {
    if (-not $Sha256) { return }
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '') }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
    if ($actual -ne $Sha256) { throw "Checksum mismatch: $Path" }
}

function Complete-Download([string]$Partial, [string]$Destination, [string]$Sha256, [long]$ExpectedBytes) {
    if (-not (Test-InstalledFile $Partial)) { throw "Downloaded file is empty: $Partial" }
    if ($ExpectedBytes -gt 0 -and (Get-Item -LiteralPath $Partial).Length -ne $ExpectedBytes) {
        throw "Downloaded file length did not match the source: $Partial"
    }
    Confirm-DownloadHash $Partial $Sha256
    Move-Item -Force -LiteralPath $Partial -Destination $Destination
}

function Download-File([string]$Url, [string]$Destination, [string]$Sha256, [long]$ExpectedBytes) {
    if (Test-InstalledFile $Destination) {
        Write-Host "Already exists: $Destination" -ForegroundColor DarkGray
        return
    }
    $partial = "$Destination.part"
    if ($Sha256 -and $ExpectedBytes -gt 0 -and (Test-InstalledFile $partial) -and
        (Get-Item -LiteralPath $partial).Length -eq $ExpectedBytes) {
        Complete-Download $partial $Destination $Sha256 $ExpectedBytes
        return
    }
    Write-Host "Downloading $([IO.Path]::GetFileName($Destination)) ..." -ForegroundColor Cyan
    & curl.exe -L --fail --retry 3 --retry-delay 3 --proto '=https' --proto-redir '=https' -C - -o $partial $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    Complete-Download $partial $Destination $Sha256 $ExpectedBytes
}

function Get-EngineVersion([string]$Path) {
    if (-not (Test-InstalledFile $Path)) { return }
    $ErrorActionPreference = 'Continue'
    $version = & $Path --version 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $version.Trim()) { return $version.Trim() }
}

function Install-Archive($Asset) {
    $archivePath = Join-Path $DownloadsDir ([IO.Path]::GetFileName($Asset.name))
    $alreadyHadArchive = Test-InstalledFile $archivePath
    $hash = if ($Asset.digest -match '^sha256:([a-fA-F0-9]{64})$') { $Matches[1] } else { '' }
    Download-File $Asset.browser_download_url $archivePath $hash $Asset.size
    if ($alreadyHadArchive) { Confirm-DownloadHash $archivePath $hash }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $EngineDir -Force
    if (-not $alreadyHadArchive) { return $archivePath }
}

$installedExe = Join-Path $EngineDir 'sd-cli.exe'
$installedVersion = Get-EngineVersion $installedExe

if ($installedVersion -and -not $UpdateEngine) {
    Write-Host "Using installed engine: $installedVersion" -ForegroundColor DarkGray
} else {
    Write-Host 'Finding the stable-diffusion.cpp Windows release...' -ForegroundColor Cyan
    $headers = @{ 'User-Agent' = 'aimage-installer' }
    $release = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/latest'
    $engineAsset = $release.assets | Where-Object { $_.name -match "^sd-.*-bin-win-$EngineBackend-x64\.zip$" } | Select-Object -First 1
    $cudartAsset = $release.assets | Where-Object { $_.name -match 'cudart.*win-cu12-x64\.zip$' } | Select-Object -First 1

    if (-not $engineAsset) { throw "Could not find Windows $EngineBackend x64 stable-diffusion.cpp asset in latest release." }

    $releaseCommit = [regex]::Match($engineAsset.name, '^sd-master-([a-f0-9]+)-').Groups[1].Value
    $newArchives = @()
    if ($releaseCommit -and $installedVersion -match "commit $releaseCommit") {
        Write-Host "Engine already current: $releaseCommit" -ForegroundColor DarkGray
    } else {
        $newArchives += @(Install-Archive $engineAsset)
    }

    if ($EngineBackend -eq 'vulkan') {
        Write-Host 'Vulkan uses the installed graphics driver; CUDA runtime is not required.' -ForegroundColor DarkGray
    } elseif ($cudartAsset) {
        if (-not $installedVersion -or -not (Test-InstalledFile (Join-Path $EngineDir 'cudart64_12.dll'))) {
            $newArchives += @(Install-Archive $cudartAsset)
        } else {
            Write-Host 'CUDA runtime already present.' -ForegroundColor DarkGray
        }
    } else {
        Write-Warning 'Separate CUDA runtime asset was not found. This is okay if the runtime is bundled or installed system-wide.'
    }
    if (-not (Get-EngineVersion $installedExe)) {
        throw "The Windows $EngineBackend engine could not start. Check the graphics driver and Windows runtime dependencies before installing models."
    }
    if (-not $KeepDownloads) {
        foreach ($archivePath in $newArchives) { [IO.File]::Delete($archivePath) }
    }
}

if ($EngineOnly) {
    Write-Host 'Engine setup complete. Use setup.cmd -ModelFamily to install a model, or place compatible weights in the model folder.'
    Write-Host "Models: $ModelsDir"
    exit 0
}

if ($ModelFamily -eq 'qwen21') {
    $modelBase = 'https://huggingface.co/abenzerps/Qwen-Image-2.1-Turbo-Quantized/resolve/base'
    $encoderBase = 'https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/resolve/main'
    $diffusionName = "qwen-image-2.1-$DiffusionQuantization.gguf"
    Download-File "$modelBase/${diffusionName}?download=true" (Join-Path $ModelsDir $diffusionName)
    Download-File "$encoderBase/Qwen3-VL-8B-Instruct-Q4_K_M.gguf?download=true" (Join-Path $ModelsDir 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf')
    Download-File "$modelBase/vae/qwen_image_2.1_vae_bf16.safetensors?download=true" (Join-Path $ModelsDir 'qwen_image_2.1_vae_bf16.safetensors')
    if ($IncludeVision) {
        $visionBase = 'https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main'
        Download-File "$visionBase/mmproj-Qwen3VL-8B-Instruct-F16.gguf?download=true" (Join-Path $ModelsDir 'mmproj-Qwen3VL-8B-Instruct-F16.gguf')
    }
} elseif ($ModelFamily -eq 'flux1-schnell') {
    $fluxBase = 'https://huggingface.co/leejet/FLUX.1-schnell-gguf/resolve/main'
    $fluxVaeBase = 'https://huggingface.co/unsloth/FLUX.1-schnell/resolve/main'
    $fluxTextBase = 'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main'
    Download-File "$fluxBase/flux1-schnell-q3_k.gguf?download=true" (Join-Path $ModelsDir 'flux1-schnell-q3_k.gguf')
    Download-File "$fluxVaeBase/ae.safetensors?download=true" (Join-Path $ModelsDir 'ae.safetensors')
    Download-File "$fluxTextBase/clip_l.safetensors?download=true" (Join-Path $ModelsDir 'clip_l.safetensors')
    Download-File "$fluxTextBase/t5xxl_fp16.safetensors?download=true" (Join-Path $ModelsDir 't5xxl_fp16.safetensors')
} elseif ($ModelFamily -eq 'lustify-zenith-v9') {
    $zenithUrl = 'https://huggingface.co/torestinbar/krea2-resources/resolve/main/checkpoints/civitai-3045803-1a3abf0bf481-lustifyNSFWCheckpoint_zenithV9.safetensors'
    Download-File $zenithUrl (Join-Path $ModelsDir 'lustifyNSFWCheckpoint_zenithV9.safetensors') '1a3abf0bf48113eb5e17d2f8ae012c5b60cb97d81d79c4d9e47cd5af56c162f1' 6938143490
} else {
    $kreaBase = 'https://huggingface.co/kkkkk26/lustifyNSFWCheckpoint_v10Krea2Turbo/resolve/main'
    $kreaTextBase = 'https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/resolve/main'
    $kreaVaeBase = 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae'
    $kreaSource = Join-Path $ModelsDir 'lustifyNSFWCheckpoint_v10Krea2.safetensors'
    $kreaQ8 = Join-Path $ModelsDir 'lustifyNSFWCheckpoint_v10Krea2-Q8_0.gguf'
    Download-File "$kreaTextBase/Qwen3VL-4B-Instruct-Q4_K_M.gguf?download=true" (Join-Path $ModelsDir 'Qwen3VL-4B-Instruct-Q4_K_M.gguf')
    Download-File "$kreaVaeBase/wan_2.1_vae.safetensors?download=true" (Join-Path $ModelsDir 'wan_2.1_vae.safetensors')
    if (-not (Test-InstalledFile $kreaQ8)) {
        $alreadyHadSource = Test-InstalledFile $kreaSource
        Download-File "$kreaBase/lustifyNSFWCheckpoint_v10Krea2.safetensors?download=true" $kreaSource
        $kreaQ8Partial = "$kreaQ8.$([Guid]::NewGuid().ToString('N')).gguf"
        try {
            Write-Host 'Converting Lustify Krea 2 to Q8 for faster local generation...' -ForegroundColor Cyan
            & $installedExe --mode convert --model $kreaSource --output $kreaQ8Partial --type q8_0
            if ($LASTEXITCODE -ne 0 -or -not (Test-InstalledFile $kreaQ8Partial)) { throw 'Krea 2 Q8 conversion failed.' }
            $converted = [IO.File]::OpenRead($kreaQ8Partial)
            try {
                $magic = [byte[]]::new(4)
                if ($converted.Read($magic, 0, 4) -ne 4 -or [Text.Encoding]::ASCII.GetString($magic) -cne 'GGUF') {
                    throw 'Krea 2 conversion did not produce a GGUF model.'
                }
            } finally { $converted.Dispose() }
            Move-Item -Force -LiteralPath $kreaQ8Partial -Destination $kreaQ8
        } finally {
            if ([IO.File]::Exists($kreaQ8Partial)) { [IO.File]::Delete($kreaQ8Partial) }
        }
        if (-not $alreadyHadSource -and -not $KeepDownloads) { [IO.File]::Delete($kreaSource) }
    }
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "Engine: $EngineDir"
Write-Host "Models: $ModelsDir"
Write-Host ''
if ($ModelFamily -eq 'flux1-schnell') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'queue.ps1') model -Model flux1-schnell
    if ($LASTEXITCODE -ne 0) { throw 'FLUX.1 files downloaded, but selecting its profile failed.' }
}
Write-Host 'Next run: aimage.cmd' -ForegroundColor Green
