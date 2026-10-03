# syntax=docker/dockerfile:1.7
# =============================================================================
# 轻量代码沙箱（aio-code）—— 官方 sandbox-code 封装 AIO Daemon
#
#   上游一: cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code
#           官方代码执行环境（E2B SDK 兼容）：envd(49983) + Python3.12 + uv
#           + Jupyter Server(127.0.0.1:8888) + code-interpreter uvicorn(:49999)
#           基底 = uv python3.12-bookworm-slim，未压缩层合计仅 ~110MB
#
#   上游二: aio-static.tos-cn-beijing.volces.com 的 aiod 单文件守护进程
#           musl 静态构建；`aiod start` 前台监听 :18091（AIO_PORT 可改），
#           提供 v1/v2 双面 API；缺能力只降级对应路由（503），不阻塞启动
#
#   启动: tini → entrypoint-aio.sh
#           ├─ 后台: 原 start 脚本（envd + Jupyter + code-interpreter）
#           └─ 受监管: aiod start（前台）
#         任一进程退出 → 全部终止 → 容器退出（交给平台重建）
#
#   定位: 轻量级（不装 Chromium/VNC/桌面），覆盖 编辑文件/跑脚本/数据处理/
#         git/HTTP 抓取（Python 生态）/E2B 代码执行。
#         需要浏览器 → aio-daemon；需要桌面 → aio-computer。
# =============================================================================
ARG BASE_IMAGE=cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code:latest
FROM ${BASE_IMAGE}

# ---- 1) aiod 单文件守护进程（固定版本 + SHA256 校验） -----------------------
# 官方部署文档（/zh/daemon/ops/deployment）：发布目录 /v<version>/<platform>/
# 提供 aiod 与 SHA256SUMS，供自行拉取的镜像构建使用；固定版本可复现。
ARG AIOD_VERSION=v0.9.2
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com

ADD ${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/SHA256SUMS /tmp/aiod-SHA256SUMS
ADD ${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/aiod /usr/local/bin/aiod

RUN set -eux; \
    chmod +x /usr/local/bin/aiod; \
    grep -E '[[:space:]]aiod$' /tmp/aiod-SHA256SUMS | (cd /usr/local/bin && sha256sum -c -); \
    /usr/local/bin/aiod version; \
    rm -f /tmp/aiod-SHA256SUMS

# ---- 2) 必要工具（--no-install-recommends 控体积） ---------------------------
#   ca-certificates/curl/git  代码与网络（git 走 https 克隆）
#   jq/ripgrep/tmux           数据面常用；`aiod doctor` 会探测 rg 和 tmux
#   procps/vim-tiny           排障与临时编辑
#   tini                      PID1：信号转发 + 孤儿收尸
#   nodejs                    aiod 的 node 执行后端之一（缺失则 node 路由 503）
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl git jq procps ripgrep tmux tini vim-tiny nodejs; \
    rm -rf /var/lib/apt/lists/*; \
    git --version; jq --version; rg --version | head -1; node --version; tini --version

# ---- 3) 启动包装：原服务树（后台）+ aiod（受监管） ---------------------------
COPY entrypoint-aio.sh /usr/local/bin/entrypoint-aio.sh
RUN set -eux; chmod +x /usr/local/bin/entrypoint-aio.sh; sh -n /usr/local/bin/entrypoint-aio.sh

# aiod 与内置组件的桥接（官方排障表口径）：
#   AIO_JUPYTER_ENDPOINT → 内置 Jupyter(127.0.0.1:8888)，否则 /v1/jupyter 返回 501
#   AIO_HOST/AIO_PORT 默认 0.0.0.0:18091；AIO_API_SURFACE 默认 full（v1+v2）
ENV AIO_JUPYTER_ENDPOINT="http://127.0.0.1:8888"

# 对外端口：envd(49983) / code-interpreter(49999) / aiod(18091)
# Jupyter(8888) 仅监听 127.0.0.1（aiod 内部访问），不对外暴露
EXPOSE 49983 49999 18091

# 就绪探针用 envd（起得最快，平台模板探针同口径）
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

# ---- 4) 模板默认值（建模板免手填；`cubesandbox-sdk-go tpl-from-image` 读取） --
LABEL org.opencontainers.image.title="CubeSandbox lightweight code sandbox (aio-code)" \
      org.opencontainers.image.description="Official sandbox-code (envd + Python3.12 + Jupyter + E2B code-interpreter) wrapped with AIO daemon aiod" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="native (sandbox-code 内置)" \
      io.cubesandbox.aiod.version="${AIOD_VERSION}" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,49999,18091],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":3072,"alias":"aio-code","notes":"轻量：envd+Py3.12+Jupyter+E2B code-interpreter+aiod v1/v2；无浏览器/桌面（浏览器→aio-daemon，桌面→aio-computer）"}' \
      io.cubesandbox.template.exposed-ports="49983,49999,18091" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="10G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="3072" \
      io.cubesandbox.template.alias="aio-code"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint-aio.sh"]
CMD ["/usr/local/bin/start-lightweight-code-interpreter.sh"]
