# MyShell Windows 开发规范

## 1. 交付目标

`windows/` 交付真正的 Windows 原生终端客户端，支持 PowerShell、CMD、WSL、
系统 OpenSSH，并与 Web、macOS 使用同一套 Sync Hub 和加密契约。

macOS 稳定且 `shared/` 完成跨语言验证前，不建立正式 Windows 工程。

## 2. 推荐技术栈

| 领域 | 技术 |
| --- | --- |
| 语言 | 当前稳定 .NET LTS 对应的 C# |
| UI | WinUI 3 / Windows App SDK |
| 本地终端 | ConPTY，通过窄 P/Invoke 封装 |
| Shell | PowerShell、CMD、WSL |
| SSH | Windows 系统 OpenSSH |
| 网络 | `HttpClient` + async/await |
| 加密 | `System.Security.Cryptography.AesGcm` |
| 密钥/Token | Windows Credential Manager |
| 持久化 | 事务性本地存储抽象，具体实现建项时确认 |
| 日志 | EventSource/ILogger 脱敏适配 |
| 测试 | 当前稳定 .NET 测试框架 |

C# + WinUI 3 是当前推荐，不是不可更改的既成事实。W0 必须用最小 ConPTY 原型
验证终端渲染可行性、内存和打包；若需要终端核心或 SQLite NuGet 包，必须先
提交依赖评估并获得批准。不得改用 Electron/Tauri 规避原生问题。

## 3. 计划目录

```text
windows/
├── README.md
├── DEVELOPMENT.md
├── MyShell.sln
├── src/
│   ├── MyShell.App/
│   ├── MyShell.Terminal/
│   ├── MyShell.Connections/
│   ├── MyShell.Security/
│   ├── MyShell.Sync/
│   ├── MyShell.Status/
│   └── MyShell.SharedAdapters/
├── tests/
│   ├── MyShell.Terminal.Tests/
│   ├── MyShell.Security.Tests/
│   └── MyShell.Sync.Tests/
└── docs/
```

WinUI 页面不得直接操作 ConPTY、Credential Manager、文件或网络。

## 4. 功能节点

### N0：平台原型与公共契约

- 确认最低 Windows、x64/ARM64、安装和签名方式
- 建立最小 WinUI 3 + ConPTY 原型
- 验证 AesGcm 与 `shared/` 固定向量
- 测量空工程和单 PTY 的资源基线

验收：技术栈、终端方案和资源结果获得所有者确认后再建立正式解决方案。

### N1：原生应用骨架

- App、窗口、设置、依赖注入和脱敏日志
- Debug/Release/Test/Package 命令
- 崩溃和取消边界

### N2：本地 Shell 与 ConPTY

- PowerShell、CMD 和可用 WSL 发行版检测
- 输入输出、尺寸、退出、编码和会话回收
- 有界缓冲与滚屏

验收：三类 Shell、Unicode、Vim/全屏程序、调整尺寸和关闭正常，无孤儿进程。

### N3：终端 UI

- 原生多窗口、多标签、连接侧边栏和状态栏
- 五主题、字体、快捷键和 Windows 可访问性
- 增量绘制与后台标签降频

验收：不使用 WebView 套壳；高输出无 UI 长时间阻塞或无限内存增长。

### N4：SSH

- Windows OpenSSH、用户配置、known_hosts 和 Agent
- 密码、指纹、错误、超时和退出状态
- ProxyJump 等由系统配置提供的高级能力

密码不得进入命令参数、环境、日志或普通配置。

### N5：连接、凭据和本地状态

- 连接、分组、标签、备注、终端配置
- 稳定 UUID、事务、版本和 tombstone
- Credential Manager 保存 Token 和保险库密钥
- 搜索、最近连接和错误恢复

### N6：Sync Hub

- 登记、游标、版本、队列和幂等键
- 离线、重试、取消、冲突和删除
- 恢复密钥导入

验收：Web、macOS、Windows 三端新增、修改、删除、冲突和恢复最终一致。

### N7：状态与生命周期

- Sync Hub 和 SSH 目标检查
- 手动、计划、并发、超时和提示
- 睡眠、锁屏、网络变化、注销和应用升级

### N8：打包、性能和发布

- MSIX 或经确认的安装方式
- 代码签名、安装、升级、卸载和回滚
- 长时间会话、崩溃恢复和资源测量

## 5. 设计指标

受 WinUI/.NET 基础成本影响，预算与 macOS/Web 分开：

| 指标 | 初始目标 |
| --- | --- |
| 冷启动到可输入 | `< 1.5 s` |
| 空闲 CPU | 平均 `< 0.5%` |
| 无会话基础 RSS | `< 120 MiB` |
| 每个空闲终端增量 | `< 20 MiB` |
| 默认最大终端数 | `12` |
| 默认滚屏 | `10,000` 行 |
| 正常输入回显 | `p95 < 60 ms` |
| 状态检查并发 | `4` |

使用 Release 打包版本，在代表性 x64/ARM64 设备上分别记录 Windows、.NET、
Windows App SDK、硬件、提交和测试命令。

## 6. 完成定义

- N0–N8 全部通过
- PowerShell、CMD、WSL 和 SSH 稳定
- 三端共享加密向量和同步矩阵通过
- Credential Manager、日志、本地数据库和崩溃报告无秘密泄露
- 无孤儿 ConPTY/SSH 进程或明显资源泄漏
- 安装、升级、卸载和回滚可复现
- 指标达标或偏差经所有者批准

## 7. Codex 接手指令

必须在真实 Windows 环境验证 WinUI、ConPTY、Credential Manager、打包和性能。
Agent 第一轮只完成 N0 调查与原型计划，不得直接承诺终端核心依赖或固化安装
方式。每次只推进一个 N 节点并提交测试证据。
