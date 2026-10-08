# agent-infra/aio-default —— 与本地 iSH 同源的极简 Alpine 沙箱

**定位**：本地 iSH（iOS 上的 Alpine）的云端“手脚延伸”。双端同一套工具、同族系统、
同一安装脚本与路径手感 —— agent 在 iSH 上熟悉的命令，云端沙箱零学习成本直接复用。

## 设计原则

1. **同版本同规则**：基础镜像 `alpine:3.21.0`，与本地 iSH 完全同版本；除 CPU 架构
   （amd64 vs aarch64）外无差异。
2. **零 apk 软件**：镜像内除平台必需组件外，不安装任何发行版软件包；
   “干活工具”全部来自 ish-toolbox 46 件静态二进制（与 iSH 同仓库、同 commit、同校验）。
   系统 `/bin/busybox` 亦切换为工具箱完整版 1.38.0（408 applet；原系统版 304）。
3. **平台契约优先**：envd / cube-entrypoint 与官方 base 逐字节一致；
   tini 因 base 原版为 glibc 动态链接而改用工具箱静态版（同为 v0.19.0）；
   aiod 固定 v0.9.2（musl 静态，SHA256SUMS 校验）。
4. **路径手感对齐 iSH**：`/usr/local/bin` 工具入口、`/opt/skills/tools` 工具树、
   `/opt/bin`、`/root/workspace`、`PATH` 与 iSH 完全相同。

## 组成

| 层 | 内容 | 来源 |
|---|---|---|
| 基础 | Alpine 3.21.0（系统 busybox 切换为 1.38.0） | `alpine:3.21.0` |
| 契约 | envd / cube-entrypoint.sh（逐字节复制） | `ghcr.io/tencentcloud/cubesandbox-base` |
| PID 1 | tini v0.19.0（静态单文件） | ish-toolbox |
| 守护 | aiod v0.9.2 | aio-static.tos-cn-beijing.volces.com |
| 工具 | ish-toolbox 46 件 @ `c6a7f163`（逐件 SHA256 校验） | otaku-say/skills |
| 适配 | aiod 专用 tmux 3.8-rc3（纯静态单文件，zig 0.18-dev 编译） | 本目录产物（构建档案见 BUILD-NOTES.md） |

## 与本地 iSH 的同源对照

| 维度 | 本地 iSH | aio-default |
|---|---|---|
| 系统 | Alpine 3.21.0 (aarch64) | Alpine 3.21.0 (amd64) |
| busybox | 系统 1.37 + 工具箱 1.38（命令层） | 系统已切 1.38 + 工具箱 1.38 |
| 工具箱 | ish-toolbox 46 件 | 同 commit、同版本、同安装脚本（`scripts/install.sh`） |
| 工具入口 | `/usr/local/bin` 软链 + shell PATH 块 | 相同（非登录 shell 场景亦全量可见，46/46） |
| PATH | `/usr/local/sbin:…:/usr/bin:/sbin:/bin:/opt/bin` | 完全一致 |
| 关键链接 | `/bin/bash`、`/usr/bin/python3` → 工具箱 | 相同 |

## 构建

- CI：本目录发生变更 push 后自动构建（`build.yml` 推 `:latest`；特性分支走
  `branch-build.yml` 构建 + 冒烟后推 `:test`）。
- 本地：`./build.sh`（构建 + 冒烟测试）；`./build.sh --push` 追加推送。

## 注册模板

镜像 LABEL 已携带全套模板默认值（端口 / 探针 / 可写层 / CPU / 内存 / 别名），一键注册：

```sh
cube-cli tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-default:latest \
  --alias=aio-default --create
```

## 验收记录

> 2026-10-08：v1/v2 已通过 CI 冒烟与真机全量验收；v3（aiod 专用 tmux 3.8-rc3 静态单文件）
> 数据待刷新。

## 已知事项与边界

1. **aiod 专用 tmux 3.8-rc3（纯静态单文件）**
   tmux **3.7** 存在 `list-keys -T <table> <key>` 按 key 筛选的回归（返回空），会破坏
   aiod 能力探测（回退 native shell backend）；alpine edge 官方编译的 3.7c 与本项目
   自编译 3.7c 行为完全一致，属**上游回归**（3.5a/3.6 正常）。
   **3.8-rc3 已修复该回归**，故本镜像采用 `aiod-tmux-3.8rc3-x86_64-static`
   （zig 0.18-dev 静态编译，1.44MB 单文件，SHA256 内嵌于 Dockerfile 校验），
   仅经 `AIO_TMUX_BIN` 供 aiod 使用；用户/agent 手敲的 `tmux`（工具箱 3.7c）不受影响。
   移除方式：删除该文件与 Dockerfile 中 `AIO_TMUX_BIN` 一行（aiod 将回退 native）。
   构建与升级流程见 `BUILD-NOTES.md`（正式 3.8 发布后按同流程重编替换即可）。
2. **不包含 pip / git / gh / uv / zig 等**
   本镜像策略为“零额外软件”。如需增补，参见附带的《建议软件清单》
   （git/gh 与 pip 为第一梯队候选）。
3. **升级手册**
   - `TOOLBOX_REF`（ish-toolbox commit）变更：同步更新 `fetch-toolbox.sh` 内嵌的
     4 个 SHA256（脚本头部附命令）并重建。
   - `AIOD_VERSION` 变更：改 Dockerfile ARG；升级后 `smoke-test.sh` 的
     `"selected":"tmux"` 断言会兜底检查兼容性是否仍成立。
   - aiod 专用 tmux：见 `BUILD-NOTES.md`；`smoke-test.sh` 含版本断言（3.8）。
   - 上游 digest 由 `Track Upstream Images` 每日巡检；变更会自动触发重建并开 issue。
