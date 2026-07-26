# Web 阶段完成审计

本文件是 `docs/DEVELOPMENT.md` Web 完成门禁的证据索引。只有“实现、自动化、
容器、浏览器、真实外部服务”证据全部通过后，才能标记 Web 阶段完成。

| 要求 | 实现证据 | 验证证据 | 状态 |
| --- | --- | --- | --- |
| 初始化、登录、退出、限速、过期 | `internal/auth/`、`internal/httpapp/` | `auth_test.go`、`app_test.go`、容器 E2E | 通过 |
| 交互改密并注销会话 | `cmd/server/main.go` | 单元测试及真实 TTY 容器命令 | 通过 |
| 本地 PTY、WebSocket、缩放、回收 | `internal/terminal/` | PTY 与 WebSocket 集成测试 | 通过 |
| 系统 SSH、指纹、密码、断开 | `internal/terminal/` | Docker 内临时 sshd 真实测试 | 通过 |
| 连接资料磁盘密文 | `internal/vault/` | 明文扫描、篡改及重载测试 | 通过 |
| 版本冲突和恢复历史 | `internal/vault/` | 冲突及历史上限测试 | 通过 |
| 手动/定时状态检查 | `internal/health/`、后台调度器 | 并发及定时测试 | 通过 |
| GitHub/Gitea 加密备份 | `internal/backup/` | 两种 API 模拟测试；真实 GitHub 全流程通过 | 通过 |
| 预览及确认恢复 | 备份预览/恢复 API 与设置界面 | HTTP 端到端测试 | 通过 |
| 五主题、代码高亮、响应式界面 | `web/src/` | Playwright 1.62.0 桌面/390px 移动交互及截图 | 通过 |
| HTTPS、Secret、非 root、只读容器 | 中间件、`Dockerfile`、Compose | 本机 TLS 1.3 反代、安全 Cookie、HTTP 拒绝及加固容器 | 通过 |
| 低资源指标 | 有界会话/缓冲/请求/检查 | `docs/PERFORMANCE.md` 实测 | 通过 |
| 长时间稳定性 | 清理、超时和调度实现 | 25 次真实浏览器断开压力测试通过；长期运行待测 | 部分待测 |

## 最终必须执行

```bash
cd web && npm ci && npm run build
go test -race ./...
go vet ./...
go build ./cmd/server
docker build --target test -t myshell:test .
docker build -t myshell:dev .
```

随后使用测试账号/密码 `111111` 完成浏览器流程，使用一个真实私有 GitHub 或
Gitea 测试仓库完成备份恢复，并将性能结果写入 `docs/PERFORMANCE.md`。

## 浏览器验收记录

2026-07-26 使用 Playwright 1.62.0 与 Chromium 在
`1536×1024`、`390×844` 视口完成 HTTPS/WSS 流程：

- 账号 `111111` 登录，新增连接并确认保险库版本写入。
- 切换 Nord 主题，打开设置并确认五主题及 GitHub/Gitea 选项。
- Prism 代码预览生成 32 个高亮 token。
- 创建真实容器 PTY，执行 `echo browser-terminal-ok` 并收到回显。
- 手动状态检查、移动侧栏和无横向溢出通过。
- 浏览器控制台错误、警告和未捕获页面错误均为 0。

截图位于验收主机的 `/tmp/myshell-desktop.png`、
`/tmp/myshell-settings.png` 和 `/tmp/myshell-mobile.png`。本次验收修复了连接
表单提交、登录加载竞态、`hidden` 样式覆盖及空连接列表序列化问题。

随后执行 25 次浏览器终端创建并直接关闭页面的断开压力测试，每轮均回到 0 个
活动会话，最终容器只剩 `myshell-server`。该测试发现并修复了 WebSocket
断开后 PTY 读取阻塞造成的孤儿 Shell，并新增自动化回归测试。

## 真实 GitHub 备份验收

2026-07-26 使用 `yingshu0218/myshell` 的
`agent/shared-sync-fixtures` 分支完成真实 API 验收。服务读取
`shared/fixtures/vault-sync-v1.json`，创建并列出 AES-256-GCM 备份，预览得到
3 条活动连接；未输入 `RESTORE` 的恢复请求被拒绝。修改本地名称和密码后确认
恢复，版本递增到 4，4 条记录逐字段一致。两个远程备份均通过明文扫描。
