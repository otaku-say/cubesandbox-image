# /etc/bash/env.sh —— aio-default 的非交互 bash 初始化（BASH_ENV 指向本文件）
# 仅定义一个轻量“命令未找到”提示：给 agent/用户指出可用的替代工具。
# 不产生任何正常输出；收尾保持退出码 127，语义与默认行为一致。

command_not_found_handle() {
    printf 'bash: %s: command not found\n' "$1" >&2
    case "$1" in
        wget) printf '  → 用 curl（apk 提供）：curl -fsSL -o <文件> <URL>\n' >&2 ;;
        xxd|hexdump) printf '  → 用 od -An -tx1 <文件>，或 python3 -c "print(open(...,\"rb\").read().hex())"\n' >&2 ;;
        jq) printf '  → 本环境有 jaq（工具箱，jq 兼容）与 jq（apk）两套，按需调用\n' >&2 ;;
        yq) printf '  → 工具箱自带 yq：yq ...（YAML/JSON 通用）\n' >&2 ;;
        dig|nslookup) printf '  → drill（drill example.com）或 dig（apk bind-tools，两者均可用）\n' >&2 ;;
        unzip|zip) printf '  → 工具箱自带 unzip/zip（支持加密包与 Zip64）\n' >&2 ;;
        *) printf '  → 提示：本沙箱 = ish-toolbox 43 件静态工具 + apk 系统层；运行 toolbox 查看清单与替代建议（rg、fd、jaq、yq、sd、qjs、gawk、tmux …）；系统包缺失可 apk add <包> 秒装\n' >&2 ;;
    esac
    return 127
}
