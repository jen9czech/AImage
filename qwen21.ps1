param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$OutputName,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Prompt,

    [Parameter(Position = 2)]
    [int]$Width = 1024,

    [Parameter(Position = 3)]
    [int]$Height = 1024,

    [Parameter(Position = 4)]
    [int]$Steps = 0,

    [Parameter(Position = 5)]
    [int]$Seed = 42,

    [string]$Model = 'qwen-image-2.1-Q4_K_M.gguf',
    [string]$NegativePrompt,

    [string]$ReferenceImage,
    [string]$InitImage,
    [double]$Strength = 0.75
)

$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$EnginePath         = Join-Path $BaseDir "engine\sd-cli.exe"
$DefaultOutputDir   = Join-Path $BaseDir "output"

if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt cannot be empty.' }
if ($ReferenceImage -and $InitImage) { throw 'Use either -ReferenceImage or -InitImage for one job.' }
if ($PSBoundParameters.ContainsKey('Strength') -and -not $InitImage) { throw '-Strength applies only with -InitImage.' }
if ($Strength -le 0 -or $Strength -gt 1) { throw 'Strength must be greater than 0 and at most 1.' }
if ($Width -lt 32 -or $Width % 32 -ne 0 -or $Height -lt 32 -or $Height % 32 -ne 0) {
    throw 'Width and height must be positive multiples of 32.'
}
if ($Steps -lt 0) { throw 'Steps must be at least 1 when specified.' }

if (!(Test-Path $EnginePath)) {
    throw "sd-cli.exe not found: $EnginePath"
}

if ([IO.Path]::GetFileName($Model) -eq $Model -and $Model -match '^qwen[-_]image[-_]2[._]1.*\.gguf$') {
    $ModelLabel = "Qwen Image 2.1 ($Model)"
    $DiffusionModelPath = Join-Path $BaseDir (Join-Path 'models' $Model)
    $LlmPath = Join-Path $BaseDir 'models\Qwen3-VL-8B-Instruct-Q4_K_M.gguf'
    $VaePath = Join-Path $BaseDir 'models\qwen_image_2.1_vae_bf16.safetensors'
    foreach ($path in @($DiffusionModelPath, $LlmPath, $VaePath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Model file not found: $path" }
    }
    $ModelArgs = @('--diffusion-model', $DiffusionModelPath, '--llm', $LlmPath, '--vae', $VaePath,
        '--backend', 'diffusion=cuda0,te=cpu,vae=cpu', '--diffusion-fa', '--sampling-method', 'euler', '--cfg-scale', '6.0')
    if ($ReferenceImage) {
        $VisionPath = Join-Path $BaseDir 'models\mmproj-Qwen3VL-8B-Instruct-F16.gguf'
        if (-not (Test-Path -LiteralPath $VisionPath -PathType Leaf)) {
            throw 'Vision projector missing. Run setup.ps1 -IncludeVision to enable Qwen image editing.'
        }
        $ModelArgs += @('--llm_vision', $VisionPath, '--model-args', 'qwen_image_2_1_prefix_cache=false')
    }
    if ($Steps -eq 0) { $Steps = 40 }
} else {
    if ($Model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw 'Specify a model profile ID or a Qwen Image 2.1 GGUF filename.' }
    $profilePath = Join-Path $BaseDir (Join-Path 'profiles' "$Model.json")
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Profile not found: $profilePath" }
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($profile.id -ne $Model -or -not $profile.args -or -not $profile.requiredFiles) { throw "Invalid profile: $profilePath" }
    if ($ReferenceImage -and -not $profile.supportsReferenceImage) { throw "Profile '$Model' does not support reference images." }
    foreach ($file in $profile.requiredFiles) {
        $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $BaseDir $file }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Profile '$Model' needs: $path" }
    }
    $ModelLabel = if ($profile.name) { $profile.name } else { $Model }
    $ModelArgs = @($profile.args | ForEach-Object { ([string]$_).Replace('{root}', $BaseDir) })
    if ($Steps -eq 0) { $Steps = if ($profile.defaults.steps -gt 0) { [int]$profile.defaults.steps } else { 40 } }
    if (@($ModelArgs | Where-Object { $_ -match '^(-p|--prompt|-n|--negative-prompt|-o|--output|-W|--width|-H|--height|--steps|-s|--seed)$' }).Count) {
        throw "Profile '$Model' contains a job-specific argument. Remove prompt, negative prompt, output, size, steps, and seed from its args."
    }
}

if ($ReferenceImage) {
    if (-not (Test-Path -LiteralPath $ReferenceImage -PathType Leaf)) { throw "Reference image not found: $ReferenceImage" }
    $ModelArgs += @('-r', (Resolve-Path -LiteralPath $ReferenceImage).Path)
}
if ($InitImage) {
    if (-not (Test-Path -LiteralPath $InitImage -PathType Leaf)) { throw "Initial image not found: $InitImage" }
    $ModelArgs += @('--init-img', (Resolve-Path -LiteralPath $InitImage).Path,
        '--strength', $Strength.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))
}

if (!(Test-Path $DefaultOutputDir)) {
    New-Item -ItemType Directory -Path $DefaultOutputDir | Out-Null
}

# Resolve output path
if ([System.IO.Path]::IsPathRooted($OutputName)) {
    $OutputPath = $OutputName
} else {
    $OutputPath = Join-Path $DefaultOutputDir $OutputName
}

# Add .png if missing
if ([System.IO.Path]::GetExtension($OutputPath) -eq "") {
    $OutputPath = $OutputPath + ".png"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Output already exists: $OutputPath"
}

# Ensure target directory exists
$TargetDir = Split-Path -Parent $OutputPath
if ($TargetDir -and !(Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

Write-Host ""
Write-Host "=== $ModelLabel ==="
Write-Host "Output : $OutputPath"
Write-Host "Size   : ${Width}x${Height}"
Write-Host "Steps  : $Steps"
Write-Host "Seed   : $Seed"
Write-Host "Prompt : $Prompt"
if ($NegativePrompt) { Write-Host "Avoid  : $NegativePrompt" }
Write-Host ""

if ($NegativePrompt) { $ModelArgs += @('--negative-prompt', $NegativePrompt) }
& $EnginePath @ModelArgs `
    --steps $Steps `
    --seed $Seed `
    -W $Width `
    -H $Height `
    -p $Prompt `
    -o $OutputPath `
    -v

$ExitCode = $LASTEXITCODE

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "Done: $OutputPath"
} else {
    Write-Host "Generation failed with exit code $ExitCode"
}

exit $ExitCode
