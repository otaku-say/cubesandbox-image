# CubeSandbox AIO 双通道镜像（agent-infra/sandbox）

在 agent-infra 官方 **AIO Sandbox** 上注入 E2B envd 启动契约的薄壳镜像，
使 CubeSandbox 沙箱同时具备 **envd** 与 **AIO API** 两条控制通道。

| 项 | 值 |
|---|---|
| 上游 | `ghcr.io/agent-infra/sandbox`（Browser/VNC/Terminal/File/VSCode/Jupyter/MCP Hub/Skills） |
| 产出 | `ghcr.io/otaku-say/cubesandbox-image/agent-infra/sandbox:latest` |
| 注入 | envd 启动契约（tini + cube-entrypoint，取自官方 cubesandbox-base） |
| 增补 | yq / fd / sqlite3 / tcpdump / strace / tesseract(+简中) / dnsutils / playwright 库（均属"必须清单"缺口，同功能择优） |

## 构建

- **自动**：本目录任一文件 push，或 Actions 页 dispatch `Build Images`
- **本地**：`bash build.sh`（需先 `docker login ghcr.io`）

## 注册为 CubeSandbox 模板（在控制节点执行）

```bash
cubemastercli tpl create-from-image \
  --image ghcr.io/otaku-say/cubesandbox-image/agent-infra/sandbox:latest \
  --alias aio --writable-layer-size 20G \
  --expose-port 49983 --expose-port 8080 --expose-port 6080 \
  --expose-port 8091 --expose-port 8888 --expose-port 8200 \
  --allow-internet-access \
  --registry-username <user> --registry-password <token>
# 私有包需带凭证；包改为 Public 后可省略（GitHub 包设置 → Change visibility）
```

## 使用（双通道）

- **管理 / 轻执行**：CubeSandbox API + envd（csb / Connect-RPC，端口 49983）
- **浏览器 / Jupyter / MCP**：AIO 官方 SDK ——
  `Sandbox(base_url="http://<host>/sandbox/<id>/8080")`（Python）
  或 Go SDK 客户端（`LXC_BASE=http://<host>/sandbox/<id>/8080` 覆盖）
- **网关入口**（经 CubeSandbox 路径路由）：
  `/sandbox/<id>/8080/` 仪表盘 · `/vnc/` · `/terminal/` · `/code-server/` · `/jupyter/`
