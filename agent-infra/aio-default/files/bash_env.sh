# /etc/bash/env.sh —— aio-default 的非交互 bash 初始化（BASH_ENV 指向本文件）
# 仅定义一个轻量“命令未找到”提示：给 agent/用户指出可用的替代工具。
# 不产生任何正常输出；手尾保持退出码 127，语义与默认行为一致。

command_not_found_handle() {
    printf 'bash: %s: command not found\n' "$1" >&2
    case "$1" in
        pip|pip3) printf '  → 本环境 Python 包管理请用 uv：uv venv .venv && uv pip install <包>；或 uv tool run <工具>\n' >&2 ;;
        node|npm|npx|yarn|pnpm) printf '  → 未装 Node；轻量 JS 可用 qjs（QuickJS）。需要时可 apk add nodejs\n' >&2 ;;
        dig) printf '  → 本环境提供 drill（用法类似 dig：drill example.com）\n' >&2 ;;
        jq) printf '  → 本镜像用工具箱的 jaq（jq 兼容实现）：把 jq 换成 jaq 即可；确实需要原版时可 apk add jq\n' >&2 ;;
        *) printf '  → 提示：本沙箱自带 ish-toolbox 58 件工具，运行 toolbox 查看清单与替代建议（jaq、rg、fd、sd、qjs、yq、sqlite3 …）；系统包缺失可 apk add <包> 秒装\n' >&2 ;;
    esac
    return 127
}
