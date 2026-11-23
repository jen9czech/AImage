param([string]$OutputPath = (Join-Path $PSScriptRoot 'dist\AImage-source.zip'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# List the release files explicitly. Runtime data and private settings can
# never enter the ZIP just because they were saved inside the project.
$sourceFiles = @(
    '.gitignore', '.github/workflows/smoke.yml', 'LICENSE', 'README.md',
    'THIRD_PARTY_NOTICES.md', 'PERFORMANCE.md', 'RELEASE_NOTES.md', 'package.ps1',
    'setup.cmd', 'setup.ps1', 'aimage.cmd', 'aimage.ps1', 'qwen21.cmd', 'qwen21.ps1',
    'queue.cmd', 'queue.ps1', 'paths.ps1', 'launcher-input.ps1',
    'generation-settings.ps1', 'test-qwen21.cmd',
    'profiles/README.md', 'profiles/flux1-schnell.json',
    'profiles/lustify-v10-krea2-turbo.json', 'profiles/lustify-zenith-v9.json',
    'tests/run-all.cmd', 'tests/run-all.ps1', 'tests/queue-smoke.ps1',
    'tests/runner-smoke.ps1', 'tests/aimage-smoke.ps1', 'tests/launcher-navigation.ps1',
    'tests/launcher-display.ps1', 'tests/console-input.ps1', 'tests/settings-history.ps1',
    'tests/elapsed-format.ps1', 'tests/verify-generated-images.ps1',
    'tests/benchmark-krea-speed.ps1', 'tests/benchmark-qwen.cmd', 'tests/benchmark-qwen.ps1'
)

$fullPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.File]::Exists($fullPath)) { throw "Package already exists. Choose another -OutputPath: $fullPath" }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath))
$partial = "$fullPath.$([Guid]::NewGuid().ToString('N')).part"
try {
    $archive = [IO.Compression.ZipFile]::Open($partial, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($relative in $sourceFiles) {
            $file = Get-Item -LiteralPath (Join-Path $PSScriptRoot $relative) -Force
            if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 512KB) {
                throw "Unexpected source file in the package: $relative"
            }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal
            )
        }
    } finally { $archive.Dispose() }
    [IO.File]::Move($partial, $fullPath)
} finally {
    if ([IO.File]::Exists($partial)) { [IO.File]::Delete($partial) }
}
Write-Host ("Created {0} ({1:N0} bytes, {2} source files)" -f $fullPath, (Get-Item -LiteralPath $fullPath).Length, $sourceFiles.Count)
