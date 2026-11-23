$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'launcher-input.ps1')
$script:AImageLauncherPages = [Collections.Generic.List[object]]::new()
try {
    Show-AImageLauncherStep -Step model
    Write-AImageLauncherText 'Model menu retained' -ForegroundColor Cyan
    Save-AImageLauncherInput -Lines @('Choice: 1')
    Show-AImageLauncherStep -Step quality
    if ($script:AImageLauncherPages.Count -ne 2 -or $script:AImageLauncherPages[0].Lines.Count -ne 2) {
        throw 'Forward navigation lost the previous menu or accepted input.'
    }
    Write-AImageLauncherText 'Old quality menu'
    Save-AImageLauncherInput -Lines @('Choice: 2')
    Show-AImageLauncherStep -Step mode
    Write-AImageLauncherText 'Cancelled image mode menu'
    $redrawn = @(Show-AImageLauncherStep -Step quality 6>&1) | Out-String
    if ($script:AImageLauncherPages.Count -ne 2 -or $script:AImageLauncherPages[1].Lines.Count -ne 0 -or
        $redrawn -notmatch 'Model menu retained' -or $redrawn -notmatch 'Choice: 1' -or
        $redrawn -match 'Old quality menu|Cancelled image mode menu') {
        throw 'Back navigation duplicated the target menu or retained cancelled steps.'
    }
    Write-AImageLauncherText 'Replacement quality menu'
    Show-AImageLauncherStep -Step mode
    $redrawn = @(Show-AImageLauncherStep -Step quality 6>&1) | Out-String
    if ($redrawn -match 'Replacement quality menu' -or $script:AImageLauncherPages.Count -ne 2) {
        throw 'Repeated Esc accumulated a previous copy of the question.'
    }
    Write-Host 'Launcher transcript display tests passed.' -ForegroundColor Green
} finally { $script:AImageLauncherPages = $null }
