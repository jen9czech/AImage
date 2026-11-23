# Model profiles

`lustify-zenith-v9` loads the installed complete SDXL checkpoint `lustifyNSFWCheckpoint_zenithV9.safetensors` through `--model`, including its bundled encoders and VAE. It defaults to 1024x1024 and 20 steps on the automatically selected CUDA or Vulkan GPU; Qwen's separate weights and sampler configuration are not used. Select it with `queue.cmd model -Model lustify-zenith-v9`.

`lustify-v10-krea2-turbo` loads the locally converted Q8 Lustify v10 Krea 2 Turbo diffusion model together with the required Qwen3-VL 4B text encoder and Wan 2.1 VAE. It uses Krea Turbo's native 1024x1024, 8-step Euler configuration with CFG 1. Q8 cuts the diffusion weights from about 25 GB to 13 GB, reducing shared-memory pressure and model loading time on integrated Radeon graphics.

Each JSON file in this folder describes one image model family for `sd-cli.exe`. The file name (without `.json`) must match `id`. Place the required weights in the configured model folder (by default `C:\AI\Models\Image`), then run `queue.cmd models` and select the profile with `queue.cmd model -Model ID`.

Example:

```json
{
  "id": "my-image-model",
  "name": "My image model",
  "requiredFiles": [
    "{models}/my-diffusion.gguf",
    "{models}/my-vae.safetensors"
  ],
  "defaults": { "steps": 20 },
  "args": [
    "--diffusion-model", "{models}/my-diffusion.gguf",
    "--vae", "{models}/my-vae.safetensors",
    "--sampling-method", "euler",
    "--cfg-scale", "6.0"
  ]
}
```

`{root}` becomes the project folder, `{models}` becomes the configured model folder, `{output}` becomes the configured image folder, and `{gpu}` becomes `cuda0` or `Vulkan0` according to the selected engine. Use engine options documented for that model family by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs). The runner supplies prompt, output, width, height, steps, and seed for each job; leave those options out of `args`. List every required local file in `requiredFiles`. Relative paths there start at the project folder. A profile appears as ready only after all its files exist.

`defaults.steps` is optional; new jobs use it unless `-Steps` is supplied. The fallback is 40.

`defaults.width` and `defaults.height` work the same way, with a fallback of 1024. Each must be a positive multiple of 32. Explicit `-Width` and `-Height` take precedence independently. Queue jobs store their resolved dimensions and step count when added.

The built-in Qwen selection uses native 1024x1024 / 40-step generation and supports reference-image editing when its optional vision projector is installed.

If a model supports clean reference images, add `"supportsReferenceImage": true` and include its required vision weights and engine flags in `requiredFiles` and `args`. Any profile can use an initial image through the engine's `--init-img` option; `-Strength` controls that mode.

Profiles are local configuration, and jobs record the profile ID. Changing a profile changes how future runs of queued jobs with that ID execute, so create a new profile ID when you need reproducible settings.
