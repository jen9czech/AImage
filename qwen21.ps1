param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$OutputName,

    [Parameter(Position = 1)]
    [string]$Prompt,

    [string]$PromptFile,
    [switch]$PromptFromEnvironment,

    [Parameter(Position = 2)]
    [int]$Width = 1024,

    [Parameter(Position = 3)]
    [int]$Height = 1024,

    [Parameter(Position = 4)]
    [int]$Steps = 0,

    [Parameter(Position = 5)]
    [int]$Seed = 42,

    [string]$Model = 'qwen-image-2.1-Q4_K_M.gguf',

    [string]$QualityPreset = '',

    [ValidateSet('Original', 'Natural', 'Realistic')]
    [string]$Appearance = 'Original',

    [ValidateSet('Auto', 'FullBody', 'Portrait', 'Wide')]
    [string]$PhotoComposition = 'Auto',

    [ValidateRange(1, 100)]
    [int]$JpegQuality = 95,

    [switch]$VerboseEngine,

    [string]$ReferenceImage,
    [string]$InitImage,
    [double]$Strength = 0.75,

    [ValidateSet('auto', 'cpu', 'gpu')]
    [string]$VaeBackend = 'auto',

    [ValidateSet('auto', 'cuda12', 'vulkan')]
    [string]$EngineBackend = 'auto'
)

$ErrorActionPreference = "Stop"
if ($PromptFile -and ($PromptFromEnvironment -or $PSBoundParameters.ContainsKey('Prompt'))) {
    throw 'Use one prompt source at a time.'
}
if ($PromptFromEnvironment) {
    $Prompt = $env:AIMAGE_JOB_PROMPT
    $env:AIMAGE_JOB_PROMPT = $null
}
if ($PromptFile) { $Prompt = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PromptFile).Path) }

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $BaseDir 'paths.ps1')
. (Join-Path $BaseDir 'generation-settings.ps1')
$Paths = Get-AImagePaths -Root $BaseDir

function Format-AImageElapsed {
    param([double]$Seconds)
    $span = [TimeSpan]::FromSeconds([Math]::Max([double]0, $Seconds))
    if ($span.TotalHours -ge 1) {
        return ('{0}h {1:00}m {2:00}s' -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds)
    }
    return ('{0}m {1:00}s' -f [Math]::Floor($span.TotalMinutes), $span.Seconds)
}

function Write-AImageWrappedText {
    param(
        [string]$Prefix,
        [AllowEmptyString()][string]$Text
    )
    $width = 120
    try { $width = [Console]::WindowWidth } catch { }
    if ($width -lt 20) { $width = 20 }
    $prefixLength = $Prefix.Length
    $available = [Math]::Max(10, $width - $prefixLength - 1)
    $indent = ' ' * $prefixLength
    $firstLine = $true
    foreach ($paragraph in [regex]::Split([string]$Text, "\r?\n")) {
        $remaining = $paragraph.Trim()
        if ($remaining.Length -eq 0) {
            $linePrefix = if ($firstLine) { $Prefix } else { $indent }
            Write-Host $linePrefix
            $firstLine = $false
            continue
        }
        while ($remaining.Length -gt 0) {
            if ($remaining.Length -le $available) {
                $piece = $remaining
                $remaining = ''
            } else {
                $breakAt = $remaining.LastIndexOf(' ', [Math]::Min($available, $remaining.Length - 1))
                if ($breakAt -le 0) { $breakAt = $available }
                $piece = $remaining.Substring(0, $breakAt).TrimEnd()
                $remaining = $remaining.Substring($breakAt).TrimStart()
            }
            $linePrefix = if ($firstLine) { $Prefix } else { $indent }
            Write-Host ($linePrefix + $piece)
            $firstLine = $false
        }
    }
}

$CudaEnginePath = Join-Path $BaseDir 'engine\sd-cli.exe'
$VulkanEnginePath = Join-Path $BaseDir 'engine-vulkan\sd-cli.exe'
$NvidiaDriverPath = Join-Path ([Environment]::SystemDirectory) 'nvcuda.dll'
if ($EngineBackend -eq 'cuda12') {
    $EnginePath = $CudaEnginePath
    $gpuBackend = 'cuda0'
} elseif ($EngineBackend -eq 'vulkan') {
    $EnginePath = $VulkanEnginePath
    $gpuBackend = 'Vulkan0'
} elseif ((Test-Path -LiteralPath $CudaEnginePath) -and (Test-Path -LiteralPath $NvidiaDriverPath)) {
    # Prefer CUDA on NVIDIA. The NVIDIA display driver supplies nvcuda.dll.
    $EnginePath = $CudaEnginePath
    $gpuBackend = 'cuda0'
} elseif (Test-Path -LiteralPath $VulkanEnginePath) {
    $EnginePath = $VulkanEnginePath
    $gpuBackend = 'Vulkan0'
} else {
    $EnginePath = $CudaEnginePath
    $gpuBackend = 'cuda0'
}
$ModelsDir = $Paths.Models
$DefaultOutputDir = $Paths.Output

# PowerShell passes quotes literally when a path is entered at an interactive
# prompt. Normalize both interactive and direct-command input before resolving.
if ($InitImage) { $InitImage = $InitImage.Trim().Trim('"') }
if ($ReferenceImage) { $ReferenceImage = $ReferenceImage.Trim().Trim('"') }

if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt cannot be empty.' }
$imageMode = if ($ReferenceImage) { 'Edit image' } elseif ($InitImage) { 'Start from image' } else { 'Text to image' }
$promptSettings = Get-AImagePromptSettings -Prompt $Prompt -Model $Model -Appearance $Appearance -PhotoComposition $PhotoComposition -ImageMode $imageMode
$effectivePrompt = $promptSettings.Prompt
if ($Seed -lt 0) { $Seed = Get-Random -Minimum 1 -Maximum 2147483647 }
if ($ReferenceImage -and $InitImage) { throw 'Use either -ReferenceImage or -InitImage for one job.' }
if ($PSBoundParameters.ContainsKey('Strength') -and -not $InitImage) { throw '-Strength applies only with -InitImage.' }
if ([double]::IsNaN($Strength) -or $Strength -le 0 -or $Strength -gt 1) { throw 'Strength must be greater than 0 and at most 1.' }
if ($Width -lt 32 -or $Width % 32 -ne 0 -or $Height -lt 32 -or $Height % 32 -ne 0) {
    throw 'Width and height must be positive multiples of 32.'
}
if ($Steps -lt 0) { throw 'Steps must be at least 1 when specified.' }

if (!(Test-Path $EnginePath)) {
    throw "sd-cli.exe not found: $EnginePath"
}

$IsBuiltinQwen = [IO.Path]::GetFileName($Model) -eq $Model -and $Model -match '^qwen[-_]image[-_]2[._]1.*\.gguf$'
$OutputScale = 1
if ($IsBuiltinQwen) {
    $ModelLabel = "Qwen Image 2.1 / Native quality ($Model)"
    $DiffusionModelPath = Join-Path $ModelsDir $Model
    $LlmPath = Join-Path $ModelsDir 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf'
    $VaePath = Join-Path $ModelsDir 'qwen_image_2.1_vae_bf16.safetensors'
    foreach ($path in @($DiffusionModelPath, $LlmPath, $VaePath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Model file not found: $path" }
    }
    $ModelArgs = @('--diffusion-model', $DiffusionModelPath, '--llm', $LlmPath, '--vae', $VaePath,
        '--backend', "diffusion=$gpuBackend,te=cpu,vae=cpu", '--diffusion-fa', '--sampling-method', 'euler', '--cfg-scale', '6.0')
    if ($ReferenceImage) {
        $VisionPath = Join-Path $ModelsDir 'mmproj-Qwen3VL-8B-Instruct-F16.gguf'
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
        $path = Resolve-AImageProfilePath -Path ([string]$file) -Paths $Paths
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Profile '$Model' needs: $path" }
    }
    $ModelLabel = if ($profile.name) { $profile.name } else { $Model }
    if ($profile.outputScale -gt 1) { $OutputScale = [int]$profile.outputScale }
    if (-not $PSBoundParameters.ContainsKey('Width') -and $profile.defaults.width) { $Width = [int]$profile.defaults.width }
    if (-not $PSBoundParameters.ContainsKey('Height') -and $profile.defaults.height) { $Height = [int]$profile.defaults.height }
    if ($Width -lt 32 -or $Width % 32 -ne 0 -or $Height -lt 32 -or $Height % 32 -ne 0) {
        throw 'Profile width and height must be positive multiples of 32.'
    }
    $ModelArgs = @($profile.args | ForEach-Object {
        ([string]$_).Replace('{root}', $BaseDir).Replace('{models}', $ModelsDir).Replace('{output}', $DefaultOutputDir).Replace('{gpu}', $gpuBackend)
    })
    if ($Steps -eq 0) { $Steps = if ($profile.defaults.steps -gt 0) { [int]$profile.defaults.steps } else { 40 } }
    if (@($ModelArgs | Where-Object { $_ -match '^(-p|--prompt|-o|--output|-W|--width|-H|--height|--steps|-s|--seed)$' }).Count) {
        throw "Profile '$Model' contains a job-specific argument. Remove prompt, output, size, steps, and seed from its args."
    }
}

# Keep older profiles portable while newer profiles use the {gpu} placeholder.
$ModelArgs = @($ModelArgs | ForEach-Object {
    if ($gpuBackend -eq 'Vulkan0') { ([string]$_).Replace('cuda0', 'Vulkan0') }
    else { ([string]$_).Replace('Vulkan0', 'cuda0') }
})

# Only change the VAE assignment, preserving the text encoder and profile backend.
# Auto keeps the old CUDA placement; Vulkan can use the shared-memory GPU for decoding.
if ($VaeBackend -eq 'auto' -and $InitImage -and $Model -eq 'lustify-v10-krea2-turbo' -and $gpuBackend -eq 'Vulkan0') {
    # The local image-input trial stalled loading Krea weights after GPU VAE
    # encoding. CPU VAE completed with the source intact. Keep this fallback
    # scoped to Krea image-to-image on Vulkan; explicit overrides still win.
    $VaeBackend = 'cpu'
}
$useGpuVae = $VaeBackend -eq 'gpu' -or ($VaeBackend -eq 'auto' -and $IsBuiltinQwen -and $gpuBackend -eq 'Vulkan0')
$hasBackend = $false
for ($i = 0; $i -lt $ModelArgs.Count - 1; $i++) {
    if ($ModelArgs[$i] -eq '--backend') {
        $hasBackend = $true
        if ($useGpuVae -or $VaeBackend -eq 'cpu') {
            $vaeDevice = if ($useGpuVae) { $gpuBackend } else { 'cpu' }
            $assignment = @($ModelArgs[$i + 1] -split ',' | Where-Object { $_ -notmatch '(?i)^vae=' })
            $ModelArgs[$i + 1] = ($assignment + "vae=$vaeDevice") -join ','
        }
    }
}
if (-not $hasBackend -and $VaeBackend -ne 'auto') {
    $vaeDevice = if ($useGpuVae) { $gpuBackend } else { 'cpu' }
    $ModelArgs += @('--backend', "vae=$vaeDevice")
}
if ($IsBuiltinQwen -and $useGpuVae -and $gpuBackend -eq 'Vulkan0') {
    # Avoid the large im2col buffers used by the default VAE convolutions.
    $ModelArgs += '--vae-conv-direct'
}

# Retain the measured Qwen/SDXL override, but let Krea use the engine's
# physical-core default. Its matching local probes did not benefit from
# forcing all logical processors. Explicit profile settings still win.
if ($gpuBackend -eq 'Vulkan0' -and $Model -ne 'lustify-v10-krea2-turbo' -and $ModelArgs -notcontains '--threads') {
    $logicalThreads = [Environment]::ProcessorCount
    if ($logicalThreads -gt 0) { $ModelArgs += @('--threads', [string]$logicalThreads) }
}

if ($ReferenceImage) {
    if (-not (Test-Path -LiteralPath $ReferenceImage -PathType Leaf)) { throw "Reference image not found: $ReferenceImage" }
    $resolvedReferenceImage = (Resolve-Path -LiteralPath $ReferenceImage).Path
    $ModelArgs += @('-r', $resolvedReferenceImage)
}
if ($InitImage) {
    if (-not (Test-Path -LiteralPath $InitImage -PathType Leaf)) { throw "Initial image not found: $InitImage" }
    $resolvedInitImage = (Resolve-Path -LiteralPath $InitImage).Path
    $ModelArgs += @('--init-img', $resolvedInitImage,
        '--strength', $Strength.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))
}
$resolvedVaeBackend = 'auto'
for ($i = 0; $i -lt $ModelArgs.Count - 1; $i++) {
    if ($ModelArgs[$i] -eq '--backend') {
        foreach ($assignment in ($ModelArgs[$i + 1] -split ',')) {
            if ($assignment -match '(?i)^vae=(.+)$') { $resolvedVaeBackend = $Matches[1] }
        }
    }
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
if ([IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -notin @('.png', '.jpg', '.jpeg')) {
    throw 'Output filename must use PNG or JPG.'
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
Write-AImageWrappedText -Prefix 'Prompt : ' -Text $Prompt
if ($InitImage) { Write-Host "Starting image : $resolvedInitImage" }
if ($ReferenceImage) { Write-Host "Reference image: $resolvedReferenceImage" }
Write-Host ""

$overallTimer = [Diagnostics.Stopwatch]::StartNew()
Write-Host 'Preparing the model and reading your description...' -ForegroundColor Cyan
$generationTimer = [Diagnostics.Stopwatch]::StartNew()
$workDir = Join-Path $TargetDir ('.aimage-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workDir)
$engineImage = Join-Path $workDir ([IO.Path]::GetFileNameWithoutExtension($OutputPath) + '.png')
$enginePromptFile = Join-Path $workDir 'prompt.txt'
$utf8 = [Text.UTF8Encoding]::new($false)
$engineArguments = @($ModelArgs) + @('--steps', $Steps, '--seed', $Seed,
    '-W', $Width, '-H', $Height, '--prompt-file', $enginePromptFile, '-o', $engineImage)
$phase = 'prepare'
$lastProgress = -1
$previousErrorPreference = $ErrorActionPreference
try {
    [IO.File]::WriteAllText($enginePromptFile, $effectivePrompt, $utf8)
    if ($promptSettings.NegativePrompt) {
        $negativeFile = Join-Path $workDir 'negative.txt'
        [IO.File]::WriteAllText($negativeFile, $promptSettings.NegativePrompt, $utf8)
        $engineArguments += @('--negative-prompt-file', $negativeFile)
    }
    # Windows PowerShell wraps native stderr records as ErrorRecord objects.
    # Keep them available for the short progress parser without writing a log.
    $ErrorActionPreference = 'Continue'
    & $EnginePath @engineArguments 2>&1 | ForEach-Object {
        $line = [string]$_
        if ($VerboseEngine) { Write-Host $line }
        elseif ($line -match 'get_learned_condition.*completed.*?(\d+(?:\.\d+)?)s') {
            Write-Host ('Description understood ({0}). Preparing picture creation...' -f (Format-AImageElapsed ([double]$Matches[1]))) -ForegroundColor Cyan
            $phase = 'create'
        } elseif ($line -match 'sampling completed, taking (\d+(?:\.\d+)?)s') {
            Write-Host ('Picture created ({0}). Finishing image detail...' -f (Format-AImageElapsed ([double]$Matches[1]))) -ForegroundColor Cyan
            $phase = 'finish'
        } elseif ($line -match 'decode_first_stage completed, taking (\d+(?:\.\d+)?)s') {
            Write-Host ('Image detail finished ({0}).' -f (Format-AImageElapsed ([double]$Matches[1]))) -ForegroundColor Green
        } elseif ($phase -eq 'create' -and $line -match '(\d+)/(\d+)\s+-\s+\d+(?:\.\d+)?s/it') {
            $done = [int]$Matches[1]; $total = [int]$Matches[2]
            if ($done -ne $lastProgress) {
                Write-Host ('Creating picture: {0}/{1} steps, {2} elapsed' -f $done,$total,(Format-AImageElapsed $generationTimer.Elapsed.TotalSeconds))
                $lastProgress = $done
            }
        }
    }
    $ExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorPreference
    if ($ExitCode -eq 0) {
        try {
            Save-AImageValidatedPicture -PngPath $engineImage -OutputPath $OutputPath -Width $Width -Height $Height -JpegQuality $JpegQuality
        } catch {
            $ExitCode = 2
            Write-Host "Picture failed validation: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} finally {
    $ErrorActionPreference = $previousErrorPreference
    # Only files created by this invocation are in the unique staging folder.
    foreach ($file in Get-ChildItem -LiteralPath $workDir -File) { [IO.File]::Delete($file.FullName) }
    [IO.Directory]::Delete($workDir)
}

$generationTimer.Stop()

Write-Host ""
if ($ExitCode -eq 0) {
    $finalizeTimer = [Diagnostics.Stopwatch]::StartNew()
    $mode = if ($ReferenceImage) { 'Edit image' } elseif ($InitImage) { 'Start from image' } else { 'Text to image' }
    $source = if ($ReferenceImage) { $resolvedReferenceImage } elseif ($InitImage) { $resolvedInitImage } else { '' }
    $historyPath = Write-AImageGenerationHistory -Paths $Paths -Prompt $Prompt -Model $Model -OutputPath $OutputPath `
        -QualityPreset $QualityPreset -Width $Width -Height $Height -Steps $Steps -Appearance $Appearance `
        -EffectivePrompt $effectivePrompt -NegativePrompt $promptSettings.NegativePrompt -Seed $Seed `
        -PhotoComposition $promptSettings.PhotoComposition -ResolvedPhotoComposition $promptSettings.ResolvedPhotoComposition `
        -Backend $gpuBackend -VaeDevice $resolvedVaeBackend -ImageMode $mode -SourceImage $source -Strength $Strength -ElapsedSeconds $generationTimer.Elapsed.TotalSeconds
    $finalizeTimer.Stop()
    $overallTimer.Stop()
    Write-Host ("History saved ({0})." -f (Format-AImageElapsed $finalizeTimer.Elapsed.TotalSeconds)) -ForegroundColor DarkGray
    Write-Host ("Finished in {0}. Image saved to: {1}" -f (Format-AImageElapsed $overallTimer.Elapsed.TotalSeconds), $OutputPath) -ForegroundColor Green
    Write-Host "History: $historyPath" -ForegroundColor DarkGray
} else {
    $overallTimer.Stop()
    Write-Host ("Image creation stopped after {0}." -f (Format-AImageElapsed $overallTimer.Elapsed.TotalSeconds)) -ForegroundColor Yellow
    Write-Host "Generation failed with exit code $ExitCode"
    Write-Host 'No diagnostic log was written.' -ForegroundColor Yellow
}

exit $ExitCode
