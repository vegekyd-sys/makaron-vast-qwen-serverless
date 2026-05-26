import base64
import io
import os
import random
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import requests
from fastapi import FastAPI, HTTPException
from PIL import Image


COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8188").rstrip("/")
COMFY_DIR = Path(os.environ.get("COMFY_DIR", "/workspace/ComfyUI"))
CHECKPOINT = os.environ.get("COMFYUI_CHECKPOINT", "Qwen-Rapid-AIO-NSFW-v23.safetensors")
ANGLES_LORA = os.environ.get(
    "COMFYUI_ANGLES_LORA",
    "qwen-image-edit-2511-multiple-angles-lora.safetensors",
)
INPUT_DIR = COMFY_DIR / "input"

app = FastAPI()


def _resolve_image_to_bytes(image: str) -> bytes:
    if image.startswith("http://") or image.startswith("https://"):
        res = requests.get(image, timeout=120)
        res.raise_for_status()
        raw = res.content
    else:
        payload = image.split(",", 1)[1] if image.startswith("data:image/") else image
        raw = base64.b64decode(payload)

    with Image.open(io.BytesIO(raw)) as im:
        im = im.convert("RGB")
        im.thumbnail((2048, 2048))
        out = io.BytesIO()
        im.save(out, format="JPEG", quality=90)
        return out.getvalue()


def _write_input(image: str, prefix: str) -> str:
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    name = f"{prefix}_{int(time.time() * 1000)}_{random.randint(1000, 9999)}.jpg"
    path = INPUT_DIR / name
    path.write_bytes(_resolve_image_to_bytes(image))
    return name


def _build_workflow(
    image_names: list[str],
    prompt: str,
    seed: int | None = None,
    rotate: bool = False,
    width: int = 0,
    height: int = 0,
) -> dict[str, Any]:
    actual_seed = seed if seed is not None else random.randint(1, 999999999)
    workflow: dict[str, Any] = {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "5": {
            "class_type": "QwenImageIntegratedKSampler",
            "inputs": {
                "model": ["2", 0] if rotate else ["1", 0],
                "clip": ["1", 1],
                "vae": ["1", 2],
                "positive_prompt": prompt,
                "negative_prompt": "",
                "generation_mode": "图生图 image-to-image" if image_names else "文生图 text-to-image",
                "batch_size": 1,
                "width": width,
                "height": height,
                "seed": actual_seed,
                "steps": 4,
                "cfg": 1.0,
                "sampler_name": "euler",
                "scheduler": "simple",
                "denoise": 1.0,
                "auraflow_shift": 3.0,
                "cfg_norm_strength": 1.0,
            },
        },
        "6": {"class_type": "SaveImage", "inputs": {"images": ["5", 0], "filename_prefix": "api_output"}},
    }

    if rotate:
        workflow["2"] = {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["1", 0], "lora_name": ANGLES_LORA, "strength_model": 1.0},
        }

    for idx, image_name in enumerate(image_names[:5], start=1):
        node_id = str(10 + idx)
        workflow[node_id] = {"class_type": "LoadImage", "inputs": {"image": image_name}}
        workflow["5"]["inputs"][f"image{idx}"] = [node_id, 0]

    return workflow


def _submit_and_wait(workflow: dict[str, Any], timeout_s: int = 300) -> dict[str, str]:
    submit = requests.post(f"{COMFY_URL}/prompt", json={"prompt": workflow}, timeout=30)
    submit.raise_for_status()
    prompt_id = submit.json()["prompt_id"]
    deadline = time.time() + timeout_s

    while time.time() < deadline:
        hist = requests.get(f"{COMFY_URL}/history/{prompt_id}", timeout=30)
        hist.raise_for_status()
        data = hist.json()
        if prompt_id in data:
            entry = data[prompt_id]
            status = entry.get("status", {}).get("status_str")
            if status == "error":
                raise RuntimeError(str(entry.get("status", {}).get("messages", ""))[:1000])
            for output in entry.get("outputs", {}).values():
                images = output.get("images") or []
                if images:
                    return images[0]
        time.sleep(1)

    raise TimeoutError(f"ComfyUI job timed out after {timeout_s}s")


def _download_image(image_meta: dict[str, str]) -> str:
    params = urlencode(
        {
            "filename": image_meta["filename"],
            "subfolder": image_meta.get("subfolder", ""),
            "type": image_meta.get("type", "output"),
        }
    )
    res = requests.get(f"{COMFY_URL}/view?{params}", timeout=120)
    res.raise_for_status()
    with Image.open(io.BytesIO(res.content)) as im:
        im = im.convert("RGB")
        out = io.BytesIO()
        im.save(out, format="JPEG", quality=92)
    return "data:image/jpeg;base64," + base64.b64encode(out.getvalue()).decode("ascii")


def _generate(payload: dict[str, Any], warmup: bool = False) -> dict[str, Any]:
    prompt = payload.get("prompt") or "a simple red apple on a plain white background"
    seed = payload.get("seed")
    rotate = bool(payload.get("rotate"))
    images = payload.get("images") or payload.get("image_urls") or []
    if payload.get("image"):
        images = [payload["image"], *images]
    if warmup:
        images = []
        payload.setdefault("width", 512)
        payload.setdefault("height", 512)

    image_names = [_write_input(img["url"] if isinstance(img, dict) else img, "input") for img in images[:5]]
    workflow = _build_workflow(
        image_names,
        prompt,
        seed=seed,
        rotate=rotate,
        width=int(payload.get("width", 0)),
        height=int(payload.get("height", 0)),
    )
    t0 = time.time()
    image_meta = _submit_and_wait(workflow, timeout_s=int(payload.get("timeout_s", 300)))
    image = _download_image(image_meta)
    return {
        "image": image,
        "model": "qwen",
        "checkpoint": CHECKPOINT,
        "rotate": rotate,
        "elapsed_s": round(time.time() - t0, 2),
    }


@app.get("/health")
def health() -> dict[str, Any]:
    checkpoint_path = COMFY_DIR / "models" / "checkpoints" / CHECKPOINT
    lora_path = COMFY_DIR / "models" / "loras" / ANGLES_LORA
    return {
        "ok": checkpoint_path.exists(),
        "checkpoint": CHECKPOINT,
        "checkpoint_exists": checkpoint_path.exists(),
        "lora_exists": lora_path.exists(),
    }


@app.post("/warmup")
def warmup(payload: dict[str, Any] | None = None) -> dict[str, Any]:
    try:
        return _generate(payload or {}, warmup=True)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/generate")
def generate(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return _generate(payload)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

