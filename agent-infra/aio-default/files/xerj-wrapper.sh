#!/bin/sh
# /usr/local/bin/xerj —— 透明按需惰性包装入口
set -e

XERJ_REAL="${XERJ_REAL:-/usr/local/bin/xerj-real}"
SERVICE_CMD="${SERVICE_CMD:-/usr/local/bin/xerj-service}"

is_offline_cmd() {
    case "${1:-}" in
        --help|-h|--version|-V|help|version) return 0 ;;
        --*)
            for arg in "$@"; do
                case "$arg" in
                    autoindex|search|def|ask|code|corpus|brain|share|feedback|gain|mcp|index)
                        return 1 ;;
                esac
            done
            return 0
            ;;
        *) return 1 ;;
    esac
}

if ! is_offline_cmd "$@"; then
    if [ -x "${SERVICE_CMD}" ]; then
        "${SERVICE_CMD}" ensure
    fi
fi

exec "${XERJ_REAL}" "$@"
