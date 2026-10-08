#!/bin/sh
# =============================================================================
# aio-default-tmux-shim —— aiod ↔ tmux 兼容桥
#
# 背景（基于 execve 级实测）：
#   aiod 启动时对 tmux 做能力探测（12 条命令序列）：
#     tmux -V / start-server / show-options... / list-keys -T root WheelUpPane / kill-server
#   其中 `list-keys -T root <key>`（按 key 筛选）在 tmux 3.4+ 行为变更：
#     - 官方镜像（Ubuntu + tmux 3.2a）：返回该键的绑定行 → 探测通过
#     - Alpine 侧 tmux 3.7c：同命令返回空（需全表 grep 才能取到），
#       aiod 判定 “tmux copy-mode -H is unavailable” → 回退 native shell backend
#
# 本桥行为：
#   1. 仅拦截 list-keys 查询，按“官方镜像验证过的绑定视图”回放
#      （同目录 aio-default-tmux-keys.txt = tmux 3.2a + aiod 配置的 list-keys 输出）
#   2. 其余 tmux 调用一律原样透传给真 tmux（/opt/skills/tools/tmux/amd64/tmux）
#   3. 数据文件缺失时直接透传 —— 退化为“无桥”行为（aiod 回退 native），不会更坏
#
# 生效方式：镜像 ENV AIO_TMUX_BIN 指向本脚本（只影响 aiod 进程；
#          用户/agent 手敲的 tmux 命令不受影响，仍为工具箱 tmux 3.7c）。
# 维护提示：aiod 升级后如探测序列变化，需同步复核本桥与 keys 数据。
# =============================================================================
REAL=/opt/skills/tools/tmux/amd64/tmux
DATA=/usr/local/libexec/aio-default-tmux-keys.txt

# 参数扫描：定位 `... list-keys -T <table> [key] ...` 形态
seen_lk=0; seen_t=0; tbl_seen=0; key=""
for a in "$@"; do
  if [ "$seen_lk" = 1 ]; then
    if [ "$seen_t" = 1 ]; then
      if [ "$tbl_seen" = 0 ]; then tbl_seen=1; continue; fi
      case "$a" in
        -*) ;;
        *) [ -z "$key" ] && key="$a" ;;
      esac
    elif [ "$a" = "-T" ]; then
      seen_t=1
    fi
    continue
  fi
  [ "$a" = "list-keys" ] && seen_lk=1
done

if [ "$seen_lk" = 1 ] && [ -f "$DATA" ]; then
  if [ -n "$key" ]; then
    # 按 key 回放（模拟 tmux 3.2a 的筛选行为；取前 3 行足够 aiod 解析）
    grep -E "^bind-key +-T root +${key} " "$DATA" 2>/dev/null | head -3
  else
    # 无 key 的全表查询
    cat "$DATA"
  fi
  exit 0
fi

# 非 list-keys 调用 / 数据缺失：原样透传
exec "$REAL" "$@"
