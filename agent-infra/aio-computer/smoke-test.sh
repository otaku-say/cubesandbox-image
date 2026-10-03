#!/usr/bin/env bash
# =============================================================================
# 冒烟测试（aio-computer 套壳）：envd → 网关 → v1/v2 双面 → **computer-use 面**
# 用法: smoke-test.sh <image>          （需本机有 docker）
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aioc-smoke-$$"
ENVD_HOST_PORT="${ENVD_HOST_PORT:-49983}"
CANDIDATE_PORTS=("${AIO_PORT:-}" 8080 8091)

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 启动容器 ${NAME}（${IMG}） =="
docker run -d --name "${NAME}" \
    -p "${ENVD_HOST_PORT}:49983" -p 8080:8080 -p 8091:8091 "${IMG}" >/dev/null

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
    docker logs "${NAME}" 2>&1 | tail -n 60 >&2
    return 1
}

echo "[1/6] envd 契约"
need "envd :49983/health" "http://127.0.0.1:${ENVD_HOST_PORT}/health" 204 60

echo "[2/6] 网关端口发现 + AIO API 就绪（最多 180s；桌面镜像启动更慢）"
AIO=""
deadline=$((SECONDS + 180))
while [ "${SECONDS}" -lt "${deadline}" ]; do
    for p in "${CANDIDATE_PORTS[@]}"; do
        [ -z "${p}" ] && continue
        code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${p}/v1/capabilities" || true)"
        if [ "${code}" = "200" ]; then
            AIO="http://127.0.0.1:${p}"
            echo "  ✔ 网关在宿主端口 ${p} 上服务"
            break 2
        fi
    done
    sleep 5
done
[ -n "${AIO}" ] || { echo "  ✘ 8080/8091 均未就绪" >&2; docker logs "${NAME}" | tail -n 60 >&2; exit 1; }

echo "[3/6] 双面 API 核对"
v1="$(curl -s -o /dev/null -w '%{http_code}' "${AIO}/v1/capabilities")"
v2="$(curl -s -o /dev/null -w '%{http_code}' "${AIO}/v2/sandbox")"
echo "  v1 /v1/capabilities => ${v1}"; echo "  v2 /v2/sandbox      => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }

echo "[4/6] **computer-use 面**（本镜像的核心差异，必须可用）"
need "GET /v2/computer/info" "${AIO}/v2/computer/info" 200 120
curl -fsS "${AIO}/v2/computer/info" | python3 -c '
import json, sys
d = json.load(sys.stdin)
data = d.get("data", {})
print("  显示器:", {k: data.get(k) for k in ("width", "height", "display", "backend") if data.get(k) is not None})
' || true
shot_code="$(curl -s -o /tmp/aioc-shot.png -w '%{http_code}' "${AIO}/v2/computer/screenshot")"
if [ "${shot_code}" = "200" ] && head -c 8 /tmp/aioc-shot.png | grep -q PNG; then
    echo "  ✔ GET /v2/computer/screenshot => 200（PNG，$(wc -c < /tmp/aioc-shot.png) 字节）"
else
    echo "  ✘ 桌面截图失败（HTTP ${shot_code}）" >&2; exit 1
fi
for ep in cursor clipboard windows accessibility; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "${AIO}/v2/computer/${ep}")"
    echo "  · /v2/computer/${ep} => ${code}"
done

echo "[5/6] 能力与功能抽查"
curl -fsS "${AIO}/v1/capabilities" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
print("  browser:", d.get("browser", {}).get("status"),
      "| code_interpreter:", d.get("code_interpreter", {}).get("status"),
      "| computer:", (d.get("computer") or {}).get("status"))
'
curl -fsS -X POST "${AIO}/v2/commands" -H 'Content-Type: application/json' \
    -d '{"command":"echo smoke-ok"}' | grep -q "smoke-ok" && echo "  ✔ /v2/commands"

echo "[6/6] 体积"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  镜像体积: %.2f GB\n", s/1024/1024/1024 }'

echo "✔ 冒烟测试全部通过：${IMG}（网关端口 ${AIO##*:}）"
