#!/bin/sh
# =============================================================================
# fetch-toolbox.sh —— 构建期安装 ish-toolbox（58 件静态工具，含 GNU 套件/unzip/yq）到 /opt/skills/tools
#
# 仅使用 Alpine 自带 busybox 能力（wget/tar/sha256sum），不依赖任何 apk 包。
#
# 流程：
#   1. 下载 codeload tarball（固定 commit，禁止浮动）
#   2. 解压，校验 4 个关键文件的 SHA256（内嵌常量，锁定执行链与校验清单）
#   3. 布局到 /opt/skills/tools
#   4. 运行官方一键安装 scripts/install.sh --set-default-busybox
#      （内部：逐件 SHA256 校验 + 裁剪 arm64 目录 + 写 shell PATH 块
#        + “发现即替换”系统 busybox 为工具箱版 1.38.0，原版备份 /bin/busybox.pre-toolbox）
#   5. /usr/local/bin 建立 58 个工具软链（保证非登录 shell 场景全量可见）
#   6. 收尾断言（busybox 版本/计数）并清理临时文件
#
# 内嵌哈希维护：TOOLBOX_REF 变更后，在解压目录内执行
#   sha256sum tools/scripts/install.sh tools/scripts/update.sh \
#             tools/SHA256SUMS.amd64 tools/DOCS.sha256
# 并把结果更新到下方 4 个常量。
# =============================================================================
set -eu

: "${TOOLBOX_REF:?必须指定 TOOLBOX_REF（40 位 Git commit）}"
case "$TOOLBOX_REF" in
  *[!0-9a-f]*) echo "TOOLBOX_REF 含非十六进制字符" >&2; exit 1 ;;
esac
[ "${#TOOLBOX_REF}" -eq 40 ] || { echo "TOOLBOX_REF 长度不是 40" >&2; exit 1; }

# ---- 关键文件哈希（随 TOOLBOX_REF 锁定；REF 变更时必须同步更新）----
H_INSTALL="a44259076a0b8bec898ca48746325d49f77ad6585d18e2c3512f81f96058cb6a"
H_UPDATE="0a2072ea2fc6d4a0b3a18ccdfbd63ae0edaa093668ab287a7a1903d062c5ebc0"
H_SUMS="a38e0cab0cdc747c330976c5973e4a8ac054538dba3e000c638afc39cdbc7989"
H_DOCS="e48b1d23c0e73d8da6faf057ec8fc4095bb5d7374d92211b71132db78268e5f6"

TARBALL=/tmp/toolbox-src.tgz
TDIR=/tmp/toolbox-src
DEST=/opt/skills/tools

check_hash() { # <文件> <期望哈希> <描述>
  actual=$(sha256sum "$1" | awk '{print $1}')
  [ "$actual" = "$2" ] || { echo "校验失败: $3" >&2; exit 1; }
}

echo "[1/6] 下载 toolbox tarball @ $(echo "$TOOLBOX_REF" | cut -c1-12)…"
wget -q -O "$TARBALL" "https://codeload.github.com/otaku-say/skills/tar.gz/${TOOLBOX_REF}"

echo "[2/6] 解压"
rm -rf "$TDIR"
mkdir -p "$TDIR"
tar -xzf "$TARBALL" -C "$TDIR"

echo "[3/6] 关键文件完整性校验（4/4）"
SRC=$(find "$TDIR" -maxdepth 2 -type d -name tools | head -1)
[ -n "$SRC" ] || { echo "未找到 tools 目录" >&2; exit 1; }
check_hash "$SRC/scripts/install.sh"    "$H_INSTALL" "scripts/install.sh"
check_hash "$SRC/scripts/update.sh"     "$H_UPDATE"  "scripts/update.sh"
check_hash "$SRC/SHA256SUMS.amd64"      "$H_SUMS"    "SHA256SUMS.amd64"
check_hash "$SRC/DOCS.sha256"           "$H_DOCS"    "DOCS.sha256"

echo "[4/6] 布局到 $DEST"
rm -rf /opt/skills
mkdir -p /opt/skills
cp -r "$SRC" "$DEST"

echo "[5/6] 官方一键安装（校验 + PATH 块 + 「发现即替换」系统 busybox）"
HOME=/root sh "$DEST/scripts/install.sh" --set-default-busybox

echo "[6/6] /usr/local/bin 工具软链 + 收尾断言"
n=0
for d in "$DEST"/*/; do
  t=$(basename "$d")
  if [ -f "$d/amd64/$t" ]; then
    ln -sf "$DEST/$t/amd64/$t" "/usr/local/bin/$t"
    n=$((n+1))
  fi
done
echo "toolbox 安装完成：$n 个工具软链"
[ "$n" -ge 50 ] || { echo "工具数量异常：$n" >&2; exit 1; }
/bin/busybox | head -1 | grep -q "v1.38.0" || { echo "默认 busybox 断言失败：$(/bin/busybox | head -1)" >&2; exit 1; }
echo "默认终端 busybox：$(/bin/busybox | head -1)"

rm -rf "$TDIR" "$TARBALL"
