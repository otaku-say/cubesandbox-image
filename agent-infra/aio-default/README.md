# agent-infra/aio-default —— 与本地 iSH 同源的 Alpine 沙箱（v6）

**定位**：本地 iSH（iOS 上的 Alpine）的云端“手脚延伸”；v5 起扩展为**可编译、可跑 GitHub 工作流**的完整开发沙箱；v6 起与 iSH 的「AOJIT 迁移」对齐——工具箱只留增强件，系统能力由 apk 提供。

## v6 变更摘要（2026-10-12）

1. **工具箱 58 → 43 件**：AOJIT 内置加速的 15 件从工具箱下架
   （`busybox` `python3` `curl` `openssl` `ssh` `scp` `sftp` `ssh-add` `ssh-agent` `ssh-keygen` `ssh-keyscan` `sqlite3` `socat` `drill` `uv`）
2. **下架件改由 apk 提供**（云端没有 AOJIT，取 apk 源最新版即可，**不与 iSH 对齐版本号**）：
   `python3 py3-pip py3-setuptools py3-pillow py3-numpy nodejs npm curl openssl sqlite socat drill uv bind-tools openssh-client jq`
   —— 已按「有替代」或「交互式 TUI」裁掉 `vim 7zip b3sum nnn ncdu`
3. **不再替换系统 busybox**（工具箱已无 busybox）：`/bin/busybox` 保持 Alpine 原版
4. **不再做 `pip → uv` 桥接**：装真 pip（与本地 iSH 手感一致）；`uv` 仍可用
5. **构建输入改为直取产物源**：`fetch-toolbox.sh` 从 `otaku-say/ish-toolbox` 的固定 commit
   取 43 件产物 + `SHA256SUMS.amd64` 逐件校验（不再依赖 skills 镜像仓、不再内嵌脚本哈希常量）
6. 其余保持 v5：`alpine:3.23.6`、envd 直取官方桶、git edge 四件套、zig 0.17.0、
   `TZ=Asia/Shanghai`、`AIO_API_SURFACE=v2`、模板标签 **30G / cpu=3000 / memory=3000**

## 设计原则

1. **工具层 = 工具箱 43 件 + apk 系统层**。工具箱（与 iSH 同源同校验）保留**系统没有或明显更强**的部分：
   GNU 套件（coreutils/grep+PCRE2/sed/find/xargs/diff/tar/xz/zip）、现代搜索与数据工具（rg/fd/sd/jaq/yq）、
   终端与进程（tmux/faketty/tini/chronic/pstree）、加密（rage/rage-keygen）、脚本（bash/patch）等；
   解释器与网络/加密 CLI 由 apk 提供。
2. **平台契约对齐官方 base**：envd(`:49983`) / cube-entrypoint / `/usr/bin/nice` / `user(uid=1000)` 账号
   （免密 sudo、`/etc/shells` 登记、可写 `/workspace` 工作目录）
3. **路径手感对齐 iSH**：`/usr/local/bin` 工具入口、`/opt/skills/tools` 工具树、`/opt/bin`、`/root/workspace`、PATH 一致

## 组成

| 层 | 内容 | 来源 |
|---|---|---|
| 基础 | Alpine 3.23.6（系统 busybox 原版） | `alpine:3.23.6` |
| 契约 | envd `v0.9.202610091259-…`（sha 校验）；cube-entrypoint.sh（vendored） | e2b-artifact-binaries / CubeSandbox master |
| PID 1 | tini v0.19.0（静态单文件） | 工具箱 43 件之一 |
| 守护 | aiod v0.9.2（musl 静态 + SHA256SUMS 校验） | aio-static.tos-cn-beijing.volces.com |
| 工具 | 工具箱 43 件（逐件 SHA256 校验；含 GNU 套件 / unzip / yq / **tmux 3.8**） | otaku-say/ish-toolbox @ TOOLBOX_REF |
| 系统 | python3/pip/pillow/numpy、node/npm、curl/openssl/sqlite/socat/drill/uv/dig/jq、openssh-client | apk（3.23 本分支最新版） |
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
- Python 包：`pip install <包>`（真 pip，`PIP_BREAK_SYSTEM_PACKAGES=1`）；也可 `uv pip install --system <包>`
- 图片/数值：`python3 -c "from PIL import Image ..."`、`python3 -c "import numpy"`
- 编译：`zig cc` / `make`；交叉：`zig cc -target aarch64-linux-musl ...`，用 `qemu-aarch64` 直接跑产物
- 工作目录：`/workspace`（容器默认 cwd，可写；`user` 可免密 `sudo`）
- 时间：容器 `TZ=Asia/Shanghai`；`date` 即东八区

## 已知事项与边界

1. **AIO_API_SURFACE=v2**：仅服务 v2 面；旧 `/v1/*` 接口返回 404（预期行为；如需 v1 兼容改 `full`）。
2. **tmux（工具箱提供，兼 aiod shell 后端）**：3.7 存在 `list-keys` 回归（破坏 aiod 探测）；
   3.8 修复且保留完整 terminfo fallback —— aiod 直接使用工具箱 tmux，无任何专用二进制/兼容层（详见 `BUILD-NOTES.md`）。
3. **工具来源分离**：`command -v rg` → 工具箱；`command -v python3` → apk。判断"是不是工具箱的"看
   `readlink -f $(command -v <名>)` 是否落在 `/opt/skills/tools/`。
4. 升级手册：`upstream.txt`（手工项清单）+ `fetch-toolbox.sh`（按 commit 的 SHA256SUMS 校验）。

## 验收记录

> v6 数据见 CI 与 `BUILD-NOTES.md`；v1–v5 历史验收见 git 历史。
