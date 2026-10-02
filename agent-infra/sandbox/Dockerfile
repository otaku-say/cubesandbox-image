# syntax=docker/dockerfile:1
# =============================================================================
# CubeSandbox AIO — 在 agent-infra AIO Sandbox 上注入 envd（双通道沙箱）
#   上游: ghcr.io/agent-infra/sandbox
#         （Browser/VNC/Terminal/File/VSCode/Jupyter/MCP Hub/Skills 全功能）
#   注入: E2B envd 启动契约（tini + cube-entrypoint，取自官方 cubesandbox-base）
#         —— 沙箱内同时提供 envd（49983）与 AIO API（8080），双通道驱动
#   增补: 仅补必须清单缺口（yq/fd/sqlite3/tcpdump/strace/tesseract/dnsutils
#         + playwright 库，经 connect_over_cdp 直连内置 Chrome，不下载浏览器）
#   产出: ghcr.io/<owner>/cubesandbox-image/agent-infra/sandbox:latest
# =============================================================================
FROM ghcr.io/agent-infra/sandbox:latest

# ---- 1) envd 启动契约 ----
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/envd /usr/bin/envd
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/tini /usr/bin/tini
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
RUN chmod +x /usr/bin/envd /usr/bin/tini /usr/local/bin/cube-entrypoint.sh

# ---- 2) 精选增补（同功能择优，只补缺口）----
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        fd-find sqlite3 tcpdump strace dnsutils \
        tesseract-ocr tesseract-ocr-eng tesseract-ocr-chi-sim \
    ; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
        -o /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq; \
    pip3 install --no-cache-dir playwright; \
    rm -rf /var/lib/apt/lists/*; \
    yq --version | head -n1; \
    fd --version; \
    sqlite3 --version; \
    strace -V 2>&1 | head -n1; \
    tesseract --version 2>&1 | head -n1

# ---- 3) 启动：tini → cube-entrypoint（后台 envd + 前台 AIO 全套服务）----
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/cube-entrypoint.sh"]
CMD ["/opt/gem/run.sh"]

LABEL org.opencontainers.image.title="CubeSandbox AIO" \
      org.opencontainers.image.description="AIO Sandbox (agent-infra) + E2B envd dual-channel image for CubeSandbox" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      org.opencontainers.image.version="1.0.0"
