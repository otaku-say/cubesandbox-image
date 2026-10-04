#!/usr/bin/env bash
# =============================================================================
# 作者: DevOps Team
# 创建时间: 2026-10-04
# 功能简述: aio-code-light 沙箱冒烟测试脚本
#           兼容动态版本工具链：覆盖 envd 探针、aiod 双面 API、命令执行面、
#           动态最新版工具可用性、C/Zig 应急编译、uv 运行环境及镜像体积检测
# 用法: ./smoke-test.sh <image>
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiocode-smoke-$$"

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== [1/7] 启动测试容器 ${NAME} (${IMG}) =="
docker run -d --name "${NAME}" -p 49983:49983 -p 8080:8080 "${IMG}" >/dev/null

need() {
    local desc="$1" url="$2" want="$3" limit="${4:-60}" i code
    for i in $(seq 1 "${limit}"); do
        code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
        if [ "${code}" = "${want}" ]; then
            echo "  ✔ ${desc} => ${code} (${i}s)"
            return 0
        fi
        sleep 1
    done
    echo "  ✘ ${desc} => ${code:-无响应} (期望 ${want})" >&2
    docker logs "${NAME}" 2>&1 | tail -n 40 >&2
    return 1
}

echo "== [2/7] 验证平台探针与 aiod 守护进程 =="
need "envd :49983/health (平台探针)" "http://127.0.0.1:49983/health" 204 60
need "aiod :8080/health (AIO Daemon)" "http://127.0.0.1:8080/health" 200 60

v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/capabilities)"
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v2/sandbox)"
echo "  v1 /v1/capabilities => ${v1}；v2 /v2/sandbox => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }

if curl -s -o /dev/null --max-time 2 http://127.0.0.1:18091/health; then
    echo "  ✘ 18091 仍处于监听状态 (端口应已统一至 8080)" >&2
    exit 1
else
    echo "  ✔ 18091 未监听 (符合单端口收敛预期)"
fi

echo "== [3/7] 验证命令执行通道 (v1 + v2) =="
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' \
    -d '{"command":"echo UID=$(id -u); echo smoke-ok; uname -m"}')"
printf '%s' "${out}" | grep -q "smoke-ok" && echo "  ✔ /v2/commands 执行正常" || { echo "  ✘ /v2/commands: ${out}" >&2; exit 1; }

curl -fsS -X POST http://127.0.0.1:8080/v1/bash/exec -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok"}' | grep -q "v1-ok" && echo "  ✔ /v1/bash/exec 执行正常"

uid="$(printf '%s' "${out}" | grep -o 'UID=[0-9][0-9]*' | head -1 || true)"
echo "  执行账户: ${uid:-UID=未捕获} (期望 UID=0)"

echo "== [4/7] 检查沙箱能力声明 =="
curl -fsS "http://127.0.0.1:8080/v1/capabilities?refresh=true" -o "/tmp/aiocode-caps-$$.json"
python3 - "/tmp/aiocode-caps-$$.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["data"]
ci, br, co = d.get("code_interpreter", {}), d.get("browser", {}), d.get("computer", {})
print("  code_interpreter:", ci.get("status"), "kinds=", ci.get("kinds"))
print("  browser:", br.get("status"), "（预期 absent：无浏览器轻量环境）")
print("  computer:", co.get("status"), "（预期 absent：无桌面环境）")
PY
rm -f "/tmp/aiocode-caps-$$.json"

echo "== [5/7] 容器内动态工具链与编译验证 =="
docker exec "${NAME}" bash -c '
set -euo pipefail

# 1. 验证必要指令是否存在
REQUIRED_BINS=(
    python3 pip uv zig cc make git jq yq rg fd gh
    shellcheck strace sqlite3 vim bat socat pkg-config
)
for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" >/dev/null 2>&1 || { echo "  ✘ 缺少命令: $bin" >&2; exit 1; }
done

# 2. 打印动态拉取的最新版本信息
echo "  python3:    $(python3 -V 2>&1)"
echo "  pip:        $(pip --version | cut -d" " -f1-2)"
echo "  uv:         $(uv --version)"
echo "  zig:        $(zig version)"
echo "  cc wrapper: $(cc --version | head -n1)"
echo "  git:        $(git --version)"
echo "  gh:         $(gh --version | head -n1)"
echo "  yq:         $(yq --version)"
echo "  jq:         $(jq --version)"
echo "  rg/fd/bat:  $(rg --version | head -n1) / $(fd --version) / $(bat --version)"
echo "  shellcheck: $(shellcheck --version | grep version:)"

# 3. 校验 Node.js 与 GDB 是否已剔除（避免内存与体积膨胀）
if command -v node >/dev/null 2>&1; then
    echo "  ✘ 依然存在 Node.js 二进制，不符合轻量预期" >&2
    exit 1
else
    echo "  ✔ Node.js 已完全剥离 (零 V8 运行时内存开销)"
fi

if command -v gdb >/dev/null 2>&1; then
    echo "  ✘ 依然存在 GDB，未移除相关动态依赖" >&2
    exit 1
else
    echo "  ✔ GDB 已剥离 (调试收敛至 strace/Zig GPA)"
fi

# 4. 验证 Python 3.12 唯一主线版本
python3 - <<\PY
import sys
assert sys.version_info[:2] == (3, 12), f"预期 Python 3.12，实际为: {sys.version}"
print("  ✔ Python 3.12 LTS 校验通过")
PY

# 5. ShellCheck 语法分析断言（正向/反向用例）
cd /tmp && rm -rf smoke-sc && mkdir -p smoke-sc && cd smoke-sc
printf "#!/bin/sh\necho \"\$1\"\n" > good.sh
printf "#!/bin/sh\necho \$1\n" > bad.sh
shellcheck good.sh
if shellcheck bad.sh >/dev/null 2>&1; then
    echo "  ✘ shellcheck 未能拦截未引号包裹的变量引用" >&2
    exit 1
fi
echo "  ✔ shellcheck 逻辑判断正常 (正确拦截瑕疵脚本)"

# 6. 验证 cc -> zig cc 包装调用及 C 源码构建运行链路
cat <<\EOF > hello.c
#include <stdio.h>
int main() {
    puts("cc-wrapper-ok");
    return 0;
}
EOF
cc hello.c -o hello
./hello | grep -q "cc-wrapper-ok" || { echo "  ✘ cc 包装编译运行失败" >&2; exit 1; }
echo "  ✔ cc (zig cc 封装) 编译与执行正常"

# 7. 验证 uv 零污染单任务测试依赖调用
uv run --with pytest python -c "import pytest; print(\"  ✔ uv 临时虚拟测试运行环境正常\")"

# 8. 验证系统调用追踪工具
strace -o /dev/null /bin/true
echo "  ✔ strace 系统调用跟踪正常"

# 9. 触发 aiod doctor 自检
aiod doctor --json 2>&1 | head -c 200 | sed "s/^/    /" || true
'

echo "== [6/7] 验证容器内部端口监听 =="
docker exec "${NAME}" bash -c 'ss -tln | grep -E ":(49983|8080)\b" || { echo "✘ 端口未正常监听" >&2; exit 1; }' | sed "s/^/  /"
echo "  ✔ 49983 与 8080 均处于监听状态"

echo "== [7/7] 镜像体积检测 =="
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  解压后镜像体积: %.2f GB\n", s/1024/1024/1024 }'

echo "✔ 全部冒烟测试项通过：${IMG}"
