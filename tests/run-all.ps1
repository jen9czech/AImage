$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errorsFound = @()
foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File) + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors) | Out-Null
    $errorsFound += @($parseErrors)
}
if ($errorsFound.Count) { $errorsFound | ForEach-Object { Write-Error $_.Message }; exit 1 }
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'profiles') -Filter '*.json' -File) {
    $profile = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($profile.id -ne $file.BaseName -or -not $profile.args -or -not $profile.requiredFiles) { throw "Invalid profile: $($file.Name)" }
}
Write-Host 'PowerShell syntax and profile validation passed.' -ForegroundColor Green
foreach ($suite in @('queue-smoke.ps1', 'runner-smoke.ps1', 'aimage-smoke.ps1', 'launcher-navigation.ps1', 'launcher-display.ps1', 'settings-history.ps1', 'elapsed-format.ps1')) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite)
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $suite" }
}
Write-Host 'All project tests passed.' -ForegroundColor Green
