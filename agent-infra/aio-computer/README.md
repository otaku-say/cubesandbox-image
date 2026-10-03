# agent-infra/aio-computer —— CubeSandbox AIO 2.x（官方「带桌面」镜像 + envd 注入）

`ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-computer:latest`

上游镜像：`enterprise-public-cn-beijing.cr.volces.com/vefaas-public/aio-computer`
（官方 2.x 预构建镜像：aiod + nginx 网关 + Chromium/VNC + **XFCE 桌面 + computer-use worker**）

> ⚠️ **上游没有 `latest` 标签**。实测 tags 只有 `1.0.0` / `1.0.1`（另有 `-nydus` 变体）。
> 本目录固定使用 **`1.0.1`**，由 `ARG AIO_COMPUTER_TAG` 控制。

## 为什么需要这个镜像

`/v2/computer/*`（桌面截图、鼠标键盘、剪贴板、窗口列表、无障碍树、录屏）**只有带
computer-use worker 的镜像才提供**：`aio-computer` 有，`aio-daemon` 没有（路由 503）。
所以它专门用来 **验收 computer-use 相关工具链**（如 `sandbox-sdk-go` 的 `cmp-*` 命令）。

## 四个镜像怎么选

| 目录 | 基础 | API 面 | computer-use | 体积（压缩） |
|---|---|---|---|---|
| `agent-infra/sandbox` | ghcr 1.x 发行镜像 | v1 only | ✗ | ≈ 9 GB 解压 |
| `agent-infra/aio-daemon` | 火山 aio-daemon 1.0.1 | v1 + v2 | ✗（503） | ≈ 3.1 GB |
| **`agent-infra/aio-computer`**（本目录） | 火山 aio-computer 1.0.1 | v1 + v2 | **✓**（XFCE + worker :18100） | ≈ 3.1 GB |
| `agent-infra/aiod` | cubesandbox-base + 自行安装 | v1 + v2 | ✗ | ≈ 1.2 GB |

## 镜像内容与端口

```
aio-computer 1.0.1（上游整套）
├── nginx 网关 :8080        ← 实测对外入口（转发 aiod 18091 / computer-use 18100）
├── aiod :18091（loopback） ← v1 + v2 双面 API
├── computer-use worker :18100（loopback） ← /v2/computer/*
├── XFCE 桌面 + VNC(5900) + Chromium（BROWSER_START_MODE=manual）
└── 本次注入：envd :49983   ← E2B/CubeSandbox 数据面（tini + cube-entrypoint 契约）
```

启动链：`tini` → `cube-entrypoint.sh`（后台起 envd）→ 前台 `/opt/gem/run.sh`（上游服务树）。

## 构建

```bash
./build.sh              # 构建 + 冒烟测试
./build.sh --push       # 追加推送 :latest
```

CI：push 到非 `main` 分支 → `Branch Build (test)`（构建 + 冒烟 + 推 `:test`）；
合入 `main` 后由 `Build Images` 推 `:latest`。

## 冒烟测试覆盖（与 aio-daemon 的差异在 [4/6]）

1. envd `:49983/health` → 204
2. 网关端口发现（8080/8091，最多等 180s，桌面镜像更慢）
3. v1/v2 双面核对
4. **computer-use 面**：`/v2/computer/info` 200、`/v2/computer/screenshot` 返回**真 PNG**，
   并逐条探测 `cursor` / `clipboard` / `windows` / `accessibility`
5. 能力抽查（browser / code_interpreter / **computer**）+ `/v2/commands`
6. 打印镜像体积

## 在 CubeSandbox 里注册模板

```bash
POST /templates
{
  "name": "aio-computer",
  "image": "ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-computer:latest",   # 建议 digest 固定
  "writableLayerSize": "12G",
  "exposedPorts": [49983, 8080],
  "probePort": 49983, "probePath": "/health",
  "cpu": 4000, "memory": 4096
}
```

> 桌面镜像比 aio-daemon 重（XFCE + worker）；若宿主机内存紧张，可用 2C/3G 的小模板跑
> （模板构建一次即可，与副本数无关）。

## 已知边界

- **仅 amd64**：上游与 Chrome 官方均只发布 x86_64。
- **桌面为「手动启动浏览器」模式**：`BROWSER_START_MODE=manual`，Chromium 不随容器启动，
  浏览器类路由在手动拉起前为 `degraded`；但 `/v2/computer/*`（桌面）不受影响。
- CDP 仍只绑 `127.0.0.1`（Chrome 111+ 行为），外部控制请走 aiod 路由。
