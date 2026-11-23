param(
    [string]$EnginePath,
    [string]$OutputName = 'krea-speed.jpg',
    [string]$DiffusionModelPath,
    [string]$Device = 'Vulkan0',
    [ValidateSet('Original', 'Natural', 'Realistic')][string]$Appearance = 'Realistic',
    [ValidateRange(256, 2048)][int]$Size = 768,
    [ValidateRange(1, 40)][int]$Steps = 8,
    [ValidateRange(1, 256)][int]$Threads = [Environment]::ProcessorCount,
    [int]$Seed = 12345,
    [string]$Prompt = 'An adult woman in a blue sweater sitting at a wooden table in a cafe, head and shoulders portrait, soft window light',
    [switch]$Mmap
)

# Keep model, prompt, seed, dimensions and steps fixed when comparing engines.
# Native diagnostics are parsed in memory; no diagnostic log is written.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'paths.ps1')
. (Join-Path $root 'generation-settings.ps1')
$paths = Get-AImagePaths -Root $root
if (-not $EnginePath) { $EnginePath = Join-Path $root 'engine-vulkan\sd-cli.exe' }
if ($Size % 32) { throw 'Size must be a multiple of 32.' }
$directory = Join-Path $root 'benchmarks\speed-review'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$output = Join-Path $directory $OutputName
if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
$profile = Get-Content (Join-Path $root 'profiles\lustify-v10-krea2-turbo.json') -Raw | ConvertFrom-Json
$settings = Get-AImagePromptSettings -Prompt $Prompt -Model $profile.id -Appearance $Appearance
$engineArgs = @($profile.args | ForEach-Object {
    ([string]$_).Replace('{models}', $paths.Models).Replace('{gpu}', $Device)
}) + @('--threads', $Threads, '--steps', $Steps, '--seed', $Seed,
    '-W', $Size, '-H', $Size, '-p', $settings.Prompt, '-o', $output, '--compression-quality', 95, '-v')
if ($Mmap) { $engineArgs += '--mmap' }
if ($DiffusionModelPath) {
    if (-not (Test-Path -LiteralPath $DiffusionModelPath -PathType Leaf)) { throw 'Comparison diffusion model does not exist.' }
    $engineArgs[[Array]::IndexOf($engineArgs, '--diffusion-model') + 1] = (Resolve-Path -LiteralPath $DiffusionModelPath).Path
}
$metrics = [ordered]@{ engine=$EnginePath; size=$Size; steps=$Steps; seed=$Seed; mmap=[bool]$Mmap; image=$output }
$metrics.device = $Device
$metrics.threads = $Threads
$metrics.preferHostMemory = [bool]$env:GGML_VK_PREFER_HOST_MEMORY
$metrics.disableCoopmat = [bool]$env:GGML_VK_DISABLE_COOPMAT
$metrics.appearance = $Appearance
$metrics.promptWords = ($settings.Prompt -split '\s+').Count
$metrics.diffusionModel = $engineArgs[[Array]::IndexOf($engineArgs, '--diffusion-model') + 1]
$timer = [Diagnostics.Stopwatch]::StartNew()
Write-Host "Comparing engine at ${Size}px, $Steps steps."
$ErrorActionPreference = 'Continue'
& $EnginePath @engineArgs 2>&1 | ForEach-Object {
    $line = [string]$_
    if ($line -match '(get_learned_condition|sampling|decode_first_stage|generate_image) completed(?:, taking| in) ([0-9.]+)s') {
        $metrics[$Matches[1] + 'Seconds'] = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
        Write-Host ($Matches[0])
    } elseif ($line -match 'loading tensors completed|compute buffer size|build cached graph cut plan|\[(?:ERROR|ERR)\b|failed|unsupported|invalid|cannot') {
        Write-Host $line
    } elseif ($line -match '(\d+)/(\d+)\s+-\s+[0-9.]+s/it') {
        Write-Host ('Step {0}/{1}; elapsed {2:N0}s' -f $Matches[1],$Matches[2],$timer.Elapsed.TotalSeconds)
    }
}
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$timer.Stop()
$metrics.wallSeconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
$metrics.exitCode = $code
$metrics | ConvertTo-Json
if ($code -ne 0) { exit $code }
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'Engine did not save the comparison image.' }
