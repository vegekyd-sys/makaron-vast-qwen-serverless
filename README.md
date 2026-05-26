# Makaron Vast Qwen Serverless

Vast.ai Serverless worker for the Makaron Qwen backend. This keeps the same
ComfyUI model and workflow used by the on-demand Vast instance:

- Checkpoint: `Qwen-Rapid-AIO-NSFW-v23.safetensors`
- Checkpoint source: `Phr00t/Qwen-Image-Edit-Rapid-AIO/v23`
- Checkpoint SHA256: `fdb919fc81bea63f13759967fc92c9118142e5c70d4e6795199233a35eefa233`
- Rotate LoRA: `qwen-image-edit-2511-multiple-angles-lora.safetensors`
- Rotate LoRA SHA256: `42426ded4e25fd22879d9e198b857556445ef4ca56e8da3246d0345155bb6765`
- ComfyUI commit: `379fbd1a827cd2ce97984a7e8ea8b7159780cd1c`
- Custom node: `luguoli/ComfyUI-Qwen-Image-Integrated-KSampler`

The worker exposes:

- `POST /generate` for img2img and rotate jobs
- `POST /warmup` for the Vast benchmark and model load check
- `GET /health` for lightweight health checks

The setup script fails closed if the downloaded checkpoint or LoRA hash does
not match, so it cannot silently swap to another model.

