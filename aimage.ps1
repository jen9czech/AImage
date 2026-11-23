param(
    [string]$Model,
    [string]$Prompt,
    [string]$PromptFile,
    [string]$InitImage,
    [string]$ReferenceImage,
    [double]$Strength = 0.40,
    [ValidateRange(1, 20)][int]$Variants = 1,
    [ValidateSet('png', 'jpg')][string]$OutputFormat = 'jpg',
    [ValidateSet('Preview', 'Standard', 'Quality')][string]$QualityPreset,
    [ValidateSet('Original', 'Natural', 'Realistic')][string]$Appearance,
    [ValidateSet('Auto', 'FullBody', 'Portrait', 'Wide')][string]$PhotoComposition = 'Auto',
    [int]$Seed = -1,
    [switch]$ListOnly,
    [switch]$NoClear,
    [switch]$NoPause,
    [ValidateSet('model', 'quality', 'mode', 'image', 'strength', 'prompt', 'appearance', 'composition', 'variants', 'format')]
    [string]$ResumeStep = 'model',
    [ValidateSet('Text to image', 'Start from image', 'Edit image')][string]$ResumeImageMode,
    [switch]$ForceInteractive
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'paths.ps1')
. (Join-Path $Root 'generation-settings.ps1')
. (Join-Path $Root 'launcher-input.ps1')
$Paths = Get-AImagePaths -Root $Root
$ModelsDir = $Paths.Models
$ProfilesDir = Join-Path $Root 'profiles'
$SettingsFile = Join-Path $Root 'queue\settings.json'
$Runner = Join-Path $Root 'qwen21.ps1'
if ($PromptFile) {
    if ($PSBoundParameters.ContainsKey('Prompt')) { throw 'Use either -Prompt or -PromptFile.' }
    $Prompt = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PromptFile).Path)
}

function Get-DefaultModel {
    if (Test-Path -LiteralPath $SettingsFile -PathType Leaf) {
        try {
            $settings = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.version -eq 1 -and $settings.defaultModel) { return [string]$settings.defaultModel }
        } catch { Write-Warning "Could not read the default model: $($_.Exception.Message)" }
    }
    return 'lustify-v10-krea2-turbo'
}

function Get-AvailableModels {
    $items = [Collections.Generic.List[object]]::new()
    $qwenReady = (Test-Path -LiteralPath (Join-Path $ModelsDir 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $ModelsDir 'qwen_image_2.1_vae_bf16.safetensors') -PathType Leaf)
    if ($qwenReady) {
        foreach ($file in @(Get-ChildItem -LiteralPath $ModelsDir -Filter '*.gguf' -File |
                Where-Object { $_.Name -match '^qwen[-_]image[-_]2[._]1.*\.gguf$' } | Sort-Object Name)) {
            $quant = if ($file.BaseName -match '(Q[0-9][A-Z0-9_]*)$') { $Matches[1] } else { $file.BaseName }
            $items.Add([pscustomobject]@{
                Id = $file.Name; Name = "Qwen Image 2.1 / Native ($quant)"
                Width = 1024; Height = 1024; Steps = 40; OutputScale = 1
            })
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $profile = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        if ($profile.id -ne $file.BaseName -or -not $profile.args -or -not $profile.requiredFiles) { continue }
        $missing = @($profile.requiredFiles | Where-Object {
            -not (Test-Path -LiteralPath (Resolve-AImageProfilePath -Path ([string]$_) -Paths $Paths) -PathType Leaf)
        })
        if ($missing.Count) { continue }
        $items.Add([pscustomobject]@{
            Id = [string]$profile.id
            Name = if ($profile.name) { [string]$profile.name } else { [string]$profile.id }
            Width = if ($profile.defaults.width) { [int]$profile.defaults.width } else { 1024 }
            Height = if ($profile.defaults.height) { [int]$profile.defaults.height } else { 1024 }
            Steps = if ($profile.defaults.steps) { [int]$profile.defaults.steps } else { 40 }
            OutputScale = if ($profile.outputScale -gt 1) { [int]$profile.outputScale } else { 1 }
        })
    }
    return @($items)
}

function Get-AImageModelHint {
    param($Model)
    switch ($Model.Id) {
        'lustify-v10-krea2-turbo' { return 'Natural-language prompts; 8-step generation. Quality gives finer photographic detail.' }
        'lustify-zenith-v9' { return 'SDXL photographs; smaller model. Standard uses native resolution; Quality adds refinement.' }
        default {
            if ($Model.Id -match '^qwen[-_]image[-_]2[._]1') { return 'Detailed descriptions and reference editing when installed. Very slow on Radeon 890M.' }
            return 'Local model profile with its own generation settings.'
        }
    }
}

if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) { throw "Generator script not found: $Runner" }
$available = @(Get-AvailableModels)
if (-not $available.Count) { throw "No ready models found in $ModelsDir. Run setup.ps1 or install the required files." }
$defaultModel = Get-DefaultModel
$available = @($available | Sort-Object @{ Expression = { if ($_.Id -eq $defaultModel) { 0 } else { 1 } } }, Name)
if ($Model -and -not ($available | Where-Object Id -eq $Model)) { throw "Model '$Model' is not ready. Run .\aimage.cmd -ListOnly." }
if ($InitImage -and $ReferenceImage) { throw 'Use either -InitImage or -ReferenceImage, not both.' }
if ($InitImage) { $InitImage = $InitImage.Trim().Trim('"').Trim("'") }
if ($ReferenceImage) { $ReferenceImage = $ReferenceImage.Trim().Trim('"').Trim("'") }

if ($ListOnly) {
    Write-Host 'Available models:'
    for ($i = 0; $i -lt $available.Count; $i++) {
        $mark = if ($available[$i].Id -eq $defaultModel) { ' [default]' } else { '' }
        Write-Host ("  {0}. {1}{2}" -f ($i + 1), $available[$i].Name, $mark)
        Write-Host ("     {0}" -f (Get-AImageModelHint $available[$i]))
    }
    exit 0
}

$directRun = -not [string]::IsNullOrWhiteSpace($Prompt) -and [bool]$Model -and -not $ForceInteractive
$state = @{
    Model = $Model; Quality = $QualityPreset; Prompt = $Prompt
    Mode = if ($ReferenceImage) { 'Edit image' } elseif ($InitImage) { 'Start from image' } elseif ($ResumeImageMode) { $ResumeImageMode } else { 'Text to image' }
    Image = if ($ReferenceImage) { $ReferenceImage } else { $InitImage }
    Strength = $Strength
    StrengthText = if ($PSBoundParameters.ContainsKey('Strength')) { $Strength.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) } else { '' }
    Appearance = $Appearance; PhotoComposition = $PhotoComposition; Variants = $Variants
    VariantsText = if ($PSBoundParameters.ContainsKey('Variants')) { [string]$Variants } else { '' }
    Format = if ($PSBoundParameters.ContainsKey('OutputFormat')) { $OutputFormat } else { '' }
}
$code = 0
$useReviewFlow = -not $PSBoundParameters.ContainsKey('ResumeStep')
while ($true) {
    if (-not $NoClear) { Clear-Host }
    Write-Host 'AImage - local image generator' -ForegroundColor Cyan
    if (-not $directRun) {
        Write-Host 'Enter accepts the displayed value. Esc goes back one step or closes at the first step.' -ForegroundColor DarkGray
        $state = Get-AImageLauncherSettings -Available $available -State $state -Paths $Paths -StartStep $ResumeStep -ReviewFlow:$useReviewFlow
        if ($null -eq $state) { Write-Host 'AImage closed.'; exit 0 }
    }
    $selected = $available | Where-Object Id -eq $state.Model | Select-Object -First 1
    $choices = @(Get-AImageQualityChoices -Model $selected)
    if (-not $state.Quality) { $state.Quality = if ($choices.Count -gt 1) { 'Standard' } else { 'Native' } }
    $quality = $choices | Where-Object Name -eq $state.Quality | Select-Object -First 1
    if (-not $quality) { throw "Quality '$($state.Quality)' is unavailable for $($selected.Name)." }
    if (-not $state.Appearance) { $state.Appearance = 'Original' }
    if (-not $state.Format) { $state.Format = 'jpg' }
    if ([string]::IsNullOrWhiteSpace($state.Prompt)) { throw 'Prompt cannot be empty.' }
    if ($state.Image -and -not (Test-Path -LiteralPath $state.Image -PathType Leaf)) { throw "Image not found: $($state.Image)" }
    if ($state.Mode -eq 'Edit image' -and $selected.Id -notmatch '^qwen[-_]image[-_]2[._]1') { throw 'Reference editing requires Qwen Image 2.1.' }
    Write-AImagePromptHistory -Paths $Paths -Prompt $state.Prompt
    $code = 0
    for ($variantIndex = 1; $variantIndex -le $state.Variants; $variantIndex++) {
        $runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $outputName = New-AImageOutputFileName -Prompt $state.Prompt -Model $selected.Id -Id $runId -Extension $state.Format
        $expectedOutput = Join-Path $Paths.Output $outputName
        $runSeed = if ($Seed -lt 0) { Get-Random -Minimum 1 -Maximum 2147483647 } else { [int](($Seed + [long]$variantIndex - 1) % 2147483647) }
        Write-Host ''
        Write-Host ("Creating version {0} of {1}: {2}, {3}x{4}, {5}" -f $variantIndex,$state.Variants,$selected.Name,$quality.Width,$quality.Height,$state.Appearance) -ForegroundColor Green
        Write-Host 'Press Ctrl+C to stop creation.' -ForegroundColor DarkGray
        $runnerArguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Runner,
            '-OutputName', $outputName, '-PromptFromEnvironment', '-Model', $selected.Id,
            '-Width', $quality.Width, '-Height', $quality.Height, '-Steps', $quality.Steps,
            '-QualityPreset', $state.Quality, '-Seed', $runSeed, '-Appearance', $state.Appearance,
            '-PhotoComposition', $state.PhotoComposition
        )
        if ($state.Mode -eq 'Start from image') { $runnerArguments += @('-InitImage', $state.Image, '-Strength', $state.Strength.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)) }
        if ($state.Mode -eq 'Edit image') { $runnerArguments += @('-ReferenceImage', $state.Image) }
        $previousJobPrompt = $env:AIMAGE_JOB_PROMPT
        try {
            $env:AIMAGE_JOB_PROMPT = $state.Prompt
            & powershell.exe @runnerArguments
            $variantCode = $LASTEXITCODE
        } finally { $env:AIMAGE_JOB_PROMPT = $previousJobPrompt }
        if ($variantCode -ne 0 -or -not (Test-Path -LiteralPath $expectedOutput -PathType Leaf)) {
            if ($variantCode -eq 0) { $variantCode = 2 }
            Write-Host "Creation failed (code $variantCode). No diagnostic log was written." -ForegroundColor Red
            if ($code -eq 0) { $code = $variantCode }
            break
        }
    }
    if ($NoPause) { exit $code }
    $nextAction = Read-AImageRawLine -Label 'Enter = another picture; C or Esc = close'
    if ($nextAction -eq '__AIMAGE_BACK__' -or $nextAction -match '^[cC]$') { Write-Host 'AImage closed.'; exit $code }
    $directRun = $false
    $ResumeStep = 'model'
    $useReviewFlow = $true
    $state = @{
        Model = ''; Quality = ''; Prompt = ''; Mode = 'Text to image'; Image = ''
        Strength = 0.40; StrengthText = ''; Appearance = ''; PhotoComposition = 'Auto'; Variants = 1; VariantsText = ''; Format = ''
    }
}
