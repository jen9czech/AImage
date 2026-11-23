# Third-party components

This repository contains scripts and configuration, not the downloaded engine or model files. `setup.ps1` fetches the following components into ignored local folders. Each component keeps its own license; a license for this repository's scripts does not change those terms.

| Component | Download source | Terms |
| --- | --- | --- |
| `stable-diffusion.cpp` Windows CUDA or Vulkan engine | [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) | [MIT](https://github.com/leejet/stable-diffusion.cpp/blob/master/LICENSE) |
| Optional Lustify Zenith V9 checkpoint | [Hugging Face mirror of Civitai version 3045803](https://huggingface.co/torestinbar/krea2-resources/blob/main/checkpoints/civitai-3045803-1a3abf0bf481-lustifyNSFWCheckpoint_zenithV9.safetensors) | Review the [original model terms](https://civitai.com/models/573152?modelVersionId=3045803) |
| Qwen Image 2.1 diffusion GGUF and VAE | [abenzerps/Qwen-Image-2.1-Turbo-Quantized](https://huggingface.co/abenzerps/Qwen-Image-2.1-Turbo-Quantized/tree/base), derived from [Qwen/Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) | [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) |
| Qwen3-VL-8B-Instruct Q4_K_M text encoder | [unsloth/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF) | [Apache-2.0](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/tree/main) |
| Optional Qwen3-VL vision projector | [Qwen/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF) | [Apache-2.0](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF) |
| Optional FLUX.1 Schnell GGUF | [leejet/FLUX.1-schnell-gguf](https://huggingface.co/leejet/FLUX.1-schnell-gguf) | [Apache-2.0](https://huggingface.co/leejet/FLUX.1-schnell-gguf) |
| Optional FLUX.1 Schnell VAE | [unsloth/FLUX.1-schnell](https://huggingface.co/unsloth/FLUX.1-schnell) | [Apache-2.0](https://huggingface.co/unsloth/FLUX.1-schnell) |
| Optional FLUX text encoders | [comfyanonymous/flux_text_encoders](https://huggingface.co/comfyanonymous/flux_text_encoders) | [Apache-2.0](https://huggingface.co/comfyanonymous/flux_text_encoders) |
| Optional Lustify v10 Krea 2 Turbo diffusion model | [kkkkk26/lustifyNSFWCheckpoint_v10Krea2Turbo](https://huggingface.co/kkkkk26/lustifyNSFWCheckpoint_v10Krea2Turbo) | Review the repository and upstream Krea 2 terms before use |
| Krea 2 Qwen3-VL 4B text encoder | [Qwen/Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF) | [Apache-2.0](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF) |
| Krea 2 Wan 2.1 VAE | [Comfy-Org/Wan_2.1_ComfyUI_repackaged](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged) | Review the repository terms before use |

The Qwen Image 2.1 source license limits use of its materials to non-commercial research or evaluation unless a separate commercial license is obtained. Users should review the current source terms before downloading or using the weights. The optional FLUX.1 Schnell model has different terms.

Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT, Copyright (c) 2026 Hangzhou Tongyi Laboratory Technology Co., Ltd. All Rights Reserved.
