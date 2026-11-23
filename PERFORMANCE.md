# Radeon 890M tuning results

## Output reliability on 22 November 2026

On Radeon driver `32.0.32029.2010`, the earlier automatic Vulkan tuning produced solid-white Krea output in matched 768×768 group runs. AImage now leaves kernel selection to the engine. With default kernels, the fixed-seed, eight-step three-hiker test saved a usable Standard JPG in 3m 35s and PNG in 3m 45s. Both showed three full-length hikers in the requested jacket colors. The same route restored 512×512 redraws with CPU VAE. At strength 0.40 the pose and most of the blue sweater remained. At 0.75 the sweater became red and the pose changed. The runner now validates its staged PNG before saving either format. All four saved files passed the image verifier.

## Speed regression investigation on 10 October 2026

The user confirmed that the earlier approximately 2.5-minute runs used Standard, 768x768 and eight steps. Embedded metadata from an earlier successful image matches the current Euler/discrete sampler, CFG 1, Q8 diffusion model, Qwen3-VL-4B encoder and Wan VAE. That comparison does not establish the same prompt, cache conditions or GPU clocks.

Sequential tests used a benign adult cafe portrait, seed 12345, 768x768, eight steps and the installed `3f8527a` Vulkan engine. No diagnostic log was created; phase output was parsed in memory. Images are in `benchmarks/speed-review/`.

| Comparison | Wall time | Finding |
| --- | --- | --- |
| Current assisted photograph | 278.454 s (4m 38s) | Baseline |
| Original prompt, assistance off | 339.805 s (5m 39s) | Disabling assistance did not restore the old speed |
| Earlier `39ada08` engine, Original prompt | 366.934 s (6m 06s) | Engine downgrade did not help |
| Latest tested `1b0ba10` engine, assisted prompt | 296.797 s (4m 56s) | Engine upgrade did not help; not installed |
| Shortened assistance, installed engine | 286.122 s (4m 46s) | No improvement; template change reverted |
| Cooperative matrix kernels disabled, original assisted prompt | 212.935 s (3m 32s) | About 24% faster than baseline |

The final row changes Vulkan kernel selection through `GGML_VK_DISABLE_COOPMAT=1`, retaining the model weights, prompt assistance, seed, resolution, sampler and eight steps. Sampling fell from about 268 seconds to 181.65 seconds, while GPU VAE decoding rose to 26.91 seconds. Total time still improved. Visual comparison found the same coherent photographic portrait, pose, clothing, hands and background, with no apparent detail reduction; numerical differences remain possible.

For that benchmark, the runner applied this setting only when the selected device was an AMD Radeon 890M and the model was Lustify v10 Krea 2. The upstream [Vulkan implementation](https://github.com/ggml-org/ggml/blob/master/src/ggml-vulkan/ggml-vulkan.cpp) defines this environment control.

Matching two-step thread probes measured 76.098 seconds at 12 threads and 77.372 seconds at 24 threads. Krea therefore returns to the engine-managed physical-core default instead of forcing all logical threads. Best Performance was confirmed through the effective Windows overlay API; about 31 GB RAM was free during generation. A separate host-memory preference experiment did not provide a useful speed improvement and was not enabled.

An elapsed-time regression was also fixed: PowerShell integer conversion rounded minutes up, so 278.454 seconds could display as `5m 38s`. It now displays `4m 38s`, with tests around minute/hour boundaries. This corrects the display, not the underlying generation duration. These trials improve current performance but do not prove the original slowdown's cause or restore a guaranteed 2.5-minute result. No lower-resolution default, reduced step count, approximate caching or lighter model weights were enabled.

`tests/benchmark-krea-speed.ps1` supports matching engine, thread, prompt and seed comparisons without writing a log. Runner tests cover AMD 890M tuning, other-GPU isolation, CUDA isolation and caller environment preservation; the full project suite passes.

The final real runner verification, with no manually set tuning environment, saved `auto-tuned-standard.jpg` successfully in 211.821 seconds (3m 32s). Its history confirms Standard, 768x768, eight steps, Realistic appearance and Vulkan0. The automatically tuned portrait was visually checked and remained coherent. This verifies the normal application path in addition to the comparison script.

## Prompt assistance follow-up on 10 October 2026

Texture guidance alone did not prevent a physically impossible composition. The user's short description of a man with a big nose among bushes and discarded bottles produced a head apparently emerging from the ground at 768px, eight steps, seed 624372630 (306.199 seconds, Natural appearance).

Assisted photograph now puts photo style and framing before the description. Automatic uses basic English crop/subject keywords, choosing full body for a person when no crop is specified. Ordinary clothing fills an unspecified human wardrobe; existing wardrobe details and source-image composition are preserved. Discarded plastic bottles in human litter scenes receive an explicit scale cue. Framing remains selectable rather than requiring a longer description. Both chosen and resolved framing, plus original/effective prompts, enter generation history.

The 768px comparison with the same description and seed fixed the missing-body composition in about 5.7 minutes, but exposed an unspecified wardrobe and oversized bottles. The final template with clothing/scale defaults was then checked at 512px Preview: 152.637 seconds, a complete clothed person standing on visible ground, with smaller bottles. Preview is a composition check with softer detail; the final clothing/scale additions have not been rerun at 768px or 1024px. Earlier local drafts either looked stylized or retained the missing body and were revised. These examples do not establish a universal realism improvement or speedup. Assistance can increase conditioning cost, and unusual anatomy can still occur.

Logs, images, and the comparison CSV are under `benchmarks/realism-assistance/`; final preview log is `benchmarks/realism-assistance-preview.log`. `tests/run-all.cmd` passes with added checks for automatic/explicit framing, original prompt preservation, source-mode isolation, wardrobe/scale overrides, history migration, and Esc navigation through the conditional framing screen. The real console input test also passed. No new model, dependency, network service, sampler, resolution default, or CUDA/Vulkan placement change was introduced.

## Project review on 9 October 2026

The installed Vulkan engine is commit `3f8527a`. Device discovery confirms Radeon 890M with FP16/BF16 and cooperative matrix support. Windows reports Ryzen AI 9 HX 370 (12 cores/24 threads), two 32 GB DDR5-5600 modules, driver `32.0.31041.1004`, and about 32 GB free RAM during the text-to-image check. The active base power plan is Balanced; this alone does not reveal the Windows Best Performance overlay setting.

Real comparisons use the same benign cafe portrait description and seed 12345. Runs are sequential on the installed GPU, not parallel. Files and full engine logs are under `benchmarks/realism-review/`.

| Test | Size / steps | Result |
| --- | --- | --- |
| Original Zenith SDXL settings | 1024 / 20 | Successful; about 2.2 minutes |
| Zenith with Natural appearance | 1024 / 20 | Successful; about 2.0 minutes |
| Zenith Quality with Natural appearance | 1024 / 30 | Successful; about 3.1 minutes |
| Krea Turbo Standard with Natural appearance | 768 / 8 | Successful; about 3.4 minutes |
| Krea source-image redraw, strength 0.40, CPU VAE | 768 / 8 requested | Successful; about 4.1 minutes; engine used 4 redraw steps |

Visual review found a coherent portrait in each completed test. Krea followed the head-and-shoulders framing most closely, with convincing skin and fabric detail. Natural appearance gave the SDXL image gentler contrast and tones, but changed composition; it does not preserve an identity. The 30-step SDXL test changed fine details without an obvious universal realism improvement. Standard remains the default, and Quality is optional. These are single trials: cache warmth, prompt, and background work affect timing. The Krea 768px measurement is not a promise that native 1024px Krea meets five minutes.

The launcher now runs navigation in one process and includes model-specific quality choices. Esc returns to each actual preceding question, including path/strength, and closes at model selection. Photo guidance is selectable, new single-image runs use random seeds, and history saves the original and effective prompts, negative prompt, appearance, seed, backend, input, and elapsed time. JPG quality is 95; PNG remains lossless. No approximate caching, extra upscaling pass, or new weights were enabled.

The quoted-path source-image test confirmed actual VAE encoding of the input. With GPU VAE encoding, diffusion-weight loading slowed dramatically and the trial was stopped before completion. CPU VAE encoding/decoding completed in about 4.1 minutes (20.07 s encoding, 1.49 s conditioning, 184.13 s sampling including 59.27 s weight loading, 38.02 s decoding). This is now a scoped automatic fallback for Krea image-to-image on Vulkan; text-to-image and CUDA placement are unchanged, and `-VaeBackend gpu` overrides it. The incomplete GPU trial does not establish a repeatable speedup ratio, and cache variability remains. History records VAE placement separately from diffusion backend.

At strength 0.40, the completed Krea redraw closely preserved the original face, framing, and blue sweater even though the description requested red. The UI now explains that low strength may preserve the source almost unchanged and suggests 0.65-0.80 for stronger redraws; that suggested range was not benchmarked here. Image-to-image is not equivalent to targeted instruction editing. The projector needed for Qwen reference editing is not installed locally, so that mode's argument routing was tested with stubs.

Krea retains the documented eight-step Turbo configuration. Reference: [official Krea inference settings](https://github.com/krea-ai/krea-2) and [natural-language prompting guide](https://github.com/krea-ai/krea-2/blob/main/docs/prompting.md). The stable-diffusion.cpp CFG=1 convention is retained; [the upstream explanation](https://github.com/leejet/stable-diffusion.cpp/issues/1781) distinguishes it from the official Diffusers CFG=0 convention.

`tests/run-all.cmd` covers syntax, model profiles, queue behavior, CUDA/Vulkan routing, source paths/strength, reproducible seeds, realism guidance, missing output/failure handling, launcher navigation, latest-prompt history, and legacy CSV migration. `tests/console-input.ps1` also passed in a real console, checking editing, arrow history, draft restoration, and Esc. A 175-character prompt was checked interactively and saved intact without repeated input lines. GPU generation was tested on AMD; NVIDIA routing is tested with a stub, not a physical NVIDIA GPU. Setup's network downloads and model conversion were not rerun.

The older measurements below used a previous engine and configuration.

Measured locally on 25 September 2026 with Ryzen AI 9 HX 370, Radeon 890M, 64 GB system memory, AMD driver 32.0.31041.1004, and stable-diffusion.cpp Vulkan build `39ada08`.

## Earlier target: Lustify Zenith V9 SDXL

The user selected `lustifyNSFWCheckpoint_zenithV9.safetensors` and reported Adrenalin 26.8.1 with Windows Best Performance enabled. The local safetensors header identifies `stable-diffusion-xl-v1-base` and includes both CLIP encoders and a VAE. It is loaded as a complete checkpoint with `--model`; Qwen companion weights are not used.

The `lustify-zenith-v9` profile uses 1024x1024, 20 steps, DPM++ 2M, Karras, CFG 5.5, flash attention, CPU text encoding, and GPU diffusion/VAE with direct VAE convolution. The launcher substitutes CUDA on NVIDIA and Vulkan otherwise. A full Vulkan owl test at seed 42 completed successfully: 2.95 s conditioning, 109.08 s sampling, 8.79 s decoding, 120.85 s engine generation time, approximately two minutes including launch. The resulting `lustify-owl-1024.png` in the configured output folder was visually checked for a coherent photographic owl and successful decoding. Log: `benchmarks/lustify-owl-1024.log`.

This single complete run meets the five-minute target with the requested checkpoint at native 1024x1024. It is not a guarantee for every prompt, image-to-image task, concurrent workload, or higher step count. No additional dependencies were required. The engine applies its built-in SDXL VAE convolution scaling; its log warning about no separately specified VAE does not mean the bundled VAE is missing.

The profile is now the default for new queue jobs. Existing Qwen jobs retain their model and settings; changing the default does not convert or interrupt them. The Qwen measurements below are historical and should not be used as Lustify timing estimates.

The Qwen diffusion model is Q4_K_M, the text encoder is Qwen3-VL-8B Q4_K_M, and the VAE is Qwen Image 2.1 BF16. Tests use `a photograph of cute owl`, seed 42, Euler, CFG 6, and flash attention unless otherwise stated. Runs are sequential. Model/driver caches and background desktop activity can affect timings; these are short local trials, not repeated statistical benchmarks.

## Applied changes

- Built-in Qwen on Vulkan uses GPU VAE decoding with `--vae-conv-direct`. This avoids the large temporary buffers used by the default convolution implementation.
- Text encoding stays on CPU. Flash attention and automatic memory placement remain enabled.
- Built-in Qwen retains its original 1024x1024 / 40-step mode. CPU VAE compatibility remains available with `qwen21.cmd ... -VaeBackend cpu`.
- The earlier native 768x768 / 24-step and preview 512x512 / 12-step profiles were removed after poor-quality results. Only native Qwen remains in the launcher.
- Queue jobs save resolved profile dimensions and elapsed seconds. Explicit dimensions/steps override defaults. Existing queued jobs retain their saved settings.

Custom model profiles can keep explicit backend placement or use `{gpu}` for automatic CUDA/Vulkan substitution. GPU arithmetic may produce slightly different pixels across backends.

## Full-resolution timing probes

| Configuration | Size | Steps | Sampling | VAE decode | Total wall time |
| --- | --- | --- | --- | --- | --- |
| Original: GPU diffusion, CPU text/VAE | 1024x1024 | 2 | 156.65 s | 81.92 s | 242.58 s |
| GPU VAE, default convolution | 1024x1024 | 2 | 151.15 s | 71.95 s | 227.36 s |
| GPU VAE, direct convolution | 1024x1024 | 1 | 72.05 s | 16.78 s | 93.14 s |

The direct-convolution test uses **one step**, so its total time must not be compared as an overall speedup against the two-step rows. Its VAE phase processes the same image dimensions and was approximately 4.9 times faster than CPU decoding. The default GPU convolution produced pinned-buffer size warnings at 1024; direct convolution completed without those warnings.

This saves about a minute of decoding in these tests. It does **not** make a 40-step image five times faster: the repeated diffusion steps still dominate. A full 1024x1024 / 40-step run has not been repeated during tuning.

## Exploratory 512x512 probes

| Configuration | Steps | Sampling | VAE decode | Total wall time |
| --- | --- | --- | --- | --- |
| No flash attention; CPU text, GPU VAE | 2 | 42.37 s | 8.12 s | 54.69 s |
| All GPU; flash attention | 2 | 35.46 s | 9.13 s | 49.64 s |
| Prefer host memory; CPU text, GPU VAE | 2 | 41.71 s | 7.49 s | 53.44 s |

A later same-session comparison with direct VAE convolution measured 40.57 seconds for CPU text encoding and 51.88 seconds with every component forced onto the Radeon. Keeping the text encoder on CPU was therefore about 22% faster by total wall time in that comparison.

These exploratory runs do not isolate every variable or establish repeatable gains. GPU text encoding took 3.21 seconds, similar to roughly 3.1 seconds on CPU. Forced host memory and disabling flash attention are not enabled in the launchers.

## Ryzen AI 9 HX 370 thread tuning

A warmed 512x512, three-step Lustify Zenith V9 comparison used the same prompt and seed. The default 12 physical CPU cores completed in 14.73 seconds; all 24 logical processors completed in 12.83 seconds, about 13% faster. Adding direct diffusion convolution to the 24-thread configuration increased the time to 14.89 seconds. Vulkan runs therefore use all logical processors and retain flash attention plus direct VAE convolution without direct diffusion convolution.

## Krea 2 Q8 conversion

The 25 GB Lustify Krea 2 FP16/BF16 checkpoint used 27.7 GB for all model parameters and showed severe cold-load variability: one 1024px run spent 591 seconds loading tensors and completed eight steps in 1,598 seconds. Converting the compatible checkpoint to Q8 reduced total parameter memory to 15.6 GB. A native 1024px one-step probe loaded the diffusion weights in 4.54 seconds from the warm filesystem cache, sampled in 85.54 seconds, and completed in 97.68 seconds. The earlier FP16 256px probe sampled one step in 87.57 seconds, while the matching Q8 probe sampled in 16.94 seconds. Disabling diffusion flash attention made the native Q8 step much slower at 162.91 seconds, so flash attention remains enabled. The active Krea profile therefore uses Q8 with diffusion flash attention.

## Complete preview check

The final launcher generated `890m-preview-owl.png` in the configured output folder using `qwen21-890m-preview` at its actual defaults: 512x512, 12 steps, seed 42. Generation took 181.91 seconds (about 3 minutes): 3.01 s text conditioning, 174.13 s sampling, and 4.77 s VAE decoding. The image was visually checked: it is a recognizable owl with visibly soft/rough details, appropriate as a composition preview rather than a substitute for the full-quality image. Log: `benchmarks/preview-owl.log`.

The balanced 768x768 / 24-step profile was reported at 850.29 seconds. The preview's speed difference from the original job includes reducing both resolution and step count; it is not an engine-only speedup.

## Rejected low-step experiment

The 640x640 / 10-step experiment completed in 244.97 seconds, but visual inspection found unacceptable softness and facial artifacts. It is not used by any final preset. Log: `benchmarks/gpu-vae-direct-640-10steps-20260925-224219.log`.

## Rejected generation-plus-upscaling experiment

The 512x512 / 20-step generation completed in 288.04 seconds. Vulkan 2× ESRGAN with a 512-pixel tile then produced a 1024x1024 output in 13.94 seconds, for a combined time of about 5 minutes 2 seconds. User review found the result unacceptable compared with native Qwen and Lustify outputs. Upscaling enlarged the image but could not restore semantic and fine detail lost during lower-resolution diffusion, so this profile was removed.

## Reproduce

```powershell
.\tests\benchmark-qwen.cmd -Variant baseline -Size 1024 -Steps 2
.\tests\benchmark-qwen.cmd -Variant gpu-vae-direct -Size 1024 -Steps 2
```

The benchmark saves timestamped logs, images, and JSON phase timings in `benchmarks\`. Avoid concurrent image generation while comparing timings. Two-step output is a timing probe, not a quality example.

Use the `.cmd` launcher on systems where direct PowerShell script execution is disabled. It sets execution policy for its child PowerShell process only; it does not change the system-wide policy.

## Follow-up target and hardware checks

The requested target is local photographic generation at 1024 pixels in no more than five minutes. The balanced 768x768 / 24-step job recorded 850.29 seconds (14 minutes 10 seconds), so it does not meet this target.

The user subsequently switched Windows Power mode from Balanced to Best Performance. Their Task Manager screenshot shows 64 GB DDR5, 5600 MT/s, 2 of 2 slots populated, 44.9 GB available, and 4.4 GB hardware reserved. This snapshot does not indicate a memory-capacity shortage; occupied slots alone do not verify channel operation. Previous benchmark timings predate the power-mode change. GPU clocks, utilization, temperature, power readings, and a repeat short benchmark are still needed.

Queue and runner smoke tests cover profile defaults, explicit overrides, backend routing, CPU VAE fallback, invalid dimensions, and existing queue/image-input behavior without loading real weights.

## Hardware interpretation

The PC's [listed configuration](https://www.alza.cz/acemagic-f3a-ryzen-ai-9-hx-370-64-1tb-black-d12819998.htm#description) includes a 12-core HX 370 and 64 GB DDR5-5600. Shared GPU memory is system RAM, rather than additional dedicated high-bandwidth VRAM. The screenshot shows compute activity and unused system memory; it does not by itself establish a RAM shortage or identify the slow operation. Engine phase timings are more useful here. The installed engine reports CPU and Vulkan devices, with no NPU backend.

Reference: [upstream backend selection](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/backend.md), [Qwen Image 2.1 options](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/qwen_image_2.1.md). The installed binary's help is authoritative for this build; newer upstream options can differ.
