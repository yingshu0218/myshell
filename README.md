# MyShell

MyShell 是一个个人自用的跨平台终端系统。它不使用 Electron、Tauri 或网页套壳
统一三个平台，而是在同一仓库中分别开发：

- `web/`：部署在 VPS Docker 中的网页终端
- `macos/`：Swift 编写的 macOS 原生客户端
- `windows/`：Windows 原生客户端

三个客户端拥有各自的终端、SSH 和界面实现，通过独立的
[Sync Hub](https://github.com/yingshu0218/sync-hub) 服务同步加密连接数据。
GitHub/Gitea 只作为 Sync Hub 的可选加密备份目标，不参与日常实时同步。

## 当前状态

| 模块 | 状态 | 当前重点 |
| --- | --- | --- |
| Sync Hub | `v0.1.0` 接入基线已完成 | 固定 API 与安全契约 |
| MyShell Web | 视觉与功能规范已完成，代码尚未开始 | 当前优先开发 |
| macOS | 需求已确定，代码尚未开始 | Web 验收后开发 |
| Windows | 需求已确定，技术基线待最终确认 | macOS 稳定后开发 |
| Shared | schema、加密信封和测试向量待建立 | Web 编码前完成 |

Sync Hub 接入固定基线：

- 逻辑版本：`v0.1.0`
- 提交：`7b5038c15fb87158de4bbd43d7fb510c7a52521e`
- API 前缀：`/v1`
- 正式环境必须使用可信 HTTPS

## 仓库结构

```text
myshell/
├── AGENTS.md                         # 全仓库 Agent 强制规则
├── README.md                         # 项目入口和接手规范
├── docs/
│   ├── PROJECT_OVERVIEW.md           # 产品、架构、安全和开发顺序
│   ├── SYNC_HUB_DEVELOPMENT_HANDOFF.md
│   └── SYNC_HUB_DECISIONS.md         # 编码前创建的决策记录
├── shared/
│   ├── README.md                     # 跨端共享边界
│   ├── schemas/                      # 版本化 JSON schema（未来）
│   ├── crypto/                       # 加密信封规范（未来）
│   └── test-vectors/                 # 跨语言测试向量（未来）
├── web/
│   ├── README.md
│   ├── docs/
│   ├── cmd/                          # Go 服务入口（未来）
│   ├── internal/                     # Web 后端模块（未来）
│   └── frontend/                     # 原生 HTML/CSS/JS（未来）
├── macos/
│   ├── README.md
│   ├── MyShell.xcodeproj/            # 未来
│   ├── Sources/                      # 未来
│   └── Tests/                        # 未来
└── windows/
    ├── README.md
    ├── MyShell.sln                   # 未来
    ├── src/                          # 未来
    └── tests/                        # 未来
```

三个客户端目录必须保持独立：

- 不允许把 Web 构建产物复制进 macOS 或 Windows 源码作为套壳 UI。
- 不允许跨目录直接引用另一客户端的内部实现。
- 可共享的内容只能进入 `shared/`，且必须是平台无关的规范、schema、测试向量
  或固定测试样例。
- 各端必须能够独立构建、测试、发布和回滚。

## 产品能力

### 三端共同能力

- 连接列表、分组、标签、备注和搜索
- SSH 主机、端口、用户名和密码管理
- 多标签终端
- Sync Hub 加密同步
- 离线待上传队列、幂等重试、冲突和删除处理
- Sync Hub 与 SSH 目标手动/定时状态检查
- 多套主题和非敏感终端设置同步
- 明确的连接、同步和错误状态

### Web

- 单用户账号密码登录，不开放注册
- Docker 容器 Shell
- 由 Go 后端创建 PTY 和系统 SSH 会话
- 原生 HTML、CSS、JavaScript 界面
- 五套主题、代码预览与语法高亮
- Docker Secret 保存恢复密钥和 Sync Hub Token
- VPS 本地交互式密码重置

### macOS

- Swift + SwiftUI/AppKit
- 本机 Zsh、系统 OpenSSH 和 `~/.ssh/config`
- 多窗口、多标签和 macOS Keychain
- Apple Silicon 与 Intel 支持范围在建项时确认

### Windows

- 真正的 Windows 原生 UI，初步建议 C# + WinUI 3
- PowerShell、CMD、WSL 和系统 OpenSSH
- Windows Credential Manager
- 最低 Windows 版本和最终 UI 技术在建项时确认

## 同步与安全边界

日常同步只通过 Sync Hub。MyShell 客户端负责加密，Sync Hub 只保存不透明密文、
版本、时间、tombstone、游标和允许的同步元数据。

第一版允许同步：

- 主机、端口、显示名称
- SSH 用户名
- 经过 MyShell 客户端加密并认证的 SSH 密码
- 分组、标签、备注
- 非敏感终端配置和显示设置

禁止同步：

- 任何明文密码或连接凭据
- SSH 私钥和私钥口令
- 终端输入、输出、滚屏和命令历史
- Sync Hub Token
- 保险库主密钥和恢复密钥
- Cookie、Web 登录密码和运行中会话
- 日志、崩溃报告和诊断原文

平台密钥位置：

- Web：只读 Docker Secret
- macOS：Keychain
- Windows：Credential Manager 或经批准的系统安全存储

三个端必须使用同一套版本化加密信封和跨语言测试向量。正式编码前必须建立
`docs/SYNC_HUB_DECISIONS.md`，确认 schema、稳定 ID、nonce、恢复密钥、删除和
冲突策略。

## 开发顺序

1. 完成公共 schema、加密信封、测试向量和决策文档。
2. 开发并验收 `web/`。
3. 开发并验收 `macos/`。
4. 开发并验收 `windows/`。
5. 完成三端互操作、恢复、冲突和兼容测试。

每个端都要独立通过构建、自动化测试、安全检查、长时间会话和资源测量，不能
因为其他端可用而跳过本端验收。

## Agent 接手与调用规范

任何 Agent 在修改仓库前，必须从仓库根目录开始，并按顺序完整阅读：

1. `AGENTS.md`
2. 本文件 `README.md`
3. `docs/PROJECT_OVERVIEW.md`
4. `docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md`
5. `shared/README.md`
6. 当前任务对应端的 README：
   - Web：`web/README.md`
   - macOS：`macos/README.md`
   - Windows：`windows/README.md`
7. 当前端已有的 `docs/`、入口、存储、网络、安全和测试代码

然后 Agent 必须先输出：

1. 当前仓库和目标端的实际状态。
2. 本次任务允许修改的目录和明确不修改的目录。
3. 需求与现有文档、Sync Hub 契约之间的冲突。
4. 是否需要第三方依赖、数据迁移或不可逆操作。
5. 分阶段、可测试、可回滚的执行计划。

只有在范围和关键决策明确后才能开始实现。

### Agent 强制规则

- 一次任务默认只修改一个客户端目录和必要的 `shared/` 或 `docs/`。
- 跨端行为变化必须同步更新公共规范和测试向量。
- 未经所有者明确批准，不得引入或下载第三方依赖。
- 不得使用任何 Superpowers 技能。
- 不得猜测 Sync Hub API；按固定提交的实现和文档确认。
- 不得关闭 TLS 校验或把测试自签名证书永久信任。
- 不得把秘密写入源码、普通配置、日志、命令参数、镜像或 Git。
- 不得在未经批准的情况下固化不可逆数据格式或执行数据迁移。
- 不得声称完成，除非当前端的测试、构建和适用的运行验证真实通过。

推荐给新 Codex 会话的第一条消息：

```text
请从仓库根目录开始，完整阅读 AGENTS.md、README.md、
docs/PROJECT_OVERVIEW.md、docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md、
shared/README.md，以及当前任务所属端的 README 和 docs。

先不要修改代码。请先说明当前仓库状态、任务范围、文档或契约冲突、
需要确认的依赖与安全决策，并给出分阶段可验证计划。
```

## 依赖管理

根仓库不建立跨端统一依赖清单。每个客户端在自己的目录管理依赖：

- Web：`web/go.mod` 及前端静态资源清单
- macOS：Xcode/Swift Package 配置
- Windows：解决方案与 NuGet 配置

依赖申请必须说明用途、无依赖替代方案、许可证、包体积、运行时开销和维护风险。
批准仅针对明确名称和用途，不自动批准同生态的其他包。

## 文档索引

- [项目整体说明](docs/PROJECT_OVERVIEW.md)
- [Sync Hub 开发交接](docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md)
- [Web 独立说明](web/README.md)
- [Web 页面设计](web/docs/UI_DESIGN.md)
- [Web 主题规范](web/docs/THEMES.md)
- [Web 代码高亮](web/docs/CODE_HIGHLIGHTING.md)

## 当前没有统一构建命令

仓库目前仍处于设计和建项阶段，因此根目录暂不提供虚假的 `make build` 或
`make test`。各端建立工程后，必须在自己的 README 中记录真实的构建、测试、
运行和发布命令。未来可以增加只负责调度、不隐藏失败的根级验证脚本。
