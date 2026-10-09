# aio-default 工具箱速查（AGENT-GUIDE）

> 本沙箱自带 **ish-toolbox 58 件静态工具**（与本地 iSH 同源），外加 apk 刚需组件（编译链 / 证书 / 时区等）。
> 找不到命令时先 `command -v <名称>` 检查，或运行 **`toolbox`** 查看本表与全量清单。

## 1. 高频对应关系（LLM 工作流最常踩的"命令没有"）

| 常想用的 | 本环境可用 | 说明 |
|---|---|---|
| jq | `jaq`（工具箱） | 本镜像用 jaq——jq 语法基本兼容，直接 `jaq ...`；确实需要原版时可 `apk add jq` |
| yq | `yq`（工具箱；自动跟随上游） | YAML/JSON 通用处理（jq 语法体系） |
| unzip | `unzip`（工具箱） | 解压 .zip（加密包带 `-P`；busybox 版不支持加密/Zip64） |
| grep | `grep`（GNU）+ **`rg`** | 大目录搜索优先 `rg`（ripgrep，自动忽略 .gitignore） |
| find | `find`（GNU）+ **`fd`** | 简单查找优先 `fd`（如 `fd 关键词 /path`） |
| sed | `sed`（GNU）+ `sd` | 交互式替换 `sd '旧' '新' 文件`；脚本照常用 sed |
| awk | `gawk`（GNU awk） | 直接按 `awk` 用 |
| python | `python3` / `python`（3.12.15） | 无 pip——包管理用 **`uv`**（见下） |
| node | `qjs`（QuickJS，轻量 JS） | 需要完整 Node 时：`apk add nodejs` |
| dig | `drill` | 用法与 dig 类似（`drill example.com`） |
| hexdump/xxd | `xxd`（busybox） | 备用 `od` |
| wget/curl | `wget`、`curl` | 均有（curl 为静态版，内嵌 CA，https 开箱用） |

## 2. 工具箱全清单（58 件，直接按名字调用）

**文本/数据**：`rg` `fd` `jaq` `yq` `gawk` `sd` `head-tail` `sponge` `csvquote` `jo` `lowdown`
**格式/网页**：`html2text` `hxselect` `strip-ansi` `qjs`
**文件/归档**：`zstd` `unzip` `pv` `entr` `fzy` `tree` `diffstat` `xxhsum`
**网络/传输**：`curl` `ssh` `scp` `sftp` `ssh-keygen` `ssh-agent` `ssh-add` `ssh-keyscan` `socat` `drill`
**GNU 静态套件（自编上架）**：`coreutils`（单文件多路复用）`grep`（PCRE2）`sed` `find` `xargs` `diff` `tar` `xz` `zip`
**安全/加密**：`openssl`（LibreSSL）`rage` `rage-keygen`（age 加密）
**进程/终端**：`pstree` `faketty` `chronic`  `su-exec` `tini`
**脚本/开发**：`bash` `envsubst` `patch` `sqlite3` `python3` `uv` `tmux` `busybox`

## 3. 开发链（本镜像新增）

- **git 全套（Alpine edge 官方构建）**：git 2.56 / git-perl（`git add -i` 等 Perl 子命令）/ git-lfs / gh（GitHub CLI）
- **zig 0.17.0**：`zig cc` / `zig c++` 即 C/C++ 编译器（也支持交叉编译：`zig cc -target aarch64-linux-musl ...`）
- **编译支撑**：`make` `perl` `pkgconf` `binutils` `autoconf` `automake` `libtool` `bison` `flex` `linux-headers`
- **交叉测试**：`qemu-aarch64`（如在 x86 沙箱里跑 aarch64 产物）
- **GNU 套件（工具箱）**：`coreutils` `grep`（PCRE2）`sed` `find` `xargs` `diff` `tar` `xz` `zip`（全静态，GNU 语义一致）

## 4. Python 包管理（重点）

本环境**没有 pip**，统一走 `uv`（`pip`/`pip3` 命令已桥接到 uv，直接调用也可）：

```sh
uv venv .venv && source .venv/bin/activate
uv pip install requests            # venv 内安装
uv pip install --system <包>        # 或系统级安装
uv tool run cowsay -t hi           # 临时运行工具
```

## 5. 惯例与文档

- 每个工具都带说明：`/opt/skills/tools/<工具名>/USAGE.md`
- **优先级**：`/usr/local/bin` 在 PATH 最前——凡工具箱有同名工具（curl / python3 / uv / rg / fd / jaq / gawk / grep / sed / find / xargs / diff / tar / xz / zip / tmux / zstd / ssh 系等）按名字调用即命中工具箱版；`awk` 已直接指向工具箱 `gawk`
- 二进制真实位置：`/opt/skills/tools/<工具名>/amd64/<工具名>`（已统一软链到 `/usr/local/bin`）
- 系统 busybox 已是工具箱 1.38 版（`/bin/sh` 等全部 applet 同款）
- 容器内时间：`TZ=Asia/Shanghai`（`date` 即东八区）
- 默认工作目录 `/workspace`（可写）；`user`（uid 1000）可免密 `sudo`
