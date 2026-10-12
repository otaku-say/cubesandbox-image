# aio-default 工具箱速查（AGENT-GUIDE）

> 本沙箱 = **ish-toolbox 43 件静态工具**（与本地 iSH 同源同版本）+ **apk 系统层**（解释器 / 网络与加密 CLI / 编译链）。
> 找不到命令时先 `command -v <名称>` 检查，或运行 **`toolbox`** 查看本表与全量清单。

## 1. 命令落位（2026-10 AOJIT 迁移后）

| 命令 | 来自 | 说明 |
|---|---|---|
| `rg` `fd` `jaq` `yq` `sd` `gawk`（`awk`）`coreutils` `grep` `sed` `find` `xargs` `diff` `tar` `xz` `zip` `unzip` | 工具箱 | GNU / 现代替代，静态单文件 |
| `tmux` `faketty` `tini` `chronic` `pstree` `qjs` `rage` `sponge` `tree` `zstd` `bash` `patch` 等 | 工具箱 | 见 `toolbox` 清单 |
| `python3` `pip` `node` `npm` | apk | 系统版（云端无 AOJIT，取 apk 最新版；版本与 iSH 不要求一致） |
| `curl` `openssl` `sqlite3` `socat` `drill` `uv` `dig` `jq` | apk | 原工具箱自带，AOJIT 迁移后改由 apk 提供 |
| `git` `git-lfs` `gh` | apk(edge) | git 2.56 + LFS + GitHub CLI |
| `zig` `cc` `c++` `make` `pkgconf` `binutils` | apk / 官方包 | 编译链（`zig cc` 即 C/C++ 编译器） |

**已下架（不再随工具箱分发）**：`busybox` `python3` `curl` `openssl` `ssh` `scp` `sftp` `ssh-add` `ssh-agent` `ssh-keygen` `ssh-keyscan` `sqlite3` `socat` `drill` `uv` —— 前 15 件均由系统自带的 apk 包装提供。

## 2. 高频对应关系（LLM 工作流最常踩的"命令没有"）

| 常想用的 | 本环境可用 | 说明 |
|---|---|---|
| jq | `jaq`（工具箱）+ `jq`（apk） | 两者都有；`jaq` 为 Rust 实现，`--stream`/`-a` 未实现，需要这两项时用 `jq` |
| yq | `yq`（工具箱） | YAML/JSON 通用处理（jq 语法体系） |
| unzip | `unzip`（工具箱） | 解压 .zip（加密包带 `-P`；busybox 版不支持加密/Zip64） |
| grep / find / sed | 工具箱 GNU 版 + `rg` / `fd` / `sd` | 大目录搜索优先 `rg`，简单查找用 `fd` |
| awk | `gawk`（工具箱，`awk` 已指向它） | GNU Awk 5.4.1（`--csv`、`gensub`、`asort`） |
| python | `python3` / `pip`（apk 真 pip） | 需装包：`pip install <包>` 或 `uv pip install --system <包>` |
| node | `node` / `npm` / `npx`（apk） | 也可用 `qjs`（QuickJS，轻量、无 npm 生态） |
| dig | `drill` / `dig` | 两者都可用（apk bind-tools 提供 dig） |
| ssh/scp | 系统 `ssh` `scp` `sftp` `ssh-keygen` 等 | apk openssh-client 提供 |
| 图片处理 | `python3 -c "from PIL import Image ..."` | py3-pillow 已装 |
| 数值/数组 | `python3 -c "import numpy"` | py3-numpy 已装 |

## 3. 工具箱全清单（43 件，直接按名字调用）

**文本/数据**：`rg` `fd` `jaq` `yq` `gawk` `sd` `head-tail` `sponge` `csvquote` `jo` `lowdown`
**格式/网页**：`html2text` `hxselect` `strip-ansi` `qjs`
**文件/归档**：`zstd` `unzip` `pv` `entr` `fzy` `tree` `diffstat` `xxhsum`
**GNU 静态套件**：`coreutils`（单文件多路复用）`grep`（PCRE2）`sed` `find` `xargs` `diff` `tar` `xz` `zip`
**安全/加密**：`rage` `rage-keygen`（age 加密）
**进程/终端**：`pstree` `faketty` `chronic` `su-exec` `tini` `tmux`
**脚本/开发**：`bash` `envsubst` `patch`

## 4. Python 包管理

真 pip 已就绪（`pip` / `pip3` / `python3 -m pip`），也与 `uv` 并存：

```sh
pip install requests                 # 直接装（PIP_BREAK_SYSTEM_PACKAGES=1 已设）
uv pip install --system requests     # 或用 uv（更快）
uv venv .venv && source .venv/bin/activate && uv pip install requests
```

## 5. 惯例与文档

- 每个工具箱工具都带说明：`/opt/skills/tools/<工具名>/USAGE.md`
- **优先级**：`/usr/local/bin` 在 PATH 最前——凡工具箱有同名工具（`rg`/`fd`/`jaq`/`yq`/`gawk`/`grep`/`sed`/`find`/`xargs`/`diff`/`tar`/`xz`/`zip`/`tmux`/`zstd`/`bash` 等）按名字调用即命中工具箱版；`awk` 已直接指向工具箱 `gawk`
- 二进制真实位置：`/opt/skills/tools/<工具名>/amd64/<工具名>`
- 容器内时间：`TZ=Asia/Shanghai`（`date` 即东八区）
- 默认工作目录 `/workspace`（可写）；`user`（uid 1000）可免密 `sudo`
