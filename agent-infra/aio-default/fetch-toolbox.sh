#!/bin/sh
# =============================================================================
# fetch-toolbox.sh —— 构建期安装 ish-toolbox（43 件静态工具）到 /opt/skills/tools
#
# v6（2026-10 AOJIT 迁移）：工具箱已裁到 43 件——15 件 AOJIT 内置加速的工具
# 下架，改由 apk 提供（见 Dockerfile 步骤 1）。本脚本直取 canonical 产物源
# otaku-say/ish-toolbox 的固定 commit：该仓库双架构产物与 SHA256SUMS 同 commit
# 发布，比 skills 镜像仓（可能滞后）更适合作为构建输入。
#
# 仅使用 Alpine 自带 busybox 能力（wget/tar/sha256sum），不依赖任何 apk 包。
#
# 流程：
#   1. 下载 codeload tarball（固定 commit，禁止浮动）
#   2. 解压，逐件比对 tools/SHA256SUMS.amd64（缺失/哈希不符即失败）
#   3. 布局到 /opt/skills/tools：<工具>/amd64/<工具> + <工具>/USAGE.md
#      + 校验清单（SHA256SUMS.amd64 / DOCS.sha256，供冒烟测试复核）
#   4. /usr/local/bin 建立 43 个工具软链（非登录 shell 场景全量可见）
#   5. 收尾断言（工具数 = 43）
# =============================================================================
set -eu

: "${TOOLBOX_REF:?必须指定 TOOLBOX_REF（40 位 Git commit）}"
case "$TOOLBOX_REF" in
  *[!0-9a-f]*) echo "TOOLBOX_REF 含非十六进制字符" >&2; exit 1 ;;
esac
[ "${#TOOLBOX_REF}" -eq 40 ] || { echo "TOOLBOX_REF 长度不是 40" >&2; exit 1; }

EXPECTED=43
TARBALL=/tmp/toolbox-src.tgz
TDIR=/tmp/toolbox-src
DEST=/opt/skills/tools

echo "[1/5] 下载 toolbox tarball @ $(echo "$TOOLBOX_REF" | cut -c1-12)…"
wget -q -O "$TARBALL" "https://codeload.github.com/otaku-say/ish-toolbox/tar.gz/${TOOLBOX_REF}"

echo "[2/5] 解压"
rm -rf "$TDIR"; mkdir -p "$TDIR"
tar -xzf "$TARBALL" -C "$TDIR"
SRC=$(find "$TDIR" -maxdepth 2 -type d -name tools | head -1)
[ -n "$SRC" ] || { echo "未找到 tools 目录" >&2; exit 1; }
[ -f "$SRC/SHA256SUMS.amd64" ] || { echo "缺少 SHA256SUMS.amd64" >&2; exit 1; }

echo "[3/5] 逐件校验 + 布局到 $DEST"
rm -rf /opt/skills; mkdir -p "$DEST"
n=0
while read -r expected rel; do
  [ -n "$expected" ] || continue
  tool="${rel%%/*}"
  f="$SRC/$rel"
  [ -f "$f" ] || { echo "缺失：$rel" >&2; exit 1; }
  actual=$(sha256sum "$f" | awk '{print $1}')
  [ "$actual" = "$expected" ] || { echo "SHA256 不符：$rel" >&2; exit 1; }
  mkdir -p "$DEST/$tool/amd64"
  cp "$f" "$DEST/$tool/amd64/$tool"
  chmod 0755 "$DEST/$tool/amd64/$tool"
  [ -f "$SRC/$tool/USAGE.md" ] && cp "$SRC/$tool/USAGE.md" "$DEST/$tool/USAGE.md"
  n=$((n + 1))
done < "$SRC/SHA256SUMS.amd64"
cp "$SRC/SHA256SUMS.amd64" "$DEST/SHA256SUMS.amd64"
[ -f "$SRC/DOCS.sha256" ] && cp "$SRC/DOCS.sha256" "$DEST/DOCS.sha256"

echo "[4/5] /usr/local/bin 工具软链"
nlink=0
for d in "$DEST"/*/; do
  t=$(basename "$d")
  if [ -x "$d/amd64/$t" ]; then
    ln -sf "$DEST/$t/amd64/$t" "/usr/local/bin/$t"
    nlink=$((nlink + 1))
  fi
done
echo "  已建成 $nlink 个软链"

echo "[5/5] 收尾断言"
[ "$n" -eq "$EXPECTED" ] || { echo "工具数量异常：$n（期望 $EXPECTED）" >&2; exit 1; }
[ "$nlink" -eq "$EXPECTED" ] || { echo "软链数量异常：$nlink（期望 $EXPECTED）" >&2; exit 1; }
echo "toolbox 安装完成：$n 件（校验通过 + 软链就位）"

rm -rf "$TDIR" "$TARBALL"
