$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $PSScriptRoot ('.queue-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$previousModelsDir = $env:AIMAGE_MODELS_DIR
$previousOutputDir = $env:AIMAGE_OUTPUT_DIR
try {
    Copy-Item (Join-Path $project 'queue.ps1') $sandbox
    Copy-Item (Join-Path $project 'paths.ps1') $sandbox
    $env:AIMAGE_MODELS_DIR = Join-Path $sandbox 'models'
    $env:AIMAGE_OUTPUT_DIR = Join-Path $sandbox 'output'
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'models') | Out-Null
    Set-Content -Path (Join-Path $sandbox 'models\qwen-image-2.1-Q4_K_M.gguf') -Value 'stub'
    Set-Content -Path (Join-Path $sandbox 'models\qwen-image-2.1-Q5_K_M.gguf') -Value 'stub'
    Set-Content -Path (Join-Path $sandbox 'models\Qwen3-VL-8B-Instruct-Q4_K_M.gguf') -Value 'stub'
    Set-Content -Path (Join-Path $sandbox 'models\qwen_image_2.1_vae_bf16.safetensors') -Value 'stub'
    Set-Content -Path (Join-Path $sandbox 'models\mmproj-Qwen3VL-8B-Instruct-F16.gguf') -Value 'stub'
    Set-Content -Path (Join-Path $sandbox 'input.png') -Value 'stub'
    New-Item -ItemType Directory -Path (Join-Path $sandbox 'profiles') | Out-Null
    Set-Content -Path (Join-Path $sandbox 'models\other-model.gguf') -Value 'stub'
    @{
        id = 'other-family'; name = 'Other family'; requiredFiles = @('models/other-model.gguf')
        defaults = @{ steps = 4; width = 768; height = 640 }
        args = @('--diffusion-model', '{root}/models/other-model.gguf')
    } | ConvertTo-Json | Set-Content -Path (Join-Path $sandbox 'profiles\other-family.json') -Encoding UTF8
    @'
param([string]$OutputName, [switch]$PromptFromEnvironment, [int]$Width, [int]$Height, [int]$Steps, [int]$Seed, [string]$Model,
    [string]$ReferenceImage, [string]$InitImage, [double]$Strength)
if (-not $PromptFromEnvironment) { exit 3 }
$Prompt = $env:AIMAGE_JOB_PROMPT
if ($Prompt -eq 'FAIL') { exit 7 }
$outputDir = $env:AIMAGE_OUTPUT_DIR
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$detail = if ($ReferenceImage) { "|ref=$ReferenceImage" } elseif ($InitImage) { "|init=$InitImage|strength=$Strength" } else { '' }
Set-Content -Path (Join-Path $outputDir $OutputName) -Value "$Prompt$detail"
'@ | Set-Content -Path (Join-Path $sandbox 'qwen21.ps1') -Encoding UTF8
    @('First prompt', '', 'FAIL', 'Third prompt') | Set-Content -Path (Join-Path $sandbox 'prompts.txt') -Encoding UTF8
    $queue = Join-Path $sandbox 'queue.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -PromptFile (Join-Path $sandbox 'prompts.txt') -Width 512 -Height 512 -Steps 2
    if ($LASTEXITCODE -ne 0) { throw 'Batch add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs.Count -ne 3) { throw 'Batch add count mismatch.' }
    if ($state.jobs[0].output -notmatch 'first-prompt' -or $state.jobs[2].output -notmatch 'third-prompt') {
        throw 'Queued filenames do not contain abbreviated prompts.'
    }
    if ($state.jobs[0].output -notmatch '^\d{8}-\d{6}-qwen-image-2-1-q4-k-m-first-prompt-') {
        throw 'Queued filename does not contain the selected model after the timestamp.'
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue model -Model Q5_K_M
    if ($LASTEXITCODE -ne 0) { throw 'Model selection failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue edit -Id $state.jobs[2].id -Model Q5_K_M
    if ($LASTEXITCODE -ne 0) { throw 'Job model edit failed.' }
    $editedState = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($editedState.jobs[2].output -notmatch '-qwen-image-2-1-q5-k-m-third-prompt-') { throw 'Changing a queued model did not update its automatic filename.' }
    $state = $editedState
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue edit -Id $state.jobs[0].id.Substring(0, 4) -Prompt 'Edited prompt'
    if ($LASTEXITCODE -ne 0) { throw 'Edit failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue run
    if ($LASTEXITCODE -ne 1) { throw 'Worker should report one failed job.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (($state.jobs.status -join ',') -ne 'done,failed,done') { throw 'Worker statuses mismatch.' }
    foreach ($completedJob in $state.jobs) {
        if (-not $completedJob.PSObject.Properties['elapsedSeconds'] -or $completedJob.elapsedSeconds -lt 0) { throw 'Run duration was not saved.' }
    }
    if ($state.jobs[2].model -ne 'qwen-image-2.1-Q5_K_M.gguf') { throw 'Selected model was not preserved.' }
    $image = Get-Content (Join-Path $sandbox "output\$($state.jobs[0].output)") -Raw
    if ($image.Trim() -ne 'Edited prompt') { throw 'Edited prompt did not reach generator.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue retry -Id $state.jobs[1].id
    if ($LASTEXITCODE -ne 0) { throw 'Retry failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue remove -Id $state.jobs[1].id
    if ($LASTEXITCODE -ne 0) { throw 'Remove failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue model -Model other-family
    if ($LASTEXITCODE -ne 0) { throw 'Cross-family profile selection failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Another family prompt' -Width 512 -Height 512 -Steps 2
    if ($LASTEXITCODE -ne 0) { throw 'Cross-family add failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue run -Limit 1
    if ($LASTEXITCODE -ne 0) { throw 'Cross-family run failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs[-1].model -ne 'other-family' -or $state.jobs[-1].status -ne 'done') { throw 'Cross-family job mismatch.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Uses profile step default' -Width 512 -Height 512
    if ($LASTEXITCODE -ne 0) { throw 'Profile-default add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs[-1].steps -ne 4) { throw 'Profile step default was ignored.' }
    if ($state.jobs[-1].width -ne 512 -or $state.jobs[-1].height -ne 512) { throw 'Explicit dimensions were overwritten by profile defaults.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Uses profile size defaults'
    if ($LASTEXITCODE -ne 0) { throw 'Profile-size add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs[-1].width -ne 768 -or $state.jobs[-1].height -ne 640) { throw 'Profile size defaults were ignored.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue remove -Id $state.jobs[-1].id
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Overrides only width' -Width 320
    if ($LASTEXITCODE -ne 0) { throw 'Partial dimension override failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs[-1].width -ne 320 -or $state.jobs[-1].height -ne 640) { throw 'Dimensions must be resolved independently.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue remove -Id $state.jobs[-1].id
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Variation' -InitImage (Join-Path $sandbox 'input.png') -Strength 0.5
    if ($LASTEXITCODE -ne 0) { throw 'Initial image add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (-not (Test-Path $state.jobs[-1].initImage) -or $state.jobs[-1].strength -ne 0.5) { throw 'Initial image was not staged.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue model -Model Q4_K_M
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Change the sky' -ReferenceImage (Join-Path $sandbox 'input.png')
    if ($LASTEXITCODE -ne 0) { throw 'Reference image add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (-not (Test-Path $state.jobs[-1].referenceImage)) { throw 'Reference image was not staged.' }
    if ($state.jobs[-1].width -ne 1024 -or $state.jobs[-1].height -ne 1024 -or $state.jobs[-1].steps -ne 40) {
        throw 'Native Qwen queue defaults were not preserved.'
    }
    Remove-Item -LiteralPath (Join-Path $sandbox 'input.png')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue run -Limit 3
    if ($LASTEXITCODE -ne 0) { throw 'Image input jobs failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (($state.jobs[-3..-1].status -join ',') -ne 'done,done,done') { throw 'Image input job statuses mismatch.' }
    $variation = Get-Content (Join-Path $sandbox "output\$($state.jobs[-2].output)") -Raw
    $edit = Get-Content (Join-Path $sandbox "output\$($state.jobs[-1].output)") -Raw
    if ($variation -notmatch 'init=.*strength=0.5' -or $edit -notmatch 'ref=') { throw 'Image inputs did not reach the runner.' }
    $stagedReference = $state.jobs[-1].referenceImage
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue remove -Id $state.jobs[-1].id
    if ($LASTEXITCODE -ne 0 -or (Test-Path $stagedReference)) { throw 'Removing a job did not clean its staged image.' }
    Write-Host 'Queue smoke test passed.' -ForegroundColor Green
} finally {
    $env:AIMAGE_MODELS_DIR = $previousModelsDir
    $env:AIMAGE_OUTPUT_DIR = $previousOutputDir
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    $testsRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $resolvedSandbox.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside tests directory.' }
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
