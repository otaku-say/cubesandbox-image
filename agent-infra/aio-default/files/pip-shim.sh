#!/bin/sh
# pip / pip3 → uv 桥（aio-default：本环境无 pip，Python 包管理统一走 uv）
#   - 未激活 venv 时自动加 --system（系统级安装）
#   - venv 内保持标准语义（不加 --system）
set -u
UV="${UV_BIN:-uv}"
cmd="${1:-}"
if [ $# -gt 0 ]; then shift; fi
case "$cmd" in
  install|uninstall|list|freeze|show|check|download|wheel)
    if [ -n "${VIRTUAL_ENV:-}" ]; then
      exec "$UV" pip "$cmd" "$@"
    else
      exec "$UV" pip "$cmd" --system "$@"
    fi ;;
  ""|-V|--version)
    exec "$UV" --version ;;
  *)
    exec "$UV" pip "$cmd" "$@" ;;
esac
