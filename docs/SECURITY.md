# 安全设计

## 凭据

账号密码只保存 bcrypt 哈希。SSH 用户名、密码、连接信息和备份配置统一放入
AES-256-GCM 保险库；磁盘文件和 Git 备份仅包含认证密文。保险库密钥必须是
32 个随机字节的 Base64，并通过只读 Docker Secret 挂载。

SSH 密码通过权限为 `0600`、随机命名且读取一次即删除的 Unix Socket 传给内部
AskPass 子命令，不进入命令参数、普通环境变量、日志或磁盘文件。SSH 私钥不
进入保险库或 Git 备份，只能由 VPS 管理员放在容器用户可读取的受控位置。

## SSH 主机身份

新主机先由 `ssh-keyscan` 获取公钥，再用 `ssh-keygen` 计算指纹并显示给用户。
用户核对并确认后写入 `/data/known_hosts`。正式连接使用
`StrictHostKeyChecking=yes`，主机密钥变化会被 OpenSSH 拒绝。

## Web 防护

- HttpOnly、Secure、SameSite=Strict Cookie
- 空闲和绝对会话过期，密码重置注销全部会话
- 登录失败限速及临时锁定
- 非 GET 请求使用 CSRF Token
- 同源 WebSocket、CSP、HSTS、禁止嵌入和 MIME 嗅探
- 公网模式拒绝未标记为 HTTPS 的请求

反向代理必须覆盖客户端提供的 `X-Forwarded-Proto`，不能直接透传不可信值。

## 日志

服务仅记录请求方法、路径、耗时和远端 IP。禁止增加请求体、Cookie、授权头、
终端内容、主机密码、恢复密钥或 Git Token 日志。提交前运行敏感信息扫描并检查
Docker 镜像层。
