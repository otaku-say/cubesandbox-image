#!/usr/bin/env bash
# =============================================================================
# 冒烟测试（aio-code：官方 sandbox-code + aiod）
#   envd 契约 → aiod 存活/双面 API → 执行面 → 能力面 → Jupyter+工具集 → 体积
# 用法: smoke-test.sh <image>          （需本机有 docker）
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiocode-smoke-$$"

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 启动容器 ${NAME}（${IMG}） =="
docker run -d --name "${NAME}" \
    -p 49983:49983 -p 49999:49999 -p 18091:18091 "${IMG}" >/dev/null

# need <说明> <url> <期望状态码> [超时秒]
need() {
    local desc="$1" url="$2" want="$3" limit="${4:-60}" i code
    for i in $(seq 1 "${limit}"); do
        code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
        if [ "${code}" = "${want}" ]; then
            echo "  ✔ ${desc} => ${code}（${i}s）"
            return 0
        fi
        sleep 1
    done
    echo "  ✘ ${desc} => ${code:-无响应}（期望 ${want}）" >&2
    docker logs "${NAME}" 2>&1 | tail -n 40 >&2
    return 1
}

echo "[1/6] envd 契约（平台模板探针同口径）"
need "envd :49983/health" "http://127.0.0.1:49983/health" 204 60

echo "[2/6] aiod 守护进程（:18091）"
need "aiod /health" "http://127.0.0.1:18091/health" 200 60
v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18091/v1/capabilities)"
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18091/v2/sandbox)"
echo "  v1 /v1/capabilities => ${v1}"
echo "  v2 /v2/sandbox      => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }

echo "[3/6] 执行面（v2 + v1）"
out="$(curl -fsS -X POST http://127.0.0.1:18091/v2/commands -H 'Content-Type: application/json' \
    -d '{"command":"echo UID=$(id -u); echo smoke-ok; uname -m"}')"
printf '%s' "${out}" | grep -q "smoke-ok" && echo "  ✔ /v2/commands" || { echo "  ✘ /v2/commands: ${out}" >&2; exit 1; }
curl -fsS -X POST http://127.0.0.1:18091/v1/bash/exec -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok"}' | grep -q "v1-ok" && echo "  ✔ /v1/bash/exec"
# 执行账户（base 以 root 运行，aiod 应同样以 root 执行命令）
uid="$(printf '%s' "${out}" | grep -o 'UID=[0-9][0-9]*' | head -1 || true)"
echo "  执行账户 ${uid:-UID=未捕获}（期望 UID=0）"

echo "[4/6] 能力面（?refresh=true 强制新探测，绕开 5s 缓存）"
curl -fsS "http://127.0.0.1:18091/v1/capabilities?refresh=true" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
ci, br, co = d.get("code_interpreter", {}), d.get("browser", {}), d.get("computer", {})
print("  code_interpreter:", ci.get("status"), "kinds=", ci.get("kinds"))
print("  browser:", br.get("status"), "（轻量镜像预期 absent/degraded）")
print("  computer:", co.get("status"), "（轻量镜像预期 absent）")
'
echo "  code-interpreter :49999 => $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:49999/ || true)"
echo "  aiod doctor（探测 bash/rg/tmux/浏览器进程/CDP 端口）:"
docker exec "${NAME}" /usr/local/bin/aiod doctor --json 2>&1 | head -c 800 | sed 's/^/    /' || true
echo

echo "[5/6] Jupyter(loopback) + 工具集"
jcode=000
for i in $(seq 1 60); do
    jcode="$(docker exec "${NAME}" curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8888/api/status || true)"
    [ "${jcode}" = "200" ] && break
    sleep 1
done
echo "  jupyter 127.0.0.1:8888/api/status => ${jcode}（期望 200，等待 ${i}s）"
if [ "${jcode}" != "200" ]; then
    echo "  ✘ Jupyter 未就绪 —— 排障输出：" >&2
    docker logs "${NAME}" 2>&1 | tail -n 30 >&2
    echo "  ---- /var/log/jupyter.log ----" >&2
    docker exec "${NAME}" tail -n 40 /var/log/jupyter.log 2>&1 >&2 || true
    echo "  ---- 进程表 ----" >&2
    docker exec "${NAME}" ps aux 2>&1 | head -n 20 >&2 || true
    exit 1
fi
docker exec "${NAME}" bash -lc '
    set -e
    python3 -V
    node --version
    git --version >/dev/null && jq --version >/dev/null && rg --version >/dev/null
    tmux -V
    /usr/local/bin/aiod version
' | sed 's/^/  /'

echo "[6/6] 体积"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  镜像体积: %.2f GB（解压后）\n", s/1024/1024/1024 }'

echo "✔ 冒烟测试全部通过：${IMG}"
