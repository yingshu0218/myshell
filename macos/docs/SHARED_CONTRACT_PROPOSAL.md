# macOS Shared Contract Adoption

原提案已于 2026-07-26 被采纳并写入 `shared/`。正式定义以
`shared/schemas/`、`shared/crypto/envelope-v1.md`、`shared/test-vectors/`
和 `shared/fixtures/` 为准；本文件只保留 macOS 采纳记录。

## 需要的正式交付物

macOS M0 验收依赖以下 `shared/` 文件：

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

## 候选记录边界

| Collection | 一条记录 | 稳定 ID | 冲突要求 |
| --- | --- | --- | --- |
| `connections` | 一个 SSH 连接 | 客户端生成 UUID | 不含密码；冲突必须用户选择 |
| `groups` | 一个分组及排序信息 | 客户端生成 UUID | 安全合并或用户选择 |
| `terminal-profiles` | 一个非秘密终端配置 | 客户端生成 UUID | 无法合并时用户选择 |

连接候选字段包括显示名称、主机、端口、用户名、加密密码字段、分组引用、标签、
备注和终端配置引用。终端内容、历史、私钥、Token、主密钥、恢复密钥和运行状态
不进入任何记录。

## 候选加密约束

- 算法：AES-256-GCM
- 主密钥：32 个随机字节
- nonce：每次加密唯一；建议 12 个随机字节
- AAD 至少绑定 app ID、collection、record ID、schema version
- 信封必须显式包含格式版本、算法标识、nonce、ciphertext 和 authentication tag
- JSON 字符串使用明确的 UTF-8 与 Base64 编码规则
- 未知信封版本、AAD 不匹配、tag 或密文损坏必须在返回任何明文前失败
- 解密后执行大小上限和 schema 验证

需要公共规范精确定义 AAD 的字节拼接或长度编码方式、Base64 变体、字段顺序是否
有语义、恢复密钥文本编码，以及 `checksum` 与 GCM authentication tag 的关系。

## macOS 互操作验收

正式向量可用后，macOS 使用 CryptoKit 验证：

1. 固定 key、nonce、AAD、plaintext 得到完全相同的 ciphertext 和 tag。
2. 正常信封能够解密并通过 schema。
3. app ID、collection、record ID 或 schema version 任一改变均解密失败。
4. nonce、ciphertext 或 tag 任一损坏均安全失败。
5. 未知信封或 schema 版本安全拒绝且不破坏本地记录。
6. 同一向量能够被 Web 和 Windows 的契约测试实现读取。

## 验证状态

macOS CryptoKit 已通过正常向量、错误 AAD、损坏 payload 和恢复密钥校验测试。
真实 Sync Hub 写入、冲突 UI 与 Web/Windows 互操作仍需继续完成，不能仅凭单端
向量测试宣称 M6 完成。
