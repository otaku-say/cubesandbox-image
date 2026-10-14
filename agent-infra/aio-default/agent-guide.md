# aio-default 沙箱环境指南（AGENT-GUIDE）

> 本沙箱为 **CubeSandbox 深度对齐环境**，集成：
> 1. **ish-toolbox 静态工具**（GNU 套件与现代 CLI 增强）
> 2. **apk 系统层**（解释器、编译工具链、网络与系统工具）
> 3. **最新独立 uv / uvx 工具链**（极速 Python 包管理与工具运行器）
> 4. **官方 mcp-gateway 服务**（E2B 兼容的 MCP 服务协议，支持内置/GitHub/自定义工具）

---

## 1. 核心服务与端口

| 服务 | 端口 | 协议/说明 |
|---|---|---|
| **envd** | `49983` | CubeSandbox 控制与执行协议，健康探针端点 `/health` |
| **aiod** | `8080` | 数据面 API 服务（AIO v2 接口） |
| **mcp-gateway** | `50005` | E2B 兼容的 MCP 流式 HTTP 网关端点 `/mcp`，`/health` 探针 |

---

## 2. 真实可用工具分类

### 文本搜索与处理
- `rg`：ripgrep，大代码库快速搜索首选
- `fd`：简单目录与文件查找首选
- `jaq` / `jq`：JSON 处理（两者皆可用）
- `yq`：YAML / JSON 通用转换与查询
- `sd`：轻量正则替换
- `gawk`（`awk`）：GNU Awk
- GNU 套件：`coreutils`、`grep`（PCRE2）、`sed`、`find`、`xargs`、`diff`

### 归档与解压
- `tar`、`xz`、`zip`、`unzip`（支持密码与 Zip64）、`zstd`

### 语言与运行环境
- **Python 栈**：
  - `python3` / `pip`（Python 3.12+，系统环境预置 `py3-pillow`、`py3-numpy`）
  - **`uv` / `uvx`**：最新版静态二进制（推荐，速度提升数倍至数十倍）
- **Node.js 栈**：
  - `node` / `npm` / `npx`
  - `qjs`（QuickJS，轻量快速无依赖执行）
- **编译工具链**：
  - `zig`（0.17.0），提供 `cc` / `c++` 交叉与本机编译
  - `make`、`pkgconf`、`binutils`、`linux-headers`、`qemu-aarch64`

### 版本控制与协作
- `git`（2.56+）
- `git-lfs`（大文件存储已初始化）
- `gh`（GitHub CLI）

### 网络与诊断
- `curl`、`openssl`、`drill`、`dig`、`socat`、`sqlite3`
- `openssh-client`（`ssh`、`scp`、`sftp`、`ssh-keygen` 等）

### MCP Gateway
- **`mcp-gateway`**：沙箱内部 MCP 聚合网关
  - `mcp-gateway catalog`：查看支持的预装 MCP 服务（`duckduckgo`、`fetch`、`time`、`arxiv`、`filesystem`、`memory`、`sequentialthinking`）
  - 支持 `mcp-gateway --config '<json>'`（E2B 规范）自动拉起后台服务并写入 `/etc/mcp-gateway/.token`

### 终端与进程控制
- `tmux`、`tini`、`pstree`、`faketty`、`chronic`、`sponge`、`tree`、`bash`

---

## 3. 高频使用模式与技巧

### Python 包管理与运行
```sh
# 推荐优先使用 uv（比传统 pip 快 10-100 倍）：
uv pip install --system requests
uvx duckduckgo-mcp-server --help

# 亦可直接使用常规 pip：
pip install requests
```

### 权限与目录
- 默认工作目录：`/workspace`（可写）
- 普通用户：`user`（uid 1000），已配置免密 `sudo`
- 环境变量：`TZ=Asia/Shanghai`（时间默认东八区）
