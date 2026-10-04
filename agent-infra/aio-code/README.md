# agent-infra/aio-code —— 轻量代码沙箱（cubesandbox-base + AIO Daemon）

**定位**：专为自动化 Agent 打造的低内存（<2GB RAM 配额）、通用性开发与调试沙箱。  
**特性**：**无** Node.js、**无** 浏览器、**无** 桌面、**无** Jupyter。纯净高效，常驻内存仅 ~80MB。

| 组成 | 来源 | 说明 |
|---|---|---|
| 基底 | `ghcr.io/tencentcloud/cubesandbox-base` | Ubuntu 22.04 + **envd(49983)/tini/cube-entrypoint 原生启动契约** |
| aiod | `aio-static.tos-cn-beijing.volces.com/v0.9.2/linux-x86_64/aiod` | AIO Daemon 单文件守护进程（musl 静态），构建时按 SHA256SUMS 校验；`AIO_PORT=8080`，提供 `/v1` 与 `/v2` 双面 API |

---

## 架构拓扑：本地遥控 + 云端沙箱 + GitHub Actions CI

本环境采用三层协作设计，彻底杜绝沙箱内部运行 Docker-in-Docker（DinD）导致的 OOM 风险：

```
┌──────────────────┐      HTTP / RPC      ┌───────────────────────────────────┐
│  本地 iSH (iOS)   │ ──────────────────> │   云端 OpenMinis + CubeSandbox    │
│   [轻量遥控器]    │                     │   [Agent 执行车间 (2GB 内存配额)] │
└──────────────────┘                     └─────────────────┬─────────────────┘
  • 发送任务意图，不跑任务                                   │
  • 不拉取代码，不装依赖                                     │ 1. 检视代码、改写 Dockerfile
                                                           │ 2. git push / gh 触发 Actions
                                                           │ 3. gh run watch 监听构建日志
                                                           ▼
                                         ┌───────────────────────────────────┐
                                         │         GitHub Actions CI         │
                                         │     [7GB+ 内存 Runner 云端构建]    │
                                         └─────────────────┬─────────────────┘
                                                           │ docker buildx
                                                           │ push image
                                                           ▼
                                         ┌───────────────────────────────────┐
                                         │       ghcr.io 容器镜像仓库        │
                                         └───────────────────────────────────┘
```

---

## 镜像内容与端口

```
aio-code (运行时基础内存 ~80MB)
├── envd :49983   ← CubeSandbox / E2B 平台探针与数据面通道
├── aiod :8080    ← AIO Daemon，/v1 + /v2 双面 API（AIO_PORT=8080）
└── 工具链（版本全部固定，升级改 Dockerfile ARG）
    ├─ Python 3.12（deadsnakes 唯一版本）+ dev 头文件 + pip + uv（单文件/测试环境秒级运行）
    ├─ Zig 0.17.0（主开发语言；自带 cc / c++ 封装软链，可作为 C 编译器使用）
    ├─ 文本与文档：bat（语法高亮与行号查看）/ vim-tiny / less / tree / ripgrep / fd
    ├─ 远端调度：gh（GitHub CLI）/ git（内置 256M 内存限制与 safe.directory）/ yq / jq
    ├─ 编译依赖：make / pkg-config / libssl-dev / zlib1g-dev / diffutils / patch
    └─ 网络与调试：socat / netcat / rsync / openssh-client / sqlite3 / shellcheck / strace
```

启动链路：base 镜像自带的 `tini → cube-entrypoint.sh`（后台运行 envd + 前台执行 CMD 并做信号转发），`CMD = ["/usr/local/bin/aiod", "start"]`。

---

## 设计取舍与低内存防御（<2GB 优化）

1. **移除 Node.js 全家桶**：彻底移除 V8 引擎运行时，消除单次前端构建吃满 1.5GB 内存的隐患，释放约 150MB 磁盘空间与 ~100MB 运行内存。
2. **移除交互式 GDB**：避免拉取 Python 3.10 动态共享库；底层故障排查与系统调用追踪完全由轻量的 `strace` 与 Zig 自带 Panic 追踪覆盖。
3. **Glibc 防碎片**：全局设定 `MALLOC_ARENA_MAX=2`，在多核宿主机上大幅削减多线程内存池碎片。
4. **Git 打包防暴毙**：配置 `pack.windowMemory="256m"` 与 `pack.threads="2"`，防止拉取大型仓库时内存毛刺冲垮容器。
5. **并发控制**：全局设置 `MAKEFLAGS="-j2"` 与 `UV_CONCURRENT_INSTALLS=2`，防止多核宿主机并发任务打满 2GB 内存。

---

## 本地构建与冒烟测试

本地仅用于快速验证 Dockerfile 语义和产物连通性：

```bash
# 构建本地镜像并执行完整冒烟测试（含 aiod、探针、编译测试、工具链检测）
./build.sh

# 测试通过后推送到 GHCR（需本地具备写入权限）
./build.sh --push
```

### 冒烟测试覆盖范围（7 项验证）
1. `envd :49983/health` 响应 204
2. `aiod :8080/health` 响应 200，且 `/v1/capabilities` 与 `/v2/sandbox` 双面就绪（旧端口 18091 确认未监听）
3. 命令执行面：`/v2/commands` 与 `/v1/bash/exec` 正确执行且 UID 为 0
4. 能力面：`/v1/capabilities?refresh=true` 确认 code_interpreter 正确，无冗余桌面组件
5. 工具链实跑：
   - Python 3.12 唯一性及头文件
   - `uv` 动态加载 pytest 临时测试运行
   - `cc` 符号软链成功包装 `zig cc` 编译并执行 C 产物
   - `bat`、`socat`、`pkg-config`、`shellcheck` 语法断言
   - 确认无残留 `node` 二进制
6. 端口监听：`ss -tln` 确认 49983 和 8080 正常开放
7. 镜像体积统计输出

---

## 注册 CubeSandbox 模板

镜像内标签 `io.cubesandbox.template.*` 已固化推荐规格，可使用 SDK 直接导入：

```bash
cubesandbox-sdk-go tpl-from-image ghcr.io/otaku-say/cubesandbox-image/agent-infra/aio-code:latest --create
```

手工注册 API 参数（2GB 内存契约）：

```json
POST /templates
{
  "name": "aio-code",
  "image": "ghcr.
