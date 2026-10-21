# agent-infra/aio-default —— 与本地 iSH 同源的 Alpine 沙箱（v8）

**定位**：本地 iSH（iOS 上的 Alpine）的云端“手脚延伸”；v5 起扩展为**可编译、可跑 GitHub 工作流**的完整开发沙箱；v6 起与 iSH 的「AOJIT 迁移」对齐——工具箱只留增强件，系统能力由 apk 提供；v7 集成官方 MCP 网关；v8 集成 AI-Native 搜索引擎 XERJ（透明按需自愈激活与代码段精准召回）。

## v8 变更摘要（2026-10-21）

1. **集成 AI-Native 搜索引擎 XERJ**（支持 Elasticsearch 8.x 协议兼容）：
   - 上游直装官方 musl 静态单文件，动态追踪最新 Release（`ARG XERJ_VERSION=latest`）+ SHA256 强校验；
   - 部署真实二进制至 `/usr/local/bin/xerj-real`，提供透明惰性按需拉起包装器 `/usr/local/bin/xerj`；
   - **0 初始内存开销**：沙箱冷启动不拉起后台服务；首次调用 `autoindex` / `search` / `def` / `mcp` 时秒级自动激活（~200ms）；
   - 提供 `xerj-service {start|stop|restart|status}` 进程管理工具，任务完成后可 `stop` 彻底释放内存；
   - 暴露端口 `9200`（原生 REST 9201，gRPC 9202），与 `aiod` 8080 和 `envd` 49983 端口物理隔离。
2. **工作区开箱即用 MCP 与 Agent 引导**：
   - 在 `/workspace` 预置 `.mcp.json`（原生 17 个 XERJ MCP 工具）与 `AGENTS.md`；
   - 同步更新 `AGENT-GUIDE.md`、`motd`、`bash_env.sh`：强力引导 Agent 在复杂项目排查时**放弃大面积 grep 盲刷，改用 xerj 智能代码段召回（精准行号与上下文，节省 2.7x Token）**。
3. **冒烟测试与模板标签同步**：
   - `smoke-test.sh` 覆盖 XERJ 默认未监听（0 内存）、首次调用自动自愈激活、search 代码段召回、`xerj-service stop` 优雅停机全链路；
   - 模板标签补充 `9200` 端口暴露。

## 设计原则

1. **工具层 = 工具箱 43 件 + apk 系统层 + 上游优先服务（uv / mcp-gateway / xerj）**。
   工具箱保留 GNU 套件、现代搜索与数据工具（rg/fd/sd/jaq/yq）等 43 件增强；
   `xerj` 与 `uv` 遵循上游优先原则由官方 Release 提供。
2. **资源极致按需**：后台重型服务采用透明惰性激活，冷启动 0 内存占用，兼顾开箱即用与轻量高效。
3. **平台契约对齐官方 base**：envd(`:49983`) / cube-entrypoint / `/usr/bin/nice` / `user(uid=1000)` 账号
   （免密 sudo、`/etc/shells` 登记、可写 `/workspace` 工作目录）
4. **路径手感对齐 iSH**：`/usr/local/bin` 工具入口、`/opt/skills/tools` 工具树、`/opt/bin`、`/root/workspace`、PATH 一致

## 组成

| 层 | 内容 | 来源 |
|---|---|---|
| 基础 | Alpine 3.23.6（系统 busybox 原版） | `alpine:3.23.6` |
| 契约 | envd `v0.9.202610091259-…`（sha 校验）；cube-entrypoint.sh | e2b-artifact-binaries / CubeSandbox master |
| PID 1 | tini v0.19.0（静态单文件） | 工具箱 43 件之一 |
| 守护 | aiod v0.9.2（musl 静态 + SHA256SUMS 校验） | aio-static.tos-cn-beijing.volces.com |
| 搜索 | **XERJ 最新版**（musl 静态 + sha256 校验；透明按需自愈激活；端口 9200） | xerj-org/xerj GitHub Release |
| 网关 | mcp-gateway（CubeSandbox 官方源码编译；端口 50005） | TencentCloud/CubeSandbox v0.7.3 |
| 工具 | 工具箱 43 件（逐件 SHA256 校验；含 GNU 套件 / unzip / yq / tmux 3.8） | otaku-say/ish-toolbox @ TOOLBOX_REF |
| 系统 | python3/pip/pillow/numpy、node/npm、curl/openssl/sqlite/socat/drill/uv/dig/jq、openssh-client | apk（3.23 本分支最新版） |
| 开发链 | git 四件套（edge：git/git-perl/git-lfs/github-cli）；zig 0.17.0 / 编译组件 / qemu-aarch64 | apk（edge 四件套）+ 官方 Release（zig） |

## 构建

- CI：本目录变更 push 后自动构建（`build.yml` 推 `:latest`；特性分支走 `branch-build.yml` 构建 + 冒烟后推 `:test`）。
- 本地：`./build.sh`（构建 + 冒烟测试）；`./build.sh --push` 追加推送。

## 注册模板

镜像 LABEL 已携带全套模板默认值（端口 / 探针 / 可写层 40G / CPU 3000 / 内存 4000 / 别名），一键注册：

```sh
cube-cli tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-default:latest \
  --alias=aio-default --create
```

## 给 Agent 的用法（速查）

- 工具速查：`toolbox`（或读 `/opt/skills/tools/AGENT-GUIDE.md`）
- 代码检索：`xerj autoindex <项目>` 后用 `xerj search "<内容>"` 检索代码段（自动按需拉起；任务结束可 `xerj-service stop` 释放内存）
- Python 包：`uv pip install --system <包>`（极速推荐）；也可 `pip install <包>`
- 编译：`zig cc` / `make`；交叉：`zig cc -target aarch64-linux-musl ...`，用 `qemu-aarch64` 直接跑产物
- 工作目录：`/workspace`（容器默认 cwd，可写；预置 `.mcp.json`；`user` 可免密 `sudo`）
- 时间：容器 `TZ=Asia/Shanghai`；`date` 即东八区
