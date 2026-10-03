# syntax=docker/dockerfile:1.7
# =============================================================================
# CubeSandbox AIO（aio-daemon 2.x 发行镜像）—— 注入 envd 双通道
#
#   上游: enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-daemon
#         官方 2.x 预构建镜像：aiod 守护进程 + nginx 网关(8091) + Chromium/VNC
#         + Python/Node 工具链，同时提供 /v1/*（1.x 兼容）与 /v2/*（原生）双面 API
#         注意：上游没有 latest 标签，最新为 1.0.1（tags: 1.0.0 / 1.0.1[/-nydus]）
#
#   注入: E2B envd 启动契约（tini + cube-entrypoint，取自官方 cubesandbox-base）
#         —— 沙箱内同时提供 envd(49983) 与 AIO API(8091)，双通道驱动
#
#   与 ../sandbox（1.x 套壳）的区别：这里套的是 2.x daemon 镜像，API 面是 v1+v2；
#   与 ../aiod（从源构建）的区别：这里直接复用上游发行镜像的全部内容（含桌面、
#   VNC、Jupyter、code-server 等），代价是体积大、内容随上游。
# =============================================================================
ARG AIO_DAEMON_IMAGE=enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-daemon
ARG AIO_DAEMON_TAG=1.0.1
FROM ${AIO_DAEMON_IMAGE}:${AIO_DAEMON_TAG}

# ---- 1) envd 启动契约（与官方 cubesandbox-base 逐字节一致） ------------------
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/envd /usr/bin/envd
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/bin/tini /usr/bin/tini
COPY --from=ghcr.io/tencentcloud/cubesandbox-base:latest /usr/local/bin/cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh

RUN set -eux; \
    chmod +x /usr/bin/envd /usr/bin/tini /usr/local/bin/cube-entrypoint.sh; \
    /usr/bin/envd -version; \
    sh -n /usr/local/bin/cube-entrypoint.sh

# ---- 2) 启动：tini → cube-entrypoint（后台 envd + 前台 AIO 全套服务） --------
# cube-entrypoint 的后台 envd + 前台 CMD 语义与上游 /opt/gem/run.sh 兼容：
# run.sh 作为被等待的前台进程，其退出码决定容器退出码，SIGTERM 会被转发。
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cube-entrypoint.sh"]
CMD ["/opt/gem/run.sh"]

# envd 49983 / nginx 网关 8091（AIO API 入口）/ 镜像声明的 8080 / CDP 9222（仅 loopback）
EXPOSE 49983 8091 8080 9222

# 就绪探针用 envd（~1s 起），AIO 服务由冒烟测试单独验证
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

LABEL org.opencontainers.image.title="CubeSandbox AIO (aio-daemon)" \
      org.opencontainers.image.description="AIO Sandbox 2.x daemon image + E2B envd dual-channel contract for CubeSandbox" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="2026.16" \
      io.cubesandbox.upstream.tag="${AIO_DAEMON_TAG}"

# ---- 3) 模板默认值（建模板免手填） ------------------------------------------
# 任何工具都能从 registry 的镜像 config 里读到这些值；本仓库配套命令：
#   cubesandbox-sdk-go tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-daemon:latest
# → 直接输出/提交 CubeSandbox 建模板请求（exposedPorts / probe / 可写层 / CPU / 内存 / 别名全部填好）
LABEL io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"12G","cpu":2000,"memory":3072,"alias":"aio-daemon-small","notes":"envd 49983 + AIO 网关 8080"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="12G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="3072" \
      io.cubesandbox.template.alias="aio-daemon-small"
