#!/usr/bin/env bash
set -euo pipefail

cd /workspace
if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends git ca-certificates
fi

if [ ! -d makaron-vast-qwen-serverless/.git ]; then
  git clone https://github.com/vegekyd-sys/makaron-vast-qwen-serverless.git makaron-vast-qwen-serverless
else
  git -C makaron-vast-qwen-serverless pull --ff-only
fi

exec bash /workspace/makaron-vast-qwen-serverless/setup.sh
