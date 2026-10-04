#!/usr/bin/env bash
# =============================================================================
# 冒烟测试（aio-code：cubesandbox-base + aiod + 代码工具链）
#   envd 契约 → aiod 双面 API → 执行面 → 能力面 → 工具链（python/node/zig/
#   shellcheck/gdb/strace…）→ 端口监听 → 体积
# 用法: smoke-test.sh <image>          （需本机 docker）
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiocode-smoke-$$"

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== 启动容器 ${NAME}（${IMG}） =="
docker run -d --name "${NAME}" -p 49983:49983 -p 8080:8080 "${IMG}" >/dev/null

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

echo "[1/7] envd 契约（平台模板探针同口径）"
need "envd :49983/health" "http://127.0.0.1:49983/health" 204 60

echo "[2/7] aiod 守护进程（:8080，AIO_PORT 生效）"
need "aiod :8080/health" "http://127.0.0.1:8080/health" 200 60
v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/capabilities)"
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v2/sandbox)"
echo "  v1 /v1/capabilities => ${v1}；v2 /v2/sandbox => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }
if curl -s -o /dev/null --max-time 2 http://127.0.0.1:18091/health; then
    echo "  ✘ 18091 仍在监听（端口应只走 8080）" >&2; exit 1
else
    echo "  ✔ 18091 未监听（旧端口已移除）"
fi

echo "[3/7] 执行面（v2 + v1）"
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' \
    -d '{"command":"echo UID=$(id -u); echo smoke-ok; uname -m"}')"
printf '%s' "${out}" | grep -q "smoke-ok" && echo "  ✔ /v2/commands" || { echo "  ✘ /v2/commands: ${out}" >&2; exit 1; }
curl -fsS -X POST http://127.0.0.1:8080/v1/bash/exec -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok"}' | grep -q "v1-ok" && echo "  ✔ /v1/bash/exec"
uid="$(printf '%s' "${out}" | grep -o 'UID=[0-9][0-9]*' | head -1 || true)"
echo "  执行账户 ${uid:-UID=未捕获}（期望 UID=0）"

echo "[4/7] 能力面（?refresh=true 绕开 5s 缓存）"
curl -fsS "http://127.0.0.1:8080/v1/capabilities?refresh=true" -o "/tmp/aiocode-caps-$$.json"
python3 - "/tmp/aiocode-caps-$$.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
ci, br, co = d.get("code_interpreter", {}), d.get("browser", {}), d.get("computer", {})
print("  code_interpreter:", ci.get("status"), "kinds=", ci.get("kinds"), "missing=", ci.get("missing"))
print("  browser:", br.get("status"), "（预期 absent/degraded：轻量镜像无 Chromium）")
print("  computer:", co.get("status"), "（预期 absent）")
PY
rm -f "/tmp/aiocode-caps-$$.json"

echo "[5/7] 工具链（版本 + 功能）"
docker exec "${NAME}" bash -c '
set -e
for c in python3 pip uv node npm zig git jq yq rg fd gh shellcheck gdb strace sqlite3 vim; do
    command -v "$c" >/dev/null 2>&1 || { echo "  BAD: 缺少命令 $c" >&2; exit 1; }
done
echo "  python3:    $(python3 -V 2>&1)"
echo "  pip:        $(pip --version)"
echo "  uv:         $(uv --version)"
echo "  node:       $(node -v)"
echo "  npm:        $(npm -v)"
echo "  zig:        $(zig version)"
echo "  git:        $(git --version)"
echo "  rg/fd:      $(rg --version | head -n1) / $(fd --version)"
echo "  jq/yq:      $(jq --version) / $(yq --version)"
echo "  gh:         $(gh --version | head -n1)"
echo "  shellcheck: $(shellcheck --version | grep version:)"
echo "  gdb:        $(gdb --version | head -n1)"
echo "  strace:     $(strace -V 2>&1 | head -n1)"
echo "  sqlite3:    $(sqlite3 --version | cut -d" " -f1)"
echo "  vim/xxd:    $(vim --version | head -n1) / $(xxd -h 2>&1 | head -n1 || true)"
if command -v python3.10 >/dev/null 2>&1; then
    echo "  WARN: 存在 python3.10 二进制（预期不应出现）"
else
    echo "  OK 无其他 python 解释器版本"
fi
python3 - <<\PY
import sys
assert sys.version_info[:2] == (3, 12), "python != 3.12: " + sys.version
print("  OK python3 = 3.12（唯一版本，默认）")
PY
node -e "if(!process.versions.node.startsWith(\"24\")) throw new Error(process.versions.node); console.log(\"  OK node = 24 LTS\")"
zig version | grep -q "^0.17[.]0$" || { echo "  BAD: zig 版本异常" >&2; exit 1; }
echo "  OK zig = 0.17.0"
cd /tmp && rm -rf smoke-sc && mkdir smoke-sc && cd smoke-sc
printf "#!/bin/sh\necho \"\$1\"\n" > good.sh
printf "#!/bin/sh\necho \$1\n" > bad.sh
shellcheck good.sh
if shellcheck bad.sh >/dev/null 2>&1; then echo "  BAD: shellcheck 未能发现 bad.sh 的问题" >&2; exit 1; fi
echo "  OK shellcheck（good 通过 / bad 正确报错）"
printf "#include <stdio.h>\nint main(){puts(\"zigcc-ok\");return 0;}\n" > hello.c
zig cc hello.c -o hello
./hello | grep -q zigcc-ok || { echo "  BAD: zig cc 编译产物运行失败" >&2; exit 1; }
echo "  OK zig cc 编译 C 并运行（应急编译通道）"
python3 -m venv /tmp/smoke-sc/venv
/tmp/smoke-sc/venv/bin/python -V
/tmp/smoke-sc/venv/bin/pip --version | head -n1
echo "  OK venv（venv 内自带 pip）"
strace -o /dev/null /bin/true
echo "  OK strace"
gdb -batch -ex "run" /tmp/smoke-sc/hello 2>/dev/null | grep -q zigcc-ok || { echo "  BAD: gdb 运行失败" >&2; exit 1; }
echo "  OK gdb（载入并运行）"
aiod doctor --json 2>&1 | head -c 300 | sed "s/^/    /" || true
'

echo "[6/7] 端口监听（ss）"
docker exec "${NAME}" bash -c 'ss -tln | grep -E ":(49983|8080)\b" || { echo "缺少监听端口" >&2; exit 1; }' | sed "s/^/  /"
echo "  ✔ 49983 + 8080 均在监听"

echo "[7/7] 体积"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  镜像体积: %.2f GB（解压后）\n", s/1024/1024/1024 }'

echo "✔ 冒烟测试全部通过：${IMG}"
