param(
    [Parameter(Mandatory = $true)]
    [string]$Directory,

    [ValidateRange(1, 10000)]
    [int]$ExpectedCount
)

# Run against an isolated generation test directory containing photographic
# prompts. A uniform image in this test is a failure, even if the engine
# exited successfully and the output appears in generation-history.csv.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Get-Item -LiteralPath $Directory
if (-not $root.PSIsContainer) { throw 'Provide the directory containing your test outputs.' }
$historyFiles = @(Get-ChildItem -LiteralPath $root.FullName -Recurse -File -Filter 'generation-history.csv')
if (-not $historyFiles.Count) { throw "No generation history was found in $($root.FullName)." }

$results = foreach ($history in $historyFiles) {
    foreach ($row in Import-Csv -LiteralPath $history.FullName) {
        $imagePath = Join-Path $history.DirectoryName ([IO.Path]::GetFileName($row.outputFile))
        $bitmap = $null
        $problem = ''
        $dimensions = ''
        try {
            $bitmap = [Drawing.Bitmap]::new($imagePath)
            $dimensions = '{0}x{1}' -f $bitmap.Width, $bitmap.Height
            $ext = [IO.Path]::GetExtension($imagePath).ToLowerInvariant()
            $format = switch ($ext) {
                '.jpg' { [Drawing.Imaging.ImageFormat]::Jpeg }
                '.jpeg' { [Drawing.Imaging.ImageFormat]::Jpeg }
                '.png' { [Drawing.Imaging.ImageFormat]::Png }
            }
            if (-not $format -or $bitmap.RawFormat.Guid -ne $format.Guid) {
                $problem = 'File contents do not match the selected format.'
            } elseif ($bitmap.Width -ne [int]$row.width -or $bitmap.Height -ne [int]$row.height) {
                $problem = 'Decoded dimensions differ from generation history.'
            } else {
                $firstPixel = $bitmap.GetPixel(0, 0).ToArgb()
                $uniform = $true
                for ($y = 0; $y -lt $bitmap.Height -and $uniform; $y++) {
                    for ($x = 0; $x -lt $bitmap.Width; $x++) {
                        if ($bitmap.GetPixel($x, $y).ToArgb() -ne $firstPixel) {
                            $uniform = $false
                            break
                        }
                    }
                }
                if ($uniform) { $problem = 'All pixels are the same color.' }
            }
        } catch {
            $problem = 'Cannot open the output as an image.'
        } finally {
            if ($bitmap) { $bitmap.Dispose() }
        }
        [pscustomobject]@{
            File = $imagePath
            Quality = $row.qualityPreset
            Appearance = $row.appearance
            Strength = $row.strength
            Dimensions = $dimensions
            Seconds = $row.elapsedSeconds
            Result = if ($problem) { $problem } else { 'PASS' }
        }
    }
}
$results | Format-List
if (-not $results) { throw 'Generation history contains no test results.' }
if ($PSBoundParameters.ContainsKey('ExpectedCount') -and @($results).Count -ne $ExpectedCount) {
    throw "Expected $ExpectedCount recorded images. Found $(@($results).Count)."
}
if ($results | Where-Object Result -ne 'PASS') { exit 1 }
