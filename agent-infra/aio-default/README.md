# agent-infra/aio-default —— 与本地 iSH 同源的 Alpine 沙箱（v5）

**定位**：本地 iSH（iOS 上的 Alpine）的云端“手脚延伸”；v5 起扩展为**可编译、可跑 GitHub 工作流**的完整开发沙箱。

## v5 变更摘要（2026-10-09）

1. 基座 `alpine:3.21.0` → **`alpine:3.23.6`**（最新 3.23.x）
2. **envd 改直取官方产物**：`storage.googleapis.com/e2b-artifact-binaries`（最新构建 + sha256 边车校验）；
   `cube-entrypoint.sh` 采用 CubeSandbox 官方 master 版（vendored，sha 见 `upstream.txt`）
   —— **不再依赖 cubesandbox-base 镜像**
3. **git 全套（官方 edge 源，四件套）**：git / git-perl / git-lfs / github-cli(gh) 统一 `@edge` 安装
   （官方 musl 构建；依赖实测全部来自 3.23 stable；含 `git lfs install --system` 全局初始化；
   当前版本 git 2.56 / git-lfs 3.7.1 / gh 2.102.0，随 edge 滚动）
4. **开发链**：**zig 0.17.0**（含 `cc`/`c++` wrapper 与交叉编译）、qemu-aarch64（交叉测试）、
   make/perl/pkgconf/binutils/linux-headers/autotools 全家（GNU 基础套件由工具箱提供）
5. **Agent 工具体验**：tar/xz/zip/grep/sed/find/xargs/diff/unzip/yq 全部由工具箱提供（unzip/yq 自动跟随上游）；curl/wget/jq/nc 由工具箱或 busybox 承担；apk 仅保留 16 件刚需；`toolbox` 速查命令 +
   `/opt/skills/tools/AGENT-GUIDE.md` + 命令未找到提示（BASH_ENV）+ `pip`→`uv` 桥
6. 环境：`TZ=Asia/Shanghai`、`AIO_API_SURFACE=v2`（仅服务 v2 面）；模板标签 **30G / cpu=3000 / memory=3000**

## 设计原则

1. **工具层 = ish-toolbox 全量 58 件**（与 iSH 同仓库、同 commit、同安装脚本、同校验；含 GNU 套件 coreutils/grep/sed/find/xargs/diff/tar/xz/zip、unzip、yq）；
   系统 `/bin/busybox` 由官方安装脚本“发现即替换”为工具箱 1.38.0，**作为沙箱默认终端**
   （原版备份 `/bin/busybox.pre-toolbox`，`--unset-default-busybox` 可还原）
2. **平台契约对齐官方 base**：envd(`:49983`) / cube-entrypoint / `/usr/bin/nice` / `user(uid=1000)` 账号（免密 sudo、`/etc/shells` 登记、可写 `/workspace` 工作目录）
3. **路径手感对齐 iSH**：`/usr/local/bin` 工具入口、`/opt/skills/tools` 工具树、`/opt/bin`、`/root/workspace`、PATH 一致
4. **v5 起允许 apk 软件**（开发链所需；与工具箱互补——工具箱仍是首选工具层）

## 组成

| 层 | 内容 | 来源 |
|---|---|---|
| 基础 | Alpine 3.23.6（busybox 切换为工具箱 1.38.0 默认终端） | `alpine:3.23.6` |
| 契约 | envd `v0.9.202610091259-…`（sha 校验）；cube-entrypoint.sh（vendored） | e2b-artifact-binaries / CubeSandbox master |
| PID 1 | tini v0.19.0（静态单文件） | ish-toolbox |
| 守护 | aiod v0.9.2（musl 静态 + SHA256SUMS 校验） | aio-static.tos-cn-beijing.volces.com |
| 工具 | ish-toolbox 58 件（逐件 SHA256 校验；含 GNU 套件 / unzip / yq 与 **tmux 3.8**） | otaku-say/skills @ TOOLBOX_REF |
| 开发链 | git 四件套（edge：git/git-perl/git-lfs/github-cli）；zig 0.17.0 / 编译组件 / qemu-aarch64 | apk（edge 四件套）+ 官方 Release（zig） |

## 构建

- CI：本目录变更 push 后自动构建（`build.yml` 推 `:latest`；特性分支走 `branch-build.yml` 构建 + 冒烟后推 `:test`）。
- 本地：`./build.sh`（构建 + 冒烟测试）；`./build.sh --push` 追加推送。

## 注册模板

镜像 LABEL 已携带全套模板默认值（端口 / 探针 / 可写层 30G / CPU 3000 / 内存 3000 / 别名），一键注册：

```sh
cube-cli tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-default:latest \
  --alias=aio-default --create
```

## 给 Agent 的用法（速查）

- 工具速查：`toolbox`（或读 `/opt/skills/tools/AGENT-GUIDE.md`）
- Python 包：`uv venv .venv && uv pip install ...`（`pip`/`pip3` 命令已桥接到 uv）
- 编译：`zig cc` / `make`；交叉：`zig cc -target aarch64-linux-musl ...`，用 `qemu-aarch64` 直接跑产物
- 工作目录：`/workspace`（容器默认 cwd，可写；`user` 可免密 `sudo`）
- 时间：容器 `TZ=Asia/Shanghai`；`date` 即东八区

## 已知事项与边界

1. **AIO_API_SURFACE=v2**：仅服务 v2 面；旧 `/v1/*` 接口返回 404（预期行为；如需 v1 兼容改 `full`）。
2. **tmux（工具箱提供，兼 aiod shell 后端）**：3.7 存在 `list-keys` 回归（破坏 aiod 探测）；
   3.8 修复且保留完整 terminfo fallback —— aiod 直接使用工具箱 tmux，无任何专用二进制/兼容层（详见 `BUILD-NOTES.md`）。
3. 工具箱 python3 无 pip/ensurepip（设计如此，用 uv）；未装 Node（轻量 JS 用 `qjs`；需要时 `apk add nodejs`）。
4. 升级手册：`upstream.txt`（手工项清单）+ `fetch-toolbox.sh` 头部（4 个内嵌哈希的维护命令）。

## 验收记录

> v5 数据见 CI 与 `BUILD-NOTES.md`；v1–v4 历史验收见 git 历史。
