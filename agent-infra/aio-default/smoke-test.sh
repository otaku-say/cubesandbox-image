#!/usr/bin/env bash
# =============================================================================
# aio-default 冒烟测试（v5）—— 构建后容器级验收（需要 docker）
# 用法: ./smoke-test.sh <image>
# 覆盖：探针/v2 API（v1 应关闭）/ 内部一致性（3.23.6、busybox 1.38、TZ=+0800）/
#       58 工具全量探测 / 全清单校验 / tini 信号 / tmux 后端 /
#       v2 命令通道端到端（rg/python/jaq）/ Agent 层（toolbox/AGENT-GUIDE/缺命令提示/pip 桥）/
#       开发链（git 2.56、zig 编译、gh、git-lfs、uv）/ LABEL 与体积
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

echo "== [2/9] 平台探针与 v2 API =="
need "envd :49983/health（平台探针）" "http://127.0.0.1:49983/health" 204 60
need "aiod :8080/health" "http://127.0.0.1:8080/health" 200 60
v2="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v2/sandbox)"
v1="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/capabilities)"
echo "  v2 /v2/sandbox => ${v2}；v1 /v1/capabilities => ${v1}（AIO_API_SURFACE=v2 预期关闭）"
[ "${v2}" = "200" ] || { echo "  ✘ v2 面异常" >&2; exit 1; }
[ "${v1}" = "404" ] || { echo "  ✘ v1 应关闭（AIO_API_SURFACE=v2），实际 ${v1}" >&2; exit 1; }
if curl -s -o /dev/null --max-time 2 http://127.0.0.1:18091/health; then
  echo "  ✘ 18091 意外处于监听" >&2; exit 1
else
  echo "  ✔ 18091 未监听（单端口收敛）"
fi

echo "== [3/9] 镜像内部一致性 =="
docker exec "${NAME}" sh -c '
set -eu
[ "$(cat /etc/alpine-release)" = "3.23.6" ] || { echo "alpine 版本不符: $(cat /etc/alpine-release)" >&2; exit 1; }
[ "$PATH" = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin" ] || { echo "PATH 不符: $PATH" >&2; exit 1; }
for f in /bin/bash /usr/bin/python3 /usr/bin/tini /usr/local/bin/aiod /usr/local/bin/curl \
         /usr/bin/git /usr/local/bin/zig /usr/bin/gh /usr/bin/git-lfs /usr/local/bin/toolbox; do
  [ -x "$f" ] || { echo "$f 缺失" >&2; exit 1; }
done
/bin/busybox | head -1 | grep -q "v1.38.0" || { echo "系统 busybox 未切换为 1.38.0" >&2; exit 1; }
[ "$(date +%z)" = "+0800" ] || { echo "TZ 未生效: $(date +%z)" >&2; exit 1; }
[ "${AIO_API_SURFACE:-}" = "v2" ] || { echo "AIO_API_SURFACE != v2" >&2; exit 1; }
[ -d /workspace ] && [ -w /workspace ] || { echo "/workspace 缺失或不可写" >&2; exit 1; }
command -v sudo >/dev/null || { echo "sudo 缺失" >&2; exit 1; }
grep -q "^/bin/bash$" /etc/shells || { echo "/etc/shells 未登记 /bin/bash" >&2; exit 1; }
! grep -q "@edge" /etc/apk/world || { echo "apk world 残留 @edge" >&2; exit 1; }
! grep -q "@edge" /etc/apk/repositories || { echo "repositories 残留 @edge" >&2; exit 1; }
apk add --simulate file >/dev/null 2>&1 || { echo "apk 不可用（world 依赖异常）" >&2; exit 1; }
printf "  · %s / PATH 一致 / TZ=$(date +%z) / pwd=%s\n" "$(cat /etc/alpine-release)" "$(pwd)"
printf "  · busybox(系统)=%s\n" "$(/bin/busybox | head -1)"
'

echo "== [4/9] 工具箱全量探测（动态比对数量）+ 清单校验 =="
docker exec "${NAME}" sh -c '
set -eu
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
exp=$(wc -l < /opt/skills/tools/SHA256SUMS.amd64)
[ "$n" -eq "$exp" ] || { echo "  ✘ 工具数量不符（$n != $exp）" >&2; exit 1; }
[ -z "$bad" ] || { echo "  ✘ 存在无响应工具" >&2; exit 1; }
cd /opt/skills/tools && sha256sum -c SHA256SUMS.amd64 >/dev/null
echo "  ✔ $n/$exp 可执行 + sha256 清单复核通过"
for t in curl python python3 uv rg fd jaq gawk awk coreutils grep sed find xargs diff tar xz zip unzip yq tmux sqlite3 zstd patch openssl bash tini tree; do
  p=$(command -v "$t" 2>/dev/null) || { echo "  ✘ $t 缺失" >&2; exit 1; }
  r=$(readlink -f "$p")
  case "$r" in /opt/skills/tools/*) : ;; *) echo "  ✘ $t 未解析到工具箱: $r" >&2; exit 1 ;; esac
done
echo "  ✔ 工具箱优先链路（抽查 28 项全部命中 /opt/skills/tools）"
'

echo "== [5/9] tini 信号链路 =="
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

echo "== [6/9] aiod shell 后端断言（工具箱 tmux 3.8） =="
docker exec "${NAME}" tmux -V | grep -q "3\.8" || { echo "  ✘ tmux 版本异常" >&2; exit 1; }
tmux_ok=0
for _ in $(seq 1 20); do
  if docker logs "${NAME}" 2>&1 | grep -q '"selected":"tmux"'; then tmux_ok=1; break; fi
  sleep 1
done
[ "${tmux_ok}" = "1" ] || { echo "  ✘ tmux backend 未激活" >&2; docker logs "${NAME}" 2>&1 | tail -20 >&2; exit 1; }
echo "  ✔ $(docker exec "${NAME}" tmux -V) ；shell backend = tmux"

echo "== [7/9] v2 命令通道：工具链端到端 =="
cat > /tmp/v2cmd.json <<'JSONEOF'
{"command":"echo SMOKE=$0; pwd; rg --version | head -1; python3 -c \"print(6*7)\"; echo '{\"a\":12345}' | jaq -r .a"}
JSONEOF
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' --data-binary @/tmp/v2cmd.json)"
printf '%s' "${out}" | grep -q "SMOKE=" || { echo "  ✘ v2/commands: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q '"exit_code":0' || { echo "  ✘ v2 退出码非 0: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "12345" || { echo "  ✘ jaq 输出缺项: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "42" || { echo "  ✘ 输出缺 42: ${out}" >&2; exit 1; }
echo "  · v2 输出片段: $(printf '%s' "${out}" | head -c 220)"
echo "  ✔ v2/commands：rg / python3 / jaq 端到端可用"

echo "== [8/9] Agent 层与开发链 =="
docker exec "${NAME}" bash -c '
set -eu
v="$(git --version | awk "{print \$3}")"
[ "$(printf "%s\n2.56.0\n" "$v" | sort -V | head -1)" = "2.56.0" ] || { echo "  ✘ git 版本过低: $v" >&2; exit 1; }
git config --system --get filter.lfs.clean >/dev/null || { echo "  ✘ git-lfs 未初始化（filter.lfs 缺失）" >&2; exit 1; }
printf "  · %s\n" "$(git --version)" "$(git-lfs --version | head -1)" "$(gh --version | head -1)" "zig $(zig version)" "$(uv --version)" "$(python3 -V)"
out=$(bash -c definitely-not-a-cmd-xyz 2>&1 || true)
echo "$out" | grep -q "ish-toolbox" || { echo "  ✘ 缺命令提示未生效: $out" >&2; exit 1; }
out=$(pip --version 2>&1 || true)
echo "$out" | grep -q "uv" || { echo "  ✘ pip 桥异常: $out" >&2; exit 1; }
toolbox | head -5 | grep -q "工具箱" || { echo "  ✘ toolbox 命令异常" >&2; exit 1; }
[ -f /opt/skills/tools/AGENT-GUIDE.md ] || { echo "  ✘ AGENT-GUIDE 缺失" >&2; exit 1; }
cd /tmp && rm -rf gsm && mkdir gsm && cd gsm && git init -q && git config user.email a@b && git config user.name a \
  && echo x > a && git add a && git commit -qm t && git log --oneline | grep -q " t"
printf "int main(){return 7;}\n" > z.c
zig cc z.c -o z
rc=0; ./z || rc=$?
[ "$rc" = "7" ] || { echo "  ✘ zig cc 冒烟失败 rc=$rc" >&2; exit 1; }
sudo -u user id 2>/dev/null | grep -q "uid=1000" || { echo "  ✘ sudo -u user 异常" >&2; exit 1; }
sudo -u user sudo -n id 2>/dev/null | grep -q "uid=0" || { echo "  ✘ user 免密 sudo 未生效" >&2; exit 1; }
echo "  ✔ git 提交/日志、zig cc 编译运行、gh/git-lfs/uv、toolbox、pip 桥、缺命令提示、user 免密 sudo 全部可用"
'

echo "== [9/9] LABEL 与体积 =="
lbl="$(docker image inspect "${IMG}" --format '{{json .Config.Labels}}')"
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.writable-layer-size":"30G"' || { echo "  ✘ 30G 标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.cpu":"3000"' || { echo "  ✘ cpu=3000 标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.memory":"3000"' || { echo "  ✘ memory=3000 标签缺失" >&2; exit 1; }
echo "  ✔ 模板标签（30G / cpu=3000 / memory=3000）"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  · 镜像体积: %.1f MB\n", s/1024/1024 }'

echo "✔ aio-default 冒烟测试全部通过：${IMG}"
