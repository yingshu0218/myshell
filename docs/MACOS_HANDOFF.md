# macOS Codex 交接指南（未来阶段）

> 当前不执行本指南。项目已调整为先完成 Docker 网页终端和中转服务；
> 只有 `docs/DEVELOPMENT.md` 的 Web/中转完成标准通过后才进入 macOS 阶段。

## 迁移内容

迁移包应包含：

```text
AGENTS.md
README.md
.gitignore
docs/
├── DEVELOPMENT.md
├── IMPLEMENTATION_PLAN.md
└── MACOS_HANDOFF.md
```

包内不包含密码、Git Token、恢复密钥、SSH 私钥、构建产物或第三方依赖。

## 在 Mac 上准备

1. 安装最新版稳定版 Xcode。
2. 启动一次 Xcode，并接受许可证及安装必要组件。
3. 解压迁移包到 `~/Developer/MyShell`。
4. 打开终端并检查：

```bash
xcodebuild -version
swift --version
git --version
```

5. 打开 Codex macOS 客户端，选择 `~/Developer/MyShell` 作为项目文件夹。

## 发送给 Codex 的第一条消息

```text
请先完整阅读 AGENTS.md、README.md、docs/DEVELOPMENT.md 和
docs/IMPLEMENTATION_PLAN.md。

这是 MyShell 的 macOS 客户端开发任务。Web/中转阶段已经完成并验收。
不得使用 Superpowers 技能，也不得未经我的明确批准引入任何第三方依赖。

先检查 Xcode、Swift、Git 和当前仓库状态。然后向我说明准备创建的 Xcode
工程结构、最低 macOS 版本和验证命令；得到确认后建立原生 macOS 应用骨架。
完成后必须运行 Debug 构建、Release 构建和测试，并报告完整结果。
```

## 建立私有代码仓库

在 GitHub 或 Gitea 新建空的私有仓库后，于项目目录运行：

```bash
git init
git add .
git commit -m "Add initial MyShell specification"
git branch -M main
git remote add origin <私有仓库地址>
git push -u origin main
```

不要把未来用于同步连接保险库的仓库与源代码仓库混为一体。建议分别使用
`myshell`（源代码）和 `myshell-vault`（加密连接数据）两个私有仓库。

## 首次确认事项

建立 Xcode 工程前，由仓库所有者确认：

- 最低支持的 macOS 版本
- Bundle Identifier
- 是否同时支持 Intel Mac
- 应用显示名称是否保持为 `MyShell`

其余产品范围以 `docs/DEVELOPMENT.md` 为准。
