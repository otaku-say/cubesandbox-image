# syntax=docker/dockerfile:1.7
# =============================================================================
# 项目名称：aio-default 沙箱镜像 (CubeSandbox)
# 作    者：CubeSandbox 架构维护团队
# 创建时间：2026-10-09
# 功能简述：基于 Alpine 3.23 的 MicroVM 代码执行沙箱基础镜像，集成 BusyBox 1.38
#           默认终端、ish-toolbox 扩展、envd 与 aiod 守护进程、Git Edge 最新
#           构建套件以及 Zig 0.17 跨平台编译工具链。
# 设计原则：工具层 = ish-toolbox 58 件（与 iSH 同源同校验，busybox 1.38 默认终端）；
#           平台契约对齐官方 base（envd :49983 / cube-entrypoint / nice / user 账号）。
# 变更记录：见 BUILD-NOTES.md（v5 选型与实测证据）
# =============================================================================
FROM alpine:3.23.6

ARG ENVD_VERSION=v0.9.202610091259-41ed62c3bc4
ARG TOOLBOX_REF=b77dd03a2ee61ff055f2a7285ee9c0ed4568d745
ARG AIOD_VERSION=v0.9.2
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com
ARG ZIG_VERSION=0.17.0

# ---- 1) 系统软件（编译基础设施与运行库；可替代项一律不装——工具层见步骤 2）----
# 安装系统基础依赖、编译链及 sudo；Perl 由后续 git-perl 统一维护管理
RUN set -eux; \
    apk add --no-cache \
        ca-certificates tzdata sudo \
        make pkgconf linux-headers binutils file \
        autoconf automake libtool m4 bison flex \
        qemu-aarch64 gcompat; \
    rm -rf /var/cache/apk/*; \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone

# ---- 2) ish-toolbox 全量 58 件（强校验 → 一键安装 → busybox 替换 → 软链）----
#   （先于各下载步骤安装：后续 envd/aiod/zig 全部使用工具箱静态 curl）
COPY fetch-toolbox.sh /tmp/fetch-toolbox.sh
RUN sh /tmp/fetch-toolbox.sh && rm -f /tmp/fetch-toolbox.sh

# ---- 3) envd：官方桶直取 + sha256 边车校验（最新构建；使用工具箱 curl）----
RUN set -eux; \
    curl -fsSL --retry 3 "https://storage.googleapis.com/e2b-artifact-binaries/envd/${ENVD_VERSION}/envd" -o /usr/bin/envd; \
    curl -fsSL --retry 3 "https://storage.googleapis.com/e2b-artifact-binaries/envd/${ENVD_VERSION}/envd.sha256" -o /tmp/envd.sha256; \
    grep -E '[[:space:]]envd$' /tmp/envd.sha256 > /tmp/envd.sum; \
    (cd /usr/bin && sha256sum -c /tmp/envd.sum); \
    chmod 0755 /usr/bin/envd; rm -f /tmp/envd.sha256 /tmp/envd.sum; \
    mkdir -p /var/log; \
    /usr/bin/envd -version

# ---- 4) cube-entrypoint.sh（官方 master 版，vendored；sha256 记录于 upstream.txt）----
COPY cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
RUN chmod 0755 /usr/local/bin/cube-entrypoint.sh

# ---- 5) tini（工具箱静态版，替代 base 的 glibc 动态版）----
RUN install -m 0755 /opt/skills/tools/tini/amd64/tini /usr/bin/tini && /usr/bin/tini --version

# ---- 6) aiod（musl 静态单文件 + SHA256SUMS 校验）----
RUN set -eux; \
    curl -fsSL --retry 3 "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/SHA256SUMS" -o /tmp/aiod-SHA256SUMS; \
    curl -fsSL --retry 3 "${AIOD_BASE_URL}/${AIOD_VERSION}/${AIOD_PLATFORM}/aiod" -o /usr/local/bin/aiod; \
    chmod 0755 /usr/local/bin/aiod; \
    grep -E '[[:space:]]aiod$' /tmp/aiod-SHA256SUMS > /tmp/aiod.sum; \
    (cd /usr/local/bin && sha256sum -c /tmp/aiod.sum); \
    /usr/local/bin/aiod version; rm -f /tmp/aiod-SHA256SUMS /tmp/aiod.sum

# ---- 7) git 核心四件套（edge 分支定向构建）----
#   通过 edge 源拉取最新版；依赖实测全部来自 3.23 stable；装完清理 @edge（repositories
#   与 apk world 双清理——只删 repositories 会留下 world 缺 tag 的隐患，见 BUILD-NOTES）
RUN set -eux; \
    echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories; \
    echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories; \
    apk update; \
    apk add --no-cache \
        git@edge \
        git-perl@edge \
        git-lfs@edge \
        github-cli@edge; \
    git lfs install --system; \
    sed -i '/@edge/d' /etc/apk/repositories; \
    sed -i 's/@edge//g' /etc/apk/world; \
    rm -rf /var/cache/apk/*; \
    ! grep -q '@edge' /etc/apk/world; \
    git --version; git-lfs --version; gh --version | head -n 1

# ---- 8) zig 0.17.0（官方静态包）+ cc/c++ wrapper ----
RUN set -eux; \
    curl -fsSL --retry 3 "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz; \
    ACT=$(sha256sum /tmp/zig.tar.xz | awk '{print $1}'); \
    [ "$ACT" = "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026" ] || { echo "zig sha256 校验失败"; exit 1; }; \
    mkdir -p /usr/local/zig; \
    tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 --no-same-owner; \
    rm -f /tmp/zig.tar.xz; \
    ln -sf /usr/local/zig/zig /usr/local/bin/zig; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig cc "$@"\n' > /usr/local/bin/cc; \
    printf '#!/bin/sh\nexec /usr/local/bin/zig c++ "$@"\n' > /usr/local/bin/c++; \
    chmod 0755 /usr/local/bin/cc /usr/local/bin/c++; \
    zig version

# ---- 9) 基础系统软链接、用户权限与 Git 运行时优化 ----
# 映射 bash、python 路径，awk 指向工具箱 gawk（同名兼容语义优先），
# 登记标准 shell，配置 user 免密 sudo 与可写工作目录
RUN set -eux; \
    ln -sf /opt/skills/tools/bash/amd64/bash /bin/bash; \
    grep -qxF '/bin/bash' /etc/shells || echo '/bin/bash' >> /etc/shells; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/bin/python3; \
    ln -sf /opt/skills/tools/python3/amd64/python3 /usr/local/bin/python; \
    ln -sf /opt/skills/tools/gawk/amd64/gawk /usr/local/bin/awk; \
    ln -sf /bin/busybox /usr/bin/nice; \
    mkdir -p /opt/bin /workspace /root/workspace; \
    mkdir -p /tmp/.cube-cli-pty /tmp/.cube-cli-exec && chmod 1777 /tmp/.cube-cli-pty /tmp/.cube-cli-exec; \
    adduser -D -u 1000 -s /bin/bash user; \
    echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/user; \
    chmod 0440 /etc/sudoers.d/user; \
    chown -R user:user /workspace; \
    git config --system safe.directory '*'; \
    git config --system init.defaultBranch main; \
    git config --system user.name 'CubeSandbox Agent'; \
    git config --system user.email 'agent@localhost'; \
    git config --system pack.windowMemory 256m; \
    git config --system pack.threads 2

# ---- 10) Agent 层：速查命令 / 指南 / 缺命令提示 / pip→uv 桥 ----
COPY files/bash_env.sh /etc/bash/env.sh
COPY files/toolbox.sh /usr/local/bin/toolbox
COPY files/pip-shim.sh /usr/local/bin/pip
COPY files/motd /etc/motd
COPY agent-guide.md /opt/skills/tools/AGENT-GUIDE.md
RUN set -eux; \
    chmod 0755 /usr/local/bin/toolbox /usr/local/bin/pip; \
    ln -sf pip /usr/local/bin/pip3; \
    chmod 0644 /etc/bash/env.sh /etc/motd /opt/skills/tools/AGENT-GUIDE.md

# ---- 11) 环境变量（PATH 与 iSH 一致；TZ；v2 面；三核口径）----
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai \
    ENVD_PORT=49983 \
    ENVD_VERSION=${ENVD_VERSION} \
    ENVD_REF=${ENVD_VERSION} \
    AIO_HOST=0.0.0.0 \
    AIO_PORT=8080 \
    AIO_API_SURFACE=v2 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    UV_CONCURRENT_INSTALLS=3 \
    MAKEFLAGS=-j3 \
    BASH_ENV=/etc/bash/env.sh

# ---- 12) 运行时配置、工作目录与健康检查探针 ----
WORKDIR /workspace
EXPOSE 49983 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=12 \
    CMD curl -fsS "http://127.0.0.1:49983/health" >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cube-entrypoint.sh"]
CMD ["/usr/local/bin/aiod", "start"]

LABEL org.opencontainers.image.title="CubeSandbox code sandbox (aio-default)" \
      org.opencontainers.image.description="iSH 同源 Alpine 沙箱 v5：alpine 3.23.6 + busybox 1.38 默认终端 + ish-toolbox 58 件 + envd/aiod + git 2.56/zig 0.17 开发链" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="${ENVD_VERSION}" \
      io.cubesandbox.toolbox.ref="otaku-say/skills@${TOOLBOX_REF}" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"30G","cpu":3000,"memory":3000,"alias":"aio-default","notes":"iSH 同源：alpine 3.23.6 + busybox 1.38 默认终端 + 58 件工具箱 + git/zig 开发链"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="30G" \
      io.cubesandbox.template.cpu="3000" \
      io.cubesandbox.template.memory="3000" \
      io.cubesandbox.template.alias="aio-default"
