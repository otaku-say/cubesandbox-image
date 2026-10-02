#!/usr/bin/env bash
# 本地构建并推送（GitHub Actions 也会自动构建；本脚本用于本地/控制节点应急）
# 需先: docker login ghcr.io -u <user> -p <token>
set -euo pipefail
cd "$(dirname "$0")"
IMAGE="ghcr.io/otaku-say/cubesandbox-image/agent-infra/sandbox:latest"
docker build -t "$IMAGE" .
docker push "$IMAGE"
echo "✔ 已推送 $IMAGE"
