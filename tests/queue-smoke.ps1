$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $PSScriptRoot ('.queue-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
    Copy-Item (Join-Path $project 'queue.ps1') $sandbox
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
        defaults = @{ steps = 4 }
        args = @('--diffusion-model', '{root}/models/other-model.gguf')
    } | ConvertTo-Json | Set-Content -Path (Join-Path $sandbox 'profiles\other-family.json') -Encoding UTF8
    @'
param([string]$OutputName, [string]$Prompt, [int]$Width, [int]$Height, [int]$Steps, [int]$Seed, [string]$Model,
    [string]$ReferenceImage, [string]$InitImage, [double]$Strength)
if ($Prompt -eq 'FAIL') { exit 7 }
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'output') | Out-Null
$detail = if ($ReferenceImage) { "|ref=$ReferenceImage" } elseif ($InitImage) { "|init=$InitImage|strength=$Strength" } else { '' }
Set-Content -Path (Join-Path $PSScriptRoot "output\$OutputName") -Value "$Prompt$detail"
'@ | Set-Content -Path (Join-Path $sandbox 'qwen21.ps1') -Encoding UTF8
    @('First prompt', '', 'FAIL', 'Third prompt') | Set-Content -Path (Join-Path $sandbox 'prompts.txt') -Encoding UTF8
    $queue = Join-Path $sandbox 'queue.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -PromptFile (Join-Path $sandbox 'prompts.txt') -Width 512 -Height 512 -Steps 2
    if ($LASTEXITCODE -ne 0) { throw 'Batch add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if ($state.jobs.Count -ne 3) { throw 'Batch add count mismatch.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue model -Model Q5_K_M
    if ($LASTEXITCODE -ne 0) { throw 'Model selection failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue edit -Id $state.jobs[2].id -Model Q5_K_M
    if ($LASTEXITCODE -ne 0) { throw 'Job model edit failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue edit -Id $state.jobs[0].id.Substring(0, 4) -Prompt 'Edited prompt'
    if ($LASTEXITCODE -ne 0) { throw 'Edit failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue run
    if ($LASTEXITCODE -ne 1) { throw 'Worker should report one failed job.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (($state.jobs.status -join ',') -ne 'done,failed,done') { throw 'Worker statuses mismatch.' }
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
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Variation' -InitImage (Join-Path $sandbox 'input.png') -Strength 0.5
    if ($LASTEXITCODE -ne 0) { throw 'Initial image add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (-not (Test-Path $state.jobs[-1].initImage) -or $state.jobs[-1].strength -ne 0.5) { throw 'Initial image was not staged.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue model -Model Q4_K_M
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $queue add -Prompt 'Change the sky' -ReferenceImage (Join-Path $sandbox 'input.png')
    if ($LASTEXITCODE -ne 0) { throw 'Reference image add failed.' }
    $state = Get-Content (Join-Path $sandbox 'queue\jobs.json') -Raw | ConvertFrom-Json
    if (-not (Test-Path $state.jobs[-1].referenceImage)) { throw 'Reference image was not staged.' }
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
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
