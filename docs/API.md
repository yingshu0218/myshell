# Web API

所有 `/api/v1/` 接口都要求有效的 `myshell_session` HttpOnly Cookie。非 GET
请求还必须提供登录响应中的 `X-CSRF-Token`。请求体上限为 1 MiB，保险库加密
信封上限为 2 MiB。

## 账号

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/session` | 初始化及当前会话状态 |
| `POST` | `/api/setup` | 仅首次启动可创建管理员 |
| `POST` | `/api/login` | 登录 |
| `POST` | `/api/logout` | 删除当前会话 |

## 保险库和同步

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/v1/vault` | Web 界面使用的已解密数据 |
| `PUT` | `/api/v1/vault` | 使用 `expectedVersion` 条件更新 |
| `GET` | `/api/v1/vault/envelope` | 获取 AES-256-GCM 加密快照 |
| `PUT` | `/api/v1/vault/envelope` | 验证并恢复加密快照 |

版本不一致返回 `409` 和服务端当前版本，绝不静默覆盖。

## 终端与 SSH

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/v1/connections/{id}/host-key` | 检查或扫描主机指纹 |
| `POST` | `/api/v1/connections/{id}/host-key/trust` | 确认刚扫描的指纹 |
| `POST` | `/api/v1/terminals` | 创建本地 Shell 或 SSH PTY |
| `GET` | `/api/v1/terminals/{id}/stream` | 二进制 WebSocket 输入输出 |
| `POST` | `/api/v1/terminals/{id}/resize` | 调整行列 |
| `DELETE` | `/api/v1/terminals/{id}` | 关闭并回收进程 |

## 状态与备份

- `GET /api/v1/status`
- `POST /api/v1/status/check`
- `GET /api/v1/backups`
- `POST /api/v1/backups`
- `POST /api/v1/backups/preview`
- `POST /api/v1/backups/restore`

预览会下载、认证并解密快照，但不会修改当前保险库，也不会返回密码。恢复请求
必须同时提供当前 `expectedVersion` 和字符串 `RESTORE`。
