$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'launcher-input.ps1')
# Exercise the real editor with deterministic key events; a console is needed
# for rendering. The main test suites test navigation without a console.
$script:keys = [Collections.Queue]::new()
foreach ($item in @(
    @('End',[char]0), @('X',[char]'X'), @('UpArrow',[char]0), @('DownArrow',[char]0),
    @('LeftArrow',[char]0), @('Backspace',[char]0), @('Home',[char]0), @('Delete',[char]0),
    @('End',[char]0), @('Y',[char]'Y'), @('Enter',[char]0)
)) { $script:keys.Enqueue([pscustomobject]@{Key=$item[0]; KeyChar=$item[1]}) }
function Read-AImageConsoleKey { return $script:keys.Dequeue() }
$result = Read-AImageRawLine -Label 'Console editor test' -Initial 'abc' -History @('latest','older')
if ($result -ne 'bXY' -or $script:keys.Count) { throw "Editor returned '$result', expected 'bXY'." }
$script:keys.Enqueue([pscustomobject]@{Key='Escape'; KeyChar=[char]0})
if ((Read-AImageRawLine -Label 'Escape test') -ne '__AIMAGE_BACK__') { throw 'Escape key ignored.' }
function Get-Clipboard {
    param([switch]$Raw)
    return $script:longPrompt
}
$script:longPrompt = ('A trail with amber leaves and a sign reading "Forest Trail". ' * 22) + ([string][char]0x6F22 * 45)
$script:keys.Enqueue([ConsoleKeyInfo]::new([char]22, [ConsoleKey]::V, $false, $false, $true))
$script:keys.Enqueue([ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false))
if ((Read-AImageRawLine -Label 'Paste test') -cne $script:longPrompt) { throw 'A long paste changed the text.' }
$layout = Get-AImageEditorLayout -Label 'Describe' -Text $script:longPrompt -Cursor $script:longPrompt.Length -Width 39
if ($layout.Lines | Where-Object { (Get-AImageCellWidth $_) -gt 39 }) { throw 'Wide text overflowed a line.' }
foreach ($name in 'LeftArrow', 'Backspace', 'Enter') {
    $script:keys.Enqueue([pscustomobject]@{Key=$name; KeyChar=[char]0})
}
$emoji = [char]::ConvertFromUtf32(0x1F989)
if ((Read-AImageRawLine -Label 'Unicode editing test' -Initial ("a${emoji}b")) -cne 'ab') {
    throw 'Backspace split a Unicode character.'
}
Write-Host 'Console editing, draft restoration, history, and Esc test passed.' -ForegroundColor Green
