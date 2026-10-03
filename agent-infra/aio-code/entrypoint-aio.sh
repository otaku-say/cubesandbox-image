#!/bin/sh
# =============================================================================
# aio-code 启动包装：tini → 本脚本
#   ① 后台运行原 CMD（默认 start-lightweight-code-interpreter.sh：
#      起 envd:49983 + Jupyter:8888(loopback) + code-interpreter:49999）
#   ② 受监管运行 aiod start（默认 :18091；AIO_PORT/AIO_HOST 可改）
#   任一进程退出 → 全部终止 → 容器退出（交给平台重建）
# =============================================================================
set -u

echo "[aio-code] service tree: $*"
"$@" &
TREE=$!

AIO_PORT="${AIO_PORT:-18091}"
echo "[aio-code] aiod start (AIO_HOST=${AIO_HOST:-0.0.0.0} AIO_PORT=${AIO_PORT})"
AIO_PORT="${AIO_PORT}" /usr/local/bin/aiod start &
AIOD=$!

term() {
    echo "[aio-code] TERM received → stopping aiod(${AIOD}) and tree(${TREE})"
    kill -TERM "${AIOD}" "${TREE}" 2>/dev/null || true
}
trap term TERM INT

# 等待任一进程结束（两者都活着才继续等）
while kill -0 "${TREE}" 2>/dev/null && kill -0 "${AIOD}" 2>/dev/null; do
    sleep 1
done

wait || true
exit 1
