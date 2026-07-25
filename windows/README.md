# MyShell for Windows

`windows/` 用于真正的 Windows 原生客户端，不得使用 Electron、Tauri 或浏览器
套壳复用 Web 界面。

开始工作前完整阅读 [Windows 开发规范](DEVELOPMENT.md) 和
[跨端兼容规范](../shared/COMPATIBILITY.md)。

## 计划能力

- 初步建议 C# 与 WinUI 3，建立工程前由所有者最终确认
- PowerShell、CMD、WSL 和系统 OpenSSH
- 多窗口、多标签、连接管理、主题和状态检查
- Sync Hub 加密同步
- Windows Credential Manager 或经批准的系统安全存储
- 安装、升级、启动、空闲 CPU、内存和吞吐测量

## 当前状态

尚未建立解决方案。macOS 客户端稳定且共享契约通过跨端验证前，不开始实现。

建项前必须确认：

- 最低 Windows 版本
- C# + WinUI 3 或其他原生 UI 技术
- x64/ARM64 支持范围
- WSL 检测和本地 Shell 生命周期
- 安装包、签名和更新方式
- 终端渲染与 ConPTY 所需的第三方依赖是否获批

未来工程应在本目录独立构建、测试和发布，并在本 README 中记录真实命令。
