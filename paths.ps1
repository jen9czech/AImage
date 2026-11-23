function Test-AImageUniformPicture {
    param($Bitmap)

    $firstPixel = $Bitmap.GetPixel(0, 0).ToArgb()
    $width = $Bitmap.Width
    $height = $Bitmap.Height
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            if ($Bitmap.GetPixel($x, $y).ToArgb() -ne $firstPixel) { return $false }
        }
    }
    return $true
}

function Save-AImageValidatedPicture {
    param([string]$PngPath, [string]$OutputPath, [int]$Width, [int]$Height, [int]$JpegQuality)

    Add-Type -AssemblyName System.Drawing
    if (-not [IO.File]::Exists($PngPath)) { throw 'The engine did not save an image.' }
    try { $bitmap = [Drawing.Bitmap]::new($PngPath) }
    catch { throw 'The engine output could not be opened as an image.' }
    $stagedPath = $PngPath
    try {
        if ($bitmap.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or
            $bitmap.Width -ne $Width -or $bitmap.Height -ne $Height) {
            throw "Expected a ${Width}x${Height} PNG from the engine."
        }
        if (Test-AImageUniformPicture $bitmap) { throw 'The engine produced a solid-color image. No picture was saved.' }
        if ([IO.Path]::GetExtension($OutputPath) -in @('.jpg', '.jpeg')) {
            $stagedPath = [IO.Path]::ChangeExtension($PngPath, '.jpg')
            $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
            $options = [Drawing.Imaging.EncoderParameters]::new(1)
            try {
                $options.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)
                $bitmap.Save($stagedPath, $codec, $options)
            } finally { $options.Dispose() }
            $jpeg = [Drawing.Bitmap]::new($stagedPath)
            try {
                if ($jpeg.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Jpeg.Guid -or $jpeg.Width -ne $Width -or $jpeg.Height -ne $Height -or
                    (Test-AImageUniformPicture $jpeg)) {
                    throw 'The JPEG encoder did not produce the expected image.'
                }
            } finally { $jpeg.Dispose() }
        }
    } finally { $bitmap.Dispose() }
    [IO.File]::Move($stagedPath, $OutputPath)
}

function Get-AImagePaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $models = if ($env:AIMAGE_MODELS_DIR) {
        $env:AIMAGE_MODELS_DIR
    } else {
        'C:\AI\Models\Image'
    }

    $pictures = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures)
    if ([string]::IsNullOrWhiteSpace($pictures)) {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if ([string]::IsNullOrWhiteSpace($userProfile)) { $userProfile = $env:USERPROFILE }
        if ([string]::IsNullOrWhiteSpace($userProfile)) { throw 'Windows user profile folder could not be determined.' }
        $pictures = Join-Path $userProfile 'Pictures'
    }
    $output = if ($env:AIMAGE_OUTPUT_DIR) {
        $env:AIMAGE_OUTPUT_DIR
    } else {
        Join-Path $pictures 'AI\AImage'
    }

    [pscustomobject]@{
        Root = [IO.Path]::GetFullPath($Root)
        Models = [IO.Path]::GetFullPath($models)
        Output = [IO.Path]::GetFullPath($output)
        Pictures = [IO.Path]::GetFullPath($pictures)
        UserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    }
}

function Resolve-AImageProfilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Paths
    )
    $expanded = $Path.Replace('{root}', $Paths.Root).Replace('{models}', $Paths.Models).Replace('{output}', $Paths.Output)
    if ([IO.Path]::IsPathRooted($expanded)) { return [IO.Path]::GetFullPath($expanded) }
    return [IO.Path]::GetFullPath((Join-Path $Paths.Root $expanded))
}

function ConvertTo-AImagePromptSlug {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [ValidateRange(8, 80)][int]$MaxLength = 48,
        [ValidateRange(1, 10)][int]$MaxWords = 6
    )

    $decomposed = $Prompt.Normalize([Text.NormalizationForm]::FormD)
    $letters = [Text.StringBuilder]::new()
    foreach ($character in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$letters.Append($character)
        }
    }
    $clean = $letters.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    $words = @($clean -split '[^\p{L}\p{Nd}]+' | Where-Object { $_ })
    $stopWords = @('a', 'an', 'the', 'of', 'in', 'on', 'at', 'with', 'and', 'or', 'to', 'for', 'from')
    $useful = @($words | Where-Object { $_ -notin $stopWords })
    if (-not $useful.Count) { $useful = $words }
    $slug = (@($useful | Select-Object -First $MaxWords) -join '-').Trim('-')
    if ($slug.Length -gt $MaxLength) { $slug = $slug.Substring(0, $MaxLength).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'image' }
    return $slug
}

function ConvertTo-AImageModelSlug {
    param(
        [Parameter(Mandatory = $true)][string]$Model,
        [ValidateRange(8, 64)][int]$MaxLength = 40
    )

    $name = [IO.Path]::GetFileNameWithoutExtension($Model).ToLowerInvariant()
    $slug = ($name -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt $MaxLength) { $slug = $slug.Substring(0, $MaxLength).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'model' }
    return $slug
}

function New-AImageOutputFileName {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Model,
        [string]$Id = ([Guid]::NewGuid().ToString('N').Substring(0, 8)),
        [ValidateSet('png', 'jpg')][string]$Extension = 'png',
        [datetime]$Time = (Get-Date)
    )

    $promptSlug = ConvertTo-AImagePromptSlug -Prompt $Prompt
    $modelSlug = ConvertTo-AImageModelSlug -Model $Model
    return '{0}-{1}-{2}-{3}.{4}' -f $Time.ToString('yyyyMMdd-HHmmss'), $modelSlug, $promptSlug, $Id, $Extension
}

function Write-AImagePromptHistory {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    New-Item -ItemType Directory -Force -Path $Paths.Output | Out-Null
    $historyPath = Join-Path $Paths.Output 'prompt-history.csv'
    $mutex = [Threading.Mutex]::new($false, 'Local\AImageGenerationHistoryCsv')
    $locked = $false
    try {
        $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
        if (-not $locked) { throw 'Timed out waiting to write prompt-history.csv.' }
        $row = [pscustomobject][ordered]@{
            timestamp = (Get-Date).ToString('o')
            prompt = $Prompt
        }
        if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
            $row | Export-Csv -LiteralPath $historyPath -NoTypeInformation -Append -Encoding UTF8
        } else {
            $row | Export-Csv -LiteralPath $historyPath -NoTypeInformation -Encoding UTF8
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Write-AImageGenerationHistory {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string]$QualityPreset = '',
        [int]$Width = 0, [int]$Height = 0, [int]$Steps = 0,
        [string]$Appearance = 'Original', [string]$EffectivePrompt, [string]$NegativePrompt,
        [string]$PhotoComposition = '',
        [string]$ResolvedPhotoComposition = '',
        [int]$Seed = 42, [string]$Backend, [string]$VaeDevice, [string]$ImageMode = 'Text to image',
        [string]$SourceImage, [double]$Strength = 0.75, [double]$ElapsedSeconds = 0
    )

    New-Item -ItemType Directory -Force -Path $Paths.Output | Out-Null
    $historyPath = Join-Path $Paths.Output 'generation-history.csv'
    $mutex = [Threading.Mutex]::new($false, 'Local\AImageGenerationHistoryCsv')
    $locked = $false
    try {
        $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
        if (-not $locked) { throw 'Timed out waiting to write generation-history.csv.' }
        $row = [pscustomobject][ordered]@{
            timestamp = (Get-Date).ToString('o'); model = $Model; qualityPreset = $QualityPreset
            width = $Width; height = $Height; steps = $Steps; prompt = $Prompt
            outputFile = [IO.Path]::GetFileName($OutputPath); appearance = $Appearance; photoComposition = $PhotoComposition
            resolvedPhotoComposition = $ResolvedPhotoComposition
            effectivePrompt = if ($EffectivePrompt) { $EffectivePrompt } else { $Prompt }
            negativePrompt = $NegativePrompt; seed = $Seed; backend = $Backend; vaeBackend = $VaeDevice; imageMode = $ImageMode
            sourceImage = $SourceImage
            strength = if ($ImageMode -eq 'Start from image') { $Strength.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) } else { '' }
            elapsedSeconds = $ElapsedSeconds.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
        }
        $columns = @($row.PSObject.Properties.Name)
        if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
            $existing = @(Import-Csv -LiteralPath $historyPath)
            $oldColumns = if ($existing.Count) { @($existing[0].PSObject.Properties.Name) } else { @() }
            if (($columns -join ',') -ne ($oldColumns -join ',')) {
                # Preserve older rows and unknown extension columns when adding fields.
                $columns += @($oldColumns | Where-Object { $_ -notin $columns })
                $upgradePath = $historyPath + '.' + [Guid]::NewGuid().ToString('N') + '.upgrade'
                try {
                    @($existing + $row) | Select-Object -Property $columns |
                        Export-Csv -LiteralPath $upgradePath -NoTypeInformation -Encoding UTF8
                    Move-Item -LiteralPath $upgradePath -Destination $historyPath -Force
                } finally {
                    if (Test-Path -LiteralPath $upgradePath) { Remove-Item -LiteralPath $upgradePath -Force }
                }
            } else {
                $row | Export-Csv -LiteralPath $historyPath -NoTypeInformation -Append -Encoding UTF8
            }
        } else {
            $row | Export-Csv -LiteralPath $historyPath -NoTypeInformation -Encoding UTF8
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
    return $historyPath
}

function Get-AImagePromptHistory {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [ValidateRange(1, 200)][int]$Maximum = 50
    )

    $entries = [Collections.Generic.List[object]]::new()
    $historyPath = Join-Path $Paths.Output 'generation-history.csv'
    if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
        try {
            foreach ($row in @(Import-Csv -LiteralPath $historyPath)) {
                if (-not [string]::IsNullOrWhiteSpace($row.prompt)) {
                    $entries.Add([pscustomobject]@{ Prompt = [string]$row.prompt; At = [string]$row.timestamp })
                }
            }
        } catch { }
    }

    $promptHistoryPath = Join-Path $Paths.Output 'prompt-history.csv'
    if (Test-Path -LiteralPath $promptHistoryPath -PathType Leaf) {
        try {
            foreach ($row in @(Import-Csv -LiteralPath $promptHistoryPath)) {
                if (-not [string]::IsNullOrWhiteSpace($row.prompt)) {
                    $entries.Add([pscustomobject]@{ Prompt = [string]$row.prompt; At = [string]$row.timestamp })
                }
            }
        } catch { }
    }

    $queuePath = Join-Path $Paths.Root 'queue\jobs.json'
    if (Test-Path -LiteralPath $queuePath -PathType Leaf) {
        try {
            $queue = Get-Content -LiteralPath $queuePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($job in @($queue.jobs)) {
                if (-not [string]::IsNullOrWhiteSpace($job.prompt)) {
                    $entries.Add([pscustomobject]@{ Prompt = [string]$job.prompt; At = [string]$job.createdAt })
                }
            }
        } catch { }
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    return @($entries | Sort-Object At -Descending | ForEach-Object {
        if ($seen.Add($_.Prompt)) { $_.Prompt }
    } | Select-Object -First $Maximum)
}
