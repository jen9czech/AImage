# AImage

A Windows command line image generator using `stable-diffusion.cpp`. Jobs live in a JSON queue so prompts can be added in batches, edited, retried, and processed one at a time. It supports Qwen Image 2.1 and other model families through profiles. The queue format is intended to support a small Windows UI later.

## Quick start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
.\queue.cmd add "A detailed photograph of a sheep in a meadow"
.\queue.cmd run
```

Find the generated PNG in `output\`. The first setup downloads several gigabytes, so it can take a while. `queue.cmd models` lists installed models and `queue.cmd model -Model ID` selects the default for new jobs.

## Requirements

- Windows 10/11 x64, NVIDIA GPU, and a current CUDA-capable driver
- About 10 GB of free disk space for model files, plus the engine and generated images
- Enough system RAM for the Qwen3-VL text encoder; the supplied backend places it on the CPU

## Install or update

From PowerShell in this folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

Setup fetches the latest official `stable-diffusion.cpp` Windows CUDA 12 release and these model files:

| Role | File | Source |
| --- | --- | --- |
| Diffusion | `qwen-image-2.1-Q4_K_M.gguf` | [abenzerps/Qwen-Image-2.1-Uncensored-GGUF, base branch](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/tree/base) |
| Text encoder | `Qwen3-VL-8B-Instruct-Q4_K_M.gguf` | [unsloth/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF) |
| VAE | `qwen_image_2.1_vae_bf16.safetensors` | [abenzerps/Qwen-Image-2.1-Uncensored-GGUF, main branch](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-GGUF/tree/main/vae) |

It reuses files that are already present. Downloads in progress use `.part` files so an interrupted transfer can resume. Re-run setup to check for a newer engine release.

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

`models` lists installed compatible GGUFs; `model` changes the default for future jobs. A job can override that default with `-Model`, or change it while queued using `queue.cmd edit -Id ab12 -Model Q5_K_M`. Existing jobs keep the model they were created with. You can also copy a compatible Qwen Image 2.1 GGUF into `models\` and select its filename.

Other image model families use a small JSON profile in [`profiles\`](profiles/README.md). A profile lists its required files and the `sd-cli` options for that family. Once its files are present, `queue.cmd models` shows it as ready and you can select its ID with `queue.cmd model -Model ID`. The queue and batch workflow stay the same.

The included `flux1-schnell` profile can be installed with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ModelFamily flux1-schnell
```

This downloads the [FLUX.1 Schnell Q3_K GGUF](https://huggingface.co/leejet/FLUX.1-schnell-gguf/tree/main), [VAE](https://huggingface.co/unsloth/FLUX.1-schnell/blob/main/ae.safetensors), and [CLIP/T5 encoders](https://huggingface.co/comfyanonymous/flux_text_encoders/tree/main), then makes it the default for new jobs. It needs about 16 GB of additional disk space and substantial system RAM for the FP16 T5 encoder. Its profile defaults to four steps. The engine settings follow the [upstream FLUX guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux.md). The existing Qwen files and jobs stay available.

For `-PromptFile`, save one prompt per line as UTF-8; blank lines are ignored. `run` processes queued jobs in order and continues after a failed job. Add `-Limit 1` to process only the next job. Each job receives a unique PNG filename in `output\`. Defaults are 1024×1024, 40 Euler steps, CFG 6.0, and a random seed (`-1`). Dimensions must be multiples of 32.

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

The direct command writes `output\sheep.png`. `test-qwen21.cmd` lists devices and runs the original 1024×1024 smoke test.

The supplied backend puts diffusion on CUDA and the text encoder and VAE on CPU to fit an 8 GB GPU. If generation fails, check the console output for model loading, CUDA, or memory errors. The [upstream Qwen Image 2.1 guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/qwen_image_2.1.md) documents the engine options.

## Data and third-party components

`queue\` contains prompt history and copies of input images. `output\` contains generated images. The downloaded engine, weights, downloads, queue, and outputs are excluded from Git by `.gitignore`. Review your prompts and images before sharing them separately.

The scripts and documentation in this repository are licensed under [MIT](LICENSE).

Setup downloads third-party components under their own licenses. In particular, the Qwen Image 2.1 weights are under the Qwen Research License, which limits use to non-commercial research or evaluation unless you obtain a separate commercial license. See [third-party notices](THIRD_PARTY_NOTICES.md) and the linked source terms before using or redistributing any downloaded files.

## Development

Run the queue smoke test on Windows without downloading weights or using a GPU:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\queue-smoke.ps1
```

The test uses temporary stub files and checks batch input, model selection, queue edits and retries, and image input routing. End-to-end generation still requires the real engine, models, and a CUDA-capable GPU. A Windows UI is planned; this repository currently provides command line scripts.
