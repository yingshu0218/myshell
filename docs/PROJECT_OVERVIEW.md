# MyShell 项目整体说明

## 1. 文档目的与优先级

本文档是 MyShell 的产品范围、总体架构和开发顺序说明。未来 Codex 开始工作前，
必须同时完整阅读：

1. 本文件 `docs/PROJECT_OVERVIEW.md`
2. `docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md`
3. Sync Hub 固定基线的 `SYNC_INTEGRATION.md`、`API.md`、`ARCHITECTURE.md`
   和 `DEPLOYMENT.md`

本文档决定 **MyShell 要做什么**；交接手册决定 **MyShell 如何安全接入
Sync Hub v0.1.0**。若两者出现冲突，不得自行猜测或立即编码，应先把冲突写入
`docs/SYNC_HUB_DECISIONS.md` 并要求项目所有者确认。

本文已经确认一个重要产品例外：MyShell 必须跨设备同步 SSH 连接用户名和密码。
因此，交接手册中“SSH 密码和连接凭据不得上传 Sync Hub”的表述，在 MyShell
项目中应解释为：**不得上传明文凭据；允许上传由 MyShell 客户端加密并认证后的
凭据密文**。Sync Hub、日志、Git 备份和未授权设备始终不能得到明文或解密密钥。

## 2. 产品愿景

MyShell 是个人自用的跨平台终端系统，不使用 Electron、Tauri 或网页套壳来冒充
原生客户端。最终提供三个独立入口：

- macOS 原生客户端
- Windows 原生客户端
- 部署在个人 VPS Docker 中的网页终端

三个入口拥有一致的连接资料和核心使用体验，但分别采用适合平台的本地技术。
它们通过独立的 Sync Hub 服务完成日常数据同步。Sync Hub 是可供未来其他个人
应用复用的通用同步与管理后台，不能加入 MyShell 专属业务字段或终端逻辑。

项目的核心目标：

- 快速打开本机或远程终端
- 在不同设备间共享服务器连接、用户名和密码
- 避免在每台设备反复录入 SSH 密码
- 保持较低的空闲 CPU、内存、启动开销和镜像体积
- 网络中断或 Sync Hub 暂时不可用时，已有本地功能仍可使用
- 所有秘密均有清晰的存储、传输、恢复和撤销边界

## 3. 总体架构

```text
macOS 客户端 ───────┐
Windows 客户端 ─────┼── HTTPS ── Sync Hub
MyShell Web 后端 ───┘              │
        │                           ├── 通用密文同步
浏览器终端                          ├── 应用/设备 Token
        │                           ├── 管理与监控
PTY / Shell / SSH                   └── 可选加密 Git 备份
```

Sync Hub 与 MyShell Web 是两个不同产品：

- **Sync Hub**：通用同步、管理、设备、Token、版本、冲突、游标、备份和监控。
- **MyShell Web**：用户登录、浏览器终端、PTY、容器 Shell、SSH 会话和连接界面。

它们可以部署在同一台 VPS，并通过 Docker Compose 统一管理，但应使用独立进程、
独立容器、独立数据目录和明确的网络边界。MyShell Web 只能通过公开的 Sync Hub
API 访问同步数据，不能直接读取 Sync Hub 数据文件。

## 4. Sync Hub 基线与职责

当前接入基线：

- 逻辑版本：`v0.1.0`
- 固定提交：`7b5038c15fb87158de4bbd43d7fb510c7a52521e`
- API 前缀：`/v1`
- 正式访问：可信 HTTPS

Sync Hub 已负责：

- 应用和设备注册、停用
- 应用或设备 Token 的签发与撤销
- 不透明密文记录的版本化存储
- `baseVersion` 乐观并发与 `409 Conflict`
- Tombstone 删除传播
- 不透明游标增量同步
- 持久化幂等写入
- 活动、备份、管理和监控

MyShell 必须负责：

- 业务模型、序列化和 schema 版本
- 客户端加密、完整性校验和密钥恢复
- 稳定 record ID、collection 和删除语义
- Token 的平台安全存储
- 游标、服务端版本、待上传队列和幂等键持久化
- 离线、重试、取消、冲突解决和用户可见状态

## 5. 三个客户端

### 5.1 MyShell Web

当前优先开发。部署为独立 Docker 容器，包括轻量后端与网页前端：

- 后端优先使用 Go 单进程
- 前端优先使用原生 HTML、CSS、JavaScript
- 浏览器与后端使用受保护的双向终端通道
- 后端创建 Linux PTY，支持容器 Shell 和系统 OpenSSH
- 支持连接列表、多标签终端、调整尺寸、复制粘贴和断线提示
- 使用单用户账号密码登录，不开放注册
- 提供交互式本地密码重置命令
- 通过 Sync Hub API 同步连接资料
- 恢复密钥通过 Docker Secret 挂载

网页中解密后的 SSH 密码只允许在 MyShell Web 进程内存中短暂存在，用于创建
当前 SSH 会话；不得写入参数、环境变量、日志、终端历史、临时文件或诊断信息。

### 5.2 macOS 客户端

Web 端达到验收条件后开发：

- Swift
- SwiftUI 负责应用结构，AppKit 处理终端视图、键盘、窗口和 PTY 细节
- 本机 `/bin/zsh`
- 系统 OpenSSH 与 `~/.ssh/config`
- 多窗口、多标签页、连接管理和状态检查
- Sync Hub Token 与保险库密钥保存在 macOS Keychain
- 以 Release 构建测量启动、空闲 CPU、内存和终端吞吐

### 5.3 Windows 客户端

macOS 客户端稳定后开发：

- 使用真正的 Windows 原生 UI；初步建议 C# 与 WinUI 3
- 支持 PowerShell、CMD、WSL 和系统 OpenSSH
- 多窗口、多标签页、连接管理和状态检查
- Sync Hub Token 与保险库密钥保存在 Windows Credential Manager
- 不使用 Electron 或浏览器套壳

Windows 技术栈和最低系统版本必须在建立工程前再次确认，不能仅凭本文建议直接
固化。

## 6. 需要同步的数据

第一版允许同步：

- 连接记录的稳定 UUID
- 显示名称
- 主机名或 IP
- SSH 端口
- SSH 用户名
- SSH 密码的客户端加密密文
- 分组、标签、备注
- 连接使用的终端配置引用
- 不含秘密的显示设置
- 记录 schema 版本、修改和删除状态

第一版禁止同步：

- 终端输入、输出、滚屏和命令历史
- SSH 私钥及私钥口令
- Sync Hub Token
- 保险库主密钥和恢复密钥
- MyShell Web 登录密码
- Cookie、会话令牌和临时认证数据
- 本地缓存、实时在线状态和运行中的终端会话
- 日志、崩溃转储和诊断原文

SSH 私钥同步属于未来独立安全设计，不得顺带加入第一版。

建议初始 collection：

| collection | 内容 | recordId | 冲突策略 |
| --- | --- | --- | --- |
| `connections` | 一台服务器的一条连接记录 | 客户端生成 UUID | 字段级安全合并；密码冲突要求用户选择 |
| `groups` | 分组名称和排序 | 客户端生成 UUID | 明确合并或用户选择 |
| `terminal-profiles` | 非秘密终端外观和行为设置 | 客户端生成 UUID | 无法安全合并时用户选择 |

这些名称是项目级初步决定。编码前应在 `SYNC_HUB_DECISIONS.md` 中补充最终
schema、删除语义和兼容规则。

## 7. 加密与恢复模型

三个端必须使用同一种版本化加密信封和测试向量，确保跨语言互操作。

基本原则：

1. 首台设备生成随机保险库主密钥。
2. 每条同步记录独立加密并认证。
3. app ID、collection、record ID 和 schema 版本应绑定为认证数据。
4. 每次加密使用满足算法要求的唯一 nonce。
5. Sync Hub 只收到密文和允许的元数据。
6. 新设备只需导入一次恢复密钥，之后保存到平台安全存储。
7. Sync Hub Token 与保险库密钥相互独立；撤销 Token 不影响本地解密。
8. GitHub/Gitea 备份仍然只包含密文。

预期使用跨平台可实现的 AES-256-GCM，但在正式编码前必须完成安全决策记录、
信封格式、nonce 生成规则、密钥导入格式和跨语言测试向量。任何第三方密码学
依赖必须先获得项目所有者明确批准。

平台密钥位置：

- macOS：Keychain
- Windows：Credential Manager 或经确认的系统安全存储
- MyShell Web：只读 Docker Secret

## 8. 同步行为

日常同步只通过 Sync Hub：

- 客户端启动或登录后拉取
- 本地数据修改后延迟上传
- 用户可手动同步
- 不进行无界高频轮询
- 网络失败进入有界待上传队列，不阻止本地终端
- 超时重试复用相同幂等键
- `401/403` 停止盲目重试并提示重新登记
- `409` 拉取当前版本并执行 collection 对应冲突策略
- 一页变更全部验证、解密并事务落地后才提交新游标

GitHub/Gitea 不是另一条实时同步路径，只是 Sync Hub 的可选加密备份目标。恢复
必须显式确认，不能自动用旧备份覆盖当前数据。

## 9. 在线状态检查

三个客户端都应在终端界面展示：

- Sync Hub 是否在线、请求延迟和最近成功同步时间
- 保存的 SSH 目标是否可达、端口延迟和最近检查时间

支持：

- 手动检查单个目标
- 手动检查全部目标
- 5、15、30、60 分钟定时检查
- 有界并发和每目标超时
- 应用休眠或后台时减少或停止检查
- 状态变化提示

SSH 在线检查默认只检测主机和端口，不执行登录，不把结果作为长期监控数据无限
保存。实时状态属于运行态，不进入连接同步 payload。

## 10. 登录与身份

- Sync Hub 管理后台使用其自己的单用户管理员账号。
- MyShell Web 使用独立的单用户账号密码，不开放注册。
- macOS、Windows 和 MyShell Web 通过各自的 Sync Hub 应用或设备 Token 调用
  同步 API。
- Token 必须可独立撤销，且不得放入普通配置或日志。
- MyShell Web 必须支持从 VPS 本地执行交互式密码重置；重置后注销全部 Web
  会话。

不要求第一版实现多用户、团队权限、邮件找回或双因素认证。

## 11. 低资源要求

所有端都要将资源占用作为验收指标，而不是开发完成后的附加优化：

- 按需创建 PTY、SSH、同步和检查任务
- 终端输出、滚屏、日志、队列、重试和并发必须有上限
- 关闭标签页后立即回收子进程、文件描述符和内存
- 空闲时不持续重绘、不维持无意义后台任务
- 网页端优先单进程和小型静态资源
- 原生客户端不使用 Electron/Tauri
- 每个阶段记录生产构建的启动时间、空闲 CPU、基础内存、每会话内存和吞吐

## 12. 仓库建议结构

```text
myshell/
├── AGENTS.md
├── README.md
├── docs/
│   ├── PROJECT_OVERVIEW.md
│   ├── SYNC_HUB_DEVELOPMENT_HANDOFF.md
│   ├── SYNC_HUB_DECISIONS.md
│   └── ...
├── shared/
│   ├── schemas/
│   └── test-vectors/
├── web/
├── macos/
└── windows/
```

三个端可以分别开发和发布，不共享 UI 实现。它们只共享：

- 数据 schema
- 加密信封规范
- 跨语言加密测试向量
- Sync Hub API 契约
- 行为和兼容性测试样例

## 13. 开发顺序

### 阶段 0：公共设计

- 创建仓库级 `AGENTS.md` 和 `README.md`
- 创建 `SYNC_HUB_DECISIONS.md`
- 固定连接 schema、稳定 ID、加密信封、恢复模型和冲突策略
- 建立共享测试向量

### 阶段 1：MyShell Web

- Web 单用户认证和本地密码重置
- 连接管理与本地加密存储
- Sync Hub 登记与单设备同步
- 双设备、离线、冲突、删除和恢复测试
- 浏览器终端、容器 Shell 和 SSH
- 状态检查、资源限制、Docker 部署与性能验收

### 阶段 2：macOS

- 原生工程与本机 Zsh
- 终端引擎、多窗口和多标签
- SSH 与连接管理
- 平台安全存储
- Sync Hub 接入和跨设备验证
- 性能、签名和发布

### 阶段 3：Windows

- 原生工程与本地 Shell
- 终端、多窗口、多标签和 SSH
- 平台安全存储
- Sync Hub 接入和三端互操作
- 性能、安装和发布

每个端都必须独立通过构建、自动化测试、安全检查、长时间会话和资源测量，不能
因为另一端可用而跳过本端验收。

## 14. 第一版非目标

- 多用户和团队协作
- 插件或主题市场
- AI 功能
- 移动端
- SSH 私钥同步
- SFTP 文件管理
- 终端历史同步
- 集群或多节点 Sync Hub
- 复杂监控平台
- 各端完全一致的像素级界面

## 15. Codex 接手时的第一项任务

Codex 阅读本文和交接手册后，不应立即搭建三个端。第一轮必须：

1. 总结项目边界和当前仓库状态。
2. 核对 Sync Hub 固定提交的实际 API。
3. 指出本文与交接文档、代码或安全边界的冲突。
4. 创建 `SYNC_HUB_DECISIONS.md` 草案。
5. 提出公共 schema、加密信封和跨语言测试向量方案。
6. 列出需要项目所有者确认的决定。
7. 给出只针对 MyShell Web 第一阶段的可测试、可回滚计划。

没有获得确认前，不得引入第三方依赖、固化不可逆数据格式或开始 macOS/Windows
实现。仓库开发过程中不得使用任何 Superpowers 技能。
