# syntax=docker/dockerfile:1.7
# =============================================================================
# 项目名称：aio-default 沙箱镜像 (CubeSandbox)  v6「AOJIT 迁移对齐版」
# 创建时间：2026-10-12
# 功能简述：基于 Alpine 3.23 的 MicroVM 代码执行沙箱基础镜像。
#
# v6 变更（对齐本地 iSH 手感；云端无 AOJIT，取 apk 源最新版即可）：
#   1) 工具箱裁到 43 件：原 58 件中，AOJIT 内置加速的 15 件已下架
#      （busybox/python3/curl/openssl/ssh 全家/sqlite3/socat/drill/uv）
#   2) 下架的 15 件改由 apk 提供：python3/py3-pip/nodejs/npm/curl/openssl/
#      sqlite/socat/drill/uv/openssh-client/bind-tools；busybox 用系统自带
#   3) 不再替换系统 busybox（工具箱已无 busybox）；不再做 pip→uv 桥接
#      （装真 pip，与本地 iSH 一致）
#   4) 手感补位（人工确认保留）：jq + python3/py3-pip/py3-setuptools/
#      py3-pillow/py3-numpy；已按「有替代」或「交互式 TUI」裁掉
#      vim/7zip/b3sum/nnn/ncdu
#
# 设计原则：工具层 = 工具箱 43 件（静态，与 iSH 同源同校验，直取
#          otaku-say/ish-toolbox 的产物 commit）+ apk 系统层（编译链 /
#          解释器 / 网络与加密 CLI）；平台契约对齐官方 base
#          （envd :49983 / cube-entrypoint / nice / user 账号）。
# =============================================================================
FROM alpine:3.23.6

ARG ENVD_VERSION=v0.9.202610091259-41ed62c3bc4
# TOOLBOX_REF = otaku-say/ish-toolbox 的产物 commit（工具箱 43 件）
ARG TOOLBOX_REF=671e3d063253c49dbb7ceaf50228804b822803f7
ARG AIOD_VERSION=v0.9.2
ARG AIOD_PLATFORM=linux-x86_64
ARG AIOD_BASE_URL=https://aio-static.tos-cn-beijing.volces.com
ARG ZIG_VERSION=0.17.0

# ---- 1) 系统软件层（apk；取本分支最新版，不与 iSH 对齐版本号）----
#  A. 编译基础设施与运行库
#  B. AOJIT 迁移补位：原工具箱自带、现由 apk 提供的 CLI 与解释器
#  C. 高频手感工具：jq + Python 图像/数值栈（人工确认保留）
RUN set -eux; \
    apk add --no-cache \
        ca-certificates tzdata sudo \
        make pkgconf linux-headers binutils file \
        autoconf automake libtool m4 bison flex \
        qemu-aarch64 gcompat \
        jq \
        python3 py3-pip py3-setuptools py3-pillow py3-numpy \
        nodejs npm \
        curl openssl sqlite socat drill uv bind-tools \
        openssh-client; \
    rm -rf /var/cache/apk/*; \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone

# ---- 2) ish-toolbox 43 件（与本地 iSH 同一套：逐件强校验 → 软链）----
COPY fetch-toolbox.sh /tmp/fetch-toolbox.sh
RUN sh /tmp/fetch-toolbox.sh && rm -f /tmp/fetch-toolbox.sh

# ---- 3) envd：官方桶直取 + sha256 边车校验 ----
RUN set -eux; \
    curl -fsSL --retry 3 "https://storage.googleapis.com/e2b-artifact-binaries/envd/${ENVD_VERSION}/envd" -o /usr/bin/envd; \
    curl -fsSL --retry 3 "https://storage.googleapis.com/e2b-artifact-binaries/envd/${ENVD_VERSION}/envd.sha256" -o /tmp/envd.sha256; \
    grep -E '[[:space:]]envd$' /tmp/envd.sha256 > /tmp/envd.sum; \
    (cd /usr/bin && sha256sum -c /tmp/envd.sum); \
    chmod 0755 /usr/bin/envd; rm -f /tmp/envd.sha256 /tmp/envd.sum; \
    mkdir -p /var/log; \
    /usr/bin/envd -version

# ---- 4) cube-entrypoint.sh（官方 master 版，vendored）----
COPY cube-entrypoint.sh /usr/local/bin/cube-entrypoint.sh
RUN chmod 0755 /usr/local/bin/cube-entrypoint.sh

# ---- 5) tini（工具箱静态版，替代 base 的 glibc 动态版；仍在 43 件内）----
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
#   通过 edge 源拉取最新版；依赖实测全部来自 3.23 stable；装完清理 @edge
#   （repositories 与 apk world 双清理——只删 repositories 会留下 world 缺 tag 的隐患）
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

# ---- 9) 基础软链接、用户权限与 Git 运行时优化 ----
#  说明：python3/pip 由 apk 提供（不再软链工具箱）；awk 指向工具箱 gawk；
#        bash 为工具箱静态版（Alpine 系统无 bash）。
RUN set -eux; \
    ln -sf /opt/skills/tools/bash/amd64/bash /bin/bash; \
    grep -qxF '/bin/bash' /etc/shells || echo '/bin/bash' >> /etc/shells; \
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

# ---- 10) Agent 层：速查命令 / 指南 / 缺命令提示 ----
#  pip 桥已移除（现在装的是真 pip，与本地 iSH 一致）
COPY files/bash_env.sh /etc/bash/env.sh
COPY files/toolbox.sh /usr/local/bin/toolbox
COPY files/motd /etc/motd
COPY agent-guide.md /opt/skills/tools/AGENT-GUIDE.md
RUN set -eux; \
    chmod 0755 /usr/local/bin/toolbox; \
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
      org.opencontainers.image.description="iSH 同源 Alpine 沙箱 v6：alpine 3.23.6 + ish-toolbox 43 件 + apk 系统层（python3/nodejs/curl/openssl/git/zig）" \
      org.opencontainers.image.source="https://github.com/otaku-say/cubesandbox-image" \
      io.cubesandbox.envd.ref="${ENVD_VERSION}" \
      io.cubesandbox.toolbox.ref="otaku-say/ish-toolbox@${TOOLBOX_REF}" \
      io.cubesandbox.template.defaults='{"exposedPorts":[49983,8080],"probePort":49983,"probePath":"/health","writableLayerSize":"30G","cpu":3000,"memory":3000,"alias":"aio-default","notes":"iSH 同源：alpine 3.23.6 + 工具箱 43 件 + apk 系统层"}' \
      io.cubesandbox.template.exposed-ports="49983,8080" \
      io.cubesandbox.template.probe-port="49983" \
      io.cubesandbox.template.probe-path="/health" \
      io.cubesandbox.template.writable-layer-size="40G" \
      io.cubesandbox.template.cpu="3000" \
      io.cubesandbox.template.memory="4000" \
      io.cubesandbox.template.alias="aio-default"
