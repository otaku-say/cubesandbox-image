# agent-infra/aio-code —— 代码沙箱（cubesandbox-base + AIO Daemon）

**定位**：写代码 / 测试 / 编译 / 调试。轻量：**无**浏览器、**无**桌面、**无** Jupyter。
需要浏览器 → [`agent-infra/aio-daemon`](../aio-daemon)；需要桌面 → [`agent-infra/aio-computer`](../aio-computer)。

| 组成 | 来源 | 说明 |
|---|---|---|
| 基底 | `ghcr.io/tencentcloud/cubesandbox-base` | Ubuntu 22.04 + **envd(49983)/tini/cube-entrypoint 原生契约**（压缩层 ~36MB） |
| aiod | `aio-static.tos-cn-beijing.volces.com/v0.9.2/linux-x86_64/aiod` | AIO Daemon 单文件（musl 静态），构建时按 SHA256SUMS 校验；`AIO_PORT=8080` |

## 镜像内容与端口

```
aio-code
├── envd :49983   ← CubeSandbox/E2B 数据面（cubesandbox-base 原生）
├── aiod :8080    ← AIO Daemon，v1+v2 双面 API（AIO_PORT=8080，与 aio-daemon 一致）
└── 工具链（版本固定，升级改 Dockerfile ARG）
    ├─ Python 3.12（唯一版本，默认 python3）+ pip + venv + uv
    ├─ Node.js 24 LTS（v24.21.0）+ npm
    ├─ Zig 0.17.0（我们 CLI 主语言；兼 C/C++ 应急编译 zig cc）
    ├─ 日常：git / jq / yq / ripgrep / fd / tmux / vim / xxd / file / less / tree
    │        diffutils / patch / zip / unzip / xz / zstd / bzip2 / rsync
    │        openssh-client / wget / sqlite3 / openssl / gh
    └─ 调试：shellcheck / gdb / strace / iproute2(ip,ss) / ping / nc
```

启动链：base 的 `tini → cube-entrypoint.sh`（后台 envd + 前台 CMD + 信号转发），
CMD = `aiod start`。

## 设计取舍（为什么这么轻）

- **不装 Jupyter / code-interpreter**：用不到。`/v1/code`、`/v2/code` 有 python3/node
  即正常工作，仅 `/v1/jupyter` 路由返回 501。
- **不装系统 C/C++ 工具链**：Zig CLI 编译完全自包含；真要编 C，`zig cc` 直接可用
  （已进冒烟测试），或沙箱内 `apt-get install build-essential` 临时装。
- **网络调试工具收最小集**（ip/ss/ping/nc）：家庭网络排障类工具（tcpdump/dig）
  需要时沙箱内 apt 临时装。
- **版本全部固定**：Node/Zig/yq/gh/aiod……升级改对应 ARG，push 即触发重建。
- **gdb 说明**：依赖 libpython3.10 运行库（仅共享库，不会出现 3.10 解释器）。

## 构建

```bash
./build.sh              # 构建 + 冒烟测试
./build.sh --push       # 追加推送 :latest

# 换版本：
docker build --build-arg AIOD_VERSION=v0.9.1 -t aio-code:dev .
docker build --build-arg NODE_VERSION=v24.20.0  -t aio-code:dev .
docker build --build-arg BASE_IMAGE=...         -t aio-code:dev .
```

CI：push 到非 `main` 分支 → `Branch Build (test)`（构建 + 冒烟 + 推 `:test`）；
合入 `main` 后由 `Build Images` 推 `:latest`。

## 冒烟测试覆盖

1. envd `:49983/health` → **204**（与平台模板探针同口径）
2. aiod `:8080/health` → 200，`/v1/capabilities` + `/v2/sandbox` 双面齐；
   且 **18091 不再监听**（端口已统一到 8080）
3. 执行面：`/v2/commands`、`/v1/bash/exec`，并核对执行账户（root=0）
4. 能力面：`/v1/capabilities?refresh=true` 输出 code_interpreter/browser/computer 状态
5. 工具链：python3=3.12（且无其他解释器版本）、node=24、zig=0.17.0、venv、shellcheck
   正/负样例、**zig cc 编译 C 并运行**、strace/gdb 实跑、aiod doctor
6. 端口：ss 确认 49983 + 8080 在监听
7. 打印镜像体积

## 在 CubeSandbox 里注册模板（默认值已写进镜像，免手填）

```bash
# 一条命令读出镜像自带的默认值并直接建模板
cubesandbox-sdk-go tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-code:latest --create
#（或不带 --create 打印请求体 / --curl 输出可执行 curl）
```

等价手工参数（与 `io.cubesandbox.template.*` 标签一致）：

```json
POST /templates
{
  "name": "aio-code",
  "image": "ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-code:latest",
  "writableLayerSize": "10G",
  "exposedPorts": [49983, 8080],
  "probePort": 49983, "probePath": "/health",
  "cpu": 2000, "memory": 3072
}
```

## 使用

```bash
# 平台数据面（经网关路径路由，端口 = 容器内端口）
BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>"
curl -o /dev/null -w '%{http_code}\n' "$BASE/49983/health"     # envd → 204
curl "$BASE/8080/health"                                        # aiod → 200
curl "$BASE/8080/v2/commands" -X POST -H 'Content-Type: application/json' -d '{"command":"uname -a"}'

# sandbox-sdk-go 直接对接（SANDBOX_BASE 指到 /8080）
```

## 升级路径（常见改动）

| 要改什么 | 改哪里 |
|---|---|
| aiod 版本 | Dockerfile `ARG AIOD_VERSION`（track-upstream 有新版巡检会自动开 issue） |
| Node / Zig / yq / gh | 对应 `ARG *_VERSION`（Zig 校验值自动从 index.json 取） |
| Python 版本 | deadsnakes 包名 `python3.12` → 新版本（并同步 python3/python 软链） |
| 临时装工具 | 沙箱内直接 `apt-get install` / `uv tool` / `npm -g`（有网，秒级） |
