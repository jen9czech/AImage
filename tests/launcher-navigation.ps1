$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'paths.ps1')
. (Join-Path $root 'generation-settings.ps1')
. (Join-Path $root 'launcher-input.ps1')
$sandbox = Join-Path $PSScriptRoot ('.navigation-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
    $paths = [pscustomobject]@{ Root = $sandbox; Models = $sandbox; Output = $sandbox }
    $image = Join-Path $sandbox 'starting image.jpg'
    Set-Content -LiteralPath $image -Value 'stub'
    $models = @(
        [pscustomobject]@{ Id='lustify-v10-krea2-turbo'; Name='Krea'; Width=1024; Height=1024; Steps=8 },
        [pscustomobject]@{ Id='qwen-image-2.1-Q4_K_M.gguf'; Name='Qwen'; Width=1024; Height=1024; Steps=40 }
    )
    function Get-AImageModelHint { param($Model) return $Model.Name }
    $script:screenReplaced = $false
    function Show-AImageLauncherStep {
        param($Step)
        # Every question, including a revisited question, replaces its page.
        $script:screenReplaced = $true
    }
    function New-TestState {
        return @{ Model=''; Quality=''; Mode='Text to image'; Image=''; Strength=0.4; StrengthText='';
            Prompt=''; Appearance=''; PhotoComposition='Auto'; Variants=1; VariantsText=''; Format='' }
    }
    # Use the same wizard as the real launcher with scripted answers. Unexpected
    # questions fail immediately, detecting skipped or looping Esc destinations.
    function Read-AImageChoice {
        param($Title,$Choices,$Default,$Current,$InputLabel)
        if ($Title -match 'appearance|framing') { $script:choiceDefaults[$Title] = $Default }
        $answer = Get-TestAnswer $Title
        if ($Title -eq 'Review settings:' -and ($Default -ne 0 -or $InputLabel -notmatch 'Enter to generate')) { throw 'Review must separate generating from numbered settings.' }
        if ($answer -ne '__AIMAGE_BACK__' -and $answer -ne $Default -and ([int]$answer -lt 1 -or [int]$answer -gt $Choices.Count)) { throw 'Disabled choice was offered or selected.' }
        return $answer
    }
    function Read-AImageRawLine {
        param($Label,$Initial,$History)
        return Get-TestAnswer $Label
    }
    function Get-TestAnswer {
        param([string]$Question)
        if (-not $script:screenReplaced) { throw 'Question was appended without replacing the previous page.' }
        $script:screenReplaced = $false
        if (-not $script:answers.Count) { throw "Unexpected question: $Question" }
        $item = $script:answers.Dequeue()
        if ($Question -notmatch $item[0]) { throw "Expected '$($item[0])', got '$Question'." }
        return $item[1]
    }
    $script:answers = [Collections.Queue]::new()
    $script:choiceDefaults = @{}
    foreach ($item in @(
        @('Choose a model',1), @('detail and speed',2), @('image mode',2),
        @('Image path',('"' + $image + '"')), @('Change strength','__AIMAGE_BACK__'),
        @('Image path',('"' + $image + '"')), @('Change strength','0.35'),
        @('finished image','__AIMAGE_BACK__'), @('Change strength','0.4'),
        @('finished image','a fox on a rock'), @('appearance',3),
        @('Different versions','__AIMAGE_BACK__'), @('appearance',2),
        @('Different versions','2'), @('file type','__AIMAGE_BACK__'),
        @('Different versions','3'), @('file type',2)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($result.Image -ne $image -or $result.Strength -ne 0.4 -or $result.Variants -ne 3 -or $result.Appearance -ne 'Original' -or $result.Format -ne 'jpg') {
        throw 'Wizard did not preserve/correct the selected settings.'
    }
    if ($script:answers.Count) { throw 'Unused navigation answers.' }
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('Choose a model',2), @('image mode','__AIMAGE_BACK__'),
        @('Choose a model',1), @('detail and speed','__AIMAGE_BACK__'),
        @('Choose a model','__AIMAGE_BACK__')
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($null -ne $result -or $script:answers.Count) { throw 'Esc did not reach model and close.' }
    $history = @(Get-AImagePromptHistory -Paths $paths)
    if ($history[0] -ne 'a fox on a rock') { throw 'Latest accepted prompt is missing.' }
    Set-Content -LiteralPath (Join-Path $sandbox 'mmproj-Qwen3VL-8B-Instruct-F16.gguf') -Value 'stub'
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('Choose a model',2), @('image mode',3), @('Image path',('"' + $image + '"')),
        @('Describe the changes','replace the background with a forest'), @('appearance',2),
        @('Different versions','1'), @('file type',1)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($result.Mode -ne 'Edit image' -or $result.Image -ne $image -or $result.Format -ne 'png') { throw 'Reference editing routing incorrect.' }
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('Choose a model',1), @('detail and speed',2), @('image mode',1),
        @('Describe the image','a man by bushes'), @('appearance',1),
        @('framing',2), @('Different versions','__AIMAGE_BACK__'),
        @('framing','__AIMAGE_BACK__'), @('appearance',1), @('framing',4),
        @('Different versions','1'), @('file type',2)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($result.Appearance -ne 'Realistic' -or $result.PhotoComposition -ne 'Wide' -or $script:answers.Count) { throw 'Assisted framing or one-step Esc failed.' }
    if ($script:choiceDefaults['Choose appearance:'] -ne 1 -or $script:choiceDefaults['Choose framing:'] -ne 1) { throw 'Assistance or Automatic framing is not the text default.' }
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('Choose a model',1), @('detail and speed',2), @('image mode',1),
        @('Describe the image','a fox'), @('appearance',1), @('framing','__AIMAGE_BACK__'),
        @('appearance',2), @('Different versions','1'), @('file type',2)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($result.Appearance -ne 'Original' -or $script:answers.Count) { throw 'Disabling assistance did not remove the framing screen.' }
    # Reproduce backing out from the empty prompt shown in the reported screen.
    # Esc must not accept the example prompt or return a generation request.
    $historyBeforeBack = @(Get-AImagePromptHistory -Paths $paths).Count
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('Choose a model',1), @('detail and speed',2), @('image mode',1),
        @('Describe the image','__AIMAGE_BACK__'), @('image mode','__AIMAGE_BACK__'),
        @('detail and speed','__AIMAGE_BACK__'), @('Choose a model','__AIMAGE_BACK__')
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths
    if ($null -ne $result -or $script:answers.Count -or @(Get-AImagePromptHistory -Paths $paths).Count -ne $historyBeforeBack) {
        throw 'Esc accepted a cancelled prompt or returned settings for generation.'
    }
    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('image mode',1), @('Describe the image',''), @('Describe the image','a fox'),
        @('Review settings',3), @('appearance',2),
        @('Review settings',5), @('file type',2),
        @('Review settings',5), @('file type',1),
        @('Review settings','__AIMAGE_BACK__'), @('Describe the image','a red fox'), @('Review settings',0)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths -ReviewFlow
    if ($result.Model -ne $models[0].Id -or $result.Quality -ne 'Standard' -or $result.Prompt -ne 'a red fox' -or
        $result.Appearance -ne 'Original' -or $result.Format -ne 'png' -or $script:answers.Count) {
        throw 'The main flow or review options did not preserve the chosen settings.'
    }

    $script:answers = [Collections.Queue]::new()
    foreach ($item in @(
        @('image mode',2), @('Image path',$image), @('finished image','/example'),
        @('Review settings',4), @('Change strength','NaN'), @('Change strength','0.75'),
        @('Review settings',0)
    )) { $script:answers.Enqueue($item) }
    $result = Get-AImageLauncherSettings -Available $models -State (New-TestState) -Paths $paths -ReviewFlow
    if ($result.Mode -ne 'Start from image' -or $result.Image -ne $image -or $result.Strength -ne 0.75 -or
        $result.Prompt -notmatch 'red leather jacket' -or $result.Format -ne 'jpg' -or $script:answers.Count) {
        throw 'The redraw review did not preserve the source, example or strength.'
    }
    Write-Host 'Launcher navigation and history test passed.' -ForegroundColor Green
} finally {
    $absolute = [IO.Path]::GetFullPath($sandbox)
    if (-not $absolute.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
