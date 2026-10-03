# agent-infra/aio-code —— 轻量代码沙箱（官方 sandbox-code + AIO Daemon）

**定位**：小体积、覆盖日常多数场景（编辑文件 / 跑脚本 / 数据处理 / git / HTTP 抓取 /
E2B 代码执行），**不带** Chromium / VNC / 桌面。
需要浏览器 → [`agent-infra/aio-daemon`](../aio-daemon)；需要桌面 → [`agent-infra/aio-computer`](../aio-computer)。

| 组成 | 来源 | 说明 |
|---|---|---|
| 基底 | `cube-sandbox-cn.tencentcloudcr.com/cube-sandbox/sandbox-code` | 官方代码执行环境，**已内置 envd**，E2B SDK 兼容；层合计仅 ~110MB |
| aiod | `aio-static.tos-cn-beijing.volces.com/v0.9.2/linux-x86_64/aiod` | AIO Daemon 单文件（musl 静态），构建时按 SHA256SUMS 校验 |

## 镜像内容与端口

```
aio-code
├── envd :49983             ← E2B/CubeSandbox 数据面（sandbox-code 原生自带）
├── code-interpreter :49999 ← E2B 兼容的 uvicorn 服务（0.0.0.0）
├── Jupyter Server :8888    ← 仅 127.0.0.1（aiod 经 AIO_JUPYTER_ENDPOINT 访问）
├── aiod :18091             ← AIO Daemon，v1+v2 双面 API（AIO_PORT 可改）
└── 工具: git curl jq ripgrep tmux procps vim-tiny tini nodejs（apt，--no-install-recommends）
```

启动链：`tini(PID1)` → `entrypoint-aio.sh`
→ 后台跑原 `start-lightweight-code-interpreter.sh`（envd + Jupyter + 代码解释器），
   前台受监管跑 `aiod start`；**任一进程退出 → 整体退出 → 平台重建**。

能力口径（`cubesandbox-sdk-go tpl-caps --probe` 实测判定）：`shell,file,code`，
**无 browser / desktop**（镜像里没有 Chromium 和 computer-use worker）。

## 构建

```bash
./build.sh              # 构建 + 冒烟测试
./build.sh --push       # 追加推送 :latest

# 换 aiod 版本 / 换 base
docker build --build-arg AIOD_VERSION=v0.9.1 -t aio-code:dev .
docker build --build-arg BASE_IMAGE=... -t aio-code:dev .
```

CI：push 到非 `main` 分支 → `Branch Build (test)`（构建 + 冒烟 + 推 `:test`）；
合入 `main` 后由 `Build Images` 推 `:latest`。

## 冒烟测试覆盖

1. envd `:49983/health` → **204**（与平台模板探针同口径）
2. aiod `:18091/health` → 200，`/v1/capabilities` + `/v2/sandbox` 双面齐
3. 执行面：`/v2/commands`、`/v1/bash/exec`，并核对执行账户（root=0）
4. 能力面：`/v1/capabilities?refresh=true`（绕开 5s 缓存）核对
   code_interpreter=ready、browser/computer=无；`aiod doctor --json` 自检 bash/rg/tmux
5. Jupyter `127.0.0.1:8888/api/status` → 200 + 工具集（python3/node/git/jq/rg/tmux/aiod）
6. 打印镜像体积

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
  "exposedPorts": [49983, 49999, 18091],
  "probePort": 49983, "probePath": "/health",
  "cpu": 2000, "memory": 3072
}
```

## 使用

```bash
# 平台数据面（经网关路径路由，端口 = 容器内端口）
BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>"
curl -o /dev/null -w '%{http_code}\n' "$BASE/49983/health"     # envd → 204
curl "$BASE/18091/health"                                       # aiod → 200
curl "$BASE/18091/v2/commands" -X POST -H 'Content-Type: application/json' -d '{"command":"uname -a"}'

# E2B SDK（官方 sandbox-code 兼容面不变）
# 代码执行走 49999；envd 走 49983
```

## 取舍与边界

- **为什么不用官方 aiod 镜像**：官方 `aio-daemon/aio-computer` 是全家桶（7.4GB，含
  Chromium/VNC/桌面），日常"改文件/跑脚本/抓数据"用不到，且拉取/构建慢、占磁盘。
  本镜像 ~110MB 基底 + 工具，构建快、拉取快。
- **浏览器/桌面刻意不带**：要就换模板（`new --need=browser/desktop` 会自动挑）。
- **Jupyter 只在 loopback**：`AIO_JUPYTER_ENDPOINT=http://127.0.0.1:8888` 让 aiod
  的 `/v1/jupyter` 可用；外部如需直连 Jupyter，自行改 `JUPYTER_HOST=0.0.0.0` 并暴露 8888。
- **aiod 未配 API key**：走平台边缘鉴权；若把 18091 暴露到公网，自行设置 `AIO_API_KEY`。
- **版本固定**：`AIOD_VERSION=v0.9.2`（可复现构建）；升版改 ARG 即触发重建。
  `latest/<platform>/aiod` 始终是最新稳定版，想追新可改 URL。
