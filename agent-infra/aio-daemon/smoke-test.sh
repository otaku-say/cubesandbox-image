#!/usr/bin/env bash
# =============================================================================
# 冒烟测试（aio-daemon 套壳）：envd 契约 → 网关端口发现 → v1/v2 双面 → 能力
# 用法: smoke-test.sh <image>          （需本机有 docker）
# 说明: 上游 1.0.1 的网关端口与文档不一致（banner 指向 8080，文档写 8091），
#       因此这里同时发布 8080/8091，运行时探测哪个在服务。
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiod2-smoke-$$"
ENVD_HOST_PORT="${ENVD_HOST_PORT:-49983}"
CANDIDATE_PORTS=("${AIO_PORT:-}" 8080 8091)

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 启动容器 ${NAME}（${IMG}） =="
docker run -d --name "${NAME}" \
    -p "${ENVD_HOST_PORT}:49983" -p 8080:8080 -p 8091:8091 "${IMG}" >/dev/null

# need <说明> <url> <期望状态码> [超时秒]
need() {
    local desc="$1" url="$2" want="$3" limit="${4:-90}" i code
    for i in $(seq 1 "${limit}"); do
        code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
        if [ "${code}" = "${want}" ]; then
            echo "  ✔ ${desc} => ${code}（${i}s）"
            return 0
        fi
        sleep 1
    done
    echo "  ✘ ${desc} => ${code:-无响应}（期望 ${want}）" >&2
    docker logs "${NAME}" 2>&1 | grep -aiE "error|fail|banner|listening|Dashboard" | tail -n 30 >&2
    return 1
}

echo "[1/5] envd 契约"
need "envd :49983/health" "http://127.0.0.1:${ENVD_HOST_PORT}/health" 204 60

echo "[2/5] 网关端口发现 + AIO API 就绪（最多 150s）"
AIO=""
deadline=$((SECONDS + 150))
while [ "${SECONDS}" -lt "${deadline}" ]; do
    for p in "${CANDIDATE_PORTS[@]}"; do
        [ -z "${p}" ] && continue
        code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${p}/v1/capabilities" || true)"
        if [ "${code}" = "200" ]; then
            AIO="http://127.0.0.1:${p}"
            echo "  ✔ 网关在宿主端口 ${p} 上服务（/v1/capabilities => 200）"
            break 2
        fi
    done
    sleep 5
done
if [ -z "${AIO}" ]; then
    echo "  ✘ 8080/8091 均未就绪" >&2
    docker logs "${NAME}" 2>&1 | tail -n 60 >&2
    exit 1
fi

echo "[3/5] API 面核对：v1 与 v2 都必须存在"
v1="$(curl -s -o /dev/null -w '%{http_code}' "${AIO}/v1/capabilities")"
v2="$(curl -s -o /dev/null -w '%{http_code}' "${AIO}/v2/sandbox")"
echo "  v1 /v1/capabilities => ${v1}"
echo "  v2 /v2/sandbox      => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }

echo "[4/5] 能力与功能抽查"
curl -fsS "${AIO}/v1/capabilities" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
b, ci = d.get("browser", {}), d.get("code_interpreter", {})
print("  browser:", b.get("status"), "| code_interpreter:", ci.get("status"), "| kinds:", ci.get("kinds"))
'
cmd_out="$(curl -fsS -X POST "${AIO}/v2/commands" -H 'Content-Type: application/json' \
    -d '{"command":"id -u; echo smoke-ok"}')"
printf '%s' "${cmd_out}" | grep -q "smoke-ok" && echo "  ✔ /v2/commands"
curl -fsS -X POST "${AIO}/v1/bash/exec" -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok"}' | grep -q "v1-ok" && echo "  ✔ /v1/bash/exec"

echo "[5/5] 体积"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  镜像体积: %.2f GB\n", s/1024/1024/1024 }'

echo "✔ 冒烟测试全部通过：${IMG}（AIO 网关宿主端口：${AIO##*:}）"
