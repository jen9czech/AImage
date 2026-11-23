# AImage

A Windows command line image generator using `stable-diffusion.cpp`. Jobs live in a JSON queue so prompts can be added in batches, edited, retried, and processed one at a time. It supports Qwen Image 2.1 and other model families through profiles. The queue format is intended to support a small Windows UI later.

Thank you to **pplloosskkii** for creating the original AImage and sharing the work this version builds on. Thanks also to the stable-diffusion.cpp contributors for the engine that powers local generation. [Original AImage](https://github.com/pplloosskkii/AImage) · [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)

## Quick start

```powershell
.\setup.cmd
.\aimage.cmd
```

`aimage.cmd` opens the task menu. Choose create from text, redraw a source picture, or edit a reference when the required model is ready. Then enter the prompt and review the settings. The review shows the prompt sent to the model and lets you change model, quality, appearance, framing, redraw strength, versions, and file type when applicable. On **Review settings**, press Enter to generate or type a setting number to edit it. Selecting a setting returns you to review with the new value shown. Lustify v10 Krea 2 Turbo, Standard quality, and JPG are the defaults. For Krea, Preview, Standard, and Quality use 512, 768, and 1024 pixels with eight steps. For Zenith SDXL, Standard uses 1024 pixels and 20 steps. Quality uses the same resolution with 30 steps. Qwen uses its native 1024 pixels and 40 steps.

Enter accepts the displayed value. Type `/example` to use the example prompt. Long prompts wrap by console display width. Up and Down recall accepted descriptions. Left and Right, Home and End, Backspace, and Delete edit text. Esc goes back one step. Esc from a setting opened in review returns to review. Esc at the task menu closes AImage. After generation, Enter starts another setup and `C` or Esc closes.

The runner shows the output path and elapsed time. It renders a temporary PNG and checks that it decodes, matches the requested dimensions, and contains more than one color. If JPG is selected, AImage encodes the validated PNG as JPEG. Only a validated image is published and recorded in `generation-history.csv`, which includes the original and effective prompts, model, dimensions, settings, seed, backend, source, and elapsed time. Temporary render files are cleaned up after the job.

### Photographic realism

Assisted photograph is the default appearance for text-to-image. The framing choices are Automatic, Full body, Portrait, and Wide scene. By default, Automatic asks for people to be shown head to toe. It uses English keywords to recognize people and groups and honors specified crops such as a close-up or head-and-shoulders shot. For a group, assistance asks for every person to fit in the frame and for natural differences in posture, gaze, and spacing. The specified headcount, appearance, placement, and activity take precedence. Choose framing explicitly for unusual scenes or descriptions in other languages.

Prompt only preserves your description exactly and remains the default for image-to-image/editing. Photo texture only retains the previous Natural setting. Assistance in source-image modes preserves source framing except for changes you request; text-to-image framing choices do not apply there. Both the original and expanded descriptions are recorded in history, together with `appearance` and `photoComposition`, so arrow-key history still recalls what you typed. No extra model, download, or network service is involved. Longer conditioning can increase generation time even though resolution and sampling steps stay unchanged. This guidance reduces ambiguity but cannot guarantee correct anatomy or placement.

For a person without wardrobe details, Assisted mode assumes ordinary casual clothing. Explicit clothing details are kept, and source-image modes do not acquire a new wardrobe. Human litter scenes with discarded plastic bottles also receive a small-object scale cue unless unusually large objects are described. These are simple local English templates, not an LLM interpreting the scene. The launcher displays Automatic's framing decision; history records both the selected `photoComposition` and the resulting `resolvedPhotoComposition` alongside the complete effective prompt.

Zenith receives negative conditioning against rendered appearance and, in Assisted mode, disconnected anatomy. Krea Turbo keeps Euler, CFG 1, and eight steps; it receives positive guidance without the SDXL negative prompt. Direct command-line calls retain Original appearance unless specified. Use `-Appearance Realistic -PhotoComposition FullBody` to enable assistance outside the menu.

Describe the actual scene in natural language: subject, clothes/materials, surroundings, framing, and light. For example: `a photograph of a 35-year-old woman in a blue wool sweater sitting by a cafe window, head and shoulders, overcast daylight`. For image-to-image describe the finished picture; it redraws the source rather than guaranteeing identity. Its default change strength is now 0.40 to retain more of the original. Reference editing instead takes an instruction describing the change and requires Qwen plus its vision projector.

In the latest Krea portrait test, 0.40 preserved the pose and most of the blue sweater. At 0.75, the sweater turned red and the pose changed. Krea redraws use the engine's default Vulkan kernels and process the VAE on CPU. Diffusion stays on the GPU. Advanced runner option `-VaeBackend gpu` overrides VAE placement. See [measured results and limitations](PERFORMANCE.md).

Every launcher run now receives a fresh random seed, including single images. For repeatable comparisons, pass `-Seed 12345`; multiple versions then use consecutive seeds. `qwen21.cmd` retains its direct-call default seed 42 and Original appearance for compatibility. JPG uses quality 95; select PNG for lossless storage. Example:

```powershell
.\aimage.cmd -Model lustify-zenith-v9 -QualityPreset Quality -Appearance Natural -Seed 12345 -Prompt "a red fox in a mossy forest, soft morning light" -NoPause
```

For command-line prompts containing literal quotation marks or long text, put the description in a UTF-8 file and pass `-PromptFile .\prompt.txt` in place of `-Prompt`.

The first setup downloads several gigabytes, so it can take a while. Advanced queue commands remain available for batches, editing, retries, image inputs, and custom generation settings. `queue.cmd models` lists installed models and `queue.cmd model -Model ID` selects the default shown first by the interactive launcher.

To list ready models without starting the menu:

```powershell
.\aimage.cmd -ListOnly
```

## Storage locations

Model weights are stored in `C:\AI\Models\Image`. Generated images are stored under the current Windows user's known Pictures folder in `AI\AImage`, normally `C:\Users\<user>\Pictures\AI\AImage`. Setup and generation create these folders when needed. The Pictures known folder is detected through Windows, so redirected or differently named user profiles work without editing the scripts.

Advanced users can override either location for one process or through persistent environment variables named `AIMAGE_MODELS_DIR` and `AIMAGE_OUTPUT_DIR`. Engine files, resumable downloads, profiles, and queue history remain in the application folder.

## Requirements

- Windows 10/11 x64, and either an NVIDIA GPU with a CUDA-capable driver or a Vulkan-capable GPU with a current graphics driver
- Free disk space for the chosen model, engine, and images. Default Qwen needs about 10.3 GB for weights. Zenith V9 uses about 6.94 GB for weights.
- Enough system RAM for the Qwen3-VL text encoder; the supplied backend places it on the CPU

## Install or update

Extract the source ZIP or clone the repository. Run setup once from that folder:

```powershell
.\setup.cmd
```

Setup downloads the official Windows engine and one model family. It selects CUDA 12 when it finds the NVIDIA driver and Vulkan otherwise. Choose the model you want to install:

| Model | Install command | Model source |
| --- | --- | --- |
| Qwen Image 2.1 | `.\setup.cmd` | [Qwen Image 2.1 base weights](https://huggingface.co/abenzerps/Qwen-Image-2.1-Turbo-Quantized/tree/base) |
| Lustify v10 Krea 2 Turbo | `.\setup.cmd -ModelFamily lustify-v10-krea2-turbo` | [Krea 2 Turbo checkpoint](https://huggingface.co/kkkkk26/lustifyNSFWCheckpoint_v10Krea2Turbo) |
| Lustify Zenith V9 | `.\setup.cmd -ModelFamily lustify-zenith-v9` | [Zenith V9 checkpoint](https://huggingface.co/torestinbar/krea2-resources/blob/main/checkpoints/civitai-3045803-1a3abf0bf481-lustifyNSFWCheckpoint_zenithV9.safetensors) |
| FLUX.1 Schnell | `.\setup.cmd -ModelFamily flux1-schnell` | [FLUX.1 Schnell weights](https://huggingface.co/leejet/FLUX.1-schnell-gguf/tree/main) |

Setup fetches the companion files needed by the chosen model. Use `.\setup.cmd -IncludeVision` to add Qwen's optional reference editing files. Run `.\aimage.cmd -ListOnly` to see which models are ready.

To use files you already have or download them manually, run `.\setup.cmd -EngineOnly` and put the weights in the configured model folder. Save the Zenith mirror file as `lustifyNSFWCheckpoint_zenithV9.safetensors`. If you have the original Krea checkpoint instead of the Q8 file, put it in the model folder and run the Krea setup command above to convert it. Setup reuses compatible files with the expected names.

Use `-EngineBackend vulkan` or `-EngineBackend cuda12` to select a backend explicitly. Vulkan installs to `engine-vulkan\` and CUDA to `engine\`. Model files are shared between engines. The files below are for the default Qwen install.

Exit code `-1073741515` (`0xC0000135`) means a required DLL could not be loaded. If the CUDA engine requires `nvcuda.dll` on an AMD-only PC, use the Vulkan engine above.

| Role | File | Source |
| --- | --- | --- |
| Diffusion | `qwen-image-2.1-Q4_K_M.gguf` | [abenzerps/Qwen-Image-2.1-Turbo-Quantized, base branch](https://huggingface.co/abenzerps/Qwen-Image-2.1-Turbo-Quantized/tree/base) |
| Text encoder | `Qwen3-VL-8B-Instruct-Q4_K_M.gguf` | [unsloth/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF) |
| VAE | `qwen_image_2.1_vae_bf16.safetensors` | [abenzerps/Qwen-Image-2.1-Turbo-Quantized, base VAE](https://huggingface.co/abenzerps/Qwen-Image-2.1-Turbo-Quantized/tree/base/vae) |

Setup reuses working engines and installed weights. Use `-UpdateEngine` to check for an engine update. Partial downloads can resume. Newly downloaded engine ZIPs are removed after successful installation unless you pass `-KeepDownloads`.

## Package for GitHub

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package.ps1` to create `dist\AImage-source.zip`. Extract it and upload its contents, including `.gitignore` and `.github`. The archive contains the scripts, stock profiles, tests, and documentation. Dependencies download on the user's machine when they run `setup.cmd`.

To install a different Qwen Image 2.1 diffusion quantization, run for example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -DiffusionQuantization Q5_K_M
```

Supported choices are `Q4_0`, `Q4_K_M`, `Q5_K_M`, `Q6_K`, and `Q8_0`. The text encoder and VAE stay the same. Higher quantizations need more VRAM; the default Q4_K_M is a practical starting point for an 8 GB GPU.

## Queue prompts

Use `queue.cmd` from Command Prompt or PowerShell. `queue.ps1` accepts the same named options.

```cmd
queue.cmd add "A detailed photograph of a sheep in a meadow"
queue.cmd add "A watercolor lighthouse at sunrise" -Width 768 -Height 1024 -Steps 30 -Seed 42
queue.cmd add -PromptFile prompts.txt
queue.cmd list
queue.cmd run
```

Choose the diffusion model without changing scripts:

```cmd
queue.cmd models
queue.cmd model -Model Q5_K_M
queue.cmd add "A forest at dusk" -Model Q4_K_M
```

`models` lists installed compatible GGUFs; `model` changes the default for future jobs. A job can override that default with `-Model`, or change it while queued using `queue.cmd edit -Id ab12 -Model Q5_K_M`. Existing jobs keep the model they were created with. You can also copy a compatible Qwen Image 2.1 GGUF into `C:\AI\Models\Image` and select its filename.

Other image model families use a small JSON profile in [`profiles\`](profiles/README.md). A profile lists its required files and the `sd-cli` options for that family. Once its files are present, `queue.cmd models` shows it as ready and you can select its ID with `queue.cmd model -Model ID`. The queue and batch workflow stay the same.

The included `flux1-schnell` profile can be installed with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ModelFamily flux1-schnell
```

This downloads the [FLUX.1 Schnell Q3_K GGUF](https://huggingface.co/leejet/FLUX.1-schnell-gguf/tree/main), [VAE](https://huggingface.co/unsloth/FLUX.1-schnell/blob/main/ae.safetensors), and [CLIP/T5 encoders](https://huggingface.co/comfyanonymous/flux_text_encoders/tree/main), then makes it the default for new jobs. It needs about 16 GB of additional disk space and substantial system RAM for the FP16 T5 encoder. Its profile defaults to four steps. The engine settings follow the [upstream FLUX guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux.md). The existing Qwen files and jobs stay available.

The Lustify v10 Krea 2 Turbo profile can be installed with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ModelFamily lustify-v10-krea2-turbo
```

It uses `lustifyNSFWCheckpoint_v10Krea2.safetensors` as the source diffusion model, converts it to `lustifyNSFWCheckpoint_v10Krea2-Q8_0.gguf`, and downloads the Qwen3-VL 4B text encoder and Wan 2.1 VAE required by Krea 2. Select `lustify-v10-krea2-turbo` in `aimage.cmd`; its profile uses the Q8 file at 1024x1024, 8 Euler steps, and CFG 1. These settings follow the [upstream Krea 2 guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/krea2.md).

If the Q8 file already exists, setup skips the original checkpoint and conversion. A fresh conversion needs room for both files while it runs. After conversion, setup removes a source checkpoint downloaded during that run unless `-KeepDownloads` is set. A source checkpoint already on disk is kept.

If the separate TurboTransformer repository is downloaded as a folder, keeping its shards, index, and `config.json` together is correct. The current engine can read its shard index, but it cannot generate from the repository's original Diffusers tensor names. Use the compatible single-file `lustify-v10-krea2-turbo` profile in AImage.

For `-PromptFile`, save one prompt per line as UTF-8; blank lines are ignored. `run` processes queued jobs in order and continues after a failed job. Add `-Limit 1` to process only the next job. Each job receives a unique PNG filename containing the model and a short form of its prompt, for example `20260925-231500-lustify-zenith-v9-cute-owl-mossy-branch-a1b2c3d4.png`, in the configured Pictures output folder. Built-in Qwen retains its native 1024×1024 / 40-step settings; model profiles supply their own defaults. The default queue seed is random (`-1`). Dimensions must be multiples of 32.

Jobs have short IDs shown by `list`. A unique ID prefix is enough for these commands:

```cmd
queue.cmd edit -Id ab12 -Prompt "A revised prompt"
queue.cmd remove -Id ab12
queue.cmd retry -Id cd34
```

`edit` works on queued jobs, `retry` on failed jobs, and `remove` does not delete an image. Queue history is stored in `queue\jobs.json`. A crashed worker leaves its current job as `running`; the next `run` marks it failed, and `retry` can put it back in the queue. You can add and edit other queued jobs while a worker is generating.

## Start from an image or edit one

Qwen Image 2.1 edits an image by reading it as a reference and following an instruction. First install its optional vision projector (about 1.16 GB):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -IncludeVision
```

Then queue an edit. The input is copied into `queue\inputs\` when you add the job, so the queued work keeps its own copy:

```cmd
queue.cmd add "Replace the blue sky with a sunset; keep the rest of the photo" -ReferenceImage "C:\Pictures\photo.png"
queue.cmd run
```

The installed Qwen model also accepts `-InitImage` for a strength based variation. `-Strength` is greater than 0 and at most 1; lower values keep more of the starting image. This is a different engine mode from Qwen's reference edit, and the strength setting has no effect on `-ReferenceImage`:

```cmd
queue.cmd add "A watercolor version of this scene" -InitImage "C:\Pictures\photo.png" -Strength 0.5
```

Use PNG, JPEG, or WebP inputs. `-ReferenceImage` and `-InitImage` are mutually exclusive for one job. A model profile must explicitly support reference images; the included FLUX.1 Schnell profile is intended for initial image variations instead. [The upstream Qwen guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/qwen_image_2.1.md) shows the reference edit flags and required vision weights.

## Generate one image directly

```cmd
qwen21.cmd sheep "A detailed photograph of a sheep"
```

Optional positional arguments are width, height, steps, and seed:

```cmd
qwen21.cmd sheep "A detailed photograph of a sheep" 768 1024 30 42 -Model qwen-image-2.1-Q5_K_M.gguf
```

The direct command writes `sheep.png` to the configured Pictures output folder. `test-qwen21.cmd` lists devices and runs the original 1024×1024 smoke test.

With CUDA, the supplied backend puts diffusion on the GPU and the text encoder and VAE on CPU to fit an 8 GB GPU. With Vulkan, built-in Qwen generation puts diffusion and VAE decoding on the GPU, keeping text encoding on CPU. Explicit model profiles retain their own placement. For a direct run with CPU decoding, pass `-VaeBackend cpu` to `qwen21.ps1` or `qwen21.cmd`. If generation fails, check the console output for model loading or memory errors. The [upstream Qwen Image 2.1 guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/qwen_image_2.1.md) documents the engine options.

The interactive launcher keeps earlier menus and accepted answers visible as you move forward. Esc removes the cancelled step and returns to the previous question or to review, without duplicating the menu.

## Radeon 890M speed options

Lustify v10 uses the engine's default Vulkan kernels and its automatic CPU thread count. On the tested Radeon 890M driver, the earlier tuning produced solid-white Krea images. With default kernels, the same Standard group test made a usable 768x768 image with eight steps in 3m 35s. See [the performance investigation](PERFORMANCE.md) for the earlier comparisons.

For the installed **Lustify Zenith V9 SDXL checkpoint**, use its own profile:

```powershell
.\queue.cmd model -Model lustify-zenith-v9
.\queue.cmd add "a photograph of a cute owl perched on a mossy branch"
.\queue.cmd run -Limit 1
```

This profile uses `lustifyNSFWCheckpoint_zenithV9.safetensors` as a complete SDXL checkpoint, including its bundled text encoders and VAE. It needs no Qwen companion models. Defaults are 1024x1024, 20 steps, DPM++ 2M, Karras, and CFG 5.5. Diffusion and direct-convolution VAE decoding run on the selected GPU, and text encoding runs on CPU. The launcher automatically selects CUDA on a system with an NVIDIA driver and the installed CUDA engine; otherwise it uses Vulkan. Pass `-EngineBackend cuda12` or `-EngineBackend vulkan` to `qwen21.cmd` for diagnostics or an explicit override. These are locally tested starting settings, not a claim of optimal settings for every prompt. The profile supports initial-image variation; it does not support Qwen-style instruction-based reference editing.

The Ryzen AI 9 HX 370 / Radeon 890M shares system memory. Available shared memory lets the model fit, but does not give it the compute speed of a large dedicated GPU. The installed engine exposes CPU and Vulkan backends; it does not use the NPU.

Qwen Vulkan runs use GPU VAE decoding with direct convolution to avoid large temporary convolution buffers. Text encoding remains on CPU because a local all-GPU comparison was slower, and diffusion keeps flash attention. On the Radeon 890M, reducing Qwen resolution or steps caused a large quality loss, while native settings took much longer than the five-minute target. Lustify is therefore the recommended model for local photographic generation on this PC.

Qwen and SDXL Vulkan generation use all logical CPU processors for text conditioning while diffusion and VAE work remain on the Radeon GPU. Krea retains the engine-managed thread count. On the Ryzen AI 9 HX 370, a warmed three-step SDXL test improved from 14.73 seconds with 12 threads to 12.83 seconds with 24 threads. Direct diffusion convolution was also tested but became slower when combined with 24 threads, so only direct VAE convolution remains enabled. Windows may still display the Balanced power scheme when its separate power-mode slider is set to Best performance.

| Model ID | Default size | Steps | Purpose |
| --- | --- | --- | --- |
| Built-in Qwen GGUF | 1024x1024 native | 40 | Best native detail, but very slow on the Radeon 890M |

Use `queue.cmd model -Model Q4_K_M` for native 1024px Qwen generation. Existing jobs keep their saved dimensions and step count. Explicit `-Width`, `-Height`, and `-Steps` override these defaults. Reference edits use the built-in Qwen selection.

Completed jobs display elapsed time and store `elapsedSeconds` in queue history. For reproducible engine comparisons, run `tests\benchmark-qwen.cmd -Variant baseline -Size 1024` and `tests\benchmark-qwen.cmd -Variant gpu-vae-direct -Size 1024` sequentially. They use the same owl prompt, seed 42, and two steps, saving phase timings, logs, and images under `benchmarks\`. Two-step images are timing probes, not quality examples. See [local performance results](PERFORMANCE.md) for the measured results and limitations.

## Data and third-party components

`queue\` contains prompt history and copies of input images. The configured Pictures output folder contains generated images. The downloaded engine, weights, downloads, queue, and legacy local output folder are excluded from Git by `.gitignore`. Review your prompts and images before sharing them separately.

The scripts and documentation in this repository are licensed under [MIT](LICENSE).

Setup downloads third-party components under their own licenses. In particular, the Qwen Image 2.1 weights are under the Qwen Research License, which limits use to non-commercial research or evaluation unless you obtain a separate commercial license. See [third-party notices](THIRD_PARTY_NOTICES.md) and the linked source terms before using or redistributing any downloaded files.

## Development

Run all project tests on Windows without downloading weights or using a GPU:

```powershell
.\tests\run-all.cmd
```

Tests cover syntax/profile validation, queue batches/edits/retries, CUDA/Vulkan routing, image path/strength, launcher navigation, prompt history, realism settings, output validation, and legacy CSV migration. Tests use temporary stubs; real AMD image checks and their limitations are documented in PERFORMANCE.md. End-to-end generation requires the installed engine, model files, and GPU. Use Windows PowerShell for the suites because the engine stub is compiled as a Windows console executable.
