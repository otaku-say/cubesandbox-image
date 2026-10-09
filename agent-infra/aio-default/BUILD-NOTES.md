# aio-default v5 重建记录（2026-10-09）

## 决策与来源（全部实测核验）

| 项 | 版本/来源 | 校验与实测 |
|---|---|---|
| 基座 | `alpine:3.23.6`（2026-09-17） | minirootfs sha256 核验 |
| envd | 官方桶最新构建 `v0.9.202610091259-41ed62c3bc4` | sha256 `f7b5a828…`（边车一致）；ELF amd64 静态 |
| cube-entrypoint.sh | TencentCloud/CubeSandbox master（vendored） | sha256 `5479737a…`（2026-10-09 获取） |
| git 全套 | **Alpine edge 四件套：git 2.56.0 / git-perl / git-lfs 3.7.1 / github-cli(gh) 2.102.0** | 干净 chroot 实测：19 包安装无 ERROR、apk rc=0；依赖全部来自 3.23 stable；`git lfs install --system` ✓ |
| zig | `0.17.0` 官方静态包 | sha `1cbe9df9…`；本机编译 + aarch64 交叉 + chroot 全通 |
| toolbox | otaku-say/skills @ `b77dd03a…`（**58 件**） | 58/58 校验（动态断言）；busybox 1.37→1.38 官方替换；幂等复跑 ✓ |
| aiod | v0.9.2（既有） | SHA256SUMS 校验 |

## git 方案选型记录（为什么最终选 edge 四件套）

1. **源码编译官方 2.56.0（放弃）** —— 预演实测在 musl 环境连续受阻：
   `REG_STARTEND` 缺失（→ NO_REGEX=NeedsStartEnd）、`linux/magic.h` 缺失（→ linux-headers）、
   **git 2.56 构建引入 Rust 组件（cargo）**，复杂度与维护量陡增 → 放弃自编译。
2. **Alpine edge 源安装（采纳，最终收敛为四件套）** —— 由 Alpine 官方团队为 musl 编译/测试：
   - 干净 chroot 实测安装清单（19 包）：仅 **git / git-init-template / perl-git / git-perl /
     git-lfs / github-cli** 6 包来自 edge；其余依赖（**libcurl 8.22.0**、libexpat、pcre2、
     perl 5.42.2、perl-error 等）**全部来自 3.23 stable** —— 无 edge 污染
   - `git-lfs` 包内置 post-install 脚本 = `git-lfs install --skip-repo --system`
     （裸 chroot 缺 /dev/null 时会报错——属测试环境假象；正常容器环境 rc=0 无报错，已实测）
   - 构建流程：临时追加 @edge(main+community) → `apk update` → 安装四件套 →
     `git lfs install --system` → **删除 @edge 行** → 清缓存（最终镜像运行时 apk 不接触 edge）
   - LFS 全链路实测：`git lfs track` → commit → `git lfs ls-files` 显示指针 ✓；
     `.gitattributes` 过滤器写入 ✓
   - 版本策略：四件套随 edge **浮动**（重建即取边缘最新稳定版）；
     冒烟断言 `git >= 2.56` 且 `filter.lfs` 已初始化
   - 已评估未装的子包：git-bash-completion / git-prompt / git-email（agent 场景低频，按精简口径不装）；
     git-svn / git-cvs 为独立子包（未装，需要可加）
   - **apk world 清理（关键修复）**：`pkg@edge` 会在 `/etc/apk/world` 留下带 tag 的世界依赖；
     只删 repositories 行会让后续任何 `apk add` 报 `missing repository tags` 直接失败（已复现，
     会堵住运行时"agent 临时装包"场景）。修复：安装后同步 `sed -i 's/@edge//g' /etc/apk/world`；
     构建内断言 `! grep @edge /etc/apk/world`，冒烟断言 world/repositories 双洁净 + `apk add --simulate` 可用
   - sudo 链：Alpine sudo 内置 `@includedir /etc/sudoers.d`（已确认）+ `visudo -cf` 解析通过；
     `sudo -u user sudo -n id` → uid=0 实测可提权（裸 chroot 的 "unable to allocate pty" 系
     devpts 缺失的嵌套环境假象；容器环境由 CI 冒烟做最终断言）

## 预演证据（alpine 3.23.6 chroot，全部实测）

- toolbox：58/58 校验安装、`--set-default-busybox` 替换 + 备份 + 幂等；python3 3.12.15 / uv 0.12.24 / tmux 3.8 / rg / GNU 套件（coreutils 9.12、grep 3.12 PCRE2、sed 4.10、find 4.11、diff 3.12、tar 1.35、xz 5.8.4、zip、unzip）/ yq 4.54.1（自动跟随）运行 ✓；https 200
- git 全套（edge 四件套）：安装无 ERROR（干净环境 rc=0）；`git --version` = 2.56.0；
  本地 init/commit、`git ls-remote https://github.com/…` ✓；`git lfs install --system` + LFS 指针提交 ✓；
  gh 2.102.0 / git-lfs 3.7.1 运行 ✓
- zig：`zig version` + `zig cc`（本机 x86_64-musl / aarch64 交叉）+ qemu 运行 ✓
- busybox 替换后 apk 操作仍正常（换装 file/zstd 实测）

## 与 v4 的差异

| 维度 | v4 | v5 |
|---|---|---|
| 基座 | alpine 3.21.0 | **alpine 3.23.6** |
| envd 来源 | COPY 自 cubesandbox-base（v0.5.13 代） | **官方桶最新构建直取（sha 校验）** |
| cube-entrypoint | COPY 自 cubesandbox-base | **官方 master vendored** |
| 工具箱 | 46 件 | **58 件**（+GNU 套件 +unzip +yq +uv；python3 动态版） |
| git 链 | 无 | **git 全套（edge 四件套：git 2.56 / git-perl / git-lfs / gh）** |
| 编译 | 无 | **zig 0.17.0 + 编译组件 + qemu-aarch64** |
| Agent 层 | 无 | **toolbox 命令 / AGENT-GUIDE / 缺命令提示 / pip→uv 桥** |
| 权限/目录 | 无 user 配置 | **user 免密 sudo + `/etc/shells` + `/workspace`（WORKDIR，user 属主）+ `awk→gawk` 工具箱优先链接** |
| ENV | LANG/LC_ALL/AIO_* | +**TZ=Asia/Shanghai**、**AIO_API_SURFACE=v2** |
| LABEL | 10G / 2000 / 2048 | **30G / cpu=3000 / memory=3000** |

## 精简记录（三轮收敛 · 终版，2026-10-09）

**原则：工具箱（58 件单文件静态）→ busybox → 最后才 apk。**

1. 一轮：裁 `curl/wget/coreutils/jq/bzip2/netcat-openbsd`（工具箱或 busybox 替代）
2. 二轮：构建序调整（工具箱 = 步骤 2，下载走工具箱 curl）；`awk`→工具箱 gawk；冒烟新增“工具箱优先链路”硬断言
3. 三轮（自编 GNU 工具上架后）→ 四轮定稿（unzip/yq 入库，TOOLBOX_REF 升至 `b77dd03a`，**58 件**）：
   - `tar / xz / zip / grep（PCRE2）/ sed / find / xargs / diff`：**全部改由工具箱 GNU 静态版提供**（语义一致，grep -P 实测可用）
   - `yq`：**纳入「跟随上游」自动链**（sync-upstream 每日巡检 mikefarah/yq latest → 三判据 → UPX 入库；弃 apk yq-go 与 Dockerfile 下载块）
   - `rsync`：裁（沙箱↔主机传输 = aiod-cli；外部增量部署属低频，`apk add rsync` 可秒回）
   - `unzip`：**自编译入库工具箱**（Info-ZIP 6.0 全静态 + Alpine 同源 30 项安全补丁；CI 双架构 UPX 后 87/90KB；apk 已移出）
   - **最终 apk 顶层 16 件**：`ca-certificates tzdata sudo / make pkgconf linux-headers binutils file / autoconf automake libtool m4 bison flex / qemu-aarch64 gcompat`
   - 校验：新 REF 4 哈希已固化（install/update 同前；SUMS `a38e0cab…` / DOCS `e48b1d23…`）；工具数 47→58（冒烟与 SHA256SUMS.amd64 行数动态比对）；冒烟优先链扩至 28 项（+unzip/yq）
   - 健壮性加固（防不可见字符）：zig 校验改“取值比较式”（不依赖双空格分隔格式）、yq 匹配改单空格；
     全量扫描（本地字节级检查 + python 16 种模式 + GNU grep -P）0 命中

## 历史记录：tmux 3.8 升级与验证（v4 归档）

> 2026-10-08 ｜ 背景：aiod 的 shell 后端探测依赖 `tmux list-keys -T <table> <key>` 行为。

- **tmux 3.7 存在 list-keys 按 key 筛选回归**（返回空）→ 破坏 aiod 探测（回退 native backend）。
  实测对照：3.5a ✓ / 3.6 ✓ / **3.7c ✗**（alpine edge 官方编译与本项目自编译行为一致 → 上游回归）。
- **tmux 3.8 已修复该回归**，且静态构建保留完整 terminfo fallback（无系统 terminfo 也可工作）。
- 工具箱 tmux 自 **3.8** 起直接服务 aiod（无需任何专用二进制或兼容层）。

验证矩阵（本地沙箱实测）：

| 检查项 | 结果 |
|---|---|
| 纯静态（readelf：无 INTERP / 无 NEEDED） | ✓ |
| `list-keys -T root WheelUpPane` 筛选输出 | ✓（3.7c 为空，3.8 正常） |
| 藏掉系统 terminfo 后 `new-session`（pty+TERM） | ✓（fallback 生效） |
| aiod 探测（AIO_TMUX_BIN 或 PATH 两种方式） | ✓ `selected=tmux` |
| aiod PTY 直连（pty-new / pty exec / pty-rm） | ✓ |

构建与发布：`ish-toolbox/scripts/build/tmux.sh`（3.8 起）→ CI 双架构 → 入库；skills 仓库 15 分钟镜像；本目录通过 `TOOLBOX_REF` 提升。
（手工复现细节见 git 历史 v4 版本。）
