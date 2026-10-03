# syntax=docker/dockerfile:1.7
# =============================================================================
# CubeSandbox AIO（aio-computer 2.x 发行镜像）—— 注入 envd 双通道
#
#   上游: enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-computer
#         官方 2.x「带桌面」镜像：aiod 守护进程 + nginx 网关 + Chromium/VNC
#         + **XFCE 桌面 + computer-use worker（:18100）** + Python/Node 工具链
#         同时提供 /v1/*（1.x 兼容）与 /v2/*（原生）双面 API，其中 /v2/computer/*
#         只有在带 worker 的镜像（本镜像 / aio-computer）上才可用
#         注意：上游没有 latest 标签，最新为 1.0.1（tags: 1.0.0 / 1.0.1[/-nydus]）
#
#   注入: E2B envd 启动契约（tini + cube-entrypoint，取自官方 cubesandbox-base）
#         —— 沙箱内同时提供 envd(49983) 与 AIO API(8080)，双通道驱动
#
#   用途：与 ../aio-daemon 配套 —— aio-daemon 用于常规执行/浏览器测试，
#         本镜像用于 **computer-use（桌面操作）测试验收**（cmp-* 命令）。
# =============================================================================
ARG AIO_COMPUTER_IMAGE=enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-computer
ARG AIO_COMPUTER_TAG=1.0.1
FROM ${AIO_COMPUTER_IMAGE}:${AIO_COMPUTER_TAG}

# ---- 1) envd 启动契约（与官方 cubesandbox-base 逐字节一致） ------------------
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/envd /usr/bin/envd
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/tini /usr/bin/tini
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh

RUN set -eux; \
    chmod +x /usr/bin/envd /usr/bin/tini /usr/local/bin/cube-entrypoint.sh; \
    /usr/bin/envd -version; \
    sh -n /usr/local/bin/cube-entrypoint.sh

# ---- 2) 启动：tini → cube-entrypoint（后台 envd + 前台 AIO 全套服务） --------
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cube-entrypoint.sh"]
CMD ["/opt/gem/run.sh"]

# envd 49983 / nginx 网关 8080（实测端口）/ CDP 9222 / VNC 5900（仅 loopback）
EXPOSE 49983 8080 9222 5900

HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

LABEL org.opencontainers.image.title="CubeSandbox AIO (aio-computer)" \
      org.opencontainers.image.description="AIO Sandbox 2.x computer-use image (XFCE desktop + worker) + E2B envd dual-channel contract" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="2026.16" \
      io.cubesandbox.upstream.tag="${AIO_COMPUTER_TAG}"

# ---- 3) 模板默认值（建模板免手填） ------------------------------------------
# 任何工具都能从 registry 的镜像 config 里读到这些值；本仓库配套命令：
#   cubesandbox-sdk-go tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-computer:latest
# → 直接输出/提交 CubeSandbox 建模板请求（exposedPorts / probe / 可写层 / CPU / 内存 / 别名全部填好）
# 桌面镜像偏重：宿主机宽裕时可用 --cpu=4000 --memory=4096 覆盖
LABEL io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"12G","cpu":2000,"memory":3072,"alias":"aio-computer","notes":"envd 49983 + AIO 网关 8080；Chromium 为 manual 模式"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="12G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="3072" \
      io.cubesandbox.template.alias="aio-computer"
