param(
    [Parameter(Position = 0)]
    [ValidateSet('add', 'list', 'run', 'edit', 'remove', 'retry', 'models', 'model', 'help')]
    [string]$Action = 'list',

    [Parameter(Position = 1)]
    [string]$Prompt,

    [string]$PromptFile,
    [string]$NegativePrompt,
    [string]$Id,
    [string]$OutputName,
    [string]$Model,
    [string]$ReferenceImage,
    [string]$InitImage,
    [double]$Strength = 0.75,
    [int]$Width = 1024,
    [int]$Height = 1024,
    [int]$Steps = 0,
    [int]$Seed = -1,
    [int]$Limit = 0
)

$ErrorActionPreference = 'Stop'
$StrengthSpecified = $PSBoundParameters.ContainsKey('Strength')
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$QueueDir = Join-Path $Root 'queue'
$QueueFile = Join-Path $QueueDir 'jobs.json'
$SettingsFile = Join-Path $QueueDir 'settings.json'
$OutputDir = Join-Path $Root 'output'
$ModelsDir = Join-Path $Root 'models'
$ProfilesDir = Join-Path $Root 'profiles'
New-Item -ItemType Directory -Force -Path $QueueDir,$OutputDir | Out-Null

# One short lock guards JSON updates; a separate lock prevents two workers.
$hash = [System.Security.Cryptography.SHA256]::Create()
try {
    $bytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))
    $key = [BitConverter]::ToString($bytes, 0, 8).Replace('-', '')
} finally { $hash.Dispose() }
$StateMutex = [Threading.Mutex]::new($false, "Local\Qwen21State_$key")
$RunMutex = [Threading.Mutex]::new($false, "Local\Qwen21Run_$key")

function Enter-Lock($Mutex, [int]$Timeout = 30000) {
    try {
        if (-not $Mutex.WaitOne($Timeout)) { throw 'Queue is busy; try again.' }
    } catch [Threading.AbandonedMutexException] {
        # The previous process died; the lock is now owned by this process.
    }
}

function Read-Jobs {
    if (-not (Test-Path $QueueFile)) { return }
    $data = Get-Content -LiteralPath $QueueFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.version -ne 1 -or $null -eq $data.jobs) { throw "Unsupported queue file: $QueueFile" }
    return $data.jobs
}

function Save-Jobs($Jobs) {
    $temp = "$QueueFile.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        @{ version = 1; jobs = @($Jobs) } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $temp -Encoding UTF8
        Move-Item -LiteralPath $temp -Destination $QueueFile -Force
    } finally {
        if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Get-DefaultModel {
    if (-not (Test-Path -LiteralPath $SettingsFile)) { return 'qwen-image-2.1-Q4_K_M.gguf' }
    $settings = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.version -ne 1 -or -not $settings.defaultModel) { throw "Unsupported model settings: $SettingsFile" }
    return $settings.defaultModel
}

function Resolve-Model([string]$Choice) {
    if (-not $Choice) { $Choice = Get-DefaultModel }
    if ($Choice -match '^(Q4_0|Q4_K_M|Q5_K_M|Q6_K|Q8_0)$') {
        $Choice = "qwen-image-2.1-$Choice.gguf"
    }
    if ($Choice -match '^qwen[-_]image[-_]2[._]1.*\.gguf$' -and [IO.Path]::GetFileName($Choice) -eq $Choice) {
        if (-not (Test-Path -LiteralPath (Join-Path $ModelsDir $Choice) -PathType Leaf)) {
            throw "Model not installed: $Choice. Run setup.ps1 -DiffusionQuantization Q5_K_M, or copy a compatible GGUF into models."
        }
        foreach ($name in @('Qwen3-VL-8B-Instruct-Q4_K_M.gguf', 'qwen_image_2.1_vae_bf16.safetensors')) {
            if (-not (Test-Path -LiteralPath (Join-Path $ModelsDir $name) -PathType Leaf)) { throw "Required companion file missing: $name" }
        }
        return $Choice
    }
    if ($Choice -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw 'Choose an installed model filename or a profile ID.' }
    $profilePath = Join-Path $ProfilesDir "$Choice.json"
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw "Profile not found: $Choice. See profiles\README.md." }
    $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($profile.id -ne $Choice -or -not $profile.args -or -not $profile.requiredFiles) { throw "Invalid profile: $profilePath" }
    foreach ($file in $profile.requiredFiles) {
        $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $Root $file }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Profile '$Choice' needs: $path" }
    }
    return $Choice
}

function Check-ImageMode([string]$Choice) {
    if ($ReferenceImage -and $InitImage) { throw 'Use either -ReferenceImage or -InitImage for one job.' }
    if ($StrengthSpecified -and -not $InitImage) { throw '-Strength applies only with -InitImage.' }
    if ($Strength -le 0 -or $Strength -gt 1) { throw 'Strength must be greater than 0 and at most 1.' }
    if (-not $ReferenceImage) { return }
    if ($Choice -match '\.gguf$') {
        $vision = Join-Path $ModelsDir 'mmproj-Qwen3VL-8B-Instruct-F16.gguf'
        if (-not (Test-Path -LiteralPath $vision -PathType Leaf)) {
            throw 'Vision projector missing. Run setup.ps1 -IncludeVision to enable Qwen image editing.'
        }
    } else {
        $profile = Get-Content -LiteralPath (Join-Path $ProfilesDir "$Choice.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $profile.supportsReferenceImage) { throw "Profile '$Choice' does not support reference images." }
    }
}

function Stage-Image([string]$Source, [string]$JobId, [string]$Kind) {
    if (-not $Source) { return $null }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Input image not found: $Source" }
    $extension = [IO.Path]::GetExtension($Source).ToLowerInvariant()
    if ($extension -notin @('.png', '.jpg', '.jpeg', '.webp')) { throw 'Input image must be PNG, JPEG, or WebP.' }
    $inputDir = Join-Path $QueueDir 'inputs'
    New-Item -ItemType Directory -Force -Path $inputDir | Out-Null
    $destination = Join-Path $inputDir "$JobId-$Kind$extension"
    Copy-Item -LiteralPath $Source -Destination $destination
    return $destination
}

function Remove-StagedImage([string]$Path, [string]$JobId, [string]$Kind) {
    if (-not $Path) { return }
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $expected = Join-Path (Join-Path $QueueDir 'inputs') "$JobId-$Kind$extension"
    if ([IO.Path]::GetFullPath($Path) -eq [IO.Path]::GetFullPath($expected) -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Find-Job($Jobs, [string]$JobId) {
    if ([string]::IsNullOrWhiteSpace($JobId)) { throw 'Specify -Id.' }
    $matches = @($Jobs | Where-Object { $_.id -eq $JobId -or $_.id.StartsWith($JobId) })
    if ($matches.Count -ne 1) { throw "Expected one job matching '$JobId'; found $($matches.Count)." }
    return $matches[0]
}

function Check-Settings {
    if ($Width -lt 32 -or $Width % 32 -ne 0 -or $Height -lt 32 -or $Height % 32 -ne 0) {
        throw 'Width and height must be positive multiples of 32.'
    }
    if ($Steps -lt 0) { throw 'Steps must be at least 1 when specified.' }
    if ($Limit -lt 0) { throw 'Limit cannot be negative.' }
}

try {
    switch ($Action) {
        'help' {
            Write-Host 'queue.cmd add "prompt" [-Model ID] [-NegativePrompt "avoid"] [-Width 1024] [-Height 1024] [-Steps 40] [-Seed -1]'
            Write-Host 'queue.cmd add "edit instruction" -ReferenceImage photo.png'
            Write-Host 'queue.cmd add "variation" -InitImage photo.png -Strength 0.5'
            Write-Host 'queue.cmd add -PromptFile prompts.txt    (one prompt per line)'
            Write-Host 'queue.cmd list | run [-Limit 1] | models'
            Write-Host 'queue.cmd model -Model ID              (default for new jobs)'
            Write-Host 'queue.cmd edit -Id ID -Prompt "new prompt" [-NegativePrompt "avoid"] [-Model ID]'
            Write-Host 'queue.cmd retry -Id ID | remove -Id ID'
        }
        'add' {
            Check-Settings
            if ($ReferenceImage -and $InitImage) { throw 'Use either -ReferenceImage or -InitImage.' }
            $prompts = [Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $prompts.Add($Prompt.Trim()) }
            if ($PromptFile) {
                if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) { throw "Prompt file not found: $PromptFile" }
                foreach ($line in (Get-Content -LiteralPath $PromptFile -Encoding UTF8)) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) { $prompts.Add($line.Trim()) }
                }
            }
            if ($prompts.Count -eq 0) { throw 'Provide a prompt or a UTF-8 prompt file with one prompt per line.' }
            if ($OutputName -and $prompts.Count -ne 1) { throw '-OutputName requires a single prompt.' }
            if ($OutputName) {
                if ([IO.Path]::GetFileName($OutputName) -ne $OutputName -or $OutputName -match '[\\/]') {
                    throw '-OutputName must be a file name inside output, without a path.'
                }
                if (-not [IO.Path]::GetExtension($OutputName)) { $OutputName += '.png' }
                if ([IO.Path]::GetExtension($OutputName) -ne '.png') { throw '-OutputName must end in .png.' }
            }
            Enter-Lock $StateMutex
            try {
                $jobs = @(Read-Jobs)
                $selectedModel = Resolve-Model $Model
                Check-ImageMode $selectedModel
                $selectedSteps = $Steps
                if ($selectedSteps -eq 0) {
                    $selectedSteps = 40
                    if ($selectedModel -match '^[a-zA-Z0-9][a-zA-Z0-9_-]*$' -and $selectedModel -notmatch '\.gguf$') {
                        $profile = Get-Content -LiteralPath (Join-Path $ProfilesDir "$selectedModel.json") -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($profile.defaults.steps -gt 0) { $selectedSteps = [int]$profile.defaults.steps }
                    }
                }
                foreach ($text in $prompts) {
                    $newId = [Guid]::NewGuid().ToString('N').Substring(0, 12)
                    $name = if ($OutputName) { $OutputName } else { "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$newId.png" }
                    if (Test-Path -LiteralPath (Join-Path $OutputDir $name)) { throw "Output already exists: $name" }
                    if (@($jobs | Where-Object { $_.output -eq $name }).Count) { throw "Output already reserved: $name" }
                    $stagedReference = Stage-Image $ReferenceImage $newId 'reference'
                    $stagedInit = Stage-Image $InitImage $newId 'init'
                    $jobs += [pscustomobject]@{
                        id = $newId; status = 'queued'; prompt = $text; negativePrompt = $NegativePrompt; output = $name
                        width = $Width; height = $Height; steps = $selectedSteps; seed = $Seed; model = $selectedModel
                        referenceImage = $stagedReference; initImage = $stagedInit; strength = $Strength
                        createdAt = (Get-Date).ToUniversalTime().ToString('o'); error = $null
                    }
                    Write-Host "Queued $newId -> output\$name"
                }
                Save-Jobs $jobs
            } finally { $StateMutex.ReleaseMutex() }
        }
        'list' {
            Enter-Lock $StateMutex
            try { $jobs = @(Read-Jobs) } finally { $StateMutex.ReleaseMutex() }
            if ($jobs.Count -eq 0) { Write-Host 'Queue is empty. Run queue.cmd help for commands.'; break }
            foreach ($job in $jobs) {
                Write-Host "[$($job.status)] $($job.id) | $($job.width)x$($job.height), $($job.steps) steps, seed $($job.seed) | $($job.prompt)"
                $jobModel = if ($job.model) { $job.model } else { 'qwen-image-2.1-Q4_K_M.gguf' }
                Write-Host "    $jobModel -> output\$($job.output)"
                if ($job.negativePrompt) { Write-Host "    avoid: $($job.negativePrompt)" }
                if ($job.referenceImage) { Write-Host "    reference: $($job.referenceImage)" }
                if ($job.initImage) { Write-Host "    initial image: $($job.initImage) (strength $($job.strength))" }
                if ($job.error) { Write-Host "    Error: $($job.error)" }
            }
        }
        'models' {
            Enter-Lock $StateMutex
            try { $defaultModel = Get-DefaultModel } finally { $StateMutex.ReleaseMutex() }
            $installed = @(Get-ChildItem -LiteralPath $ModelsDir -Filter '*.gguf' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^qwen[-_]image[-_]2[._]1.*\.gguf$' } | Sort-Object Name)
            if (-not $installed.Count) { Write-Host 'No Qwen Image 2.1 diffusion GGUF installed. Run setup.ps1.' }
            foreach ($file in $installed) {
                $mark = if ($file.Name -eq $defaultModel) { '*' } else { ' ' }
                Write-Host ("$mark {0} ({1:N2} GiB)" -f $file.Name, ($file.Length / 1GB))
            }
            foreach ($file in @(Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $profile = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($profile.id -ne $file.BaseName) { continue }
                $missing = @($profile.requiredFiles | Where-Object {
                    $path = if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $Root $_ }
                    -not (Test-Path -LiteralPath $path -PathType Leaf)
                })
                $mark = if ($profile.id -eq $defaultModel) { '*' } else { ' ' }
                $availability = if ($missing.Count) { "missing $($missing.Count) file(s)" } else { 'ready' }
                Write-Host "$mark $($profile.id) [$availability] - $($profile.name)"
            }
            Write-Host '* default for new jobs'
        }
        'model' {
            if (-not $Model) { throw 'Specify -Model with a file name or quantization, such as Q5_K_M.' }
            Enter-Lock $StateMutex
            try {
                $selectedModel = Resolve-Model $Model
                @{ version = 1; defaultModel = $selectedModel } | ConvertTo-Json |
                    Set-Content -LiteralPath $SettingsFile -Encoding UTF8
                Write-Host "Default model: $selectedModel"
            } finally { $StateMutex.ReleaseMutex() }
        }
        'edit' {
            if ([string]::IsNullOrWhiteSpace($Prompt) -and -not $Model -and -not $PSBoundParameters.ContainsKey('NegativePrompt')) { throw 'Specify a replacement -Prompt, -NegativePrompt, or -Model.' }
            Enter-Lock $StateMutex
            try {
                $jobs = @(Read-Jobs); $job = Find-Job $jobs $Id
                if ($job.status -ne 'queued') { throw 'Only queued jobs can be edited.' }
                if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $job.prompt = $Prompt.Trim() }
                if ($PSBoundParameters.ContainsKey('NegativePrompt')) {
                    if ($job.PSObject.Properties['negativePrompt']) { $job.negativePrompt = $NegativePrompt }
                    else { $job | Add-Member -NotePropertyName negativePrompt -NotePropertyValue $NegativePrompt }
                }
                if ($Model) {
                    $selectedModel = Resolve-Model $Model
                    if ($job.PSObject.Properties['model']) { $job.model = $selectedModel }
                    else { $job | Add-Member -NotePropertyName model -NotePropertyValue $selectedModel }
                }
                Save-Jobs $jobs
                Write-Host "Updated $($job.id)"
            } finally { $StateMutex.ReleaseMutex() }
        }
        'remove' {
            Enter-Lock $StateMutex
            try {
                $jobs = @(Read-Jobs); $job = Find-Job $jobs $Id
                if ($job.status -eq 'running') { throw 'Cannot remove a running job.' }
                $jobs = @($jobs | Where-Object { $_.id -ne $job.id })
                Save-Jobs $jobs
                Remove-StagedImage $job.referenceImage $job.id 'reference'
                Remove-StagedImage $job.initImage $job.id 'init'
                Write-Host "Removed $($job.id); any generated image remains in output."
            } finally { $StateMutex.ReleaseMutex() }
        }
        'retry' {
            Enter-Lock $StateMutex
            try {
                $jobs = @(Read-Jobs); $job = Find-Job $jobs $Id
                if ($job.status -ne 'failed') { throw 'Only failed jobs can be retried.' }
                $job.status = 'queued'; $job.error = $null
                Save-Jobs $jobs
                Write-Host "Requeued $($job.id)"
            } finally { $StateMutex.ReleaseMutex() }
        }
        'run' {
            Enter-Lock $RunMutex 0
            try {
                Enter-Lock $StateMutex
                try {
                    $jobs = @(Read-Jobs)
                    foreach ($old in $jobs) {
                        if ($old.status -eq 'running') {
                            $old.status = 'failed'; $old.error = 'Previous worker stopped before completion. Retry to run again.'
                        }
                    }
                    Save-Jobs $jobs
                } finally { $StateMutex.ReleaseMutex() }
                $completed = 0; $failures = 0
                while ($Limit -eq 0 -or $completed -lt $Limit) {
                    Enter-Lock $StateMutex
                    try {
                        $jobs = @(Read-Jobs)
                        $job = $jobs | Where-Object { $_.status -eq 'queued' } | Select-Object -First 1
                        if ($job) { $job.status = 'running'; Save-Jobs $jobs }
                    } finally { $StateMutex.ReleaseMutex() }
                    if (-not $job) { break }
                    Write-Host "Running $($job.id): $($job.prompt)" -ForegroundColor Cyan
                    $resultError = $null
                    $outputPath = Join-Path $OutputDir $job.output
                    try {
                        if (Test-Path -LiteralPath $outputPath) { throw "Output already exists: $outputPath" }
                        $runnerArgs = @('-OutputName', $job.output, '-Prompt', $job.prompt, '-Width', $job.width,
                            '-Height', $job.height, '-Steps', $job.steps, '-Seed', $job.seed,
                            '-Model', $(if ($job.model) { $job.model } else { 'qwen-image-2.1-Q4_K_M.gguf' }))
                        if ($job.negativePrompt) { $runnerArgs += @('-NegativePrompt', $job.negativePrompt) }
                        if ($job.referenceImage) { $runnerArgs += @('-ReferenceImage', $job.referenceImage) }
                        if ($job.initImage) {
                            $runnerArgs += @('-InitImage', $job.initImage, '-Strength',
                                ([double]$job.strength).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture))
                        }
                        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'qwen21.ps1') @runnerArgs
                        if ($LASTEXITCODE -ne 0) { throw "Generator exited with code $LASTEXITCODE" }
                        if (-not (Test-Path -LiteralPath $outputPath)) { throw 'Generator exited successfully without creating the image.' }
                    } catch { $resultError = $_.Exception.Message }
                    Enter-Lock $StateMutex
                    try {
                        $jobs = @(Read-Jobs); $current = Find-Job $jobs $job.id
                        if ($resultError) {
                            $current.status = 'failed'; $current.error = $resultError; $failures++
                            Write-Warning "$($job.id) failed: $resultError"
                        } else {
                            $current.status = 'done'; $current.error = $null
                            Write-Host "Done: $outputPath" -ForegroundColor Green
                        }
                        Save-Jobs $jobs
                    } finally { $StateMutex.ReleaseMutex() }
                    $completed++
                }
                if ($completed -eq 0) { Write-Host 'No queued jobs.' }
                if ($failures) { exit 1 }
            } finally { $RunMutex.ReleaseMutex() }
        }
    }
} finally {
    $StateMutex.Dispose()
    $RunMutex.Dispose()
}
