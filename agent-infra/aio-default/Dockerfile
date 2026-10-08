# syntax=docker/dockerfile:1.7
# =============================================================================
# aio-default —— 与本地 iSH 同源的 Alpine 沙箱镜像（v4）
#
# v4 变更（2026-10-08）：
#   1. tmux 升级为 **3.8**（ish-toolbox CI 构建：修复 3.7 的 list-keys 回归、
#      保留完整 terminfo fallback）—— aiod 直接使用工具箱 tmux（PATH），
#      **删除 v3 的 aiod 专用 tmux 与 AIO_TMUX_BIN**（不再需要任何兼容层）
#   2. 系统 /bin/busybox（即 /bin/sh 等全部 applet）指定为工具箱完整版 1.38.0
#      —— 作为沙箱**默认终端**（408 applet；原系统版 304）
#
# 设计原则（v1 起不变）：
#   1. 基础镜像 = Alpine 3.21.0，与本地 iSH 完全同版本（仅 CPU 架构不同：amd64）
#   2. 不安装任何 apk 发行包；干活工具 = ish-toolbox 全量（46 件静态二进制，
#      与 iSH 同仓库、同 commit、同安装脚本、同校验）
#   3. 平台必需组件：envd / aiod / tini / cube-entrypoint（路径与官方 base 一致）
#   4. 路径手感对齐 iSH：/usr/local/bin 工具入口（软链）、/opt/skills/tools 工具树、
#      /opt/bin、/root/workspace、PATH 与 iSH 完全相同
# =============================================================================
ARG BASE_IMAGE=alpine:3.21.0

FROM ${BASE_IMAGE}

# ---- 1) 平台契约：envd + cube-entrypoint（来自官方 base；静态二进制/纯脚本）----
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/envd /usr/bin/envd
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
RUN chmod 0755 /usr/bin/envd /usr/local/bin/cube-entrypoint.sh \
 && /usr/bin/envd -version

# ---- 2) ish-toolbox 全量（46 件，含 tmux 3.8）：同源拉取 → 四文件强校验 → 一键安装 → 软链 ----
ARG TOOLBOX_REF=87435357ff6121e5716ce82b2cce0d9e3232b1d7
COPY fetch-toolbox.sh /tmp/fetch-toolbox.sh
RUN sh /tmp/fetch-toolbox.sh && rm -f /tmp/fetch-toolbox.sh

# ---- 2.5) 系统 /bin/busybox 切换为工具箱完整版 1.38.0（沙箱默认终端）----
# （iSH 侧同为 1.38.0 工具箱版；切换后 /bin/sh、/bin/ash 等全部 applet 一并升级，408 applet）
RUN cp -f /opt/skills/tools/busybox/amd64/busybox /bin/busybox \
 && chmod 0755 /bin/busybox \
 && /bin/busybox | head -1

# ---- 3) tini：官方 base 的 tini 是 glibc 动态链接（musl 环境不可用），
#         改用工具箱静态版（同为 v0.19.0，Linux 行为等价）----
RUN install -m 0755 /opt/skills/tools/tini/amd64/tini /usr/bin/tini \
 && /usr/bin/tini --version

# ---- 4) aiod（musl 静态单文件守护进程；固定版本 + SHA256SUMS 校验）----
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
RUN set -eux; \
    ln -sf /opt/skills/tools/bash/amd64/bash /bin/bash; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/bin/python3; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/local/bin/python; \
    mkdir -p /opt/bin /root/workspace

# ---- 6) tmux（aiod shell 后端）由工具箱提供（3.8，经 /usr/local/bin/tmux）----
#      不再需要 v3 的 aiod 专用 tmux 与 AIO_TMUX_BIN；见 README「已知事项」
RUN set -eux; \
    tmux -V; \
    [ "$(tmux -V | awk '{print $2}')" = "3.8" ]

# ---- 7) 环境变量（PATH 与 iSH 完全一致；ENVD/AIO 变量与官方 base / aio-code 对齐）----
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ENVD_PORT=49983 \
    ENVD_REF=2026.16 \
    AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=full

# ---- 8) 运行时契约、健康检查与模板标签 ----
EXPOSE 49983 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD /usr/local/bin/curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cube-entrypoint.sh"]
CMD ["/usr/local/bin/aiod", "start"]

LABEL org.opencontainers.image.title="CubeSandbox code sandbox (aio-default)" \
      org.opencontainers.image.description="iSH 同源极简沙箱：Alpine 3.21.0 + busybox 1.38（默认终端）+ ish-toolbox 46 件静态工具（含 tmux 3.8）+ envd/aiod；零 apk 软件" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="native (portable; envd copied from cubesandbox-base)" \
      io.cubesandbox.toolbox.ref="otaku-say/skills@87435357ff6121e5716ce82b2cce0d9e3232b1d7" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":2048,"alias":"aio-default","notes":"与本地 iSH 同源：Alpine 3.21.0 + busybox 1.38 默认终端 + 同一套 46 件工具箱（零 apk 软件）"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="10G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="2048" \
      io.cubesandbox.template.alias="aio-default"
