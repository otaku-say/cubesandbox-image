#!/usr/bin/env bash
# 本机构建 / 冒烟 / 推送（CI 会自动做同样的事；本脚本用于本地或控制节点）
#   ./build.sh            构建 + 冒烟测试
#   ./build.sh --push     构建 + 冒烟测试 + 推送 :latest
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-code:latest}"
LOCAL_TAG="csi-test/agent-infra/aio-code:test"

# base 来自 GHCR 官方（公开，匿名可拉）；aiod / Node / Zig / yq / gh 等
# 均来自公开 CDN 或 GitHub Releases（构建时校验 SHA256）

docker build -t "${LOCAL_TAG}" .
bash ./smoke-test.sh "${LOCAL_TAG}"

if [ "${1:-}" = "--push" ]; then
    docker tag "${LOCAL_TAG}" "${IMAGE}"
    docker push "${IMAGE}"
    echo "✔ 已推送 ${IMAGE}"
else
    echo "✔ 本地镜像就绪：${LOCAL_TAG}（加 --push 可推送到 ${IMAGE}）"
fi
