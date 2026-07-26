# Docker Secrets

此目录只说明需要的 Secret，实际文件已被 `.gitignore` 排除。

生成 32 字节保险库密钥：

```bash
mkdir -p secrets
openssl rand -base64 32 > secrets/vault_key
chmod 600 secrets/vault_key
```

仅启用 GitHub/Gitea 备份时，创建 `secrets/git_token` 并写入最小权限访问令牌。
令牌文件只能包含令牌本身，不能提交到 Git。
