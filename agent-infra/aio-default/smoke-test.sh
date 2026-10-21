#!/usr/bin/env bash
# =============================================================================
# aio-default 冒烟测试（v8）—— 构建后容器级验收（需要 docker）
# 用法: ./smoke-test.sh <image>
# 覆盖：探针/v2 API（v1 应关闭）/ 内部一致性（3.23.6、系统 busybox、TZ=+0800、
#       真 pip + pillow/numpy）/ 工具箱 43 件全量探测 + 清单校验 + 15 件下架验证 /
#       tini 信号 / tmux 后端 / v2 命令通道端到端（rg/python/jaq）/ Agent 层 /
#       开发链（git 2.56、zig、gh、git-lfs、uv）/ XERJ 按需自愈与释放 / LABEL 与体积
# =============================================================================
set -euo pipefail
set -x

IMG="${1:?用法: smoke-test.sh <image>}"
NAME="aiodef-smoke-$$"
cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== [1/10] 启动测试容器 ${NAME} =="
docker run -d --name "${NAME}" -p 49983:49983 -p 8080:8080 -p 9200:9200 "${IMG}" >/dev/null

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

echo "== [2/10] 平台探针与 v2 API =="
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

echo "== [3/10] 镜像内部一致性 =="
docker exec "${NAME}" sh -c '
set -eux
[ "$(cat /etc/alpine-release)" = "3.23.6" ] || { echo "alpine 版本不符: $(cat /etc/alpine-release)" >&2; exit 1; }
case "$PATH" in */usr/local/bin*|*/bin*) : ;; *) echo "PATH 不符: $PATH" >&2; exit 1 ;; esac
for f in /bin/bash /usr/bin/python3 /usr/bin/pip /usr/bin/tini /usr/local/bin/aiod /usr/bin/curl \
         /usr/bin/git /usr/local/bin/zig /usr/bin/gh /usr/bin/git-lfs /usr/local/bin/toolbox \
         /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/mcp-gateway \
         /usr/local/bin/xerj-real /usr/local/bin/xerj /usr/local/bin/xerj-service; do
  [ -e "$f" ] || { echo "$f 缺失" >&2; exit 1; }
done
uv --version | grep -q "0.13.1" || { echo "uv 版本不是 0.13.1: $(uv --version)" >&2; exit 1; }
mcp-gateway catalog | grep -q "duckduckgo" || { echo "mcp-gateway catalog 异常" >&2; exit 1; }
# 系统 busybox 保持原版
/bin/busybox | head -1 | grep -q "BusyBox v1.3" || { echo "系统 busybox 异常: $(/bin/busybox | head -1)" >&2; exit 1; }
[ "$(date +%z)" = "+0800" ] || { echo "TZ 未生效: $(date +%z)" >&2; exit 1; }
[ "${AIO_API_SURFACE:-}" = "v2" ] || { echo "AIO_API_SURFACE != v2" >&2; exit 1; }
[ -d /workspace ] && [ -w /workspace ] || { echo "/workspace 缺失或不可写" >&2; exit 1; }
[ -f /workspace/.mcp.json ] && grep -q "xerj" /workspace/.mcp.json || { echo "/workspace/.mcp.json 缺失或缺 xerj" >&2; exit 1; }
[ -f /workspace/AGENTS.md ] || { echo "/workspace/AGENTS.md 缺失" >&2; exit 1; }
command -v sudo >/dev/null || { echo "sudo 缺失" >&2; exit 1; }
[ -d /tmp/.cube-cli-pty ] || { echo "cube-cli PTY 会话目录缺失" >&2; exit 1; }
[ -d /tmp/.cube-cli-exec ] || { echo "cube-cli exec 会话目录缺失" >&2; exit 1; }
[ "$(stat -c %a /tmp/.cube-cli-exec)" = "1777" ] || { echo "exec 会话目录权限非 1777" >&2; exit 1; }
[ "$(stat -c %a /tmp/.cube-cli-pty)" = "1777" ] || { echo "PTY 会话目录权限非 1777（--user=user 写不进）" >&2; exit 1; }
rm -f /tmp/.cube-cli-pty/smoke.log
if command -v script >/dev/null 2>&1; then
  script -q -c "echo smoke-ok" /tmp/.cube-cli-pty/smoke.log >/dev/null 2>&1
  grep -q "smoke-ok" /tmp/.cube-cli-pty/smoke.log || { echo "script 落盘冒烟失败" >&2; exit 1; }
  rm -f /tmp/.cube-cli-pty/smoke.log
fi
grep -q "^/bin/bash$" /etc/shells || { echo "/etc/shells 未登记 /bin/bash" >&2; exit 1; }
! grep -q "@edge" /etc/apk/world || { echo "apk world 残留 @edge" >&2; exit 1; }
! grep -q "@edge" /etc/apk/repositories || { echo "repositories 残留 @edge" >&2; exit 1; }
apk add --simulate file >/dev/null 2>&1 || { echo "apk 不可用（world 依赖异常）" >&2; exit 1; }

# 验证 XERJ 默认按需未拉起（0 内存消耗）
if curl -s -o /dev/null --max-time 1 http://127.0.0.1:9200/; then
  echo "  ✘ 9200 端口开机即监听（期望默认按需惰性激活）" >&2; exit 1
else
  echo "  ✔ 9200 默认未监听（惰性按需生效）"
fi
printf "  · %s / PATH 一致 / TZ=%s / pwd=%s\n" "$(cat /etc/alpine-release)" "$(date +%z)" "$(pwd)"
printf "  · busybox(系统)=%s\n" "$(/bin/busybox | head -1)"
'

echo "== [4/10] Python 栈与 AOJIT 迁移位（真 pip / pillow / numpy；15 件已下架） =="
docker exec "${NAME}" sh -c '
set -eu
p="$(pip --version 2>&1 || true)"
printf "  · %s\n" "$p"
case "$p" in pip\ *) : ;; *) echo "  ✘ pip 异常（期望真 pip）: $p" >&2; exit 1 ;; esac
python3 -c "import PIL.Image, numpy; print(\"  · pillow+numpy ok\")" || { echo "  ✘ pillow/numpy 不可用" >&2; exit 1; }
python3 -V | sed "s/^/  · /"
for t in busybox python3 curl openssl ssh scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan sqlite3 socat drill uv; do
  [ -e "/opt/skills/tools/$t" ] && { echo "  ✘ 已下架工具仍在工具箱：$t" >&2; exit 1; }
done
echo "  ✔ 15 件下架位确认（工具箱内不存在）"
'

echo "== [5/10] 工具箱全量探测（动态比对数量）+ 清单校验 =="
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
[ "$n" -eq 43 ] || { echo "  ✘ 工具箱应为 43 件（AOJIT 迁移后），实际 $n" >&2; exit 1; }
[ -z "$bad" ] || { echo "  ✘ 存在无响应工具" >&2; exit 1; }
cd /opt/skills/tools && sha256sum -c SHA256SUMS.amd64 >/dev/null
echo "  ✔ $n/$exp 可执行 + sha256 清单复核通过"
for t in rg fd jaq gawk awk coreutils grep sed find xargs diff tar xz zip unzip yq tmux zstd patch bash tini tree qjs sd sponge; do
  p=$(command -v "$t" 2>/dev/null) || { echo "  ✘ $t 缺失" >&2; exit 1; }
  r=$(readlink -f "$p")
  case "$r" in /opt/skills/tools/*) : ;; *) echo "  ✘ $t 未解析到工具箱: $r" >&2; exit 1 ;; esac
done
echo "  ✔ 工具箱优先链路（抽查 25 项全部命中 /opt/skills/tools）"
'

echo "== [6/10] tini 信号链路 =="
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

echo "== [7/10] aiod shell 后端断言（工具箱 tmux 3.8） =="
docker exec "${NAME}" tmux -V | grep -q "3\.8" || { echo "  ✘ tmux 版本异常" >&2; exit 1; }
tmux_ok=0
for _ in $(seq 1 20); do
  if docker logs "${NAME}" 2>&1 | grep -q '"selected":"tmux"'; then tmux_ok=1; break; fi
  sleep 1
done
[ "${tmux_ok}" = "1" ] || { echo "  ✘ tmux backend 未激活" >&2; docker logs "${NAME}" 2>&1 | tail -20 >&2; exit 1; }
echo "  ✔ $(docker exec "${NAME}" tmux -V) ；shell backend = tmux"

echo "== [8/10] v2 命令通道 + Agent 层与开发链 =="
cat > /tmp/v2cmd.json <<'JSONEOF'
{"command":"echo SMOKE=$0; pwd; rg --version | head -1; python3 -c \"print(6*7)\"; echo '{\"a\":12345}' | jaq -r .a; uv --version"}
JSONEOF
out="$(curl -fsS -X POST http://127.0.0.1:8080/v2/commands -H 'Content-Type: application/json' --data-binary @/tmp/v2cmd.json)"
printf '%s' "${out}" | grep -q "SMOKE=" || { echo "  ✘ v2/commands: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q '"exit_code":0' || { echo "  ✘ v2 退出码非 0: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "12345" || { echo "  ✘ jaq 输出缺项: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "42" || { echo "  ✘ 输出缺 42: ${out}" >&2; exit 1; }
printf '%s' "${out}" | grep -q "uv" || { echo "  ✘ 输出缺 uv: ${out}" >&2; exit 1; }
echo "  · v2 输出片段: $(printf '%s' "${out}" | head -c 220)"
echo "  ✔ v2/commands：rg / python3 / jaq / uv 端到端可用"

docker exec "${NAME}" bash -c '
set -eu
v="$(git --version | awk "{print \$3}")"
[ "$(printf "%s\n2.56.0\n" "$v" | sort -V | head -1)" = "2.56.0" ] || { echo "  ✘ git 版本过低: $v" >&2; exit 1; }
git config --system --get filter.lfs.clean >/dev/null || { echo "  ✘ git-lfs 未初始化（filter.lfs 缺失）" >&2; exit 1; }
printf "  · %s\n" "$(git --version)" "$(git-lfs --version | head -1)" "$(gh --version | head -1)" "zig $(zig version)" "$(uv --version)" "$(python3 -V)" "$(node --version)"
out=$(bash -c definitely-not-a-cmd-xyz 2>&1 || true)
echo "$out" | grep -q "ish-toolbox" || { echo "  ✘ 缺命令提示未生效: $out" >&2; exit 1; }
toolbox | head -10 | grep -qE "工具箱|toolbox" || { echo "  ✘ toolbox 命令异常" >&2; exit 1; }
[ -f /opt/skills/tools/AGENT-GUIDE.md ] || { echo "  ✘ AGENT-GUIDE 缺失" >&2; exit 1; }
cd /tmp && rm -rf gsm && mkdir gsm && cd gsm && git init -q && git config user.email a@b && git config user.name a \
  && echo x > a && git add a && git commit -qm t && git log --oneline | grep -q " t"
printf "int main(){return 7;}\n" > z.c
zig cc z.c -o z
rc=0; ./z || rc=$?
[ "$rc" = "7" ] || { echo "  ✘ zig cc 冒烟失败 rc=$rc" >&2; exit 1; }
sudo -u user id 2>/dev/null | grep -q "uid=1000" || { echo "  ✘ sudo -u user 异常" >&2; exit 1; }
sudo -u user sudo -n id 2>/dev/null | grep -q "uid=0" || { echo "  ✘ user 免密 sudo 未生效" >&2; exit 1; }
echo "  ✔ git 提交/日志、zig cc 编译运行、gh/git-lfs/uv/node、toolbox、缺命令提示、user 免密 sudo 全部可用"
'

echo "== [9/10] XERJ 透明惰性自愈激活与内存释放 =="
docker exec "${NAME}" bash -c '
set -eu
# 1. 帮助与版本不应唤醒服务
v=$(xerj --version)
echo "  · xerj version: $v"
! curl -s -o /dev/null --max-time 1 http://127.0.0.1:9200/ || { echo "  ✘ xerj --version 意外拉起了服务" >&2; exit 1; }

# 2. 模拟一个测试项目
mkdir -p /tmp/xerj-smoke-repo
echo "fn calculateTaxRate() { return 0.15; }" > /tmp/xerj-smoke-repo/tax.rs
echo "# CubeSandbox Documentation" > /tmp/xerj-smoke-repo/README.md

# 3. 首次调用 autoindex 自动触发服务拉起并建索引
xerj autoindex /tmp/xerj-smoke-repo --bulk-mb 4 >/dev/null
curl -fsS http://127.0.0.1:9200/ | grep -q "You Know, for Search" || { echo "  ✘ xerj 服务未就绪" >&2; exit 1; }
echo "  ✔ 首次调用 autoindex 成功自动拉起 9200 服务"

# 4. 执行 search 检索
out=$(xerj search "calculateTaxRate")
echo "$out" | grep -q "tax.rs" || { echo "  ✘ xerj search 未召回目标代码: $out" >&2; exit 1; }
echo "  ✔ xerj search 代码段召回验证通过"

# 5. 执行 stop 释放内存
xerj-service stop >/dev/null
! curl -s -o /dev/null --max-time 1 http://127.0.0.1:9200/ || { echo "  ✘ xerj-service stop 未能停机" >&2; exit 1; }
echo "  ✔ xerj-service stop 成功释放 9200 端口与内存"
'

echo "== [10/10] LABEL 与体积 =="
lbl="$(docker image inspect "${IMG}" --format '{{json .Config.Labels}}')"
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.writable-layer-size":"40G"' || { echo "  ✘ 40G 标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.cpu":"3000"' || { echo "  ✘ cpu=3000 标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '"io.cubesandbox.template.memory":"4000"' || { echo "  ✘ memory=4000 标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '50005' || { echo "  ✘ 50005 端口暴露标签缺失" >&2; exit 1; }
printf '%s' "${lbl}" | grep -q '9200' || { echo "  ✘ 9200 端口暴露标签缺失" >&2; exit 1; }
echo "  ✔ 模板标签（40G / cpu=3000 / memory=4000 / exposed 50005,9200）"
size="$(docker image inspect "${IMG}" --format '{{.Size}}')"
awk -v s="${size}" 'BEGIN { printf "  · 镜像体积: %.1f MB\n", s/1024/1024 }'

echo "✔ aio-default 冒烟测试全部通过：${IMG}"
