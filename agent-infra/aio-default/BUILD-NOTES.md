# aiod 专用 tmux 3.8-rc3 静态单文件 —— 构建档案

| 项 | 值 |
|---|---|
| 产物 | `aiod-tmux-3.8rc3-x86_64-static` |
| SHA256 | `ec334bab3b16fdf201b8df07bb94264f5ae4dd97424e430a2b702184c705a33a` |
| 大小 | 1,508,896 B |
| 版本 | `tmux 3.8-rc3` |
| 编译器 | zig 0.18.0-dev.35+5e754304d（`zig cc -target x86_64-linux-musl`） |
| 静态性 | 无 PT_INTERP / 无 NEEDED（readelf 验证） |

## 背景

- tmux **3.7** 存在 `list-keys -T <table> <key>` 按 key 筛选的**回归**（返回空），
  会破坏 aiod 的能力探测（回退 native shell backend）。
  实测：3.5a/3.6 正常；3.7c 异常（alpine edge 官方编译与自编译行为一致 → 上游问题）。
- **3.8-rc3 已修复**该回归（筛选正常、`aiod` 探测 `selected=tmux`）。
- 形态选择：**纯静态单文件**（单文件入库、无动态依赖、无 rpath/patchelf 步骤），
  与 ish-toolbox 的产物风格一致。

## 构建步骤（alpine 3.21 容器内，root）

```sh
# 0) 构建环境
apk add build-base bison patch ncurses   # ncurses 包提供 tic（构建 terminfo 必需！）
# zig：官方 0.18.0-dev tarball 解包到 /opt/zig18，wrapper：
printf '#!/bin/sh\nexec /opt/zig18/zig cc -target x86_64-linux-musl "$@"\n' > /tmp/fakebin/musl-gcc
chmod +x /tmp/fakebin/musl-gcc
export PATH=/tmp/fakebin:$PATH

# 1) ncurses 6.5（静态、wide、内嵌 fallback；配方同 ish-toolbox scripts/build/tmux.sh）
#    ./configure --without-shared --without-debug --without-ada --without-manpages \
#      --without-tests --without-progs --without-cxx --without-cxx-binding \
#      --prefix=/tmp/ncurses-build-amd64 \
#      --with-terminfo-dirs="/etc/terminfo:/usr/share/terminfo:/usr/lib/terminfo:/lib/terminfo:/usr/local/share/terminfo" \
#      --with-fallbacks="xterm-256color,xterm,screen-256color,screen,tmux-256color,vt100,linux,ansi" \
#      CC=musl-gcc CFLAGS="<CSIZE>" LDFLAGS="<CLINK>"
#    （CSIZE=-Os -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -static）
#    （CLINK=-static -Wl,--gc-sections -Wl,--strip-all）

# 2) libevent 2.1.13-stable（--disable-shared --enable-static --disable-openssl）
# 3) utf8proc 2.12.0（make libutf8proc.a）

# 4) tmux 3.8-rc3
#    源码: https://github.com/tmux/tmux/releases/download/3.8-rc3/tmux-3.8-rc3.tar.gz
#    configure 关键：同时提供各代 curses 检测变量（3.5a 用 LIBTINFO*，3.7+ 用 LIBTINFOW*）：
env LIBTINFO_CFLAGS="-I<nc>/include -I<nc>/include/ncursesw" \
    LIBTINFO_LIBS="-L<nc>/lib -lncursesw -ltinfo" \
    LIBTINFOW_CFLAGS="-I<nc>/include -I<nc>/include/ncursesw" \
    LIBTINFOW_LIBS="-L<nc>/lib -lncursesw -ltinfo" \
    LIBNCURSESW_CFLAGS="-I<nc>/include -I<nc>/include/ncursesw" \
    LIBNCURSESW_LIBS="-L<nc>/lib -lncursesw" \
    LIBEVENT_CFLAGS="-I<ev>/include" LIBEVENT_LIBS="-L<ev>/lib -levent" \
    LIBUTF8PROC_CFLAGS="-I<u8>/include" LIBUTF8PROC_LIBS="-L<u8>/lib -lutf8proc" \
    CC=musl-gcc CFLAGS="<CSIZE>" \
    LDFLAGS="<CLINK> -L<nc>/lib -L<ev>/lib -L<u8>/lib" \
    ./configure --host=x86_64-unknown-linux-musl --enable-static --enable-utf8proc
make -j2
```

## 验证记录

- `readelf -l`：无 INTERP；`readelf -d`：无 NEEDED；ELF machine = `3e`（x86_64）
- 功能：`new-session` / `send-keys` / `capture-pane` 正常
- aiod：`AIO_TMUX_BIN=<该文件>` 探测 `selected=tmux`；PTY 直连 `pty exec` 正常
- 对照矩阵：3.5a ✓ / 3.6 ✓ / **3.7c ✗（官方与自编译一致，上游回归）** / **3.8-rc3 ✓（回归修复）**

## 升级指引

- **正式 3.8 发布后**：按上述流程重编（或复跑构建档案脚本），替换本目录二进制、
  更新 Dockerfile 内嵌 SHA256 与本文件表格，重跑 `smoke-test.sh`（含 `selected=tmux` 断言）。
- 若未来某版本再次出现探测不兼容：先跑 `list-keys -T root WheelUpPane` 单测定位
  （正常应输出一行 `bind-key ... WheelUpPane ...`）。
