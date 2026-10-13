# MyShell Shared Contracts

`shared/` 只保存三个客户端必须共同遵守的平台无关契约，不保存可执行客户端代码。

详细互操作矩阵见 [COMPATIBILITY.md](COMPATIBILITY.md)。

当前正式的首版内容：

```text
shared/
├── README.md
├── schemas/          # connection/group/terminal-profile/command-group v1 JSON Schema
├── crypto/           # envelope-v1、AAD、checksum 和恢复密钥格式
├── test-vectors/     # AES-GCM 正常与失败固定向量
└── fixtures/         # 创建、更新、删除和冲突样例
```

## 允许进入 shared 的内容

- 业务记录字段及 schema 版本
- Collection 和稳定 record ID 规则
- 加密信封的字节与 JSON 表示
- 认证数据、nonce 和密钥恢复规则
- Tombstone、冲突和迁移行为
- 不含真实秘密的固定测试向量
- 跨端兼容性验收样例

## 禁止进入 shared 的内容

- Swift、Windows 或 Web UI 组件
- 平台存储封装
- PTY、SSH 进程或窗口实现
- 真实主机、用户名、密码、Token 或密钥
- 为某一端方便而加入的非通用字段
- 构建产物或生成缓存

任何公共格式变化必须：

1. 先在变更 PR 中记录决策、威胁模型和兼容性影响。
2. 分配新 schema 或信封版本。
3. 保留旧版本读取、迁移或安全拒绝策略。
4. 更新所有受影响端的固定测试向量。
5. 获得仓库所有者确认后再实现。

首版契约已经建立。客户端必须严格读取 v1；写入新版本前必须先更新这里的规范、
schema、向量和兼容性矩阵。`command-groups` 保存用户明确创建的非秘密快捷指令，
不等同于终端历史；客户端不得自动采集终端输入。v1 明确不同步密码、私钥、
私钥路径、Token、恢复密钥、终端输出、滚屏或自动采集的命令历史。
