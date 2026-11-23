$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'qwen21.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
$function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Format-AImageElapsed' }, $true)
Invoke-Expression $function.Extent.Text
foreach ($case in @(@(0, '0m 00s'), @(59.9, '0m 59s'), @(95, '1m 35s'), @(278.454, '4m 38s'), @(3599, '59m 59s'), @(7199, '1h 59m 59s'))) {
    if ((Format-AImageElapsed $case[0]) -ne $case[1]) { throw "Elapsed time incorrect for $($case[0]) seconds." }
}
Write-Host 'Elapsed time formatting passed.'
