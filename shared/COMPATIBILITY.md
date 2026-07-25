# MyShell 跨端兼容与验收规范

## 1. 目的

本文件规定 Web、macOS、Windows 必须共同遵守的业务和互操作行为。平台代码
不共享，但同一条连接记录在三个端必须能够安全读取、修改、删除和恢复。

## 2. 公共交付物

客户端接入 Sync Hub 前必须存在：

```text
shared/
├── schemas/
│   ├── connection-v1.schema.json
│   ├── group-v1.schema.json
│   └── terminal-profile-v1.schema.json
├── crypto/
│   └── envelope-v1.md
├── test-vectors/
│   ├── envelope-v1.json
│   ├── invalid-aad-v1.json
│   └── corrupted-ciphertext-v1.json
└── fixtures/
    ├── sync-create-update-delete.json
    └── sync-conflict.json
```

这些文件由项目决策产生，不得由某个端实现时临时决定。

## 3. 数据模型原则

- 所有业务记录使用客户端生成、跨重启稳定的 UUID。
- Collection 首版固定为 `connections`、`groups`、`terminal-profiles`。
- 时间统一使用 UTC RFC 3339，但冲突不能只依赖客户端时间。
- 未知字段的保留/拒绝策略必须由 schema 版本明确。
- 删除使用 Sync Hub tombstone，不以“本地不存在”等价替代。
- 密码冲突不得静默 last-write-wins；必须要求用户选择或执行已批准的安全合并。

## 4. 加密信封原则

- 算法目标为 AES-256-GCM。
- 每条记录独立使用符合规范的唯一 nonce。
- AAD 至少绑定 app ID、collection、record ID 和 schema 版本。
- 密文信封必须包含格式版本，但不包含主密钥或恢复密钥。
- 三端使用相同明文、密钥、nonce 和 AAD 时必须与固定向量一致。
- AAD、Tag、密文或版本损坏必须安全失败，不能返回部分明文。
- 解密后必须先验证大小和 schema，再进入业务模型。

正式信封字段和字节顺序必须记录在 `crypto/envelope-v1.md`，不能只存在代码中。

## 5. 同步状态

每个客户端必须跨重启持久化：

- Sync Hub app/device 标识
- 已提交的 opaque cursor
- 每条记录最近确认的服务端 version
- 有界待上传操作
- 逻辑操作对应的 Idempotency-Key
- 本地 tombstone 或删除确认状态

一页变化全部完成完整性校验、解密和事务写入后，才允许提交新 cursor。

## 6. 三端互操作矩阵

每次公共 schema、信封或同步状态机变化必须验证：

| 场景 | Web | macOS | Windows |
| --- | --- | --- | --- |
| 创建连接并被其他端下载 | 必须 | 必须 | 必须 |
| 修改非秘密字段 | 必须 | 必须 | 必须 |
| 修改 SSH 密码 | 必须 | 必须 | 必须 |
| 删除与 tombstone | 必须 | 必须 | 必须 |
| 同时修改产生 `409` | 必须 | 必须 | 必须 |
| 超时后复用幂等键 | 必须 | 必须 | 必须 |
| 重启恢复 cursor/队列 | 必须 | 必须 | 必须 |
| Token 撤销 | 必须 | 必须 | 必须 |
| 新设备恢复密钥导入 | 必须 | 必须 | 必须 |
| 未知 schema 安全拒绝 | 必须 | 必须 | 必须 |
| 密文损坏安全失败 | 必须 | 必须 | 必须 |

未开发的端可以先使用契约测试工具替代，但最终发布前必须用真实客户端完成。

## 7. 兼容性变更流程

1. 在 `docs/SYNC_HUB_DECISIONS.md` 新增决策。
2. 说明旧格式、候选方案、安全和迁移影响。
3. 获得所有者批准。
4. 新增版本，不原地改变旧版本含义。
5. 先更新规范和固定测试向量。
6. 各端分别实现读取旧版、写入新版或安全拒绝。
7. 完成三端矩阵后才把新版设为默认。

任何 Agent 不得因为当前只开发一个端而跳过公共兼容分析。
