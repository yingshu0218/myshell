# Future macOS Options

本文件是候选路线图，不代表已批准需求。任何选项进入实现前都必须补充产品价值、
安全影响、依赖、数据迁移、兼容测试和回滚方案，并由仓库所有者明确确认。

## iCloud Keychain 同步

第一版 Keychain 项目仅保存在本机。未来可以评估让受信任 Apple 设备通过 iCloud
Keychain 获得保险库材料，但不能简单打开同步开关：

- 必须明确哪些项目允许同步；Sync Hub Token 与保险库主密钥应分别评估
- 必须定义设备加入、丢失、撤销和 Apple ID 变更后的行为
- 不得绕过 MyShell 恢复密钥和 Sync Hub 设备登记模型
- 必须验证不会产生两个不兼容的密钥来源或意外覆盖本机密钥
- 用户必须主动启用，并能看见安全影响和关闭后的结果

## 平台与分发

- Apple Developer Program、Developer ID 签名和 Apple 公证
- Intel Mac 与 Universal Binary
- 低于 macOS 14 的兼容版本
- Mac App Store 与 App Sandbox
- 应用内自动更新
- DMG、ZIP 或安装包形式的选择

当前首版只面向个人自用，通过本地构建、GitHub Releases 或 Homebrew 获取。
GitHub/Homebrew 不会消除未签名应用的 Gatekeeper 提示；未来需要面向普通用户
无警告分发时，再启用 Developer ID 与公证路线。

## 安全与恢复

- Touch ID 或用户在场确认后释放 Keychain 项目
- 保险库主密钥轮换
- 恢复密钥重新包装与安全打印/导出
- 设备可信列表和远程撤销体验
- 更严格的应用自动锁定策略

## 终端与连接能力

- 经批准的第三方终端渲染组件
- SSH 私钥及私钥口令同步
- SFTP 文件管理
- 本地或远程端口转发管理
- 会话录制、终端历史或滚屏同步

SSH 私钥、终端历史和会话内容当前仍属于明确非目标，不能因列在本文件中而进入
第一版 schema 或 Sync Hub payload。
