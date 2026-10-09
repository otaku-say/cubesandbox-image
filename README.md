# cubesandbox-image

CubeSandbox 镜像构建仓库。

**规则**：每个上游项目一个目录 `<org>/<project>/`，目录内放构建该镜像所需的全部文件；
构建产出统一推送到：

```
ghcr.io/<owner>/cubesandbox-image/<org>/<project>:latest
```

> **公开仓库规范**：请勿在本仓库任何文件中写入个人/私有信息（服务器 IP、域名、令牌、密钥等）。
> 所有对外地址请使用占位符（如 `<host>`）。

## 目录规约

```
<org>/<project>/
├── Dockerfile      # 必需。FROM 上游镜像 + 定制层（如 envd 注入、必要增补）
├── upstream.txt    # 可选。上游镜像引用列表（供 Track Upstream Images 自动跟踪 digest）
├── build.sh        # 可选。本机构建推送脚本
└── README.md       # 该镜像的构建 / 注册 / 使用说明
```

- 目录名必须为**全小写**（GHCR 镜像名要求）
- **新增镜像**：新建目录 → 放入 Dockerfile → push 即自动触发 CI 构建（也可在 Actions 页手动 dispatch）
- **上游更新**：`Track Upstream Images` 工作流每日检测上游 digest，
  变更时自动触发重建并开 issue 提醒重新注册模板
- 每个目录的产出物只维护 `:latest` 标签（按需可另打版本标签）

## 当前镜像

| 目录 | 产出 | 说明 |
|---|---|---|
| `agent-infra/aio-default` | `ghcr.io/<owner>/cubesandbox-image/agent-infra/aio-default:latest` | iSH 同源轻量基座（alpine 3.23.6 + busybox 1.38 + ish-toolbox 58 件 + envd/aiod + git/zig 开发链；默认规格 30G / cpu=3000 / memory=3000，别名 `aio-default`） |
