param(
    [ValidateSet('baseline', 'gpu-vae', 'gpu-vae-direct', 'no-fa', 'all-gpu', 'all-gpu-direct', 'cpu-params', 'host-memory')]
    [string]$Variant = 'baseline',
    [ValidateRange(256, 2048)][int]$Size = 512,
    [ValidateRange(1, 40)][int]$Steps = 2
)

# Use the same harmless prompt, seed, model, and dimensions for comparisons.
$ErrorActionPreference = 'Stop'
if ($Size % 32 -ne 0) { throw 'Size must be a multiple of 32.' }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'paths.ps1')
$paths = Get-AImagePaths -Root $root
$directory = Join-Path $root 'benchmarks'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$name = '{0}-{1}-{2}steps-{3}' -f $Variant, $Size, $Steps, (Get-Date -Format 'yyyyMMdd-HHmmss')
$log = Join-Path $directory "$name.log"
$output = Join-Path $directory "$name.png"
$backend = 'diffusion=Vulkan0,te=cpu,vae=Vulkan0'
if ($Variant -eq 'baseline') { $backend = 'diffusion=Vulkan0,te=cpu,vae=cpu' }
if ($Variant -in @('all-gpu', 'all-gpu-direct')) { $backend = 'Vulkan0' }
$engineArgs = @(
    '--diffusion-model', (Join-Path $paths.Models 'qwen-image-2.1-Q4_K_M.gguf'),
    '--llm', (Join-Path $paths.Models 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf'),
    '--vae', (Join-Path $paths.Models 'qwen_image_2.1_vae_bf16.safetensors'),
    '--backend', $backend, '--sampling-method', 'euler', '--cfg-scale', '6.0',
    '--steps', $Steps, '--seed', 42, '-W', $Size, '-H', $Size,
    '-p', 'a photograph of cute owl', '-o', $output, '-v'
)
if ($Variant -ne 'no-fa') { $engineArgs += '--diffusion-fa' }
if ($Variant -eq 'cpu-params') { $engineArgs += @('--params-backend', 'cpu') }
if ($Variant -in @('gpu-vae-direct', 'all-gpu-direct')) { $engineArgs += '--vae-conv-direct' }
$timer = [Diagnostics.Stopwatch]::StartNew()
Write-Host "Running $Variant at ${Size}x${Size}, $Steps steps. Please wait; results appear when finished."
Write-Host "Log: $log"
$previousHostMemory = $env:GGML_VK_PREFER_HOST_MEMORY
if ($Variant -eq 'host-memory') { $env:GGML_VK_PREFER_HOST_MEMORY = '1' }
# Windows PowerShell reports native diagnostic stderr as non-terminating errors.
$ErrorActionPreference = 'Continue'
try {
    & (Join-Path $root 'engine-vulkan\sd-cli.exe') @engineArgs *> $log
    $code = $LASTEXITCODE
} finally {
    $env:GGML_VK_PREFER_HOST_MEMORY = $previousHostMemory
}
$ErrorActionPreference = 'Stop'
$timer.Stop()
$text = Get-Content -LiteralPath $log -Raw
$metrics = [ordered]@{
    variant = $Variant; size = $Size; steps = $Steps; seed = 42
    backend = $backend; exitCode = $code; wallSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
    log = $log; image = $output
}
foreach ($phase in @('get_learned_condition', 'sampling', 'decode_first_stage', 'generate_image')) {
    $match = [regex]::Match($text, "$phase completed(?:, taking| in) ([0-9.]+)s")
    if ($match.Success) { $metrics[$phase + 'Seconds'] = [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) }
}
$metrics | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory "$name.json") -Encoding UTF8
$metrics | ConvertTo-Json
if ($code -ne 0) { exit $code }
