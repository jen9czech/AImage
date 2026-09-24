# Model profiles

Each JSON file in this folder describes one image model family for `sd-cli.exe`. The file name (without `.json`) must match `id`. Place the required weights in `models\`, then run `queue.cmd models` and select the profile with `queue.cmd model -Model ID`.

Example:

```json
{
  "id": "my-image-model",
  "name": "My image model",
  "requiredFiles": [
    "models/my-diffusion.gguf",
    "models/my-vae.safetensors"
  ],
  "defaults": { "steps": 20 },
  "args": [
    "--diffusion-model", "{root}/models/my-diffusion.gguf",
    "--vae", "{root}/models/my-vae.safetensors",
    "--sampling-method", "euler",
    "--cfg-scale", "6.0"
  ]
}
```

`{root}` becomes the project folder. Use engine options documented for that model family by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs). The runner supplies prompt, output, width, height, steps, and seed for each job; leave those options out of `args`. List every required local file in `requiredFiles`. Relative paths there start at the project folder. A profile appears as ready only after all its files exist.

`defaults.steps` is optional; new jobs use it unless `-Steps` is supplied. The fallback is 40.

If a model supports clean reference images, add `"supportsReferenceImage": true` and include its required vision weights and engine flags in `requiredFiles` and `args`. Any profile can use an initial image through the engine's `--init-img` option; `-Strength` controls that mode.

Profiles are local configuration, and jobs record the profile ID. Changing a profile changes how future runs of queued jobs with that ID execute, so create a new profile ID when you need reproducible settings.
