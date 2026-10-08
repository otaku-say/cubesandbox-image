#!/usr/bin/env bash
# =============================================================================
# 镜像构建与本地冒烟测试脚本
# 用法:
#   ./build.sh          构建本地测试镜像并执行冒烟测试
#   ./build.sh --push   构建、冒烟测试并推送到 GHCR
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-default:latest}"
LOCAL_TAG="csi-test/agent-infra/aio-default:test"

echo "== [1/2] 构建 Docker 镜像 =="
docker build -t "${LOCAL_TAG}" .

echo "== [2/2] 冒烟测试 =="
bash ./smoke-test.sh "${LOCAL_TAG}"

if [ "${1:-}" = "--push" ]; then
    echo "== 推送至目标镜像仓库 =="
    docker tag "${LOCAL_TAG}" "${IMAGE}"
    docker push "${IMAGE}"
    echo "✔ 已推送 ${IMAGE}"
else
    echo "✔ 本地镜像就绪且测试通过：${LOCAL_TAG}（带 --push 可推送）"
fi
