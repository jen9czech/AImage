$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path $PSScriptRoot ('.runner-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$previousModelsDir = $env:AIMAGE_MODELS_DIR
$previousOutputDir = $env:AIMAGE_OUTPUT_DIR
$previousCoopmat = [Environment]::GetEnvironmentVariable('GGML_VK_DISABLE_COOPMAT', 'Process')
try {
    function Get-TestEngineArguments {
        param([string]$Name, [switch]$Raw)
        $path = Join-Path $env:AIMAGE_OUTPUT_DIR ([IO.Path]::GetFileNameWithoutExtension($Name) + '.args')
        Get-Content -LiteralPath $path -Raw:$Raw -Encoding UTF8
    }
    [Environment]::SetEnvironmentVariable('GGML_VK_DISABLE_COOPMAT', $null, 'Process')
    foreach ($directory in @('engine', 'engine-vulkan', 'models', 'profiles')) {
        New-Item -ItemType Directory -Path (Join-Path $sandbox $directory) | Out-Null
    }
    Copy-Item (Join-Path $project 'qwen21.ps1') $sandbox
    Copy-Item (Join-Path $project 'paths.ps1') $sandbox
    Copy-Item (Join-Path $project 'generation-settings.ps1') $sandbox
    $env:AIMAGE_MODELS_DIR = Join-Path $sandbox 'models'
    $env:AIMAGE_OUTPUT_DIR = Join-Path $sandbox 'output'
    foreach ($name in @('qwen-image-2.1-Q4_K_M.gguf', 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf', 'qwen_image_2.1_vae_bf16.safetensors')) {
        Set-Content -LiteralPath (Join-Path $sandbox "models\$name") -Value 'stub'
    }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
public class EngineStub {
    public static int Main(string[] args) {
        int index = Array.IndexOf(args, "-o");
        if (index < 0) return 2;
        string prompt = File.ReadAllText(args[Array.IndexOf(args, "--prompt-file") + 1]);
        if (prompt == "__missing__") return 0;
        if (prompt == "__fail__") return 7;
        var captured = new List<string>(args);
        captured.Add("-p");
        captured.Add(prompt);
        int negative = Array.IndexOf(args, "--negative-prompt-file");
        if (negative >= 0) {
            captured.Add("-n");
            captured.Add(File.ReadAllText(args[negative + 1]));
        }
        captured.Add("__coopmat=" + (Environment.GetEnvironmentVariable("GGML_VK_DISABLE_COOPMAT") ?? ""));
        string capturePath = Path.Combine(Environment.GetEnvironmentVariable("AIMAGE_OUTPUT_DIR"),
            Path.GetFileNameWithoutExtension(args[index + 1]) + ".args");
        File.WriteAllLines(capturePath, captured);
        int width = int.Parse(args[Array.IndexOf(args, "-W") + 1]);
        int height = int.Parse(args[Array.IndexOf(args, "-H") + 1]);
        if (prompt == "__wrong_dimensions__") width++;
        if (prompt == "__corrupt__") {
            File.WriteAllText(args[index + 1], "invalid picture");
            return 0;
        }
        using (var image = new Bitmap(width, height)) {
            using (var graphics = Graphics.FromImage(image)) graphics.Clear(Color.White);
            if (prompt != "__flat__") image.SetPixel(0, 0, Color.Red);
            image.Save(args[index + 1], ImageFormat.Png);
        }
        return 0;
    }
}
'@ -ReferencedAssemblies 'System.Drawing' -OutputAssembly (Join-Path $sandbox 'engine-vulkan\sd-cli.exe') -OutputType ConsoleApplication
    Copy-Item (Join-Path $sandbox 'engine-vulkan\sd-cli.exe') (Join-Path $sandbox 'engine\sd-cli.exe')
    $runner = Join-Path $sandbox 'qwen21.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner builtin 'a cute owl'
    if ($LASTEXITCODE -ne 0) { throw 'Builtin runner failed.' }
    $argsText = Get-TestEngineArguments 'builtin.png' -Raw
    if ($argsText -notmatch 'diffusion=Vulkan0,te=cpu,vae=Vulkan0') { throw 'Vulkan placement was not applied.' }
    if ($argsText -notmatch '--vae-conv-direct') { throw 'Vulkan VAE direct convolution was not enabled.' }
    if ($argsText -match '__coopmat=1') { throw 'Krea-specific matrix tuning leaked into Qwen.' }
    if ($argsText -notmatch "--threads\s+$([Environment]::ProcessorCount)") { throw 'Vulkan runner did not use all logical CPU processors.' }
    $builtinArguments = @(Get-TestEngineArguments 'builtin.png')
    if ($builtinArguments[[Array]::IndexOf($builtinArguments, '-W') + 1] -ne '1024' -or
        $builtinArguments[[Array]::IndexOf($builtinArguments, '-H') + 1] -ne '1024' -or
        $builtinArguments[[Array]::IndexOf($builtinArguments, '--steps') + 1] -ne '40') { throw 'Native Qwen defaults were not preserved.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner cpu 'a cute owl' -VaeBackend cpu
    if ($LASTEXITCODE -ne 0) { throw 'CPU VAE runner failed.' }
    $argsText = Get-TestEngineArguments 'cpu.png' -Raw
    if ($argsText -notmatch 'diffusion=Vulkan0,te=cpu,vae=cpu') { throw 'CPU VAE override was ignored.' }
    if ($argsText -match '--vae-conv-direct') { throw 'GPU VAE convolution leaked into CPU compatibility mode.' }
    $profile = @{
        id = 'custom'; name = 'Custom'; requiredFiles = @('models/qwen-image-2.1-Q4_K_M.gguf')
        defaults = @{ width = 768; height = 640; steps = 24 }
        args = @('--backend', 'diffusion={gpu},te=cpu,vae={gpu}')
    }
    $profilePath = Join-Path $sandbox 'profiles\custom.json'
    $profile | ConvertTo-Json -Depth 4 | Set-Content $profilePath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner profile 'a cute owl' -Model custom -Width 320
    if ($LASTEXITCODE -ne 0) { throw 'Profile runner failed.' }
    $arguments = @(Get-TestEngineArguments 'profile.png')
    if ($arguments[[Array]::IndexOf($arguments, '-W') + 1] -ne '320' -or
        $arguments[[Array]::IndexOf($arguments, '-H') + 1] -ne '640' -or
        $arguments[[Array]::IndexOf($arguments, '--steps') + 1] -ne '24') { throw 'Profile defaults/overrides were not respected.' }
    if ($arguments -notcontains 'diffusion=Vulkan0,te=cpu,vae=Vulkan0') { throw 'Vulkan profile placeholder was not resolved.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner cuda-profile 'a cute owl' -Model custom -EngineBackend cuda12
    if ($LASTEXITCODE -ne 0) { throw 'Explicit CUDA profile runner failed.' }
    $cudaArguments = @(Get-TestEngineArguments 'cuda-profile.png')
    if ($cudaArguments -notcontains 'diffusion=cuda0,te=cpu,vae=cuda0') { throw 'CUDA profile placeholder was not resolved.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner quality 'a cute owl' -QualityPreset Standard -Width 768 -Height 768 -Steps 8
    if ($LASTEXITCODE -ne 0) { throw 'Quality history runner failed.' }
    $inputImage = Join-Path $sandbox 'input image.jpg'
    Set-Content -LiteralPath $inputImage -Value 'stub image'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner init 'transform the image' -Model custom -InitImage ('"' + $inputImage + '"') -Strength 0.5
    if ($LASTEXITCODE -ne 0) { throw 'Initial-image runner failed.' }
    $initArguments = @(Get-TestEngineArguments 'init.png')
    if ($initArguments -notcontains '--init-img' -or $initArguments -notcontains $inputImage -or
        $initArguments[[Array]::IndexOf($initArguments, '--strength') + 1] -ne '0.5') { throw 'Quoted initial-image path or strength was not passed through.' }
    $history = @(Import-Csv -LiteralPath (Join-Path $sandbox 'output\generation-history.csv'))
    if ($history.Count -ne 6) { throw 'Generation history must contain one row per successful image.' }
    if ($history[0].prompt -ne 'a cute owl' -or $history[0].model -ne 'qwen-image-2.1-Q4_K_M.gguf' -or $history[0].outputFile -ne 'builtin.png') {
        throw 'Generation history did not preserve the prompt, model, and output filename.'
    }
    if ($history[4].qualityPreset -ne 'Standard' -or $history[4].width -ne '768' -or $history[4].height -ne '768' -or $history[4].steps -ne '8') {
        throw 'Generation history did not preserve the selected quality and settings.'
    }
    $profile.id = 'lustify-zenith-v9'
    $profile | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $sandbox 'profiles\lustify-zenith-v9.json')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner natural.jpg 'portrait by a window' -Model lustify-zenith-v9 -Appearance Natural -Seed 12345
    if ($LASTEXITCODE -ne 0) { throw 'Natural photograph run failed.' }
    $naturalArgs = @(Get-TestEngineArguments 'natural.jpg')
    if ($naturalArgs -notcontains '-n' -or $naturalArgs[[Array]::IndexOf($naturalArgs, '-p') + 1] -notmatch 'Photographic rendering') { throw 'Realism guidance was ignored.' }
    Add-Type -AssemblyName System.Drawing
    $jpeg = [Drawing.Bitmap]::new((Join-Path $env:AIMAGE_OUTPUT_DIR 'natural.jpg'))
    try {
        if ($jpeg.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Jpeg.Guid) { throw 'JPG did not contain a JPEG.' }
    } finally { $jpeg.Dispose() }
    $history = @(Import-Csv -LiteralPath (Join-Path $sandbox 'output\generation-history.csv'))
    $last = $history[-1]
    if ($last.prompt -ne 'portrait by a window' -or $last.appearance -ne 'Natural' -or $last.seed -ne '12345' -or
        $last.effectivePrompt -notmatch 'Photographic rendering' -or $last.backend -ne 'Vulkan0') { throw 'Reproducible history fields missing.' }
    $beforeFailure = $history.Count
    Set-Content -LiteralPath (Join-Path $sandbox 'models\mmproj-Qwen3VL-8B-Instruct-F16.gguf') -Value 'stub'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner reference 'change the background' -ReferenceImage $inputImage
    if ($LASTEXITCODE -ne 0) { throw 'Reference image run failed.' }
    $referenceArgs = @(Get-TestEngineArguments 'reference.png')
    if ($referenceArgs -notcontains '--llm_vision' -or $referenceArgs -notcontains '-r' -or $referenceArgs -notcontains $inputImage) { throw 'Reference vision routing incorrect.' }
    $beforeFailure++
    $profile.id = 'lustify-v10-krea2-turbo'
    $profile | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $sandbox 'profiles\lustify-v10-krea2-turbo.json')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner krea-input 'a fox' -Model lustify-v10-krea2-turbo -InitImage $inputImage -Strength 0.4
    if ($LASTEXITCODE -ne 0) { throw 'Krea source fallback failed.' }
    $kreaArgs = @(Get-TestEngineArguments 'krea-input.png')
    if ($kreaArgs -notcontains 'diffusion=Vulkan0,te=cpu,vae=cpu') { throw 'Krea Vulkan image-input fallback incorrect.' }
    if ($kreaArgs -contains '--threads') { throw 'Krea must retain the engine-managed CPU thread default.' }
    if ($kreaArgs -contains '__coopmat=1') { throw 'Krea redraw must retain stock Vulkan kernels.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner krea-gpu-input 'a fox' -Model lustify-v10-krea2-turbo -InitImage $inputImage -Strength 0.4 -VaeBackend gpu
    if ($LASTEXITCODE -ne 0) { throw 'Explicit Krea GPU VAE failed.' }
    $kreaArgs = @(Get-TestEngineArguments 'krea-gpu-input.png')
    if ($kreaArgs -notcontains 'diffusion=Vulkan0,te=cpu,vae=Vulkan0') { throw 'Explicit GPU VAE override ignored.' }
    $beforeFailure += 2
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner krea-cuda 'a fox' -Model lustify-v10-krea2-turbo -EngineBackend cuda12
    if ($LASTEXITCODE -ne 0) { throw 'Krea CUDA routing failed.' }
    $kreaCudaArgs = @(Get-TestEngineArguments 'krea-cuda.png')
    if ($kreaCudaArgs -contains '__coopmat=1' -or $kreaCudaArgs -notcontains 'diffusion=cuda0,te=cpu,vae=cuda0') { throw 'AMD tuning leaked into NVIDIA CUDA.' }
    $beforeFailure++
    $env:GGML_VK_DISABLE_COOPMAT = 'caller-setting'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner krea-environment 'a fox' -Model lustify-v10-krea2-turbo -EngineBackend vulkan
    if ($LASTEXITCODE -ne 0) { throw 'Krea caller-environment run failed.' }
    if (@(Get-TestEngineArguments 'krea-environment.png') -notcontains '__coopmat=caller-setting') { throw 'Explicit caller environment was replaced.' }
    $env:GGML_VK_DISABLE_COOPMAT = $null
    $beforeFailure++
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner assisted 'a man by bushes' -Model lustify-v10-krea2-turbo -Appearance Realistic -PhotoComposition FullBody
    if ($LASTEXITCODE -ne 0) { throw 'Assisted runner failed.' }
    $assistedArgs = @(Get-TestEngineArguments 'assisted.png')
    if ($assistedArgs -contains '__coopmat=1') { throw 'Krea text-to-image must retain stock Vulkan kernels.' }
    $assistedHistory = @(Import-Csv -LiteralPath (Join-Path $sandbox 'output\generation-history.csv'))[-1]
    if ($assistedArgs -contains '-n' -or $assistedArgs[[Array]::IndexOf($assistedArgs, '-p') + 1] -notmatch 'full-body photograph' -or
        $assistedHistory.prompt -ne 'a man by bushes' -or $assistedHistory.photoComposition -ne 'FullBody' -or $assistedHistory.resolvedPhotoComposition -ne 'FullBody' -or $assistedHistory.appearance -ne 'Realistic') { throw 'Engine conditioning and history assistance disagree.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner assisted-reference 'change the background' -Appearance Realistic -PhotoComposition FullBody -ReferenceImage $inputImage
    if ($LASTEXITCODE -ne 0) { throw 'Assisted reference runner failed.' }
    $editArgs = @(Get-TestEngineArguments 'assisted-reference.png')
    $editHistory = @(Import-Csv -LiteralPath (Join-Path $sandbox 'output\generation-history.csv'))[-1]
    if ($editHistory.photoComposition -or $editArgs[[Array]::IndexOf($editArgs, '-p') + 1] -match 'Use a full-body') { throw 'Framing leaked into reference edits.' }
    $beforeFailure += 2
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner missing '__missing__' -Model custom
    if ($LASTEXITCODE -ne 2) { throw 'Success without output was accepted.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner failed '__fail__' -Model custom
    if ($LASTEXITCODE -ne 7) { throw 'Engine failure code was not propagated.' }
    foreach ($invalidPrompt in '__flat__', '__corrupt__', '__wrong_dimensions__') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner $invalidPrompt $invalidPrompt -Model custom
        if ($LASTEXITCODE -ne 2 -or (Test-Path -LiteralPath (Join-Path $env:AIMAGE_OUTPUT_DIR "$invalidPrompt.png"))) {
            throw "Invalid output $invalidPrompt was accepted."
        }
    }
    if (@(Import-Csv -LiteralPath (Join-Path $sandbox 'output\generation-history.csv')).Count -ne $beforeFailure) { throw 'Failed runs entered successful generation history.' }
    $profile.id = 'custom'
    $profile.defaults.height = 641
    $profile | ConvertTo-Json -Depth 4 | Set-Content $profilePath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner invalid 'a cute owl' -Model custom
    if ($LASTEXITCODE -eq 0) { throw 'Invalid profile dimensions were accepted.' }
    $quoted = 'An owl beside a sign reading "Forest Trail"'
    $previousJobPrompt = $env:AIMAGE_JOB_PROMPT
    try {
        $env:AIMAGE_JOB_PROMPT = $quoted
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner quote-test -PromptFromEnvironment
        if ($LASTEXITCODE -ne 0) { throw 'Quoted prompt runner failed.' }
    } finally { $env:AIMAGE_JOB_PROMPT = $previousJobPrompt }
    $quoteArgs = @(Get-TestEngineArguments 'quote-test')
    if ($quoteArgs[[Array]::IndexOf($quoteArgs, '-p') + 1] -cne $quoted) { throw 'Native engine did not receive the exact quoted prompt.' }
    Write-Host 'Runner smoke test passed.' -ForegroundColor Green
} finally {
    $env:AIMAGE_MODELS_DIR = $previousModelsDir
    $env:AIMAGE_OUTPUT_DIR = $previousOutputDir
    [Environment]::SetEnvironmentVariable('GGML_VK_DISABLE_COOPMAT', $previousCoopmat, 'Process')
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    $testsRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $resolvedSandbox.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside tests directory.' }
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
