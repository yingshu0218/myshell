# 测试与验收

## 自动化检查

```bash
cd web && npm ci && npm run build
go test -race ./...
go vet ./...
go build ./cmd/server
docker build --target test -t myshell:test .
docker build -t myshell:dev .
```

测试覆盖账号初始化、登录限速、会话过期、密码重置、原子文件写入、保险库
加密和冲突、篡改检测、PTY 回收、终端数量、状态检查、Git 备份和确认恢复。
Docker 的 `test` 阶段还会启动一次临时 OpenSSH 服务，使用测试密码 `111111`
验证主机指纹、一次性 AskPass、真实 SSH 往返和断开清理；测试服务不会进入
最终镜像。

## 测试登录

`compose.test.yaml` 会明确启用测试初始化：

```text
用户名：111111
密码：111111
```

它只可用于本机验证。生产 Compose 不包含测试开关。

## 手动流程

1. 登录并确认错误密码及退出行为。
2. 新增 SSH 连接，核对并确认首次主机指纹。
3. 测试 Unicode、粘贴、颜色、`vim`/`top` 和终端缩放。
4. 关闭标签、浏览器和容器，确认没有残留 Shell/SSH 进程。
5. 制造保险库版本冲突，确认返回 `409`。
6. 手动及定时检查 SSH 端口。
7. 创建真实 GitHub/Gitea 加密备份，检查仓库无明文。
8. 输入 `RESTORE` 恢复，并确认形成新的本地版本。
9. 执行交互式密码重置，确认旧会话全部失效。

## 性能记录

生产镜像需要记录：

- 二进制和镜像大小
- 冷启动至 `/health` 可用时间
- 空闲 CPU 和基础 RSS
- 每增加一个终端的 RSS
- 大量终端输出吞吐
- 长时间运行后的进程、文件描述符及内存变化

目标：启动低于 1 秒、空闲 CPU 低于 0.5%、基础 RSS 低于 50 MiB、每终端
增加低于 10 MiB。真实结果记录在 `docs/PERFORMANCE.md`。
