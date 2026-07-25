# MyShell Web

`web/` 是 MyShell 网页终端的独立开发目录。它最终构建为单独的
`myshell-web` Docker 镜像，通过公开的 Sync Hub API 同步加密连接数据，
不直接读取 Sync Hub 的数据文件。

## 当前状态

当前只完成视觉规划和实现规范，尚未建立运行时代码或下载第三方依赖。视觉稿
必须先由项目所有者确认，确认后才把它当作实现基线。

必读资料：

- [项目整体说明](../docs/PROJECT_OVERVIEW.md)
- [Sync Hub 交接手册](../docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md)
- [Web 界面设计](docs/UI_DESIGN.md)
- [主题规范](docs/THEMES.md)
- [代码高亮规范](docs/CODE_HIGHLIGHTING.md)

视觉概念：

- [主终端工作台](docs/concepts/terminal-workspace.png)
- [外观与代码高亮](docs/concepts/appearance-code-highlighting.png)

## 计划目录

获得设计和依赖批准后，按以下结构实现：

```text
web/
├── README.md
├── cmd/myshell-web/          # Go 服务入口与维护命令
├── internal/
│   ├── auth/                 # 单用户登录、会话、密码重置
│   ├── terminal/             # PTY、Shell、SSH、会话回收
│   ├── vault/                # 加密连接保险库
│   ├── syncclient/           # Sync Hub 客户端
│   ├── status/               # Relay 与 SSH 目标检查
│   └── httpapi/              # HTTP 与双向终端通道
├── frontend/
│   ├── index.html
│   ├── styles/
│   ├── scripts/
│   └── assets/
├── docs/
├── test/
├── Dockerfile
└── go.mod
```

前端采用原生 HTML、CSS 和 JavaScript，不引入 React、Vue 或常驻 Node
运行时。Go 二进制最终嵌入前端静态资源。

## 功能范围

- 单用户账号密码登录与本地密码重置
- 连接列表、分组、搜索和最近连接
- 容器 Shell 与系统 SSH
- 多标签终端和可调整代码预览分屏
- 五套内置主题
- 文件/片段代码高亮
- Sync Hub 加密同步与状态展示
- SSH 目标手动/定时在线检查
- Docker 部署、安全加固和资源限制

第一版不实现 SSH 私钥同步、SFTP、插件市场、AI、多用户或终端历史同步。

## 依赖审批门禁

以下依赖只是候选，尚未获批或下载：

| 候选 | 用途 |
| --- | --- |
| xterm.js | 终端渲染、ANSI/VT、选择和可访问性 |
| `github.com/creack/pty` | Linux PTY 生命周期 |
| `github.com/coder/websocket` | 浏览器双向终端通道 |
| `golang.org/x/crypto` | Argon2id 密码哈希 |
| PrismJS（按语言裁剪） | 轻量代码高亮 |

未经仓库所有者明确批准，不得修改依赖清单、下载包或先编写依赖这些包的代码。

## 实现顺序

1. 确认视觉稿、主题和高亮范围。
2. 固定共享 schema、加密信封和测试向量。
3. 建立零依赖 Go 服务与前端 App Shell。
4. 实现登录与本地密码重置。
5. 实现 PTY、容器 Shell 和终端工作台。
6. 实现 SSH 与主机指纹确认。
7. 实现连接保险库和 Sync Hub 接入。
8. 实现状态检查、设置、主题和代码预览。
9. 完成安全、响应式、可访问性和性能验收。

每阶段必须通过相应测试和生产 Docker 构建，且不得把凭据、终端内容、密钥或
Token 写入日志、镜像、参数或普通环境变量。
