$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'paths.ps1')
. (Join-Path $root 'generation-settings.ps1')
$sandbox = Join-Path $PSScriptRoot ('.history-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
    $paths = [pscustomobject]@{ Output=$sandbox; Root=$sandbox }
    $csv = Join-Path $sandbox 'generation-history.csv'
    # Legacy format includes quotes/commas in prompts and a third-party column.
    [pscustomobject]@{timestamp='2020-01-01'; model='old'; prompt='a "fox", in snow'; outputFile='old.png'; custom='keep'} |
        Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    $null = Write-AImageGenerationHistory -Paths $paths -Prompt 'new prompt' -Model test -OutputPath 'new.jpg' -Seed 123 -Appearance Natural -EffectivePrompt 'expanded'
    $rows = @(Import-Csv -LiteralPath $csv)
    if ($rows.Count -ne 2 -or $rows[0].prompt -ne 'a "fox", in snow' -or $rows[0].custom -ne 'keep' -or $rows[1].seed -ne '123') { throw 'History upgrade lost information.' }
    $null = Write-AImageGenerationHistory -Paths $paths -Prompt 'another' -Model test -OutputPath 'another.jpg'
    if (@(Import-Csv -LiteralPath $csv).Count -ne 3) { throw 'Upgraded CSV could not be appended.' }
    $natural = Get-AImagePromptSettings -Prompt 'a fox' -Model lustify-v10-krea2-turbo -Appearance Natural
    if ($natural.NegativePrompt -or $natural.Prompt -notmatch 'Photographic rendering') { throw 'Turbo realism conditioning incorrect.' }
    $original = Get-AImagePromptSettings -Prompt 'a painting' -Model lustify-zenith-v9 -Appearance Original
    if ($original.Prompt -ne 'a painting' -or $original.NegativePrompt) { throw 'Original prompt was altered.' }
    $simple = 'man with big nose surrounded with bushes and empty plastic bottles and garbage lying around'
    $assisted = Get-AImagePromptSettings -Prompt $simple -Model lustify-v10-krea2-turbo -Appearance Realistic -PhotoComposition FullBody
    if (-not $assisted.Prompt.Contains($simple) -or -not $assisted.Prompt.StartsWith('A realistic, unretouched full-body photograph') -or $assisted.Prompt -notmatch 'full-body photograph' -or
        $assisted.Prompt -notmatch 'anatomically connected' -or $assisted.NegativePrompt -or $assisted.PhotoComposition -ne 'FullBody') { throw 'Assisted photograph lost intent, framing, or Turbo conditioning.' }
    $auto = Get-AImagePromptSettings -Prompt 'a close-up of a man sitting' -Appearance Realistic
    if ($auto.Prompt -notmatch 'Preserve any explicitly requested close-up or pose' -or $auto.Prompt -match 'Use a full-body') { throw 'Auto framing imposed a body crop.' }
    $scene = Get-AImagePromptSettings -Prompt $simple -Appearance Realistic
    if (-not $scene.Prompt.StartsWith('A realistic, unretouched full-body photograph') -or $scene.PhotoComposition -ne 'Auto' -or $scene.ResolvedPhotoComposition -ne 'FullBody') { throw 'Automatic human scene framing missing or selected value lost.' }
    $portrait = Get-AImagePromptSettings -Prompt 'portrait of a woman sitting by a window' -Appearance Realistic
    if ($portrait.Prompt -match 'full-body') { throw 'Automatic framing overrode a portrait.' }
    $groupPrompt = 'Group portrait of three hikers. The hiker on the left reads a map while the one on the right drinks water.'
    $group = Get-AImagePromptSettings -Prompt $groupPrompt -Appearance Realistic
    if ($group.ResolvedPhotoComposition -ne 'FullBody' -or -not $group.Prompt.Contains($groupPrompt) -or
        $group.Prompt -notmatch 'Every person is fully visible head to toe' -or $group.Prompt -notmatch 'vary individual looks, postures, gaze' -or
        $group.Prompt -notmatch 'Preserve the requested headcount, appearances, positions and activities') {
        throw 'Group assistance did not add full-body framing and preserve the specified actions.'
    }
    $groupCrop = Get-AImagePromptSettings -Prompt 'A close-up of three hikers' -Appearance Realistic
    if ($groupCrop.ResolvedPhotoComposition -ne 'Auto' -or $groupCrop.Prompt -match 'head to toe') {
        throw 'Group assistance overrode an explicit crop.'
    }
    $animal = Get-AImagePromptSettings -Prompt 'a fox on a rock' -Appearance Realistic
    if ($animal.Prompt -notmatch 'wide environmental photograph' -or $animal.Prompt -match 'entire subject from head to feet') { throw 'Human framing leaked into animal scene.' }
    if ($scene.Prompt -notmatch 'wearing ordinary casual clothing' -or $scene.Prompt -notmatch 'well below knee height') { throw 'Unspecified wardrobe or litter scale defaults missing.' }
    $wardrobe = Get-AImagePromptSettings -Prompt 'a woman in a red dress' -Appearance Realistic
    if ($wardrobe.Prompt -match 'wearing ordinary casual clothing') { throw 'Default clothing overrode requested wardrobe.' }
    $largeProps = Get-AImagePromptSettings -Prompt 'a man beside giant plastic bottles and garbage' -Appearance Realistic
    if ($largeProps.Prompt -match 'well below knee height') { throw 'Scale assistance overrode intentionally giant props.' }
    foreach ($mode in @('Start from image','Edit image')) {
        $edit = Get-AImagePromptSettings -Prompt 'change the coat' -Appearance Realistic -PhotoComposition FullBody -ImageMode $mode
        if ($edit.PhotoComposition -or $edit.Prompt -match 'Use a full-body' -or $edit.Prompt -notmatch 'Preserve the source composition' -or
            $edit.Prompt -notmatch 'Keep a realistic photographic appearance. change the coat') { throw 'Photo framing or subject prefix leaked into source image mode.' }
    }
    $untouched = Get-AImagePromptSettings -Prompt 'a painting' -Appearance Original -PhotoComposition FullBody
    if ($untouched.Prompt -ne 'a painting' -or $untouched.PhotoComposition) { throw 'Framing altered unassisted input.' }
    $null = Write-AImageGenerationHistory -Paths $paths -Prompt $simple -Model test -OutputPath 'assisted.jpg' -Appearance Realistic -PhotoComposition FullBody -ResolvedPhotoComposition FullBody -EffectivePrompt $assisted.Prompt
    $saved = @(Import-Csv -LiteralPath $csv)[-1]
    if ($saved.prompt -ne $simple -or $saved.photoComposition -ne 'FullBody' -or $saved.resolvedPhotoComposition -ne 'FullBody' -or $saved.effectivePrompt -ne $assisted.Prompt) { throw 'Assistance choices were not recorded.' }
    $krea = @(Get-AImageQualityChoices -Model ([pscustomobject]@{Id='lustify-v10-krea2-turbo'}))
    if (@($krea | Where-Object Steps -ne 8).Count -or $krea[1].Width -ne 768) { throw 'Turbo reference settings or Standard default changed.' }
    $sdxl = @(Get-AImageQualityChoices -Model ([pscustomobject]@{Id='lustify-zenith-v9'}))
    if ($sdxl[1].Width -ne 1024 -or $sdxl[2].Steps -ne 30) { throw 'SDXL quality settings incorrect.' }
    Write-Host 'Settings and legacy history migration test passed.' -ForegroundColor Green
} finally {
    $absolute = [IO.Path]::GetFullPath($sandbox)
    if (-not $absolute.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
