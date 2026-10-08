# syntax=docker/dockerfile:1.7
# =============================================================================
# aio-default —— 与本地 iSH 同源的 Alpine 沙箱镜像（极简版）
#
# 设计原则（逐条对应需求）：
#   1. 基础镜像 = Alpine 3.21.0，与本地 iSH 完全同版本（仅 CPU 架构不同：amd64）
#   2. 不安装任何 apk 发行包；干活工具 = ish-toolbox 全量（46 件静态二进制，
#      与 iSH 同仓库、同 commit、同安装脚本、同校验）
#   3. 平台必需组件：envd / aiod / tini / cube-entrypoint（路径与官方 base 逐字节一致）
#   4. 路径手感对齐 iSH：/usr/local/bin 工具入口（软链）、/opt/skills/tools 工具树、
#      /opt/bin、/root/workspace、PATH 与 iSH 完全相同
#
# 本镜像不含：git/gh/uv/zig/yq/make/gcc 等——需求为“零额外软件”。如需增补，
# 以“建议清单”为准（由用户决策）。
# =============================================================================
ARG BASE_IMAGE=alpine:3.21.0

FROM ${BASE_IMAGE}

# ---- 1) 平台契约：envd + cube-entrypoint（来自官方 base；静态二进制/纯脚本，可跨发行版复用）----
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/envd /usr/bin/envd
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
RUN chmod 0755 /usr/bin/envd /usr/local/bin/cube-entrypoint.sh \
 && /usr/bin/envd -version

# ---- 2) ish-toolbox 全量（46 件）：同源拉取 → 四文件强校验 → 一键安装 → 软链 ----
#      TOOLBOX_REF 为 otaku-say/skills 的固定 commit；其 4 个关键文件的哈希
#      内嵌在 fetch-toolbox.sh 中（变更 REF 时需同步更新，见脚本头部注释）
ARG TOOLBOX_REF=c6a7f163c69fc97f92dabb27ec7d1d9c871586fa
COPY fetch-toolbox.sh /tmp/fetch-toolbox.sh
RUN sh /tmp/fetch-toolbox.sh && rm -f /tmp/fetch-toolbox.sh

# ---- 3) tini：官方 base 的 tini 是 glibc 动态链接（musl 环境不可用），
#         改用工具箱静态版（同为 v0.19.0，Linux 行为等价，含 iSH 兼容补丁）----
RUN install -m 0755 /opt/skills/tools/tini/amd64/tini /usr/bin/tini \
 && /usr/bin/tini --version

# ---- 4) aiod（musl 静态单文件守护进程；固定版本 + SHA256SUMS 校验）----
#      下载用工具箱 curl（LibreSSL 静态 + 内嵌 CA，不依赖任何 apk 包）
ARG AIOD_VERSION=v0.9.2
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com
RUN set -eux; \
    /usr/local/bin/curl -fsSL --retry 3 --retry-delay 2 \
        "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/SHA256SUMS" -o /tmp/aiod-SHA256SUMS; \
    /usr/local/bin/curl -fsSL --retry 3 --retry-delay 2 \
        "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/aiod" -o /usr/local/bin/aiod; \
    chmod 0755 /usr/local/bin/aiod; \
    grep -E '[[:space:]]aiod$' /tmp/aiod-SHA256SUMS > /tmp/aiod.sum; \
    (cd /usr/local/bin && sha256sum -c /tmp/aiod.sum); \
    /usr/local/bin/aiod version; \
    rm -f /tmp/aiod-SHA256SUMS /tmp/aiod.sum

# ---- 5) 系统级链接（与 iSH 相同的关键动作：bash / python3 就位）----
#      /bin/bash    ← aiod exec 通道的解析器（实测执行 $0=/bin/bash）
#      /usr/bin/python3 ← code interpreter 依赖（aiod 会探测）
RUN set -eux; \
    ln -sf /opt/skills/tools/bash/amd64/bash /bin/bash; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/bin/python3; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/local/bin/python; \
    mkdir -p /opt/bin /root/workspace

# ---- 6) aiod ↔ tmux 兼容适配（Alpine 侧 tmux 3.7c 与 aiod 探测序列的兼容桥；见文件注释）----
COPY tmux-shim.sh /usr/local/libexec/aio-default-tmux-shim
COPY tmux-compat-keys.txt /usr/local/libexec/aio-default-tmux-keys.txt
RUN chmod 0755 /usr/local/libexec/aio-default-tmux-shim

# ---- 7) 环境变量（PATH 与 iSH 完全一致；ENVD/AIO 变量与官方 base / aio-code 对齐）----
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ENVD_PORT=49983 \
    ENVD_REF=2026.16 \
    AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=full \
    AIO_TMUX_BIN=/usr/local/libexec/aio-default-tmux-shim

# ---- 8) 运行时契约、健康检查与模板标签 ----
EXPOSE 49983 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD /usr/local/bin/curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cube-entrypoint.sh"]
CMD ["/usr/local/bin/aiod", "start"]

LABEL org.opencontainers.image.title="CubeSandbox code sandbox (aio-default)" \
      org.opencontainers.image.description="iSH 同源极简沙箱：Alpine 3.21.0 + ish-toolbox 46 件静态工具 + envd/aiod；零 apk 软件" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="native (portable; envd copied from cubesandbox-base)" \
      io.cubesandbox.toolbox.ref="otaku-say/skills@c6a7f163c69fc97f92dabb27ec7d1d9c871586fa" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":2048,"alias":"aio-default","notes":"与本地 iSH 同源：Alpine 3.21.0 + 同一套 46 件工具箱（零 apk 软件）"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="10G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="2048" \
      io.cubesandbox.template.alias="aio-default"
