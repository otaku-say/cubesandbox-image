#!/bin/sh
# =============================================================================
# fetch-tmux.sh —— 构建期装配「aiod 专用 tmux 3.5a」（自包含目录）
#
# 背景：tmux 3.7 起（实测 3.6 及以前正常、3.7c 异常）改变了 list-keys 的按 key
# 筛选行为，导致 aiod 能力探测假阴性（回退 native shell backend）。
# 对照实证据：alpine edge 官方编译的 3.7c 与工具箱自编译 3.7c 行为完全一致
#（均“筛选空”且 aiod 探测失败），确认属上游行为而非编译方式差异。
# 本步骤为 aiod 装配一个与探测兼容的 tmux 3.5a：
#   - 来源：alpine v3.21 官方仓库包（与基础镜像同版本同仓库；pin 版本 + SHA256）
#   - 形态：tmux + 2 个必需 .so 放入 /out/aiod-tmux/，patchelf 设 rpath=$ORIGIN
#   - 作用域：仅 aiod 使用（AIO_TMUX_BIN 指向之）；工具箱 tmux 3.7c 保持原样
#
# 升级手册：更换版本时需同步更新下方 3 个包文件名与 SHA256（从 APKINDEX 取版本、
#           下载后 sha256sum 计算）。
# =============================================================================
set -eu

BASE=https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64
WORK=/tmp/tmux-build
OUT=/out/aiod-tmux

TMUX_PKG=tmux-3.5a-r0.apk
TMUX_SHA=62f0845e4afd78d68137c0b23114cc82569462774367247bfb2dd790c1c58b6c
LIBEV_PKG=libevent-2.1.13-r0.apk
LIBEV_SHA=b422180ca5aa2142f4b2429c7ad2ee0d6095a217d8519f90ba7af021a3b14b12
NCURSES_PKG=libncursesw-6.5_p20241006-r3.apk
NCURSES_SHA=3919cf673e841d91865213799ccfd5f77a48f5f9f5402723167470295ee32a49

check() { # <文件> <期望SHA> <描述>
  actual=$(sha256sum "$1" | awk '{print $1}')
  [ "$actual" = "$2" ] || { echo "校验失败: $3" >&2; exit 1; }
}

echo "[1/5] 下载 3 个官方包（alpine v3.21）"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/pkgs" "$WORK/x" "$OUT"
cd "$WORK/pkgs"
for pkg in $TMUX_PKG $LIBEV_PKG $NCURSES_PKG; do
  wget -q -O "$pkg" "$BASE/$pkg"
done

echo "[2/5] SHA256 校验"
check "$TMUX_PKG" "$TMUX_SHA" "tmux"
check "$LIBEV_PKG" "$LIBEV_SHA" "libevent"
check "$NCURSES_PKG" "$NCURSES_SHA" "libncursesw"

echo "[3/5] 解包并挑取文件"
for pkg in $TMUX_PKG $LIBEV_PKG $NCURSES_PKG; do
  mkdir -p "$WORK/x/$pkg"
  tar -xzf "$pkg" -C "$WORK/x/$pkg"
done
cp -L "$WORK/x/$TMUX_PKG/usr/bin/tmux" "$OUT/tmux"
cp -L "$WORK/x/$LIBEV_PKG/usr/lib/libevent_core-2.1.so.7" "$OUT/"
cp -L "$WORK/x/$NCURSES_PKG/usr/lib/libncursesw.so.6" "$OUT/"
chmod 0755 "$OUT/tmux" "$OUT"/*.so*
# 显式完整性检查（防静默缺件）
for f in tmux libevent_core-2.1.so.7 libncursesw.so.6; do
  [ -f "$OUT/$f" ] || { echo "装配缺文件: $f" >&2; exit 1; }
done

echo "[4/5] patchelf 自包含化（rpath=\$ORIGIN）"
patchelf --set-rpath '$ORIGIN' "$OUT/tmux"
echo "rpath = $(patchelf --print-rpath "$OUT/tmux")"

echo "[5/5] 隔离验证"
env -i "$OUT/tmux" -V
rm -rf "$WORK"
echo "aiod 专用 tmux 装配完成: $OUT/tmux"
