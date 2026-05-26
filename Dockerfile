FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive \
    COMFY_DIR=/workspace/ComfyUI \
    PYWORKER_DIR=/workspace/makaron-vast-qwen-serverless \
    LOG_DIR=/var/log/makaron-qwen \
    COMFYUI_CHECKPOINT=Qwen-Rapid-AIO-NSFW-v23.safetensors \
    COMFYUI_ANGLES_LORA=qwen-image-edit-2511-multiple-angles-lora.safetensors \
    COMFY_COMMIT=379fbd1a827cd2ce97984a7e8ea8b7159780cd1c \
    CHECKPOINT_SHA256=fdb919fc81bea63f13759967fc92c9118142e5c70d4e6795199233a35eefa233 \
    LORA_SHA256=42426ded4e25fd22879d9e198b857556445ef4ca56e8da3246d0345155bb6765

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
      aria2 \
      ca-certificates \
      curl \
      git \
      procps \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt worker.py qwen_server.py start.sh ${PYWORKER_DIR}/

RUN python -m pip install --upgrade pip \
    && python -m pip install --upgrade --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128 \
    && python -m pip install -r "${PYWORKER_DIR}/requirements.txt"

RUN git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}" \
    && git -C "${COMFY_DIR}" checkout "${COMFY_COMMIT}" \
    && python -m pip install -r "${COMFY_DIR}/requirements.txt" \
    && python -m pip install \
      comfy-aimdo==0.2.12 \
      comfy-kitchen==0.2.8 \
      comfyui_frontend_package==1.41.20 \
      comfyui_workflow_templates==0.9.26

RUN mkdir -p "${COMFY_DIR}/custom_nodes" \
    && git clone https://github.com/luguoli/ComfyUI-Qwen-Image-Integrated-KSampler.git \
      "${COMFY_DIR}/custom_nodes/ComfyUI-Qwen-Image-Integrated-KSampler"

RUN mkdir -p "${COMFY_DIR}/models/checkpoints" "${COMFY_DIR}/models/loras" \
    && aria2c -x 16 -s 16 -k 1M --file-allocation=none \
      -o "${COMFYUI_CHECKPOINT}" \
      -d "${COMFY_DIR}/models/checkpoints" \
      "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors?download=true" \
    && echo "${CHECKPOINT_SHA256}  ${COMFY_DIR}/models/checkpoints/${COMFYUI_CHECKPOINT}" | sha256sum -c - \
    && aria2c -x 16 -s 16 -k 1M --file-allocation=none \
      -o "${COMFYUI_ANGLES_LORA}" \
      -d "${COMFY_DIR}/models/loras" \
      "https://huggingface.co/fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA/resolve/main/qwen-image-edit-2511-multiple-angles-lora.safetensors?download=true" \
    && echo "${LORA_SHA256}  ${COMFY_DIR}/models/loras/${COMFYUI_ANGLES_LORA}" | sha256sum -c -

RUN chmod +x "${PYWORKER_DIR}/start.sh" \
    && mkdir -p "${LOG_DIR}"

WORKDIR ${PYWORKER_DIR}
CMD ["bash", "/workspace/makaron-vast-qwen-serverless/start.sh"]
