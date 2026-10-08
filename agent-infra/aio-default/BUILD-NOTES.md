# tmux 3.8 升级与验证记录

> 2026-10-08 ｜ 背景：aiod 的 shell 后端探测依赖 `tmux list-keys -T <table> <key>` 行为。

## 结论

- **tmux 3.7 存在 list-keys 按 key 筛选回归**（返回空）→ 破坏 aiod 探测（回退 native backend）。
  实测对照：3.5a ✓ / 3.6 ✓ / **3.7c ✗**（alpine edge 官方编译与本项目自编译行为一致 → 上游回归）。
- **tmux 3.8 已修复该回归**，且静态构建保留完整 terminfo fallback（无系统 terminfo 也可工作）。
- 工具箱 tmux 自 **3.8** 起直接服务 aiod（无需任何专用二进制或兼容层）。

## 验证矩阵（本地沙箱实测）

| 检查项 | 结果 |
|---|---|
| 纯静态（readelf：无 INTERP / 无 NEEDED） | ✓ |
| `list-keys -T root WheelUpPane` 筛选输出 | ✓（3.7c 为空，3.8 正常） |
| 藏掉系统 terminfo 后 `new-session`（pty+TERM） | ✓（fallback 生效） |
| aiod 探测（AIO_TMUX_BIN 或 PATH 两种方式） | ✓ `selected=tmux` |
| aiod PTY 直连（pty-new / pty exec / pty-rm） | ✓ |

## 构建与发布（GitHub Actions）

- 构建脚本：`ish-toolbox/scripts/build/tmux.sh`（3.8 起；静态配方 = ncurses 6.5（静态+fallback）+
  libevent 2.1.13 + utf8proc 2.12 + iSH 补丁 tmux-ishfix.patch）。
- CI：`ish-toolbox` 的 `build-source.yml`（双架构矩阵）→ 产物直接提交入库（`tools/tmux/{arm64,amd64}/`）。
- 同步：`skills` 仓库每 15 分钟镜像 ish-toolbox 的 `tools/`；随后本镜像通过 `TOOLBOX_REF` 提升获取。

## 手工复现（调试用）

若需本地复现（alpine 容器）：

1. 装工具链：`apk add build-base bison patch ncurses`（**ncurses 提供 tic——fallback 生成必需**）
2. 编译器 wrapper（zig cc）：`printf '#!/bin/sh\nexec /opt/zig18/zig cc -target x86_64-linux-musl "$@"\n' > /tmp/fakebin/musl-gcc`
3. ncurses：configure 关键参数 `--without-shared --with-fallbacks="xterm-256color,...,tmux-256color,..."`；
   **安装后补软链** `libtinfo.a` / `libncurses.a` → `libncursesw.a`（tmux 链接需要）
4. tmux 3.8：configure 需同时提供各代检测变量（`LIBTINFO_*`、`LIBTINFOW_*`、`LIBNCURSESW_*`、`LIBEVENT_*`、`LIBUTF8PROC_*`）；
   `--enable-static --enable-utf8proc`
5. 验证：`readelf`（静态）+ 藏 terminfo 的 pty 测试 + aiod 探测

> 完整历史版本（3.7c 时期的手工构建档案与 aiod 专用 tmux 方案）见 git 历史；
> v4 起 tmux 完全由工具箱提供，本文件仅作升级与验证记录。
