#!/usr/bin/env bash
# =============================================================================
# 冒烟测试（aio-code-light：cubesandbox-base + aiod + 极简通用开发工具链）
#   测试项：envd 探针 → aiod 双面 API → 命令执行 → 能力面 → 工具链完整性 → 端口 → 体积
# 用法: smoke-test.sh <image>
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiocode-smoke-$$"

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 启动测试容器 ${NAME}（${IMG}） =="
docker run -d --name "${NAME}" -p 49983:49983 -p 8080:8080 "${IMG}" >/dev/null

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

echo "[1/7] envd 契约（平台探针同口径）"
need "envd :49983/health" "http://127.0.0.1:49983/health" 204 60

echo "[2/7] aiod 守护进程（:8080，AIO_PORT 生效）"
need "aiod :8080/health" "http://127.0.0.1:8080/health" 200 60
v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/capabilities)"
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v2/sandbox)"
echo "  v1 /v1/capabilities => ${v1}；v2 /v2/sandbox => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }

echo "[3/7] 执行面（v2 + v1）"
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' \
    -d '{"command":"echo UID=$(id -u); echo smoke-ok; uname -m"}')"
printf '%s' "${out}" | grep -q "smoke-ok" && echo "  ✔ /v2/commands" || { echo "  ✘ /v2/commands: ${out}" >&2; exit 1; }
curl -fsS -X POST http://127.0.0.1:8080/v1/bash/exec -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok"}' | grep -q "v1-ok" && echo "  ✔ /v1/bash/exec"

echo "[4/7] 能力面（?refresh=true 绕开 5s 缓存）"
curl -fsS "http://127.0.0.1:8080/v1/capabilities?refresh=true" -o "/tmp/aiocode-caps-$$.json"
python3 - "/tmp/aiocode-caps-$$.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
ci, br, co = d.get("code_interpreter", {}), d.get("browser", {}), d.get("computer", {})
print("  code_interpreter:", ci.get("status"), "kinds=", ci.get("kinds"))
print("  browser:", br.get("status"), "（预期 absent：轻量无头镜像）")
print("  computer:", co.get("status"), "（预期 absent）")
PY
rm -f "/tmp/aiocode-caps-$$.json"

echo "[5/7] 工具链检查（版本 + 编译验证）"
docker exec "${NAME}" bash -c '
set -e
# 校验核心命令就绪状态
for c in python3 pip uv zig cc git jq yq rg fd gh shellcheck strace sqlite3 vim bat socat pkg-config; do
    command -v "$c" >/dev/null 2>&1 || { echo "  BAD: 缺少必要命令 $c" >&2; exit 1; }
done

echo "  python3:    $(python3 -V 2>&1)"
echo "  uv:         $(uv --version)"
echo "  zig:        $(zig version)"
echo "  cc wrapper: $(cc --version | head -n1)"
echo "  git/gh:     $(git --version) / $(gh --version | head -n1)"
echo "  rg/fd/bat:  $(rg --version | head -n1) / $(fd --version) / $(bat --version)"
echo "  shellcheck: $(shellcheck --version | grep version:)"

# 确认 Node.js 已完全剥离
if command -v node >/dev/null 2>&1; then
    echo "  BAD: 检测到残留 node 二进制，不符合轻量预期" >&2; exit 1;
else
    echo "  OK Node.js 已剥离（零 V8 运行时内存开销）"
fi

# 确认 Python 版本唯一性
python3 - <<\PY
import sys
assert sys.version_info[:2] == (3, 12), "python != 3.12: " + sys.version
print("  OK python3 = 3.12（单一干净环境）")
PY

# 应急 C 编译器与 Zig 编译链路验证
cd /tmp && rm -rf smoke-test-build && mkdir smoke-test-build && cd smoke-test-build
printf "#include <stdio.h>\nint main(){puts(\"cc-wrapper-ok\");return 0;}\n" > hello.c
cc hello.c -o hello
./hello | grep -q "cc-wrapper-ok"
echo "  OK cc -> zig cc 包装调用编译运行成功"

# uv 临时测试运行环境验证（免全局污染）
uv run --with pytest python -c "import pytest; print(\"  OK uv 临时环境依赖拉取与执行正常\")"
'

echo "[6/7] 端口监听（ss）"
docker exec "${NAME}" bash -c 'ss -tln | grep -E ":(49983|8080)\b" || { echo "缺少监听端口" >&2; exit 1; }' | sed "s/^/  /"
echo "  ✔ 49983 + 8080 均处于监听状态"

echo "[7/7] 镜像体积评估"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  解压后体积: %.2f GB\n", s/1024/1024/1024 }'

echo "✔ 冒烟测试全部通过：${IMG}"
