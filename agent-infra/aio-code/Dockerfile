# syntax=docker/dockerfile:1.7
# =============================================================================
# 代码沙箱（aio-code）—— cubesandbox-base + AIO Daemon
#
#   定位：写代码 / 测试 / 编译 / 调试。轻量：无浏览器、无桌面、无 Jupyter。
#         浏览器 → agent-infra/aio-daemon；桌面 → agent-infra/aio-computer。
#
#   base: ghcr.io/tencentcloud/cubesandbox-base
#         Ubuntu 22.04 + envd(49983)/tini/cube-entrypoint 原生启动契约
#   aiod: 官方 releases 单文件守护进程（musl 静态），构建时按 SHA256SUMS 校验；
#         AIO_PORT=8080（与 aio-daemon 一致），提供 /v1 + /v2 双面 API
#
#   工具链（只装必要、同类择优；版本全部固定，升级改对应 ARG 即触发重建）：
#     Python 3.12（唯一版本，默认 python3）+ pip/venv + uv
#     Node.js 24 LTS + npm
#     Zig 0.17.0（我们 CLI 主语言；兼 C/C++ 应急编译器 zig cc）
#     日常/调试工具：git jq yq ripgrep fd tmux vim xxd shellcheck gdb strace 等
#     不装系统 C/C++ 工具链（zig cc 覆盖，需要时沙箱内 apt 临时装）
#
#   启动链: tini → cube-entrypoint.sh（后台 envd + 前台 CMD + 信号转发）
#           CMD = `aiod start`
# =============================================================================
ARG BASE_IMAGE=ghcr.io/tencentcloud/cubesandbox-base:latest
FROM ${BASE_IMAGE}

# ---- 1) aiod 单文件守护进程（固定版本 + SHA256 校验） -----------------------
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

# ---- 2) 基础工具（apt；--no-install-recommends 控体积） ---------------------
#   注：gdb 依赖 libpython3.10 运行库（仅共享库，无解释器二进制）
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git jq tmux vim-tiny xxd file less tree diffutils patch \
        zip unzip xz-utils zstd bzip2 \
        procps psmisc lsof \
        iproute2 iputils-ping netcat-openbsd rsync openssh-client \
        wget sqlite3 openssl ripgrep fd-find \
        gdb strace shellcheck; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/vim.tiny /usr/local/bin/vim; \
    rm -rf /var/lib/apt/lists/*; \
    git --version; jq --version; rg --version | head -n1; fd --version; \
    vim --version | head -n1; xxd -h 2>&1 | head -n1 || true

# ---- 3) Python 3.12（deadsnakes；单一版本，设为默认 python3） ---------------
#   不装 software-properties-common（会拖入系统 python3.10），手工配 PPA：
#   签名密钥从 Ubuntu keyserver 取（armored .asc，apt 2.4+ 原生支持）
ARG DEADSNAKES_KEY_FPR=F23C5A6CF475977595C89F51BA6932366A755776
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${DEADSNAKES_KEY_FPR}" \
        -o /etc/apt/keyrings/deadsnakes.asc; \
    head -n 1 /etc/apt/keyrings/deadsnakes.asc | grep -q 'BEGIN PGP PUBLIC KEY BLOCK'; \
    echo "deb [signed-by=/etc/apt/keyrings/deadsnakes.asc] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main" \
        > /etc/apt/sources.list.d/deadsnakes.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv; \
    rm -rf /var/lib/apt/lists/*; \
    python3.12 -V

# pip（系统级）+ 默认 python3/python/pip 指向 3.12（/usr/local/bin 优先于 /usr/bin）
RUN set -eux; \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
    python3.12 /tmp/get-pip.py --no-cache-dir --no-warn-script-location; \
    rm -f /tmp/get-pip.py; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python3; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python; \
    ln -sf /usr/local/bin/pip3 /usr/local/bin/pip; \
    python3 -V; pip --version

# uv（从官方镜像取二进制；高速安装/venv/工具运行；升级 = 改下面这行的 tag 并重建）
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/
RUN uv --version

# ---- 4) Node.js 24 LTS（官方 tarball，固定版本 + SHA256 校验） ---------------
ARG NODE_VERSION=v24.21.0
RUN set -eux; \
    base="https://nodejs.org/dist/${NODE_VERSION}"; \
    curl -fsSL "${base}/node-${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz; \
    curl -fsSL "${base}/SHASUMS256.txt" -o /tmp/node-SHASUMS256.txt; \
    grep -E "[[:space:]]node-${NODE_VERSION}-linux-x64[.]tar[.]xz$" /tmp/node-SHASUMS256.txt | (cd /tmp && sha256sum -c -); \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f /tmp/node.tar.xz /tmp/node-SHASUMS256.txt; \
    node -v; npm -v

# ---- 5) Zig 0.17.0（官方 tarball，构建时从 index.json 取 SHA256 校验） ------
ARG ZIG_VERSION=0.17.0
RUN set -eux; \
    curl -fsSL https://ziglang.org/download/index.json -o /tmp/zig-index.json; \
    sha=$(jq -r ".\"${ZIG_VERSION}\".\"x86_64-linux\".shasum" /tmp/zig-index.json); \
    [ -n "${sha}" ] && [ "${sha}" != "null" ] || { echo "无法从 index.json 取得 Zig 校验值" >&2; exit 1; }; \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz; \
    echo "${sha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /usr/local/zig; \
    tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 --no-same-owner; \
    rm -f /tmp/zig.tar.xz /tmp/zig-index.json; \
    ln -sf /usr/local/zig/zig /usr/local/bin/zig; \
    zig version

# ---- 6) 命令行小工具（yq / gh，固定版本 + 校验） ----------------------------
ARG YQ_VERSION=v4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
RUN set -eux; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /tmp/yq; \
    echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    rm -f /tmp/yq; \
    yq --version

ARG GH_VERSION=2.102.0
RUN set -eux; \
    base="https://github.com/cli/cli/releases/download/v${GH_VERSION}"; \
    curl -fsSL "${base}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz; \
    curl -fsSL "${base}/gh_${GH_VERSION}_checksums.txt" -o /tmp/gh-checksums.txt; \
    grep -E "[[:space:]]gh_${GH_VERSION}_linux_amd64[.]tar[.]gz$" /tmp/gh-checksums.txt | (cd /tmp && sha256sum -c -); \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz /tmp/gh-checksums.txt "/tmp/gh_${GH_VERSION}_linux_amd64"; \
    gh --version

# ---- 7) 运行参数、端口、探针、模板默认值 ------------------------------------
#   AIO_PORT=8080（与 aio-daemon 一致）；其余按官方 deployment 默认：
#   AIO_HOST=0.0.0.0 / AIO_API_SURFACE=full / AIO_RUST_LOG_LEVEL=info；
#   AIO_API_KEY 不设（鉴权走平台边缘）；AIO_RUNTIME_DIR / AIO_DEFAULT_USER 默认
ENV AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=full

# 对外端口：envd(49983，平台探针) / aiod(8080，AIO v1+v2)
EXPOSE 49983 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

# 启动 = base 的 cube-entrypoint（后台 envd + 前台 CMD + 信号转发）
CMD ["/usr/local/bin/aiod", "start"]

LABEL org.opencontainers.image.title="CubeSandbox code sandbox (aio-code)" \
      org.opencontainers.image.description="Lightweight code/test/build/debug sandbox: cubesandbox-base + aiod + Python3.12 / Node24 / Zig0.17 (no browser/desktop/Jupyter)" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="native (cubesandbox-base)" \
      io.cubesandbox.aiod.version="${AIOD_VERSION}" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":3072,"alias":"aio-code","notes":"代码/测试/编译/调试：aiod(8080)+Py3.12+Node24+Zig0.17；无浏览器/桌面/Jupyter"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="10G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="3072" \
      io.cubesandbox.template.alias="aio-code"
