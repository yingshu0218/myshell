# macOS Client Decisions

本文件只记录 MyShell macOS 客户端已经确认的建项决定。跨端 schema、加密信封
和同步语义仍以 `shared/` 的正式规范为准；本目录不得单方面改变公共契约。

## MAC-DEC-001：平台范围

- 状态：已接受
- 最低系统：macOS 14
- 架构：仅 Apple Silicon（`arm64`）
- UI：SwiftUI 应用结构，AppKit 仅用于终端、键盘、窗口和 PTY 等必要桥接
- 非目标：Intel、低于 macOS 14、WebView 或其他网页套壳

## MAC-DEC-002：工程与依赖

- 状态：已接受
- 使用稳定 Xcode 随附的 Swift、CryptoKit、Security、OSLog、URLSession 和 XCTest
- M0、M1 不引入第三方依赖
- 终端渲染使用已批准的 `SwiftTerm` `v1.15.0`，通过 Swift Package Manager
  精确锁定；MyShell 继续自行管理 PTY 与进程生命周期
- 其他第三方依赖仍需逐项说明用途并取得明确批准
- 暂定 Bundle Identifier：`com.yingshu0218.myshell`

若签名账号无法使用该标识，只能在首次发布和产生用户数据前修改，并在本文记录。

## MAC-DEC-003：本地持久化

- 状态：已接受
- 使用系统 SQLite，通过 macOS 客户端自己的薄封装和单一串行执行边界访问
- UI 不直接执行 SQL
- SQLite 保存业务记录、tombstone、服务端版本、opaque cursor、有界待上传队列、
  幂等键、迁移版本和非秘密设置
- SQLite 不保存明文 SSH 密码、Sync Hub Token、保险库主密钥或恢复密钥
- migration 必须版本化、事务化并有旧版本安全拒绝或兼容策略

数据库预期位于应用的 Application Support 目录。实际文件名和备份排除策略在 M5
实现前固定。

## MAC-DEC-004：本机秘密存储

- 状态：已接受
- Sync Hub Token 和保险库主密钥存入 macOS Keychain
- Keychain 项目必须显式禁止 iCloud 同步
- Token 与保险库主密钥使用不同项目，能够独立撤销或替换
- 首版不持久化或同步 SSH 密码；需要时由系统 SSH 在受控 TTY 中交互输入
- Keychain 缺失、锁定或访问失败必须安全失败，不能回退到明文文件

iCloud Keychain 属于未来可选能力，不得在第一版中隐式开启。

## MAC-DEC-005：加密与同步

- 状态：已接受，公共 v1 契约已发布并通过 macOS 固定向量测试
- 使用 CryptoKit AES-256-GCM
- 正式信封、AAD、nonce、恢复密钥和测试向量必须来自 `shared/`
- Sync Hub 固定基线为提交 `7b5038c15fb87158de4bbd43d7fb510c7a52521e`
- TLS 证书校验保持开启
- 在公共测试向量可用前，不固化 macOS 专属信封或开始真实同步写入

## MAC-DEC-006：首版分发

- 状态：已接受（2026-07-26 更新）
- 不通过 Mac App Store 分发
- 当前以个人自用为目标，通过本地构建、GitHub Releases 或 Homebrew 提供
  Apple Silicon 构建
- 当前没有 Apple Developer 账号；Developer ID 签名、公证与 stapling 不作为
  首版完成条件，移入未来规划
- Release 配置继续启用 Hardened Runtime，保留签名与公证脚本供未来使用
- 文档必须明确：GitHub/Homebrew 不能替代 Apple 签名，未签名下载可能触发
  Gatekeeper 用户确认

具体 entitlements 遵循最小权限原则，在 PTY、SSH 和发布验证阶段以实际需求确定，
不得预先添加宽泛例外。

## MAC-DEC-007：仓库写入边界

- 状态：已接受
- 当前 macOS 任务只修改 `macos/**`
- 仅可维护根 `README.md` 中与 macOS 状态、命令和技术基线直接相关的说明
- `web/**`、`windows/**`、根 `docs/**` 和 Sync Hub 仓库仍只读
- 仓库所有者已于 2026-07-26 授权维护 `shared/**` 公共契约

## MAC-DEC-008：快捷指令

- 状态：已接受（2026-07-29）
- 快捷指令按组保存，每组和每条指令使用稳定 UUID，组内顺序有语义
- 本地使用 SQLite v6；同步 collection 为 `command-groups`，schema 为
  `command-group-v1`，使用现有保险库密钥与 AES-GCM 信封
- 只允许用户主动保存非秘密命令，不自动采集终端输入或历史
- 禁止保存密码、Token、私钥、恢复密钥或其他凭据
- 单组最多 100 条，单条正文最多 10,000 字符，批量输入最多 256 KiB
- “添加到终端”不追加回车；“运行组”按顺序发送并为缺少换行的命令追加一个换行
- 冲突不得静默覆盖，沿用本机/远端显式选择
