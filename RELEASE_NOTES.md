# AImage v1.0.0

This first packaged release of this fork adds an interactive Windows launcher and downloads the engine and selected model family during setup.

- Create from text, redraw a starting picture, and review the effective prompt and generation settings before rendering.
- Choose model, resolution, photographic assistance, framing, versions, and JPG or PNG output.
- Recall prompts with arrow keys and navigate backward with Esc.
- Keep quoted prompts intact when they reach the generator.
- Validate generated images and reject solid-color, corrupt, or incorrectly sized output before recording success.
- Use default Vulkan kernels for the Radeon 890M after the earlier tuning produced blank output on the tested driver.
- Download Qwen Image 2.1, Lustify v10 Krea 2 Turbo, Lustify Zenith V9, or FLUX.1 Schnell through setup.

## Install

Extract AImage-v1.0.0-source.zip and run setup.cmd with the model family you want. For Lustify v10, run `setup.cmd -ModelFamily lustify-v10-krea2-turbo`. Then run aimage.cmd.

Model weights download separately and require several gigabytes of space. Model licenses are linked in THIRD_PARTY_NOTICES.md.

## Validation

The Windows project test suite passed. Live Radeon 890M checks produced usable Standard group images in JPG and PNG. Redraw strength 0.75 changed the sweater color and pose, while 0.40 retained most of the source. Full-body framing and varied group poses are prompt guidance and can still vary in the generated image.

## Thanks

Thank you to pplloosskkii for the original AImage project and to the stable-diffusion.cpp contributors for the generation engine.
