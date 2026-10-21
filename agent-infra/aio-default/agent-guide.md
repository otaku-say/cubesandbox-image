# aio-default 沙箱工具箱环境指南（AGENT-GUIDE）

> 本沙箱为 **CubeSandbox 深度对齐环境**，集成：
> 1. **ish-toolbox 静态工具箱**（GNU 套件与现代 CLI 增强）
> 2. **apk 系统层**（解释器、编译工具链、网络与系统工具）
> 3. **最新独立 uv / uvx 工具链**（极速 Python 包管理与工具运行器）
> 4. **官方 mcp-gateway 服务**（E2B 兼容的 MCP 服务协议，支持内置/GitHub/自定义工具）
> 5. **AI-Native 搜索引擎 XERJ**（Elasticsearch 8.x 协议兼容、透明惰性按需激活、代码段/定义检索与 17 个 MCP 工具）

---

## 1. 核心服务与端口

| 服务 | 端口 | 协议/说明 |
|---|---|---|
| **envd** | `49983` | CubeSandbox 控制与执行协议，健康探针端点 `/health` |
| **aiod** | `8080` | 数据面 API 服务（AIO v2 接口） |
| **mcp-gateway** | `50005` | E2B 兼容的 MCP 流式 HTTP 网关端点 `/mcp`，`/health` 探针 |
| **xerj** | `9200` | Elasticsearch 8.x 兼容的 AI-native 搜索引擎（透明惰性按需激活，开机 0 内存，首次调用自动秒级就绪） |

---

## 2. 真实可用工具分类

### 智能搜索与代码检索（首选）
- **`xerj`**：AI-Native 搜索引擎与代码段精准召回（**强力推荐：避免盲目 grep 撑爆上下文**）
  - `xerj autoindex <目录>`：对代码库、文档、日志一键零配置建索引（1~2秒完成）
  - `xerj search "<搜索词或描述>"`：定义优先加权、仅返回行号与关键代码块（相比 grep 节省 2.7x Token）
  - `xerj def "<符号名>"`：跨文件直达函数/类/常量定义处
  - `xerj ask "<问题>"`：从语料库中检索开源实现范式
  - `xerj-service {start|stop|status}`：服务生命周期管理，任务结束可 `stop` 彻底释放内存
- `rg`：ripgrep，单文件或小目录极简正则匹配
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

### MCP Gateway & MCP 工具
- **`mcp-gateway`**：沙箱内部 MCP 聚合网关（端口 50005）
- **XERJ MCP**：`/workspace/.mcp.json` 已预置 xerj stdio 服务，提供 `xerj_search`、`xerj_def`、`xerj_code_search` 等 17 个原生工具

### 终端与进程控制
- `tmux`、`tini`、`pstree`、`faketty`、`chronic`、`sponge`、`tree`、`bash`

---

## 3. 高频使用模式与技巧

### 代码排查与大文本检索（军规推荐）
```sh
# 1. 遇到复杂项目或多文件排查，先建立索引（秒级完成）：
xerj autoindex /workspace/<项目目录>

# 2. 搜索关键逻辑或报错（仅返回关键上下文代码块，绝不撑爆屏幕）：
xerj search "handleConnection"

# 3. 直达函数定义：
xerj def "handleConnection"

# 4. 任务结束若需释放内存：
xerj-service stop
```

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
