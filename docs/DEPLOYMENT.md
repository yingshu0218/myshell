# Docker 与 VPS 部署

## 1. 准备 Secret

```bash
mkdir -p secrets
openssl rand -base64 32 > secrets/vault_key
chmod 600 secrets/vault_key
```

启用 GitHub/Gitea 备份时：

```bash
printf '%s' '你的最小权限令牌' > secrets/git_token
chmod 600 secrets/git_token
```

## 2. 启动

```bash
export MYSHELL_PUBLIC_URL=https://shell.example.com
docker compose up -d --build
```

需要 Git 备份时：

```bash
docker compose -f compose.yaml -f compose.backup.yaml up -d
```

首次访问域名时创建唯一账号。生产环境不得启用 `MYSHELL_TEST_BOOTSTRAP`。

## 3. HTTPS 反向代理

容器端口只映射到 `127.0.0.1:8080`。反向代理必须：

- 终止 TLS 并将 HTTP 重定向到 HTTPS
- 支持 WebSocket
- 将 `Host` 传给上游
- 覆盖为 `X-Forwarded-Proto: https`
- 为终端连接使用足够长的读取超时

仓库提供可直接修改域名和证书路径的
[`deploy/Caddyfile.example`](../deploy/Caddyfile.example) 与
[`deploy/nginx.conf.example`](../deploy/nginx.conf.example)。

## 4. 升级和恢复

升级前先执行 Git 加密备份或备份 Docker 卷。然后构建新镜像并重建容器：

```bash
docker compose build --pull
docker compose up -d
docker compose ps
```

`/data` 位于命名卷，重建容器不会删除。不要使用 `docker compose down -v`，
该命令会删除保险库和账号数据。

## 5. 加固

默认 Compose 使用非 root 用户、只读根文件系统、全部 capability 删除、
进程和内存上限以及 16 MiB 临时目录。公网防火墙只需开放反向代理的 80/443，
不要公开 8080。
