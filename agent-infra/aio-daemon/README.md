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
├── nginx 网关 :8080       ← 实测对外入口（转发到 aiod 18091 / computer-use 18100）
│                           ⚠️ 官方文档写 8091，实测 1.0.1 监听的是 8080（容器内 banner
│                           亦指向 8080）；8091 未监听。冒烟测试会自动发现端口归属
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

## v2 API 全量测试（tests/）

`tests/suite.py` 是覆盖 v2 OpenAPI（0.9.2，65 路径）的可重复测试套件，直接跑在沙箱网关基址上：

```bash
BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>/8080" python3 tests/suite.py
```

覆盖八个面：运维（/health、/v2/sandbox、/v2/sandbox/packages）、命令（同步/异步/stdin/kill/
超时/输出截断/stdout-stderr 分流/offset 回读/session/shell 选择器）、文件（写读改查删拷移、
行号读、grep、glob、multipart 上传 ↔ 下载 sha256 一致）、终端（建/exec/screen/input/signal/
改尺寸/删）、监听（create/poll/list/delete）、代码（python/javascript/会话状态保持）、
浏览器（info/navigate/截图 PNG/evaluate/snapshot/fill/click/标签页/cookie/网络日志/原生 CDP/
真实站点导航）、MCP（initialize + tools/list，31 个工具）。

**最近一次实测：87 通过 / 0 失败 / 1 跳过**（跳过项 = `/v2/computer/*` 返回 503，
该镜像不含 computer-use worker，属预期）。

实测出的 API 语义（写测试时按这些断言）：

| 行为 | 实测结果 |
|---|---|
| 命令状态/退出码位置 | 在 `data.command.status` / `.exit_code`，不在 `data` 顶层 |
| kill 后 | `status=completed`、`exit_code=-1`（不单独报告 signal） |
| 命令会话 cwd | 固定在创建时的 `cwd`；会话内 `cd` **不**跨调用保留（每条命令仍是新进程） |
| 超时 | `timeout=1` 时立即返回且 `status=running`（进程继续跑，需自行 kill） |
| `/v2/sandbox/packages` | 返回**文本**清单（不是 JSON 数组）；`lang=py` 会 400，要用 `python`/`node` |
| `/v2/fs/upload` | multipart，字段名 `file`，落在 `/tmp/<filename>` |
| `/v2/browser/screenshot` | `format=png` 直接返回 PNG 字节流 |
| `/v2/browser/snapshot` | 返回可访问性快照（带 ref），可配合 `click/fill` 的 `ref` 用 |

## 在 CubeSandbox 里注册模板（默认值已写进镜像，免手填）

镜像里带了 `io.cubesandbox.template.*` 标签，一条命令读出并直接建模板：

```bash
# 只看会提交什么（读 registry 里的镜像配置）
cubesandbox-sdk-go tpl-from-image ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-daemon:latest

# 直接提交给平台（--curl 则输出可执行的 curl；--cpu/--memory 可临时覆盖）
cubesandbox-sdk-go tpl-from-image ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-daemon:latest --create
```

等价手工参数（与标签内容一致）：

```bash
POST /templates
{
  "name": "aio-daemon-small",
  "image": "ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-daemon:latest",   # 建议用 digest 固定
  "writableLayerSize": "12G",          # 镜像解压后 7.4GB，可写层给足
  "exposedPorts": [49983, 8080],
  "probePort": 49983, "probePath": "/health",
  "cpu": 2000, "memory": 3072
}
```

> **标签约定**（`docker inspect` 可见，registry config 可读；平台自身目前不读取——
> CubeTemplateCenter 源码注释明确 "ExposedPorts/Labels/Healthcheck ... intentionally omitted"）：
> `io.cubesandbox.template.defaults`（JSON 汇总）+ 单键 `exposed-ports` / `probe-port` /
> `probe-path` / `writable-layer-size` / `cpu` / `memory` / `alias`。
> 无标签的镜像由 `tpl-from-image` 回退读标准 `EXPOSE`。
> 例子：`pods` 里的 CPU/内存按宿主机余量调（本集群 2C/3G 跑得动）。

> 实测（2026-10-03）：模板构建约 12 分钟（7.4GB 镜像 pull + rootfs 分发）；
> 沙箱创建后 envd `204` 约 4 秒、网关 `200` 约 4 秒可用。

访问（数据面经网关路径路由，端口 = 容器内端口）：

```bash
BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>"
curl "$BASE/8080/v1/capabilities"          # AIO API（v1 兼容面）
curl "$BASE/8080/v2/sandbox"               # AIO API（v2 原生面）
curl -o /dev/null -w '%{http_code}\n' "$BASE/49983/health"   # envd → 204
```

本地遥控 CLI 照旧：

```bash
export SANDBOX_BASE="https://<cubesandbox-proxy-host>/sandbox/<sandboxID>/8080"
sandbox-sdk-go exec "id; uname -a"
```

## 取舍与边界

- **优点**：官方 2.x 全套（含 VNC 桌面、Jupyter、code-server、多语言工具链），v1/v2 双面，注入层只有一个 COPY 步骤，升级成本 = 改 tag。
- **代价**：体积大（约 3 GB 压缩 / 解压后更大），内容与版本随上游；构建与模板拉取都依赖**火山 Harbor 可达**（公开项目可匿名拉取，实测从 iSH 可拉）。
- **只有 envd 是"外来户"**：其余全是上游原样，出问题先看 `/opt/gem/run.sh` 与上游文档。
- 端口以实测为准：本镜像 nginx 网关实际监听 **8080**（上游文档写 8091，实测 1.0.1 不监听 8091）；镜像 `EXPOSE` 同时声明了 49983/8080/8091/9222，注册模板用 49983+8080。
