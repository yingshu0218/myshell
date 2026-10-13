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
- 可同步的多组快捷指令、单条插入和有界批量执行
- Keychain 保存 Sync Hub Token 和保险库密钥
- Release 构建的启动、空闲 CPU、内存和吞吐测量

## 当前状态

已实现 SwiftUI/AppKit 原生工程、Darwin PTY、本机 Zsh、SwiftTerm 1.15.0、
多窗口、多标签、五套主题和系统 OpenSSH。SSH 支持 `~/.ssh/config`、Agent、
known_hosts、身份文件与 ProxyJump；密码及主机指纹提示直接留在受控 TTY 中，
不会写入参数、环境、日志或数据库。

连接、分组、标签、备注和非秘密快捷指令组持久化到系统 SQLite；Sync Hub Token 与保险库密钥使用
互相独立、禁止同步的本机 Keychain 项目。连接 JSON 可通过原生文件面板安全
导入导出。Sync Hub 已实现 HTTPS 客户端、负载边界、错误分类、opaque cursor、
有界离线队列和幂等键，游标只在整页成功应用后提交。

Debug 测试现为 47 项：46 项默认测试通过，1 项真实 Sync Hub 集成测试按需运行并已通过。Release 构建已验证最低 macOS 14、最终二进制
仅 `arm64`、版本 `0.1.0 (1)`，并启用 Hardened Runtime；Developer ID 归档与
notarytool 公证流程见 [发布说明](docs/RELEASE.md)。
首版个人使用的未签名 ZIP 与 SHA-256 可由 `./script/release.sh personal` 生成。

M0 文档：

- [已确认决策](docs/DECISIONS.md)
- [未来可选能力](docs/FUTURE_OPTIONS.md)
- [公共契约提案](docs/SHARED_CONTRACT_PROPOSAL.md)
- [终端渲染依赖评估](docs/TERMINAL_DEPENDENCY_EVALUATION.md)
- [性能验证](docs/PERFORMANCE.md)
- [发布说明](docs/RELEASE.md)
- [首版验收审计](docs/FIRST_RELEASE_AUDIT.md)

暂定 Bundle Identifier 为 `com.yingshu0218.myshell`。当前唯一获批的运行时
第三方包是 SwiftTerm 1.15.0；许可信息见 [第三方声明](THIRD_PARTY_NOTICES.md)。

公共 schema（包括 `command-group-v1`）、AES-GCM 信封/AAD、恢复密钥格式和固定测试向量已发布，macOS
CryptoKit 契约测试已经通过。连接记录的真实加密 pull/push、SQLite dirty 状态、
恢复密钥和 409 冲突用户选择已经接通；本机实际 Sync Hub 的双设备加密上传、
拉取和并发冲突测试已经通过。Developer ID 签名和公证作为未来规划。

## 本地命令

当前工程使用共享的 `MyShell` Xcode scheme。开发构建关闭签名；Developer ID
签名、Hardened Runtime、归档和公证在发布阶段配置。

```bash
cd macos
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -destination 'platform=macOS,arch=arm64' build
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -destination 'platform=macOS,arch=arm64' test
xcodebuild -project MyShell.xcodeproj -scheme MyShell \
  -configuration Release -destination 'platform=macOS,arch=arm64' build
./script/build_and_run.sh
./script/build_and_run.sh --verify
DEVELOPMENT_TEAM=TEAMID ./script/release.sh archive
NOTARY_KEYCHAIN_PROFILE=myshell-notary ./script/release.sh notarize
```
