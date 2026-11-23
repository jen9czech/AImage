$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $PSScriptRoot ('.aimage-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$previousModelsDir = $env:AIMAGE_MODELS_DIR
$previousOutputDir = $env:AIMAGE_OUTPUT_DIR
try {
    foreach ($directory in @('models', 'profiles', 'queue')) {
        New-Item -ItemType Directory -Path (Join-Path $sandbox $directory) | Out-Null
    }
    Copy-Item (Join-Path $project 'aimage.ps1') $sandbox
    Copy-Item (Join-Path $project 'paths.ps1') $sandbox
    Copy-Item (Join-Path $project 'generation-settings.ps1') $sandbox
    Copy-Item (Join-Path $project 'launcher-input.ps1') $sandbox
    $env:AIMAGE_MODELS_DIR = Join-Path $sandbox 'models'
    $env:AIMAGE_OUTPUT_DIR = Join-Path $sandbox 'output'
    Set-Content -LiteralPath (Join-Path $sandbox 'models\ready.bin') -Value 'stub'
    @{
        id = 'ready-model'; name = 'Ready model'; requiredFiles = @('models/ready.bin')
        defaults = @{ width = 768; height = 1024; steps = 12 }
        args = @('--model', '{root}/models/ready.bin')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $sandbox 'profiles\ready-model.json') -Encoding UTF8
    @{
        id = 'missing-model'; name = 'Missing model'; requiredFiles = @('models/missing.bin')
        defaults = @{ width = 1024; height = 1024; steps = 20 }
        args = @('--model', '{root}/models/missing.bin')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $sandbox 'profiles\missing-model.json') -Encoding UTF8
    @{ version = 1; defaultModel = 'ready-model' } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $sandbox 'queue\settings.json') -Encoding UTF8
@'
param([string]$OutputName, [switch]$PromptFromEnvironment, [string]$Model, [int]$Width, [int]$Height, [int]$Steps, [string]$QualityPreset, [string]$Appearance, [int]$Seed, [string]$PhotoComposition)
if (-not $PromptFromEnvironment) { exit 3 }
$Prompt = $env:AIMAGE_JOB_PROMPT
$outputDir = $env:AIMAGE_OUTPUT_DIR
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
@{ prompt = $Prompt; model = $Model; width = $Width; height = $Height; steps = $Steps; qualityPreset = $QualityPreset; seed = $Seed; appearance = $Appearance; photoComposition = $PhotoComposition } | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $outputDir $OutputName) -Encoding UTF8
'@ | Set-Content -LiteralPath (Join-Path $sandbox 'qwen21.ps1') -Encoding UTF8

    $launcher = Join-Path $sandbox 'aimage.ps1'
    $listing = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -ListOnly -NoClear 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Model listing failed.' }
    if ($listing -notmatch 'Ready model \[default\]' -or $listing -match 'Missing model') {
        throw 'Launcher did not filter or mark models correctly.'
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher `
        -Model ready-model -Prompt 'a detailed owl in moonlight' -NoClear -NoPause
    if ($LASTEXITCODE -ne 0) { throw 'Non-interactive launcher run failed.' }
    $resultFile = Get-ChildItem -LiteralPath (Join-Path $sandbox 'output') -Filter '*.jpg' -File | Select-Object -First 1
    if (-not $resultFile) { throw 'Launcher did not create an output.' }
    if ($resultFile.Name -notmatch 'detailed-owl-moonlight') { throw 'Launcher filename does not contain the abbreviated prompt.' }
    if ($resultFile.Name -notmatch '^\d{8}-\d{6}-ready-model-detailed-owl-moonlight-') { throw 'Launcher filename does not contain the selected model after the timestamp.' }
    $result = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
    if ($result.model -ne 'ready-model' -or $result.prompt -ne 'a detailed owl in moonlight') {
        throw 'Launcher did not preserve the selected model and prompt.'
    }
    if ($result.seed -lt 1 -or $result.appearance -ne 'Original') { throw 'Single image seed or CLI prompt preservation incorrect.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher `
        -Model ready-model -Prompt 'seeded comparison' -Variants 2 -Seed 12345 -Appearance Natural -NoClear -NoPause
    if ($LASTEXITCODE -ne 0) { throw 'Seeded variants launcher run failed.' }
    $variants = @(Get-ChildItem -LiteralPath (Join-Path $sandbox 'output') -Filter '*seeded-comparison*.jpg' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    if ($variants.Count -ne 2 -or @($variants | Where-Object appearance -ne 'Natural').Count -or
        (@($variants.seed | Sort-Object) -join ',') -ne '12345,12346') { throw 'Variant seeds or appearance did not reach the runner.' }

    # The Krea preset must set its resolution and quality label without requiring
    # interactive input, so it remains usable from a shortcut or automation.
    Copy-Item (Join-Path $sandbox 'profiles\ready-model.json') (Join-Path $sandbox 'profiles\lustify-v10-krea2-turbo.json')
    $kreaProfilePath = Join-Path $sandbox 'profiles\lustify-v10-krea2-turbo.json'
    $kreaProfile = Get-Content -LiteralPath $kreaProfilePath -Raw | ConvertFrom-Json
    $kreaProfile.id = 'lustify-v10-krea2-turbo'
    $kreaProfile.name = 'Lustify v10 Krea 2 Turbo'
    $kreaProfile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $kreaProfilePath -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher `
        -Model lustify-v10-krea2-turbo -QualityPreset Standard -Prompt 'a city at dusk' -NoClear -NoPause
    if ($LASTEXITCODE -ne 0) { throw 'Krea Standard launcher run failed.' }
    $kreaResultFile = Get-ChildItem -LiteralPath (Join-Path $sandbox 'output') -Filter '*lustify-v10-krea2-turbo*.jpg' -File | Select-Object -First 1
    $kreaResult = Get-Content -LiteralPath $kreaResultFile.FullName -Raw | ConvertFrom-Json
    if ($kreaResult.qualityPreset -ne 'Standard' -or $kreaResult.width -ne 768 -or $kreaResult.height -ne 768 -or $kreaResult.steps -ne 8) {
        throw 'Krea Standard quality settings were not passed to the generator.'
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher `
        -Model ready-model -Prompt 'simple outdoor scene' -Appearance Realistic -PhotoComposition FullBody -NoClear -NoPause
    if ($LASTEXITCODE -ne 0) { throw 'Assisted launcher failed.' }
    $assistedFile = Get-ChildItem -LiteralPath (Join-Path $sandbox 'output') -Filter '*simple-outdoor-scene*.jpg' -File | Select-Object -First 1
    $assisted = Get-Content -LiteralPath $assistedFile.FullName -Raw | ConvertFrom-Json
    if ($assisted.appearance -ne 'Realistic' -or $assisted.photoComposition -ne 'FullBody' -or $assisted.prompt -ne 'simple outdoor scene') { throw 'Launcher lost assistance or original prompt.' }
    $quoted = 'An owl beside a sign reading "Forest Trail"'
    $promptFile = Join-Path $sandbox 'prompt.txt'
    [IO.File]::WriteAllText($promptFile, $quoted)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Model ready-model -PromptFile $promptFile -NoClear -NoPause
    if ($LASTEXITCODE -ne 0) { throw 'Quoted prompt run failed.' }
    $quoteFile = Get-ChildItem -LiteralPath (Join-Path $sandbox 'output') -Filter '*forest-trail*.jpg' -File | Select-Object -First 1
    $quotedResult = Get-Content -LiteralPath $quoteFile.FullName -Raw | ConvertFrom-Json
    if ($quotedResult.prompt -cne $quoted) { throw 'Launcher changed the quoted prompt.' }
    Write-Host 'Interactive launcher smoke test passed.' -ForegroundColor Green
} finally {
    $env:AIMAGE_MODELS_DIR = $previousModelsDir
    $env:AIMAGE_OUTPUT_DIR = $previousOutputDir
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    $testsRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $resolvedSandbox.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside tests directory.' }
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
