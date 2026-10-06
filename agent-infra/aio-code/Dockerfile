# syntax=docker/dockerfile:1.7
# =============================================================================
# 作者: DevOps Team
# 创建时间: 2026-10-04
# 功能简述: 专用于 OpenMinis 调度的低内存 AI Agent 开发沙箱
#           主环境锁定 LTS 主线版本，全部工具链在构建时动态拉取最新稳定版
# =============================================================================
ARG BASE_IMAGE=ghcr.io/tencentcloud/cubesandbox-base:latest
FROM ${BASE_IMAGE}

# ---- 1) 运行时低内存防御与全局环境策略 --------------------------------------
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=full

# ---- 2) aiod 单文件守护进程（默认拉取 latest 最新稳定版） --------------------
ARG AIOD_VERSION=latest
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com
RUN set -eux; \
    curl -fsSL "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/SHA256SUMS" -o /tmp/aiod-SHA256SUMS; \
    curl -fsSL "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/aiod" -o /usr/local/bin/aiod; \
    chmod +x /usr/local/bin/aiod; \
    grep -E '[[:space:]]aiod$' /tmp/aiod-SHA256SUMS | (cd /usr/local/bin && sha256sum -c -); \
    /usr/local/bin/aiod version; \
    rm -f /tmp/aiod-SHA256SUMS

# ---- 3) 基础工具链 + GitHub CLI 官方源（自动安装并保持最新版） --------------
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git jq tmux vim-tiny xxd file less tree diffutils patch make \
        zip unzip xz-utils zstd bzip2 \
        procps psmisc lsof \
        iproute2 iputils-ping netcat-openbsd socat rsync openssh-client \
        wget sqlite3 openssl pkg-config libssl-dev zlib1g-dev \
        ripgrep fd-find bat gh \
        strace shellcheck; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat; \
    ln -sf /usr/bin/vim.tiny /usr/local/bin/vim; \
    git config --system --add safe.directory '*'; \
    git config --system user.name "CubeSandbox Agent"; \
    git config --system user.email "agent@cubesandbox.local"; \
    git config --system pack.windowMemory "256m"; \
    git config --system pack.threads "2"; \
    rm -rf /var/lib/apt/lists/*; \
    gh --version

# ---- 4) Python 3.12（LTS 主线最新补丁）+ uv（官方最新构建） ------------------
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
    ln -sf /usr/local/bin/pip3 /usr/local/bin/pip; \
    python3 -V; pip --version

# 从官方镜像拉取最新发布的 uv / uvx 单二进制
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN uv --version

# ---- 5) Zig（从官方 index.json 解析最新稳定版）+ cc/c++ 编译器封装 ----------
RUN set -eux; \
    curl -fsSL https://ziglang.org/download/index.json -o /tmp/zig-index.json; \
    LATEST_ZIG=$(jq -r 'keys | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".") | map(tonumber)) | last' /tmp/zig-index.json); \
    tarball=$(jq -r ".\"${LATEST_ZIG}\".\"x86_64-linux\".tarball" /tmp/zig-index.json); \
    sha=$(jq -r ".\"${LATEST_ZIG}\".\"x86_64-linux\".shasum" /tmp/zig-index.json); \
    curl -fsSL "${tarball}" -o /tmp/zig.tar.xz; \
    echo "${sha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /usr/local/zig; \
    tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 --no-same-owner; \
    rm -f /tmp/zig.tar.xz /tmp/zig-index.json; \
    ln -sf /usr/local/zig/zig /usr/local/bin/zig; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig cc "$@"\n' > /usr/local/bin/cc; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig c++ "$@"\n' > /usr/local/bin/c++; \
    chmod +x /usr/local/bin/cc /usr/local/bin/c++; \
    zig version

# ---- 6) yq 结构化解析器（自动拉取 GitHub Releases 最新版） ------------------
RUN set -eux; \
    curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq; \
    chmod 0755 /usr/local/bin/yq; \
    yq --version

# ---- 7) 运行时契约、健康检查与模板标签 --------------------------------------
EXPOSE 49983 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1

CMD ["/usr/local/bin/aiod", "start"]

LABEL org.opencontainers.image.title="CubeSandbox code sandbox (aio-code-light)" \
      org.opencontainers.image.description="Lightweight auto-updated dev sandbox under 2GB RAM: aiod + Py3.12 LTS + Zig Stable + uv" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="native (cubesandbox-base)" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"10G","cpu":2000,"memory":2048,"alias":"aio-code-light","notes":"2G低内存开发沙箱：Py3.12主线/最新Zig稳定版/最新uv/gh/yq"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="10G" \
      io.cubesandbox.template.cpu="2000" \
      io.cubesandbox.template.memory="2048" \
      io.cubesandbox.template.alias="aio-code-light"
