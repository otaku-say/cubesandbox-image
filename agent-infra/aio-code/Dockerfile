# syntax=docker/dockerfile:1.7
# =============================================================================
# 作者: DevOps Team
# 创建时间: 2026-10-04
# 功能简述: 用于 OpenMinis 调度的低内存 Agent 开发沙箱
#           专注文档检索、代码修改、Zig编译，集成 gh 命令行联动 GitHub Actions
# =============================================================================
ARG BASE_IMAGE=ghcr.io/tencentcloud/cubesandbox-base:latest
FROM ${BASE_IMAGE}

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    MALLOC_ARENA_MAX=2 \
    MAKEFLAGS="-j2" \
    UV_CONCURRENT_INSTALLS=2 \
    AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=full

# 1) aiod 守护进程
ARG AIOD_VERSION=v0.9.2
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com
ADD ${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/SHA256SUMS /tmp/aiod-SHA256SUMS
ADD ${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/aiod /usr/local/bin/aiod
RUN set -eux; \
    chmod +x /usr/local/bin/aiod; \
    grep -E '[[:space:]]aiod$' /tmp/aiod-SHA256SUMS | (cd /usr/local/bin && sha256sum -c -); \
    rm -f /tmp/aiod-SHA256SUMS

# 2) 基础工具链（剔除 gdb，保留 pkg-config/socat/bat/shellcheck）
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git jq tmux vim-tiny xxd file less tree diffutils patch make ca-certificates \
        zip unzip xz-utils zstd bzip2 \
        procps psmisc lsof \
        iproute2 iputils-ping netcat-openbsd socat rsync openssh-client \
        wget sqlite3 openssl pkg-config libssl-dev zlib1g-dev \
        ripgrep fd-find bat \
        strace shellcheck; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat; \
    ln -sf /usr/bin/vim.tiny /usr/local/bin/vim; \
    git config --system --add safe.directory '*'; \
    git config --system user.name "CubeSandbox Agent"; \
    git config --system user.email "agent@cubesandbox.local"; \
    git config --system pack.windowMemory "256m"; \
    git config --system pack.threads "2"; \
    rm -rf /var/lib/apt/lists/*

# 3) Python 3.12 + uv
ARG DEADSNAKES_KEY_FPR=F23C5A6CF475977595C89F51BA6932366A755776
RUN set -eux; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${DEADSNAKES_KEY_FPR}" \
        -o /etc/apt/keyrings/deadsnakes.asc; \
    echo "deb [signed-by=/etc/apt/keyrings/deadsnakes.asc] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main" \
        > /etc/apt/sources.list.d/deadsnakes.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3.12 python3.12-dev python3.12-venv; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
    python3.12 /tmp/get-pip.py --no-cache-dir --no-warn-script-location; \
    rm -f /tmp/get-pip.py; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python3; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python; \
    ln -sf /usr/local/bin/pip3 /usr/local/bin/pip

COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/

# 4) Zig 0.17.0 + cc/c++ 编译器封装
ARG ZIG_VERSION=0.17.0
RUN set -eux; \
    curl -fsSL https://ziglang.org/download/index.json -o /tmp/zig-index.json; \
    sha=$(jq -r ".\"${ZIG_VERSION}\".\"x86_64-linux\".shasum" /tmp/zig-index.json); \
    curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz; \
    echo "${sha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /usr/local/zig; \
    tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 --no-same-owner; \
    rm -f /tmp/zig.tar.xz /tmp/zig-index.json; \
    ln -sf /usr/local/zig/zig /usr/local/bin/zig; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig cc "$@"\n' > /usr/local/bin/cc; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig c++ "$@"\n' > /usr/local/bin/c++; \
    chmod +x /usr/local/bin/cc /usr/local/bin/c++

# 5) 核心交互调度工具（yq 与 gh）
ARG YQ_VERSION=v4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
RUN set -eux; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /tmp/yq; \
    echo "${YQ_SHA256}  /tmp/yq" | sha256sum -c -; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    rm -f /tmp/yq

ARG GH_VERSION=2.102.0
RUN set -eux; \
    base="https://github.com/cli/cli/releases/download/v${GH_VERSION}"; \
    curl -fsSL "${base}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    curl -fsSL "${base}/gh_${GH_VERSION}_checksums.txt" -o /tmp/gh-checksums.txt; \
    grep -E "[[:space:]]gh_${GH_VERSION}_linux_amd64[.]tar[.]gz$" /tmp/gh-checksums.txt | (cd /tmp && sha256sum -c -); \
    tar -xzf "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz" -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz" /tmp/gh-checksums.txt "/tmp/gh_${GH_VERSION}_linux_amd64"

EXPOSE 49983 8080
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

CMD ["/usr/local/bin/aiod", "start"]

LABEL io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":2048,"alias":"aio-code-light"}'
