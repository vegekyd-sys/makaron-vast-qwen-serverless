#!/usr/bin/env bash
set -euo pipefail

export COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
export PYWORKER_DIR="${PYWORKER_DIR:-/workspace/makaron-vast-qwen-serverless}"
export LOG_DIR="${LOG_DIR:-/var/log/makaron-qwen}"
export WORKER_PORT="${WORKER_PORT:-8000}"
export COMFYUI_CHECKPOINT="${COMFYUI_CHECKPOINT:-Qwen-Rapid-AIO-NSFW-v23.safetensors}"
export COMFYUI_ANGLES_LORA="${COMFYUI_ANGLES_LORA:-qwen-image-edit-2511-multiple-angles-lora.safetensors}"

mkdir -p "$LOG_DIR"

echo "[start] starting ComfyUI"
pkill -f "ComfyUI/main.py" || true
nohup python "$COMFY_DIR/main.py" --listen 0.0.0.0 --port 8188 > "$LOG_DIR/comfyui.log" 2>&1 &

echo "[start] waiting for ComfyUI"
for _ in $(seq 1 180); do
  if curl -fsS http://127.0.0.1:8188/system_stats >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:8188/system_stats >/dev/null

echo "[start] starting qwen wrapper server"
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

echo "[start] starting Vast PyWorker"
exec python "$PYWORKER_DIR/worker.py"
