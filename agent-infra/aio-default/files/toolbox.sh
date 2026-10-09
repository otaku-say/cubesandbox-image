#!/bin/sh
# toolbox —— aio-default 工具箱速查：打印 AGENT-GUIDE + 全量工具清单
TDIR="${TOOLBOX_DIR:-/opt/skills/tools}"
GUIDE="$TDIR/AGENT-GUIDE.md"
if [ -f "$GUIDE" ]; then
  cat "$GUIDE"
else
  echo "AGENT-GUIDE.md 未找到（$GUIDE）"
fi
echo
echo "── 工具一览（$TDIR）──"
cols=0
for d in "$TDIR"/*/; do
  t=$(basename "$d")
  [ -f "$d/amd64/$t" ] || continue
  printf '%-14s' "$t"
  cols=$((cols + 1))
  if [ $((cols % 4)) -eq 0 ]; then echo; fi
done
if [ $((cols % 4)) -ne 0 ]; then echo; fi
echo
echo "每个工具文档：$TDIR/<名称>/USAGE.md"
