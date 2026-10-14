# /etc/bash/env.sh —— aio-default 的非交互 bash 初始化（BASH_ENV 指向本文件）
# 仅定义一个轻量“命令未找到”提示：给 agent/用户指出可用的替代工具。
# 不产生任何正常输出；收尾保持退出码 127，语义与默认行为一致。

command_not_found_handle() {
    printf 'bash: %s: command not found\n' "$1" >&2
    case "$1" in
        wget) printf '  → 用 curl：curl -fsSL -o <文件> <URL>\n' >&2 ;;
        xxd|hexdump) printf '  → 用 od -An -tx1 <文件>，或 python3 -c "print(open(...,\"rb\").read().hex())"\n' >&2 ;;
        jq) printf '  → 本环境有 jaq（Rust 实现）与 jq（官方 C 实现）两套，按需调用\n' >&2 ;;
        yq) printf '  → 本环境自带 yq：yq ...（YAML/JSON 通用）\n' >&2 ;;
        dig|nslookup) printf '  → drill（drill example.com）或 dig（两者均可用）\n' >&2 ;;
        unzip|zip) printf '  → 本环境自带 unzip/zip（支持加密包与 Zip64）\n' >&2 ;;
        pip) printf '  → 推荐使用 uv pip（速度大幅提升）：uv pip install <包>\n' >&2 ;;
        *) printf '  → 提示：运行 toolbox 查看环境工具清单与使用指南；系统包缺失可通过 apk add <包> 安装\n' >&2 ;;
    esac
    return 127
}
