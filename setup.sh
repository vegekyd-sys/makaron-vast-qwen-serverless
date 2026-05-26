#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
export PYWORKER_DIR="${PYWORKER_DIR:-/workspace/makaron-vast-qwen-serverless}"
export LOG_DIR="${LOG_DIR:-/var/log/makaron-qwen}"
export COMFYUI_CHECKPOINT="${COMFYUI_CHECKPOINT:-Qwen-Rapid-AIO-NSFW-v23.safetensors}"
export COMFYUI_ANGLES_LORA="${COMFYUI_ANGLES_LORA:-qwen-image-edit-2511-multiple-angles-lora.safetensors}"

CHECKPOINT_URL="${CHECKPOINT_URL:-https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors?download=true}"
CHECKPOINT_SHA256="${CHECKPOINT_SHA256:-fdb919fc81bea63f13759967fc92c9118142e5c70d4e6795199233a35eefa233}"
LORA_URL="${LORA_URL:-https://huggingface.co/fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA/resolve/main/qwen-image-edit-2511-multiple-angles-lora.safetensors?download=true}"
LORA_SHA256="${LORA_SHA256:-42426ded4e25fd22879d9e198b857556445ef4ca56e8da3246d0345155bb6765}"
COMFY_COMMIT="${COMFY_COMMIT:-379fbd1a827cd2ce97984a7e8ea8b7159780cd1c}"

mkdir -p "$LOG_DIR" /workspace

echo "[setup] installing system packages"
apt-get update
apt-get install -y --no-install-recommends git curl aria2 ca-certificates procps

echo "[setup] installing Python runtime packages"
python -m pip install --upgrade pip
python -m pip install --upgrade --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
python -m pip install -r "$PYWORKER_DIR/requirements.txt"

if [ ! -d "$COMFY_DIR/.git" ]; then
  echo "[setup] cloning ComfyUI"
  git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
fi

echo "[setup] pinning ComfyUI $COMFY_COMMIT"
git -C "$COMFY_DIR" fetch --depth 1 origin "$COMFY_COMMIT" || true
git -C "$COMFY_DIR" checkout "$COMFY_COMMIT"
python -m pip install -r "$COMFY_DIR/requirements.txt"
python -m pip install \
  comfy-aimdo==0.2.12 \
  comfy-kitchen==0.2.8 \
  comfyui_frontend_package==1.41.20 \
  comfyui_workflow_templates==0.9.26

mkdir -p "$COMFY_DIR/custom_nodes"
if [ ! -d "$COMFY_DIR/custom_nodes/ComfyUI-Qwen-Image-Integrated-KSampler/.git" ]; then
  echo "[setup] installing Qwen Integrated KSampler custom node"
  rm -rf "$COMFY_DIR/custom_nodes/ComfyUI-Qwen-Image-Integrated-KSampler"
  git clone https://github.com/luguoli/ComfyUI-Qwen-Image-Integrated-KSampler.git \
    "$COMFY_DIR/custom_nodes/ComfyUI-Qwen-Image-Integrated-KSampler"
fi

mkdir -p "$COMFY_DIR/models/checkpoints" "$COMFY_DIR/models/loras"

download_checked() {
  local url="$1"
  local dest="$2"
  local expected="$3"
  if [ -f "$dest" ]; then
    local actual
    actual="$(sha256sum "$dest" | awk '{print $1}')"
    if [ "$actual" = "$expected" ]; then
      echo "[setup] using existing $(basename "$dest")"
      return
    fi
    echo "[setup] hash mismatch for existing $(basename "$dest"), redownloading"
    rm -f "$dest"
  fi
  aria2c -x 16 -s 16 -k 1M --file-allocation=none -o "$(basename "$dest")" -d "$(dirname "$dest")" "$url"
  echo "$expected  $dest" | sha256sum -c -
}

download_checked "$CHECKPOINT_URL" "$COMFY_DIR/models/checkpoints/$COMFYUI_CHECKPOINT" "$CHECKPOINT_SHA256"
download_checked "$LORA_URL" "$COMFY_DIR/models/loras/$COMFYUI_ANGLES_LORA" "$LORA_SHA256"

echo "[setup] starting ComfyUI"
pkill -f "ComfyUI/main.py" || true
nohup python "$COMFY_DIR/main.py" --listen 0.0.0.0 --port 8188 > "$LOG_DIR/comfyui.log" 2>&1 &

echo "[setup] waiting for ComfyUI"
for _ in $(seq 1 180); do
  if curl -fsS http://127.0.0.1:8188/system_stats >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:8188/system_stats >/dev/null

echo "[setup] starting qwen wrapper server"
pkill -f "uvicorn qwen_server:app" || true
cd "$PYWORKER_DIR"
nohup uvicorn qwen_server:app --host 127.0.0.1 --port 18000 > "$LOG_DIR/qwen-server.log" 2>&1 &

for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:18000/health >/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:18000/health

echo "[setup] starting Vast PyWorker"
exec python "$PYWORKER_DIR/worker.py"
