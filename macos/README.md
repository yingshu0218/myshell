# MyShell for macOS

`macos/` 用于 Swift 编写的原生 macOS 客户端，不得包含 Web 套壳。

开始工作前完整阅读 [macOS 开发规范](DEVELOPMENT.md) 和
[跨端兼容规范](../shared/COMPATIBILITY.md)。

## 计划能力

- SwiftUI 应用结构，AppKit 处理终端视图、键盘、窗口和 PTY
- 本机 `/bin/zsh`
- 系统 OpenSSH 与 `~/.ssh/config`
- 多窗口、多标签、连接管理、主题和状态检查
- Sync Hub 加密同步
- Keychain 保存 Sync Hub Token 和保险库密钥
- Release 构建的启动、空闲 CPU、内存和吞吐测量

## 当前状态

尚未建立 Xcode 工程。Web 客户端和共享契约验收前，不开始实现。

建项前必须确认：

- 最低 macOS 版本
- Bundle Identifier
- Apple Silicon/Intel 支持范围
- 签名和分发方式
- 终端渲染与 PTY 所需的第三方依赖是否获批

未来工程应在本目录独立构建、测试和发布，并在本 README 中记录真实命令。
