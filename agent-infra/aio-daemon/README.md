# agent-infra/aio-daemon —— CubeSandbox AIO 2.x（官方发行镜像 + envd 注入）

`ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-daemon:latest`

上游镜像：`enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-daemon`
（官方 2.x 预构建镜像：aiod 守护进程 + nginx 网关 + Chromium/VNC + Python/Node 工具链，
同时提供 `/v1/*`（1.x 兼容）与 `/v2/*`（原生）双面 API）

> ⚠️ **上游没有 `latest` 标签**。实测 tags 只有 `1.0.0` / `1.0.1`（另有 `-nydus` 变体）。
> 本目录固定使用 **`1.0.1`**，由 `ARG AIO_DAEMON_TAG` 控制；上游发新版本时改这个参数即可。

## 三个目录怎么选

| 目录 | 基础 | API 面 | 体积 | 说明 |
|---|---|---|---|---|
| `agent-infra/sandbox` | `ghcr.io/agent-infra/sandbox`（1.x） | **v1 only** | ≈ 9 GB | 1.x 全功能套壳（桌面/VNC/IME/Jupyter/code-server） |
| **`agent-infra/aio-daemon`**（本目录） | `.../vefaas-public/aio-daemon`（2.x） | **v1 + v2** | ≈ 3 GB 压缩 | 直接复用上游 2.x 发行镜像，功能最全的 2.x 方案 |
| `agent-infra/aiod` | `cubesandbox-base` + 自行安装 | v1 + v2 | ≈ 1.2 GB | 从源构建，体积/内容完全自控（无桌面/VNC/Jupyter） |

## 镜像内容与端口

```
aio-daemon 1.0.1（上游整套）
├── nginx 网关 :8091       ← 对外唯一入口（转发到 aiod 18091 / computer-use 18100）
├── aiod :18091（loopback）← v1 + v2 双面 API
├── Chromium + VNC + 桌面与工具链（Python/Node/Go/uv/Jupyter/code-server…）
└── 本次注入：envd :49983  ← E2B/CubeSandbox 数据面（tini + cube-entrypoint 契约）
```

启动链：`tini` → `cube-entrypoint.sh`（后台起 envd）→ 前台 `/opt/gem/run.sh`（上游服务树）。
信号与退出码由 cube-entrypoint 转发，与上游 `docker run` 行为一致。

## 构建

```bash
./build.sh              # 构建 + 冒烟测试
./build.sh --push       # 追加推送 :latest

# 换上游版本
docker build --build-arg AIO_DAEMON_TAG=1.0.1 -t aio-daemon:dev .
```

CI：push 到非 `main` 分支 → `Branch Build (test)`（构建 + 冒烟 + 推 `:test`）；合入 `main` 后由 `Build Images` 推 `:latest`。

## 冒烟测试覆盖

`smoke-test.sh <image>`：

1. envd `:49983/health` → **204**
2. nginx 网关 `:8091/v1/capabilities` → **200**（服务树较慢，最多等 150s）
3. **双面 API 核对**：`/v1/capabilities` 与 `/v2/sandbox` 都必须 200
4. 能力与功能：`browser` / `code_interpreter` 状态 + `/v2/commands`、`/v1/bash/exec` 实跑
5. 打印镜像体积

## 在 CubeSandbox 里注册模板

```bash
# 平台侧（expose envd 49983 + nginx 8091；probe 用 envd，~1s 就绪）
POST /templates
{
  "name": "aio-daemon",
  "image": "ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-daemon:latest",
  "writableLayerSize": "16G",          # 上游镜像约 3GB 压缩，可写层给足
  "exposedPorts": [49983, 8091],
  "probePort": 49983, "probePath": "/health",
  "cpu": 4000, "memory": 4096
}
```

访问（数据面经网关路径路由，端口 = 容器内端口）：

```bash
BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>"
curl "$BASE/8091/v1/capabilities"          # AIO API（v1）
curl "$BASE/8091/v2/sandbox"               # AIO API（v2）
curl -o /dev/null -w '%{http_code}\n' "$BASE/49983/health"   # envd → 204
```

本地遥控 CLI 照旧：

```bash
export SANDBOX_BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>/8091"
sandbox-sdk-go exec "id; uname -a"
```

## 取舍与边界

- **优点**：官方 2.x 全套（含 VNC 桌面、Jupyter、code-server、多语言工具链），v1/v2 双面，注入层只有一个 COPY 步骤，升级成本 = 改 tag。
- **代价**：体积大（约 3 GB 压缩 / 解压后更大），内容与版本随上游；构建与模板拉取都依赖**火山 Harbor 可达**（公开项目可匿名拉取，实测从 iSH 可拉）。
- **只有 envd 是"外来户"**：其余全是上游原样，出问题先看 `/opt/gem/run.sh` 与上游文档。
- 端口以实测为准：nginx 监听 `8091`（文档与 `SANDBOX_SRV_PORT` 一致）；镜像元数据里声明的 `8080` 不一定是网关端口，注册模板时以冒烟测试结果为准。
