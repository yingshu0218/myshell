# MyShell macOS 开发规范

当前首版范围以 [CURRENT_SCOPE.md](../docs/CURRENT_SCOPE.md) 为准：仅推进
macOS，Sync Hub 暂缓，不要求跨端互操作与 8/24 小时长测作为当前发布门槛。
下列节点保留完整历史规划，尚未执行的验收不得标记为通过。

## 1. 交付目标

`macos/` 交付真正的原生 macOS 终端客户端。它在本机运行 Zsh，通过系统
OpenSSH 连接远程服务器，并与 MyShell Web、Windows 使用相同的加密数据和
Sync Hub 契约。

macOS 当前可独立推进平台建项、工程骨架、PTY 和原生 UI。涉及持久化的跨端业务
格式与真实 Sync Hub 写入，必须等待 `shared/` 契约和固定测试向量验收。

## 2. 固定技术栈

| 领域 | 技术 |
| --- | --- |
| 语言 | 稳定 Xcode 随附的 Swift |
| UI | SwiftUI 应用结构 + AppKit 终端/窗口桥接 |
| 本地进程 | Darwin PTY、`Process` 和受控文件描述符 |
| Shell | `/bin/zsh` |
| SSH | `/usr/bin/ssh`、`~/.ssh/config`、known_hosts、SSH Agent |
| 网络 | `URLSession` async/await |
| 加密 | CryptoKit AES-GCM，遵循 `shared/` 信封 |
| 密钥/Token | 本机 macOS Keychain，显式禁止 iCloud 同步 |
| 持久化 | 系统 SQLite 薄封装 |
| 日志 | `Logger`/OSLog，隐私字段强制脱敏 |
| 测试 | XCTest 或稳定 Xcode 随附测试框架 |

部署目标固定为 macOS 14，仅构建 Apple Silicon `arm64`。Bundle Identifier
暂定为 `com.yingshu0218.myshell`。首版个人自用，通过本地构建、GitHub Releases
或 Homebrew 分发未签名 arm64 ZIP；Developer ID 和 Apple 公证属于未来规划。

任何终端渲染、PTY、SQLite 封装或其他第三方包都需单独批准。未经批准不得把
Web 终端嵌入 WebView 代替原生终端。

## 3. 计划目录

```text
macos/
├── README.md
├── DEVELOPMENT.md
├── MyShell.xcodeproj/
├── Sources/
│   ├── App/
│   ├── Terminal/
│   ├── Connections/
│   ├── Security/
│   ├── Sync/
│   ├── Status/
│   └── SharedAdapters/
├── Tests/
│   ├── TerminalTests/
│   ├── SecurityTests/
│   ├── SyncTests/
│   └── Fixtures/
└── docs/
```

UI 不直接操作 SQLite、Keychain、PTY 或网络。各能力通过协议隔离并支持测试替身。

## 4. 功能节点

### M0：平台与公共契约

- 记录已经确认的 macOS 最低版本、Bundle ID、架构、存储和分发方式
- 在 `macos/docs/` 维护未来选项和公共契约提案，不直接修改其他客户端或 `shared/`
- 读取 `shared/` schema、加密信封和测试向量
- 验证 CryptoKit 与共享向量完全互操作

验收：平台决策有记录；公共维护者提供固定向量后，加密、解密、AAD 错误、密文
损坏和未知版本测试通过。固定向量未就绪时，M0 保持部分完成。

### M1：原生工程骨架

- SwiftUI App、窗口、设置和测试 Target
- Debug/Release/Test 命令
- 依赖注入根和脱敏 Logger

验收：干净 Mac 上 Debug、Release 和测试均成功。

### M2：Zsh 与 PTY

- 启动 `/bin/zsh`
- 输入输出、尺寸、当前目录、环境和退出码
- 有界滚屏与会话生命周期

验收：Vim、Top、Unicode、颜色、粘贴和尺寸变化正常；关闭后无子进程和描述符。

### M3：终端引擎与原生 UI

- 增量 ANSI/VT 解析和绘制
- 多窗口、多标签、侧边栏和状态栏
- 字体、五主题、快捷键和可访问性
- 后台标签降频

验收：不使用 WebView；视觉与 Web 保持语义一致但符合 macOS 交互；长输出无
无限内存增长。

### M4：SSH

- 系统 SSH、config、known_hosts、Agent 和 ProxyJump
- 密码登录与主机指纹确认
- 连接错误、超时和退出状态

密码不得进入参数、环境或日志。优先使用同一应用内受控 askpass/IPC 设计。

验收：测试 SSH 主机覆盖密码、密钥、Agent、未知/变化指纹、超时和断网。

### M5：连接与本地存储

- 连接、分组、标签、备注和终端配置
- 事务性本地记录、稳定 UUID 和 tombstone
- 本机非同步 Keychain 中相互独立的 Token 与保险库密钥
- 搜索、最近连接和安全错误 UI

验收：跨重启稳定；数据库不含明文密码；Keychain 锁定和条目缺失可恢复。

### M6：Sync Hub

- 登记、Token、游标、版本、队列和幂等键
- 拉取、事务应用、上传、离线和取消
- 冲突对比与用户选择
- 新设备恢复密钥导入

验收：执行完整交接矩阵，并与 Web 客户端真实双向同步。

### M7：状态、恢复和产品化

- Relay 与 SSH 目标手动/定时检查
- 同步状态、最近成功时间和可行动错误
- 应用重启、Mac 休眠、唤醒和网络切换
- 导入/导出、停用同步和安全清理
- 非秘密快捷指令组、本地/SSH 终端插入、有界批量执行与加密同步

### M8：性能与发布

- 冷启动、空闲、单会话、每新增会话和高吞吐测量
- 8 小时空闲、24 小时会话和崩溃恢复
- 未签名个人 ZIP、SHA-256、GitHub/Homebrew 获取、安装、升级和回滚

## 5. 设计指标

首个原型实测后可经批准调整：

| 指标 | 目标 |
| --- | --- |
| 冷启动到可输入 | `< 1 s` |
| 空闲 CPU | 平均 `< 0.3%` |
| 无会话基础 RSS | `< 80 MiB` |
| 每个空闲终端增量 | `< 15 MiB` |
| 默认最大终端数 | `12` |
| 默认滚屏 | `10,000` 行 |
| 正常输入回显 | `p95 < 50 ms` |
| 状态检查并发 | `4` |

所有性能结论使用 Release 构建，并记录硬件、macOS、Xcode、提交和测试命令。

## 6. 完成定义

- M0–M8 全部通过
- 原生 Zsh、SSH、多窗口和多标签稳定
- Web ↔ macOS 双设备同步、冲突、删除和恢复通过
- Keychain、日志、数据库和崩溃报告无秘密泄露
- 长时间会话无进程、描述符或明显内存泄漏
- 个人 Release ZIP 能在干净 Mac 安装、升级和回滚
- 指标达标或偏差得到所有者批准

## 6.1 当前验收记录

- M1–M3：Debug/Release 构建、PTY、Zsh、SwiftTerm、多标签和多窗口已验证
- M4：系统 SSH 参数安全、config/Agent/known_hosts/ProxyJump 接入和退出恢复
  已实现；密码、密钥、指纹变化、超时及断网仍需测试 SSH 主机做矩阵验证
- M5：SQLite v6、稳定 UUID、tombstone、连接/快捷指令 UI 和非同步 Keychain 已实现
- M6：共享 v1 schema、CryptoKit、恢复密钥、真实连接 pull/push、持久队列和
  409 冲突用户选择已实现；实际 Sync Hub 双设备互操作已经在本机通过
- M7：同步凭据诊断、停用清理和无秘密连接导入导出已实现；休眠/网络切换的长时
  验证仍待执行
- M8：arm64 未签名个人 ZIP 与 SHA-256 已验证；干净机安装和性能长测仍需验收，
  Developer ID 与公证不属于首版完成条件

最新自动化证据：46 项默认测试全部通过，另有 1 项按需真实 Sync Hub 集成测试
通过；Release 应用的 Bundle ID 为
`com.yingshu0218.myshell`，最低系统 14.0，版本 0.1.0 (1)，主程序仅包含 arm64。

## 7. Codex 接手指令

Agent 必须在真实 macOS/Xcode 环境执行构建和运行验证。非 macOS 环境可以分析
和编写平台无关代码，但不得声称 AppKit、PTY、Keychain、签名或性能已经验证。
每次只推进一个 M 节点，并提交对应测试证据。
