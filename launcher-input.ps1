function Read-AImageConsoleKey { return [Console]::ReadKey($true) }

function Write-AImageLauncherText {
    param([Parameter(Position=0)][object]$Object, [ConsoleColor]$ForegroundColor)
    if ($script:AImageLauncherPages -and $script:AImageLauncherPages.Count) {
        $record = @{}
        foreach ($key in $PSBoundParameters.Keys) { $record[$key] = $PSBoundParameters[$key] }
        $script:AImageLauncherPages[$script:AImageLauncherPages.Count - 1].Lines.Add($record)
    }
    Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
}

function Save-AImageLauncherInput {
    param([string[]]$Lines)
    if ($script:AImageLauncherPages -and $script:AImageLauncherPages.Count) {
        foreach ($line in $Lines) {
            $script:AImageLauncherPages[$script:AImageLauncherPages.Count - 1].Lines.Add(@{Object=$line})
        }
    }
}

function Get-AImageCellWidth {
    param([AllowEmptyString()][string]$Text)
    if ($Text -cmatch '^[ -~]*$') { return $Text.Length }
    return $Host.UI.RawUI.LengthInBufferCells($Text)
}

function Get-AImageTextBoundary {
    param([AllowEmptyString()][string]$Text, [int]$Cursor, [switch]$Previous)
    $previousOffset = 0
    foreach ($offset in [Globalization.StringInfo]::ParseCombiningCharacters($Text)) {
        if ($Previous -and $offset -ge $Cursor) { return $previousOffset }
        if (-not $Previous -and $offset -gt $Cursor) { return $offset }
        $previousOffset = $offset
    }
    if ($Previous) { return $previousOffset }
    return $Text.Length
}

function Get-AImageEditorLayout {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Label,
        [AllowEmptyString()][string]$Text = '',
        [int]$Cursor = 0,
        [int]$Width = 80
    )

    $prefix = if ($Label) { "${Label}: " } else { '  ' }
    if ($prefix.Length -gt ($Width - 5)) { $prefix = $prefix.Substring(0, [Math]::Max(1, $Width - 5)) }
    $indent = '  '
    $firstCapacity = [Math]::Max(1, $Width - $prefix.Length)
    $nextCapacity = [Math]::Max(1, $Width - $indent.Length)
    $segments = [Collections.Generic.List[object]]::new()
    $position = 0
    $first = $true

    while ($position -lt $Text.Length) {
        # Spaces used for a word break belong to neither visible line.
        while ($position -lt $Text.Length -and [char]::IsWhiteSpace($Text[$position])) { $position++ }
        if ($position -ge $Text.Length) { break }
        $capacity = if ($first) { $firstCapacity } else { $nextCapacity }
        $remaining = $Text.Substring($position)
        $end = $Text.Length
        $next = $end
        if ((Get-AImageCellWidth $remaining) -gt $capacity) {
            $limit = [Math]::Min($capacity, $remaining.Length)
            if ($remaining -cmatch '[^ -~]') {
                $boundaries = [Globalization.StringInfo]::ParseCombiningCharacters($remaining)
                $limit = 0
                for ($i = 1; $i -le $boundaries.Length; $i++) {
                    $offset = if ($i -eq $boundaries.Length) { $remaining.Length } else { $boundaries[$i] }
                    if ((Get-AImageCellWidth $remaining.Substring(0, $offset)) -gt $capacity) { break }
                    $limit = $offset
                }
                if ($limit -eq 0) { $limit = if ($boundaries.Length -gt 1) { $boundaries[1] } else { $remaining.Length } }
            }
            $breakAt = $remaining.LastIndexOf(' ', [Math]::Min($limit - 1, $remaining.Length - 1))
            if ($breakAt -gt 0) {
                $end = $position + $breakAt
                $next = $end
                while ($next -lt $Text.Length -and [char]::IsWhiteSpace($Text[$next])) { $next++ }
            } else {
                # Keep an unusually long word visible instead of losing it.
                $end = $position + $limit
                $next = $end
            }
        }
        if ($end -le $position) { $end = [Math]::Min($position + $capacity, $Text.Length); $next = $end }
        $lineText = $Text.Substring($position, $end - $position).TrimEnd()
        $segments.Add([pscustomobject]@{
            Start = $position; End = $end; Text = $lineText
            Prefix = if ($first) { $prefix } else { $indent }
        })
        $position = $next
        $first = $false
    }
    if ($segments.Count -eq 0) {
        $segments.Add([pscustomobject]@{ Start = 0; End = 0; Text = ''; Prefix = $prefix })
    }

    $lines = @($segments | ForEach-Object { $_.Prefix + $_.Text })
    $cursor = [Math]::Max(0, [Math]::Min($Cursor, $Text.Length))
    $cursorRow = $segments.Count - 1
    $cursorColumn = $segments[-1].Prefix.Length + (Get-AImageCellWidth $segments[-1].Text)
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $segment = $segments[$i]
        if ($cursor -lt $segment.Start) {
            $cursorRow = $i
            $cursorColumn = $segment.Prefix.Length
            break
        }
        if ($cursor -le $segment.End) {
            $cursorRow = $i
            $textBeforeCursor = $segment.Text.Substring(0, [Math]::Min($cursor - $segment.Start, $segment.Text.Length))
            $cursorColumn = $segment.Prefix.Length + (Get-AImageCellWidth $textBeforeCursor)
            break
        }
    }
    return [pscustomobject]@{ Lines = $lines; CursorRow = $cursorRow; CursorColumn = $cursorColumn }
}

function Write-AImageEditorLayout {
    param(
        [Parameter(Mandatory = $true)]$Layout,
        [int]$OriginTop = 0,
        [int]$PreviousRows = 1
    )

    $width = [Console]::BufferWidth
    $clearWidth = $width - 1
    $rows = [Math]::Max($PreviousRows, $Layout.Lines.Count)
    for ($i = 0; $i -lt $rows; $i++) {
        $row = $OriginTop + $i
        if ($row -ge 0 -and $row -lt [Console]::BufferHeight) {
            [Console]::SetCursorPosition(0, $row)
            [Console]::Write((' ' * $clearWidth))
        }
    }
    for ($i = 0; $i -lt $Layout.Lines.Count; $i++) {
        $row = $OriginTop + $i
        if ($row -ge 0 -and $row -lt [Console]::BufferHeight) {
            [Console]::SetCursorPosition(0, $row)
            [Console]::Write($Layout.Lines[$i])
        }
    }
    $cursorRow = $OriginTop + $Layout.CursorRow
    if ($cursorRow -ge 0 -and $cursorRow -lt [Console]::BufferHeight) {
        [Console]::SetCursorPosition([Math]::Min($Layout.CursorColumn, $width - 1), $cursorRow)
    }
    return [int]$Layout.Lines.Count
}

function Write-AImageLauncherWrappedText {
    param([string]$Label, [string]$Text)
    $width = if ([Console]::IsOutputRedirected) { 100 } else { [Math]::Max(20, [Console]::BufferWidth - 1) }
    foreach ($paragraph in ($Text -split '\r?\n')) {
        $layout = Get-AImageEditorLayout -Label $Label -Text $paragraph -Width $width
        foreach ($line in $layout.Lines) { Write-AImageLauncherText $line }
        $Label = ''
    }
}

function Read-AImageRawLine {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Initial = '',
        [string[]]$History = @()
    )

    $buffer = $Initial
    $cursor = $buffer.Length
    $historyIndex = -1
    $draft = $buffer
    $originTop = [Console]::CursorTop
    $renderedRows = 1
    $submitted = $false
    $firstDraw = $true
    while ($true) {
        # When a terminal supplies a paste as queued key events, process the
        # whole batch before redrawing. Enter still commits the final buffer.
        if ($firstDraw -or $submitted -or -not [Console]::KeyAvailable) {
            $layout = Get-AImageEditorLayout -Label $Label -Text $buffer -Cursor $cursor -Width ([Console]::BufferWidth - 1)
            # Make room before writing at the bottom of the buffer. Each newline
            # scrolls the already drawn input up by one row, including its origin.
            $height = [Console]::BufferHeight
            $visibleRows = [Math]::Min($layout.Lines.Count, $height)
            $originTop = [Math]::Min($originTop, $height - 1)
            while ($originTop + $visibleRows -gt $height) {
                [Console]::SetCursorPosition(0, $height - 1)
                [Console]::WriteLine()
                $originTop--
            }
            $firstRow = [Math]::Max(0, $layout.CursorRow - $visibleRows + 1)
            $visibleLayout = [pscustomobject]@{
                Lines = @($layout.Lines[$firstRow..($firstRow + $visibleRows - 1)])
                CursorRow = $layout.CursorRow - $firstRow
                CursorColumn = $layout.CursorColumn
            }
            $renderedRows = Write-AImageEditorLayout -Layout $visibleLayout -OriginTop $originTop -PreviousRows $renderedRows
            $firstDraw = $false
        }
        if ($submitted) {
            Save-AImageLauncherInput -Lines $layout.Lines
            [Console]::SetCursorPosition(0, $originTop + $renderedRows - 1)
            [Console]::WriteLine()
            return $buffer
        }
        $key = Read-AImageConsoleKey
        if (($key.Key -eq 'V' -and ($key.Modifiers -band [ConsoleModifiers]::Control)) -or
            ($key.Key -eq 'Insert' -and ($key.Modifiers -band [ConsoleModifiers]::Shift))) {
            $pasted = Get-Clipboard -Raw -ErrorAction SilentlyContinue
            if ($pasted) {
                # The launcher accepts one answer. Line breaks in a paste are
                # text separators, never Enter presses that advance the wizard.
                $pasted = [regex]::Replace($pasted, '\r\n|[\r\n\t]', ' ')
                $pasted = [regex]::Replace($pasted, '[\p{Cc}]', '')
                $buffer = $buffer.Insert($cursor, $pasted)
                $cursor += $pasted.Length
                $historyIndex = -1
            }
            continue
        }
        switch ($key.Key) {
            'Escape' {
                $endRow = [Math]::Min($originTop + $renderedRows, [Console]::BufferHeight - 1)
                [Console]::SetCursorPosition(0, $endRow); [Console]::WriteLine()
                return '__AIMAGE_BACK__'
            }
            'Enter' { $submitted = $true }
            'LeftArrow' { $cursor = Get-AImageTextBoundary $buffer $cursor -Previous }
            'RightArrow' { $cursor = Get-AImageTextBoundary $buffer $cursor }
            'Home' { $cursor = 0 }
            'End' { $cursor = $buffer.Length }
            'Backspace' {
                if ($cursor -gt 0) {
                    $previous = Get-AImageTextBoundary $buffer $cursor -Previous
                    $buffer = $buffer.Remove($previous, $cursor - $previous)
                    $cursor = $previous
                }
            }
            'Delete' {
                if ($cursor -lt $buffer.Length) {
                    $next = Get-AImageTextBoundary $buffer $cursor
                    $buffer = $buffer.Remove($cursor, $next - $cursor)
                }
            }
            'UpArrow' {
                if ($History.Count) {
                    if ($historyIndex -lt 0) { $draft = $buffer }
                    if ($historyIndex -lt ($History.Count - 1)) { $historyIndex++ }
                    $buffer = $History[$historyIndex]; $cursor = $buffer.Length
                }
            }
            'DownArrow' {
                if ($historyIndex -gt 0) { $historyIndex--; $buffer = $History[$historyIndex] }
                elseif ($historyIndex -eq 0) { $historyIndex = -1; $buffer = $draft }
                $cursor = $buffer.Length
            }
            default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    $buffer = $buffer.Insert($cursor, [string]$key.KeyChar); $cursor++
                    $historyIndex = -1
                }
            }
        }
    }
}

function Read-AImageChoice {
    param([string]$Title, [string[]]$Choices, [int]$Default = 1, [int]$Current = 0, [string]$InputLabel)

    Write-AImageLauncherText ''
    Write-AImageLauncherText $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $mark = if ($i + 1 -eq $Default) { ' [default]' } else { '' }
        if ($Current -gt 0 -and $i + 1 -eq $Current -and $Current -ne $Default) { $mark += ' [selected]' }
        $lines = $Choices[$i] -split "`r?`n", 2
        Write-AImageLauncherText ('  {0}. {1}{2}' -f ($i + 1), $lines[0], $mark)
        if ($lines.Count -gt 1) { Write-AImageLauncherText $lines[1] -ForegroundColor DarkGray }
    }
    $accepted = if ($Current -gt 0) { $Current } else { $Default }
    if (-not $InputLabel) { $InputLabel = "Choice [Enter = $accepted]" }
    while ($true) {
        $answer = Read-AImageRawLine -Label $InputLabel
        if ($answer -eq '__AIMAGE_BACK__') { return $answer }
        if ([string]::IsNullOrWhiteSpace($answer)) { return $accepted }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Choices.Count) { return $number }
        Write-AImageLauncherText "Enter a number from 1 to $($Choices.Count)." -ForegroundColor Yellow
    }
}

function Clear-AImageLauncherStep {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$Step
    )

    # Esc cancels the current value and everything that depends on it. This
    # prevents a later Enter from silently generating an earlier selection.
    switch ($Step) {
        'quality' {
            $State.Quality = ''
            $State.Mode = 'Text to image'; $State.Image = ''
            $State.Strength = 0.40; $State.StrengthText = ''
            $State.Prompt = ''; $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'mode' {
            $State.Mode = 'Text to image'; $State.Image = ''
            $State.Strength = 0.40; $State.StrengthText = ''
            $State.Prompt = ''; $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'image' {
            $State.Image = ''
            $State.Strength = 0.40; $State.StrengthText = ''
            $State.Prompt = ''; $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'strength' {
            $State.Strength = 0.40; $State.StrengthText = ''
            $State.Prompt = ''; $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'prompt' {
            $State.Prompt = ''
            $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'appearance' {
            $State.Appearance = ''; $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'composition' {
            $State.PhotoComposition = 'Auto'
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'variants' {
            $State.Variants = 1; $State.VariantsText = ''; $State.Format = ''
        }
        'format' {
            $State.Format = ''
        }
    }
}

function Get-AImagePromptHelp {
    param([string]$Mode)
    switch ($Mode) {
        'Start from image' {
            return @('Describe the finished image', 'Example: the same person and pose, wearing a red leather jacket, natural window light')
        }
        'Edit image' {
            return @('Describe the changes', 'Example: replace the background with a quiet forest; keep the person and clothing unchanged')
        }
        default {
            return @('Describe the image', 'Example: a man walking along a littered path between bushes')
        }
    }
}

function Show-AImageLauncherStep {
    param([string]$Step)

    $existing = -1
    for ($i = 0; $i -lt $script:AImageLauncherPages.Count; $i++) {
        if ($script:AImageLauncherPages[$i].Step -eq $Step) { $existing = $i; break }
    }
    if ($existing -ge 0) {
        # Rebuild from the kept transcript rather than cursor positions, which
        # become stale when long prompts scroll or the terminal is resized.
        $script:AImageLauncherPages.RemoveRange($existing, $script:AImageLauncherPages.Count - $existing)
        if (-not [Console]::IsOutputRedirected) { Clear-Host }
        Microsoft.PowerShell.Utility\Write-Host 'AImage - local image generator' -ForegroundColor Cyan
        Microsoft.PowerShell.Utility\Write-Host 'Enter accepts the displayed value. Esc goes back one step or closes at the first step.' -ForegroundColor DarkGray
        foreach ($page in $script:AImageLauncherPages) {
            foreach ($record in $page.Lines) { Microsoft.PowerShell.Utility\Write-Host @record }
        }
    }
    $script:AImageLauncherPages.Add([pscustomobject]@{Step=$Step; Lines=[Collections.Generic.List[hashtable]]::new()})
}

function Get-AImageLauncherSettings {
    param([object[]]$Available, [hashtable]$State, $Paths, [string]$StartStep = 'model', [switch]$ReviewFlow)

    $step = if ($ReviewFlow) { 'mode' } else { $StartStep }
    $reviewEdit = $false
    $feedback = ''
    if ($ReviewFlow -and -not $State.Model) { $State.Model = $Available[0].Id }
    $visionReady = Test-Path -LiteralPath (Join-Path $Paths.Models 'mmproj-Qwen3VL-8B-Instruct-F16.gguf') -PathType Leaf
    $editModels = @($Available | Where-Object Id -match '^qwen[-_]image[-_]2[._]1')
    $previousPages = $script:AImageLauncherPages
    $script:AImageLauncherPages = [Collections.Generic.List[object]]::new()
    try {
    :wizard while ($true) {
        $model = $Available | Where-Object Id -eq $State.Model | Select-Object -First 1
        $qualities = if ($model) { @(Get-AImageQualityChoices -Model $model) } else { @() }
        $steps = @('model')
        if ($qualities.Count -gt 1) { $steps += 'quality' }
        $steps += 'mode'
        if ($State.Mode -ne 'Text to image') { $steps += 'image' }
        if ($State.Mode -eq 'Start from image') { $steps += 'strength' }
        $steps += @('prompt', 'appearance')
        if ($State.Appearance -eq 'Realistic' -and $State.Mode -eq 'Text to image') { $steps += 'composition' }
        $steps += @('variants', 'format')
        if ($ReviewFlow) {
            $steps = @('mode')
            if ($State.Mode -ne 'Text to image') { $steps += 'image' }
            $steps += @('prompt', 'review')
        }
        $index = [Array]::IndexOf($steps, $step)
        if ($index -lt 0 -and -not $reviewEdit) {
            $step = if ($ReviewFlow) { 'mode' } else { 'model' }
            continue
        }
        Show-AImageLauncherStep -Step $step
        if ($feedback) {
            $feedbackColor = if ($step -eq 'review') { 'Green' } else { 'Yellow' }
            Write-AImageLauncherText $feedback -ForegroundColor $feedbackColor
            $feedback = ''
        }
        $answer = $null
        switch ($step) {
            'model' {
                $modelOptions = @(if ($ReviewFlow -and $State.Mode -eq 'Edit image') { $editModels } else { $Available })
                $current = 0
                for ($i = 0; $i -lt $modelOptions.Count; $i++) { if ($modelOptions[$i].Id -eq $State.Model) { $current = $i + 1 } }
                $labels = @($modelOptions | ForEach-Object { $_.Name + "`n     " + (Get-AImageModelHint -Model $_) })
                $answer = Read-AImageChoice -Title 'Choose a model:' -Choices $labels -Default 1 -Current $current
                if ($answer -ne '__AIMAGE_BACK__') {
                    $newModel = $modelOptions[[int]$answer - 1].Id
                    if ($newModel -ne $State.Model) {
                        $State.Quality = ''
                        if (-not $ReviewFlow) { $State.Mode = 'Text to image'; $State.Image = '' }
                    }
                    $State.Model = $newModel
                }
            }
            'quality' {
                $current = 0
                for ($i = 0; $i -lt $qualities.Count; $i++) { if ($qualities[$i].Name -eq $State.Quality) { $current = $i + 1 } }
                $labels = @($qualities | ForEach-Object { '{0} - {1}x{2}, {3} steps; {4}' -f $_.Name,$_.Width,$_.Height,$_.Steps,$_.Description })
                $answer = Read-AImageChoice -Title 'Choose detail and speed:' -Choices $labels -Default 2 -Current $current
                if ($answer -ne '__AIMAGE_BACK__') { $State.Quality = $qualities[[int]$answer - 1].Name }
            }
            'mode' {
                $canEdit = $visionReady -and ((($ReviewFlow) -and $editModels.Count) -or ($model.Id -match '^qwen[-_]image[-_]2[._]1'))
                $modes = @('Text to image', 'Start from image')
                $labels = @('Create from text', 'Start from a picture - redraw it; identity is not guaranteed')
                if ($canEdit) { $modes += 'Edit image'; $labels += 'Edit a picture - describe changes to the reference' }
                $current = [Array]::IndexOf($modes, $State.Mode) + 1
                $answer = Read-AImageChoice -Title 'Choose image mode:' -Choices $labels -Default 1 -Current $current
                if ($answer -ne '__AIMAGE_BACK__') {
                    $newMode = $modes[[int]$answer - 1]
                    if ($State.Mode -ne $newMode) { $State.Image = ''; $State.Appearance = '' }
                    $State.Mode = $newMode
                    if ($ReviewFlow -and $newMode -eq 'Edit image' -and $model.Id -notin $editModels.Id) {
                        $State.Model = $editModels[0].Id
                        $State.Quality = ''
                    }
                }
            }
            'image' {
                $answer = Read-AImageRawLine -Label 'Image path (quotes accepted)' -Initial $State.Image
                if ($answer -ne '__AIMAGE_BACK__') {
                    $path = $answer.Trim().Trim('"').Trim("'")
                    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
                        $feedback = 'Image not found. Enter the full path to an existing picture.'
                        continue wizard
                    }
                    $State.Image = (Resolve-Path -LiteralPath $path).Path
                }
            }
            'strength' {
                Write-AImageLauncherText 'Lower values preserve more of the original; higher values redraw more.' -ForegroundColor DarkGray
                if ($model.Id -eq 'lustify-v10-krea2-turbo') {
                    Write-AImageLauncherText 'Krea at 0.40 can retain the original almost unchanged. Try 0.65-0.80 for stronger changes.' -ForegroundColor DarkGray
                }
                $accepted = if ($State.StrengthText) { $State.StrengthText } else { '0.40' }
                $answer = Read-AImageRawLine -Label "Change strength 0.01-1.00 [Enter = $accepted]"
                if ($answer -ne '__AIMAGE_BACK__') {
                    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $accepted }
                    $number = 0.0
                    $parsed = [double]::TryParse($answer.Replace(',', '.'), [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture, [ref]$number)
                    if (-not $parsed -or [double]::IsNaN($number) -or $number -le 0 -or $number -gt 1) {
                        $feedback = 'Enter a value greater than 0 and no more than 1.'
                        continue wizard
                    }
                    $State.Strength = $number; $State.StrengthText = $answer
                }
            }
            'prompt' {
                $help = Get-AImagePromptHelp -Mode $State.Mode
                $examplePrompt = ([string]$help[1] -replace '^\s*Example:\s*', '').Trim()
                Write-AImageLauncherText ''
                Write-AImageLauncherText $help[1] -ForegroundColor DarkGray
                if ($State.Mode -eq 'Text to image') {
                    Write-AImageLauncherText 'Up/Down recalls prompts. Photo assistance and framing are available in review.' -ForegroundColor DarkGray
                } else {
                    Write-AImageLauncherText 'Describe the result or changes you want. Up/Down recalls prompts.' -ForegroundColor DarkGray
                }
                if ($ReviewFlow) { Write-AImageLauncherText 'Type /example to use the example.' -ForegroundColor DarkGray }
                $label = if ($ReviewFlow) { $help[0] } else { "$($help[0]) [Enter = example]" }
                $answer = Read-AImageRawLine -Label $label -Initial $State.Prompt -History (Get-AImagePromptHistory -Paths $Paths)
                if ($answer -ne '__AIMAGE_BACK__') {
                    if ($ReviewFlow -and [string]::IsNullOrWhiteSpace($answer)) {
                        $feedback = 'Enter a description or type /example.'
                        continue wizard
                    }
                    if ([string]::IsNullOrWhiteSpace($answer) -or ($ReviewFlow -and $answer.Trim() -eq '/example')) {
                        $answer = $examplePrompt
                        Write-AImageLauncherText "Using example description: $answer" -ForegroundColor DarkGray
                    }
                    $State.Prompt = $answer.Trim()
                    Write-AImagePromptHistory -Paths $Paths -Prompt $State.Prompt
                }
            }
            'appearance' {
                $default = if ($State.Mode -eq 'Text to image') { 1 } else { 2 }
                $current = if ($State.Appearance -eq 'Realistic') { 1 } elseif ($State.Appearance -eq 'Original') { 2 } elseif ($State.Appearance -eq 'Natural') { 3 } else { 0 }
                $answer = Read-AImageChoice -Title 'Choose appearance:' -Choices @(
                    'Assisted photograph - help with anatomy, placement, scale, and photographic detail',
                    'Prompt only - keep your description exactly as entered',
                    'Photo texture only - previous Natural photograph setting'
                ) -Default $default -Current $current
                if ($answer -ne '__AIMAGE_BACK__') { $State.Appearance = @('Realistic', 'Original', 'Natural')[[int]$answer - 1] }
            }
            'composition' {
                $frames = @('Auto', 'FullBody', 'Portrait', 'Wide')
                $current = [Array]::IndexOf($frames, $State.PhotoComposition) + 1
                $answer = Read-AImageChoice -Title 'Choose framing:' -Choices @(
                    'Automatic - show everyone head to toe unless the prompt specifies a crop',
                    'Full body - keep every person or the entire animal in frame',
                    'Portrait - head and shoulders, surroundings behind the subject',
                    'Wide scene - whole subject with more of the surroundings'
                ) -Default 1 -Current $current
                if ($answer -ne '__AIMAGE_BACK__') {
                    $State.PhotoComposition = $frames[[int]$answer - 1]
                    if ($State.PhotoComposition -eq 'Auto') {
                        if ([string]::IsNullOrWhiteSpace($State.Prompt)) {
                            $label = 'whole subject in context'
                        } else {
                            $assistance = Get-AImagePromptSettings -Prompt $State.Prompt -Model $model.Id -Appearance Realistic
                            $label = switch ($assistance.ResolvedPhotoComposition) {
                                'FullBody' { 'full body, with everyone head to toe' }; 'Wide' { 'wide scene' }; default { 'your described framing' }
                            }
                        }
                        Write-AImageLauncherText "Automatic framing: $label." -ForegroundColor DarkGray
                    }
                    Write-AImageLauncherText 'Assistance keeps your original description; the expanded version is recorded in history.' -ForegroundColor DarkGray
                }
            }
            'variants' {
                $accepted = if ($State.VariantsText) { $State.VariantsText } else { '1' }
                $answer = Read-AImageRawLine -Label "Different versions, 1-20 [Enter = $accepted]"
                if ($answer -ne '__AIMAGE_BACK__') {
                    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $accepted }
                    $number = 0
                    if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt 20) {
                        $feedback = 'Enter a whole number from 1 to 20.'
                        continue wizard
                    }
                    $State.Variants = $number; $State.VariantsText = $answer
                }
            }
            'format' {
                $current = if ($State.Format -eq 'png') { 1 } elseif ($State.Format -eq 'jpg') { 2 } else { 0 }
                if ($ReviewFlow) { Write-AImageLauncherText 'Choose a format to return to review. Esc keeps the current format.' -ForegroundColor DarkGray }
                $answer = Read-AImageChoice -Title 'Choose file type:' -Choices @('PNG - lossless, larger file', 'JPG - high quality, smaller file') -Default 2 -Current $current
                if ($answer -ne '__AIMAGE_BACK__') {
                    $State.Format = if ($answer -eq 1) { 'png' } else { 'jpg' }
                    if (-not $ReviewFlow) { return $State }
                }
            }
            'review' {
                $selectedQuality = $qualities | Where-Object Name -eq $State.Quality | Select-Object -First 1
                if (-not $selectedQuality) {
                    $selectedQuality = if ($qualities.Count -gt 1) { $qualities[1] } else { $qualities[0] }
                    $State.Quality = $selectedQuality.Name
                }
                if (-not $State.Appearance) { $State.Appearance = if ($State.Mode -eq 'Text to image') { 'Realistic' } else { 'Original' } }
                if (-not $State.Format) { $State.Format = 'jpg' }
                $settings = Get-AImagePromptSettings -Prompt $State.Prompt -Model $model.Id -Appearance $State.Appearance -PhotoComposition $State.PhotoComposition -ImageMode $State.Mode
                Write-AImageLauncherWrappedText -Label 'Prompt sent to model' -Text $settings.Prompt
                if ($settings.NegativePrompt) { Write-AImageLauncherWrappedText -Label 'Avoid' -Text $settings.NegativePrompt }
                $items = [ordered]@{ model = "Model: $($model.Name)" }
                if ($qualities.Count -gt 1) {
                    $items['quality'] = "Quality: $($State.Quality) ($($selectedQuality.Width)x$($selectedQuality.Height), $($selectedQuality.Steps) steps)"
                } else { Write-AImageLauncherText "Size: $($selectedQuality.Width)x$($selectedQuality.Height), $($selectedQuality.Steps) steps" }
                $appearanceName = @{ Realistic='Assisted photograph'; Original='Prompt only'; Natural='Photo texture' }[[string]$State.Appearance]
                $items['appearance'] = "Appearance: $appearanceName"
                if ($State.Appearance -eq 'Realistic' -and $State.Mode -eq 'Text to image') {
                    $framing = if ($State.PhotoComposition -eq 'Auto' -and $settings.ResolvedPhotoComposition -eq 'FullBody') {
                        'Automatic (head to toe)'
                    } else { $State.PhotoComposition }
                    $items['composition'] = "Framing: $framing"
                }
                if ($State.Mode -eq 'Start from image') { $items['strength'] = "Change strength: $($State.Strength)" }
                $items['variants'] = "Versions: $($State.Variants)"
                $items['format'] = "File type: $($State.Format.ToUpperInvariant())"
                $answer = Read-AImageChoice -Title 'Review settings:' -Choices @($items.Values) -Default 0 -InputLabel 'Enter to generate now, or type a setting number to change it'
                if ($answer -ne '__AIMAGE_BACK__') {
                    if ($answer -eq 0) { return $State }
                    $step = @($items.Keys)[[int]$answer - 1]
                    $reviewEdit = $true
                    continue wizard
                }
            }
        }
        if ($reviewEdit) {
            if ($answer -ne '__AIMAGE_BACK__') {
                $feedback = if ($step -eq 'format') { "File type set to $($State.Format.ToUpperInvariant())." } else { 'Setting applied.' }
            }
            $reviewEdit = $false
            $step = 'review'
            continue
        }
        if ($answer -eq '__AIMAGE_BACK__') {
            if ($index -eq 0) { return $null }
            Clear-AImageLauncherStep -State $State -Step $step
            $step = $steps[$index - 1]
        } else {
            if ($ReviewFlow) {
                $step = switch ($step) {
                    'mode' { if ($State.Mode -eq 'Text to image') { 'prompt' } else { 'image' } }
                    'image' { 'prompt' }
                    'prompt' { 'review' }
                }
                continue
            }
            # Model or mode changes may insert/remove the next screen.
            $model = $Available | Where-Object Id -eq $State.Model | Select-Object -First 1
            $steps = @('model')
            if (@(Get-AImageQualityChoices -Model $model).Count -gt 1) { $steps += 'quality' }
            $steps += 'mode'
            if ($State.Mode -ne 'Text to image') { $steps += 'image' }
            if ($State.Mode -eq 'Start from image') { $steps += 'strength' }
            $steps += @('prompt', 'appearance')
            if ($State.Appearance -eq 'Realistic' -and $State.Mode -eq 'Text to image') { $steps += 'composition' }
            $steps += @('variants', 'format')
            $step = $steps[[Array]::IndexOf($steps, $step) + 1]
        }
    }
    } finally { $script:AImageLauncherPages = $previousPages }
}
