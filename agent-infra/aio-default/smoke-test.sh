#!/usr/bin/env bash
# =============================================================================
# aio-default 冒烟测试 —— 构建后容器级验收（需要 docker）
# 用法: ./smoke-test.sh <image>
# 覆盖：启动/探针/双面API / 镜像内部一致性 / 46 工具全量探测 / 全清单校验 /
#       tini 信号 / tmux 后端断言 / exec 双通道 / 版本与体积
# =============================================================================
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiodef-smoke-$$"
cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== [1/9] 启动测试容器 ${NAME} =="
docker run -d --name "${NAME}" -p 49983:49983 -p 8080:8080 "${IMG}" >/dev/null

need() { # <描述> <url> <期望码> [limit]
  local desc="$1" url="$2" want="$3" limit="${4:-60}" i code
  for i in $(seq 1 "${limit}"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
    if [ "${code}" = "${want}" ]; then echo "  ✔ ${desc} => ${code} (${i}s)"; return 0; fi
    sleep 1
  done
  echo "  ✘ ${desc} => ${code:-无响应} (期望 ${want})" >&2
  docker logs "${NAME}" 2>&1 | tail -n 40 >&2
  return 1
}

echo "== [2/9] 平台探针与双面 API =="
need "envd :49983/health（平台探针）" "http://127.0.0.1:49983/health" 204 60
need "aiod :8080/health" "http://127.0.0.1:8080/health" 200 60
v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/capabilities)"
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v2/sandbox)"
echo "  v1 /v1/capabilities => ${v1}；v2 /v2/sandbox => ${v2}"
[ "${v1}" = "200" ] && [ "${v2}" = "200" ] || { echo "  ✘ 双面 API 不齐" >&2; exit 1; }
if curl -s -o /dev/null --max-time 2 http://127.0.0.1:18091/health; then
  echo "  ✘ 18091 意外处于监听" >&2; exit 1
else
  echo "  ✔ 18091 未监听（单端口收敛）"
fi

echo "== [3/9] 镜像内部一致性 =="
docker exec "${NAME}" sh -c '
set -eu
[ "$(cat /etc/alpine-release)" = "3.21.0" ] || { echo "alpine 版本不符: $(cat /etc/alpine-release)" >&2; exit 1; }
[ "$PATH" = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin" ] || { echo "PATH 不符: $PATH" >&2; exit 1; }
for f in /bin/bash /usr/bin/python3 /usr/bin/tini /usr/local/bin/aiod /usr/local/bin/curl; do
  [ -x "$f" ] || { echo "$f 缺失" >&2; exit 1; }
done
echo "  ✔ alpine=$(cat /etc/alpine-release) / PATH 与 iSH 一致 / 关键入口齐全"
printf "  · bash=%s\n" "$(bash --version | head -1)"
printf "  · python3=%s\n" "$(python3 -V)"
'

echo "== [4/9] 46 工具全量探测 =="
docker exec "${NAME}" sh -c '
n=0; bad=""
for d in /opt/skills/tools/*/; do
  t=$(basename "$d")
  [ -f "$d/amd64/$t" ] || continue
  n=$((n+1)); ok=0
  for f in --version -version -v --help -h; do
    out=$(timeout 5 "$d/amd64/$t" "$f" </dev/null 2>&1 | head -1) || true
    [ -n "$out" ] && { ok=1; break; }
  done
  [ "$ok" = 1 ] || bad="$bad $t"
done
echo "  探测: $n 件; 无响应:[${bad:-无}]"
[ "$n" -eq 46 ] || { echo "  ✘ 工具数量不符（期望 46）" >&2; exit 1; }
[ -z "$bad" ] || { echo "  ✘ 存在无响应工具" >&2; exit 1; }
echo "  ✔ 46/46 工具可执行"
'

echo "== [5/9] 全清单校验 =="
docker exec "${NAME}" sh -c '
cd /opt/skills/tools && sha256sum -c SHA256SUMS.amd64 >/dev/null && echo "  ✔ 46 件 sha256 清单复核通过"
'

echo "== [6/9] tini 信号链路 =="
docker exec "${NAME}" sh -c 'tini --version | sed "s/^/  · /"'
docker exec "${NAME}" sh -c 'nohup tini -- sleep 60 >/dev/null 2>&1 & echo $! > /tmp/tinip; echo started' >/dev/null
sleep 1
docker exec "${NAME}" sh -c '
tp=$(cat /tmp/tinip)
kill -0 "$tp" 2>/dev/null || { echo "  ✘ tini 后台进程不存在" >&2; exit 1; }
kill -TERM "$tp"; sleep 0.6
if kill -0 "$tp" 2>/dev/null; then echo "  ✘ tini 未响应 TERM" >&2; exit 1; fi
echo "  ✔ tini 存活 → TERM → 退出（信号转发链路正常）"
'

echo "== [7/9] aiod shell 后端断言（tmux 兼容桥生效） =="
tmux_ok=0
for _ in $(seq 1 20); do
  if docker logs "${NAME}" 2>&1 | grep -q '"selected":"tmux"'; then tmux_ok=1; break; fi
  sleep 1
done
if [ "${tmux_ok}" = "1" ]; then
  echo "  ✔ shell backend = tmux"
else
  echo "  ✘ tmux backend 未激活；日志尾部：" >&2
  docker logs "${NAME}" 2>&1 | tail -n 20 >&2
  exit 1
fi

echo "== [8/9] 命令执行通道（v2 + v1） =="
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' \
    -d '{"command":"echo SMOKE=$0; uname -m; rg --version | head -1; python3 -c \"print(6*7)\"; echo 42 | jaq ."}')"
printf '%s' "${out}" | grep -q "SMOKE=" || { echo "  ✘ v2/commands: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q '"exit_code":0' || { echo "  ✘ v2 退出码非 0: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "42" || { echo "  ✘ v2 输出缺项: ${out}" >&2; exit 1; }
echo "  ✔ v2/commands：bash 解析 + 工具链端到端可用"
curl -fsS -X POST http://127.0.0.1:8080/v1/bash/exec -H 'Content-Type: application/json' \
    -d '{"command":"echo v1-ok; tmux -V"}' | grep -q "v1-ok" && echo "  ✔ v1/bash/exec 正常"

echo "== [9/9] 版本快照与体积 =="
docker exec "${NAME}" sh -c '
printf "  · busybox(系统)=%s\n"   "$(/bin/busybox | head -1)"
printf "  · busybox(工具箱)=%s\n" "$(/usr/local/bin/busybox | head -1)"
printf "  · tmux=%s\n"            "$(tmux -V)"
printf "  · ssh=%s\n"             "$(ssh -V 2>&1)"
printf "  · gawk=%s\n"            "$(gawk --version | head -1)"
printf "  · pip=%s\n"             "$(python3 -m pip --version 2>&1 | head -1 || true)"
'
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  · 镜像体积: %.1f MB\n", s/1024/1024 }'

echo "✔ aio-default 冒烟测试全部通过：${IMG}"
