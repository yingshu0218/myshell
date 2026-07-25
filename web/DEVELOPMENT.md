# MyShell Web 开发规范

## 1. 交付目标

MyShell Web 是当前优先开发的客户端。它作为独立 Docker 容器运行在个人 VPS，
通过浏览器提供容器 Shell 和远程 SSH 终端，并作为 Sync Hub 的客户端同步
MyShell 加密连接数据。

MyShell Web 与 Sync Hub 必须保持独立：

- 独立进程、镜像、数据目录和 Secret
- 只通过 Sync Hub `/v1` HTTPS API 通信
- 不读取或修改 Sync Hub 数据文件
- 不向 Sync Hub 添加终端、PTY 或 MyShell 业务逻辑

## 2. 固定技术栈

| 领域 | 技术 |
| --- | --- |
| 后端 | Go 1.26 系列，单进程 |
| HTTP | Go `net/http` |
| 前端 | 原生 HTML、CSS、JavaScript |
| 静态资源 | Go `embed` 打包进二进制 |
| 终端进程 | Linux PTY + 系统 OpenSSH |
| 终端传输 | 经认证、校验 Origin 的 WebSocket |
| 本地存储 | 版本化文件、临时文件 + 原子替换 |
| 加密 | `shared/` 规定的 AES-256-GCM 信封 |
| 密钥 | 只读 Docker Secret |
| 部署 | 单容器，非 root，只读根文件系统 |
| HTTPS | 可信反向代理；容器默认只监听内部网络 |

不使用 React、Vue、Electron、Tauri、常驻 Node 服务或独立数据库进程。

### 候选第三方依赖

以下候选尚不代表批准。实现前必须获得所有者针对具体名称和用途的明确同意：

| 候选 | 用途 | 不使用的代价 |
| --- | --- | --- |
| xterm.js | ANSI/VT 终端渲染、输入、选择、可访问性 | 自研完整终端模拟器风险极高 |
| `github.com/creack/pty` | Linux PTY 生命周期和尺寸 | 自行维护平台 syscall |
| `github.com/coder/websocket` | 双向终端通道 | 自行实现 WebSocket 协议 |
| `golang.org/x/crypto` | Argon2id 密码哈希 | 标准库缺少合适的密码 KDF |
| PrismJS 精简 grammar | 只读代码高亮 | 自研多语言 tokenizer |

批准前不得修改 `go.mod`、下载包、复制源码或先写依赖实现。

## 3. 计划目录

```text
web/
├── README.md
├── DEVELOPMENT.md
├── go.mod
├── Dockerfile
├── cmd/myshell-web/
│   └── main.go
├── internal/
│   ├── auth/
│   ├── config/
│   ├── httpapi/
│   ├── session/
│   ├── terminal/
│   ├── ssh/
│   ├── vault/
│   ├── syncclient/
│   ├── status/
│   └── storage/
├── frontend/
│   ├── index.html
│   ├── styles/
│   ├── scripts/
│   └── assets/
├── docs/
└── test/
```

包边界必须窄。HTTP handler 不直接操作文件、PTY、凭据或 Sync Hub；所有外部
能力通过明确接口注入并可替换测试。

## 4. 功能节点

### W0：公共契约门禁

编码前完成：

- `shared/schemas/` 中连接、分组、终端配置 schema
- `shared/crypto/` 中加密信封和 AAD 规则
- `shared/test-vectors/` 中跨语言固定向量
- `docs/SYNC_HUB_DECISIONS.md`

验收：Go 测试可以读取测试向量，并得到规定的密文、解密结果和失败行为。

### W1：服务与 Docker 骨架

- 配置校验
- `/health`
- 脱敏结构化日志
- 信号处理和优雅退出
- 最小多阶段 Docker 构建

验收：测试、`go vet`、生产构建、容器启动、健康检查和停止均通过。

### W2：单用户认证

- 首次初始化唯一管理员
- 账号密码登录、退出、限速和临时锁定
- HttpOnly、Secure、SameSite Cookie
- CSRF 防护与 WebSocket Origin 校验
- 空闲及绝对会话过期
- `reset-password`、`show-account`

验收：认证绕过、固定会话、CSRF、暴力登录、重启和密码重置测试通过；重置后
所有会话失效。

### W3：容器 Shell 纵向切片

- 创建、输入、输出、调整尺寸和关闭 PTY
- 有界输出缓冲和滚屏
- 浏览器断开与超时回收
- 标签页会话状态

验收：Zsh/Bash、Unicode、颜色、Vim、Top 和尺寸变化可用；浏览器断开、容器
停止、异常退出均无孤儿进程和文件描述符泄漏。

### W4：终端工作台

- 连接侧边栏
- 多标签页
- 终端画布
- 状态栏
- 键盘导航
- 响应式抽屉

必须忠实实现 `web/docs/UI_DESIGN.md` 的已批准视觉稿。主题和代码高亮按
`THEMES.md`、`CODE_HIGHLIGHTING.md` 实现。

验收：桌面、平板和窄屏截图通过视觉对比；主题切换不重建终端会话。

### W5：SSH

- 系统 OpenSSH
- 主机、端口、用户名、密码
- known_hosts 和首次主机指纹确认
- 网络断线、退出码和重连提示
- 密码通过匿名管道或同等受控 IPC 提供

密码不得出现在命令参数、环境变量、进程列表、日志或临时文件中。

验收：一次性测试 SSH 容器覆盖成功、错误密码、未知/变化指纹、超时、断网和
正常退出。

### W6：保险库与连接管理

- 连接、分组、标签、备注和终端配置
- 本地密文快照与原子写入
- Docker Secret 导入保险库密钥
- 新建、编辑、删除、搜索和复制连接
- 密码只按需解密并尽快释放引用

验收：磁盘和日志秘密扫描无明文；错误密钥、损坏密文和未知 schema 安全失败。

### W7：Sync Hub 接入

- 应用/设备 Token 读取
- 游标、服务端版本、待上传队列和幂等键持久化
- 拉取、事务应用、上传和 tombstone
- 离线、有界退避、取消和错误分类
- `409` 冲突 UI

验收：执行交接手册完整双设备矩阵；不得首次用唯一生产数据测试。

### W8：状态检查

- Sync Hub 健康、延迟和最近同步
- SSH 主机端口可达性
- 单个、全部、5/15/30/60 分钟计划
- 超时、取消、并发上限和状态变化提示

验收：检查不登录 SSH；未配置计划时无后台轮询；一个慢目标不阻塞其他目标。

### W9：发布

- 非 root、只读根文件系统
- 仅数据和 Secret 挂载点可写/读
- HTTPS 反向代理说明
- 备份、升级、回滚和恢复说明
- 24 小时稳定性与资源基线

## 5. 设计指标

以下是第一版目标，首个可运行原型实测后可以记录理由并调整，但不能删除上限：

| 指标 | 目标 |
| --- | --- |
| 冷启动到健康 | `< 1 s` |
| 空闲 CPU | 平均 `< 0.5%` |
| 基础容器 RSS | `< 50 MiB` |
| 每个空闲终端增量 | `< 10 MiB` |
| 生产镜像 | `< 50 MiB` |
| 默认最大终端数 | `8` |
| 默认滚屏 | `10,000` 行 |
| 状态检查并发 | `4` |
| 单代码预览 | `≤ 1 MiB`、`≤ 20,000` 行 |

性能测试必须记录 VPS CPU、内存、内核、Docker 版本、镜像提交和测试命令。

## 6. 完成定义

只有同时满足以下条件，Web 端才能声明完成：

- W0–W9 全部验收通过
- 登录、PTY、SSH、同步和恢复无阻断缺陷
- 无明文凭据或孤儿进程
- Sync Hub 固定基线端到端测试通过
- 五主题、代码高亮、响应式和键盘可访问性通过
- 生产 Docker 镜像、部署和回滚文档可复现
- 资源实测达到预算或有所有者批准的偏差记录

## 7. Codex 接手指令

Agent 阅读根说明、共享规范、本文件和 Web docs 后，应先报告 W0 是否完成以及
当前最近未完成节点。每次只执行一个节点；完成后给出文件清单、测试输出、安全
影响和下一节点，不得未经确认跨越依赖或数据格式门禁。
