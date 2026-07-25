# MyShell macOS 开发规范

## 1. 交付目标

`macos/` 交付真正的原生 macOS 终端客户端。它在本机运行 Zsh，通过系统
OpenSSH 连接远程服务器，并与 MyShell Web、Windows 使用相同的加密数据和
Sync Hub 契约。

Web 端和 `shared/` 契约验收前，不建立正式 macOS 工程。

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
| 密钥/Token | macOS Keychain |
| 持久化 | 系统 SQLite 封装或经决策批准的 Apple 原生存储 |
| 日志 | `Logger`/OSLog，隐私字段强制脱敏 |
| 测试 | XCTest 或稳定 Xcode 随附测试框架 |

初始部署目标建议 macOS 14；Bundle Identifier、Intel 支持和最终最低版本必须
在 M1 建项前由所有者确认。

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

- 确认 macOS 最低版本、Bundle ID、架构和分发方式
- 读取 `shared/` schema、加密信封和测试向量
- 验证 CryptoKit 与共享向量完全互操作

验收：固定向量的加密、解密、AAD 错误、密文损坏和未知版本测试通过。

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
- Keychain 中的 Token 与保险库密钥
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

### M8：性能与发布

- 冷启动、空闲、单会话、每新增会话和高吞吐测量
- 8 小时空闲、24 小时会话和崩溃恢复
- 签名、归档、安装、升级和回滚

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
- 签名应用能在干净 Mac 安装、升级和回滚
- 指标达标或偏差得到所有者批准

## 7. Codex 接手指令

Agent 必须在真实 macOS/Xcode 环境执行构建和运行验证。非 macOS 环境可以分析
和编写平台无关代码，但不得声称 AppKit、PTY、Keychain、签名或性能已经验证。
每次只推进一个 M 节点，并提交对应测试证据。
