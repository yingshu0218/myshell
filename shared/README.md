# MyShell Shared Contracts

`shared/` 只保存三个客户端必须共同遵守的平台无关契约，不保存可执行客户端代码。

计划内容：

```text
shared/
├── README.md
├── schemas/          # 连接、分组、终端配置的版本化 JSON schema
├── crypto/           # 加密信封、AAD、nonce 和恢复密钥格式
├── test-vectors/     # 三种语言必须得到相同结果的固定向量
└── fixtures/         # Sync Hub 协议和冲突行为样例
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

1. 先记录在 `docs/SYNC_HUB_DECISIONS.md`。
2. 分配新 schema 或信封版本。
3. 保留旧版本读取、迁移或安全拒绝策略。
4. 更新所有受影响端的固定测试向量。
5. 获得仓库所有者确认后再实现。

当前目录尚未建立正式 schema。客户端不得各自发明不兼容格式。
