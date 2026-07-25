# MyShell × Sync Hub：Codex 开发交接文档

## 1. 文档目的

本文档用于把 Sync Hub `v0.1.0` 的同步能力、安全边界和接入要求交给未来负责开发 MyShell 的 Codex 会话。

当前只确定以下事实：

- Sync Hub 已实现与业务无关的加密记录同步服务。
- MyShell 是计划中的第一个客户端。
- MyShell 尚未开发或尚未经过 Sync Hub 接入分析。
- 目前不知道 MyShell 最终采用的语言、平台、本地存储、业务实体和生命周期。

因此，本文档提供的是接入流程、约束和待填写模板，**不是 MyShell 业务模型设计**。开始编码前，必须先分析 MyShell 仓库并补齐本文档要求的决策。

本交接基线：

- Sync Hub 版本：`v0.1.0`
- Sync Hub 基线提交：`7b5038c15fb87158de4bbd43d7fb510c7a52521e`
- 稳定 API 前缀：`/v1`
- 正式部署的 HTTPS：由反向代理终止 TLS；MyShell 必须访问反向代理提供的可信 HTTPS 地址

如果 Sync Hub 后续版本与本基线不一致，应先比较 API 和接入文档，再更新 MyShell 的接入设计，不能默认兼容。

## 2. 开始前必读顺序

未来 MyShell Codex 应按以下顺序阅读资料：

1. MyShell 仓库根目录的 `AGENTS.md`。
2. MyShell 的 `README.md` 和 `docs/` 目录。
3. MyShell 的入口、领域模型、本地持久化、凭据存储、网络层和测试代码。
4. 本文件 `docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md`。
5. Sync Hub 的 [`SYNC_INTEGRATION.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/SYNC_INTEGRATION.md)。
6. Sync Hub 的 [`API.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/API.md)。
7. Sync Hub 的 [`ARCHITECTURE.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/ARCHITECTURE.md)。
8. 正式部署前再阅读 Sync Hub 的 [`DEPLOYMENT.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/DEPLOYMENT.md)。

不得只根据提示词或本文档中的示例直接编码。API 细节以对应版本的 Sync Hub 文档和实现测试为准；MyShell 细节以 MyShell 仓库代码为准。

## 3. 如何开始新的 Codex 会话

本文档已经存放在 MyShell 仓库，不需要再复制。克隆或打开 MyShell 仓库后，在仓库根目录启动 Codex，并明确要求它先完整阅读：

```text
AGENTS.md（存在时）
README.md（存在时）
docs/
docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md
```

如果 Codex 可以访问 GitHub，让它继续读取本文链接的 Sync Hub `v0.1.0` 参考文档；如果开发环境不能访问私有 Sync Hub 仓库，则从固定提交 `7b5038c15fb87158de4bbd43d7fb510c7a52521e` 导出 `SYNC_INTEGRATION.md`、`API.md`、`ARCHITECTURE.md` 和 `DEPLOYMENT.md` 到 MyShell 的 `docs/sync-hub-reference/`。

不得只复制本文中的提示词而丢弃版本、职责边界、安全红线和验收要求。

## 4. 可直接复制的首次提示词

在 MyShell 仓库打开 Codex 后，可以发送：

```text
请先完整阅读本仓库的 AGENTS.md、README.md、docs 目录，以及项目入口、领域模型、
本地持久化、凭据存储、网络层和测试代码。

然后完整阅读 docs/SYNC_HUB_DEVELOPMENT_HANDOFF.md，以及其中指定的 Sync Hub v0.1.0
参考文档。MyShell 尚未完成 Sync Hub 接入分析，不要预设业务实体、collection、
recordId、加密格式或冲突策略，也不要立即修改代码。

请先输出：
1. 你对 MyShell 当前架构和数据生命周期的理解；
2. 适合同步与明确不应同步的数据清单；
3. 数据映射、稳定 ID、加密密钥、系统安全存储、游标、待上传队列和冲突策略的候选方案；
4. 需要我确认的产品或安全决策；
5. 分阶段、可测试、可回滚的实施计划。

必须遵守：业务明文、终端内容、密码、连接凭据、加密密钥和恢复密钥不得上传
Sync Hub；同步令牌不得写入普通配置或日志；Sync Hub 不得依赖 MyShell 业务结构。
正式环境通过反向代理提供可信 HTTPS。任何第三方依赖、数据迁移或不可逆操作都先说明。
```

第一轮只做分析和计划。用户确认数据范围、加密与冲突策略后，才进入实现。

## 5. Sync Hub 与 MyShell 的职责边界

### Sync Hub 负责

- 注册和停用应用、设备。
- 签发和撤销应用或设备令牌。
- 按 `application / collection / record` 保存不透明密文。
- 分配服务端版本和规范更新时间。
- 使用 `baseVersion` 检测并发冲突。
- 使用 tombstone 传播删除。
- 提供不透明游标的增量变更流。
- 为相同逻辑写入提供持久化幂等结果。
- 提供同步元数据、活动、备份和平台管理能力。

### MyShell 负责

- 决定哪些业务数据允许同步。
- 定义业务对象的序列化和 schema 版本。
- 在本地加密并认证每个 payload。
- 保管加密密钥、恢复密钥和 Sync Hub 令牌。
- 生成稳定的 collection 和 record ID。
- 持久化服务端版本、游标、待上传操作和幂等键。
- 验证完整性、解密、迁移 schema 并事务性写入本地。
- 处理 tombstone 和冲突。
- 实现离线、重试、取消、重新登记和用户可见状态。
- 确保日志、崩溃报告和诊断导出不泄露敏感内容。

Sync Hub 不解析、不查询、不合并 MyShell 业务明文。不得为了简化 MyShell 而向 Sync Hub 核心加入 MyShell 专属字段或业务逻辑。

## 6. 安全红线

以下内容不得上传 Sync Hub，也不得出现在请求日志、活动日志或错误详情中：

- 业务明文。
- 终端输入、终端输出、滚屏缓冲区和命令历史。
- SSH 密码、私钥、私钥口令、一次性验证码。
- 数据库密码、API 密钥和其他连接凭据。
- payload 加密密钥和恢复密钥。
- Sync Hub Bearer Token、Cookie 或完整请求/响应。

客户端还必须满足：

- 每个 payload 在上传前完成加密和完整性保护。
- 使用平台维护良好的密码学实现；确定算法前先做安全评审。
- nonce/随机数必须遵守所选算法要求，不得重复。
- 在可行时，把 app ID、collection、record ID 和 schema 版本绑定到认证数据。
- 先校验完整性，再解析明文；限制解密后大小并拒绝未知 schema。
- Sync Hub Token 放入操作系统安全凭据存储，不得放入普通配置、源码或日志。
- 恢复密钥与 Sync Hub Token 分离；撤销 Token 不应导致本地数据无法解密。
- 所有非 loopback 访问使用 HTTPS。正式环境由反向代理提供受信任证书，MyShell 不得关闭证书校验或永久信任当前测试自签名证书。
- 未获得明确需求时，不同步秘密材料；“先全部同步以后再过滤”不可接受。

## 7. 编码前必须从 MyShell 代码确认的信息

Codex 应给出带文件路径和代码证据的答案：

1. 支持的平台、语言、运行模式和进程生命周期。
2. 领域对象有哪些，哪些是用户生成数据，哪些只是缓存或运行态。
3. 本地数据保存在哪里，是否支持事务、迁移和唯一约束。
4. 每类对象是否已有跨重启稳定 ID；复制、导入和删除时 ID 如何变化。
5. 哪些对象包含终端内容、密码、私钥、Token 或连接凭据。
6. 是否已有端到端加密、主密钥、恢复流程和系统安全存储封装。
7. 网络层如何配置 base URL、超时、代理、TLS 和取消。
8. 后台任务如何调度，应用退出、休眠、断网时如何处理。
9. UI 中适合放置同步开关、登录/登记、进度、冲突和错误的位置。
10. 当前测试设施能否模拟双设备、重启、断网、超时和并发修改。
11. 数据导入、导出、备份和删除账户如何影响同步状态。
12. 多窗口、多进程或多线程是否会同时操作同一同步队列。

在这些信息未确认前，不得最终确定 collection、payload 格式、密钥方案或合并策略。

## 8. 分阶段实施计划

### 阶段 0：分析与决策

- 完成上一节的代码调查。
- 列出“同步 / 不同步 / 待确认”的数据。
- 填写数据映射模板。
- 确定威胁模型、密钥和恢复模型。
- 确定每个 collection 的冲突策略。
- 写入 MyShell 自己的接入决策文档并获得确认。

### 阶段 1：协议与本地状态基础

- 建立可替换的 Sync Hub API 客户端。
- 实现严格的请求/响应结构、超时、取消和错误分类。
- 在安全存储中保存 Token。
- 在本地持久化 app ID、device ID、游标、每条记录的服务端版本。
- 建立持久化待上传队列，保存逻辑操作对应的幂等键。
- 对网络层和本地状态机编写测试，不依赖真实生产数据。

### 阶段 2：加密数据封装

- 定义带 schema 版本的确定性序列化规则。
- 实现 payload 加密、认证、解密、大小限制和 schema 迁移。
- 明确密钥生成、导入、恢复、轮换和遗失处理。
- 添加防止秘密字段误入 payload 的测试。

### 阶段 3：单设备同步

- 首次拉取变更。
- 上传本地独有记录。
- 保存服务端返回的版本。
- 处理 tombstone。
- 只有本页全部事务性落地后才提交新游标。
- 实现重启恢复、离线队列和超时幂等重试。

### 阶段 4：双设备与冲突

- 完成第二设备登记和初始同步。
- 验证双向新增、修改和删除。
- 对 `409 Conflict` 获取当前状态并执行已确认的合并策略。
- 无法安全合并时提供用户选择，不静默覆盖新版本。
- 验证 Token 撤销、设备停用和重新登记。

### 阶段 5：产品化与发布

- 增加同步状态、最近成功时间、可行动错误和手动重试入口。
- 对日志、崩溃报告和诊断导出做秘密扫描。
- 使用独立测试应用和可丢弃密文完成验收矩阵。
- 记录 Sync Hub 版本、反向代理 HTTPS 地址配置和升级兼容策略。
- 先小范围启用，保留关闭同步且不破坏本地数据的回退路径。

## 9. 数据映射模板

分析 MyShell 后，在 MyShell 仓库复制并填写下表。示例 collection 名称不能直接当成最终设计。

| MyShell 业务对象 | 是否同步 | 不同步原因/敏感字段 | collection | recordId 来源与稳定性 | payload schema 版本 | 加密密钥域 | 删除语义 | 冲突策略 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 待分析 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 |

每个映射还需回答：

- 一个业务对象对应一条记录，还是多个对象打包成一条记录？
- 单条加密后 payload 是否始终低于默认解码上限 1 MiB？
- 父子对象的创建、修改和删除顺序如何保证？
- record ID 是否由客户端生成并在设备间保持稳定？
- 本地版本与 Sync Hub `version` 分别保存在哪里？
- schema 升级时旧设备是否仍能安全读取或拒绝？
- 是否允许字段级自动合并；不能合并时用户看到什么？

优先按同步行为划分 collection，而不是为了让服务端查询业务字段。Sync Hub 不会解析 collection 内的数据。

## 10. 同步 API 与算法要点

所有同步请求使用：

```http
Authorization: Bearer <application-or-device-token>
Content-Type: application/json
```

### 写入

```http
PUT /v1/apps/{appId}/collections/{collection}/records/{recordId}
Idempotency-Key: <本次逻辑修改的稳定幂等键>

{
  "baseVersion": 0,
  "payload": "<base64 编码的密文>",
  "checksum": "<客户端定义的完整性值>"
}
```

- 仅当客户端认为服务端记录不存在时使用 `baseVersion: 0`。
- 更新时使用本设备最后确认的服务端版本。
- 每个新的逻辑修改生成新幂等键。
- 超时属于结果未知，必须用**相同请求和相同幂等键**重试。
- 同一幂等键不得用于不同内容。
- 服务端分配新 `version` 和 `updatedAt`。

### 删除

```http
DELETE /v1/apps/{appId}/collections/{collection}/records/{recordId}
Idempotency-Key: <本次逻辑删除的稳定幂等键>
Content-Type: application/json

{"baseVersion": 4}
```

删除生成 tombstone。客户端必须保存并传播删除版本；本地查不到记录不代表其他设备已看到删除。

### 增量拉取

```http
GET /v1/apps/{appId}/changes?cursor=<opaque-cursor>&limit=32
```

- 首次登记省略 `cursor`。
- `limit` 范围为 1–32。
- cursor 是不可解析、不可拼接、不可修改的服务端值。
- 一页全部完成完整性校验、解密和本地事务提交后，才能持久化响应 cursor。
- 处理失败时从上一次已提交 cursor 重试。
- 持续请求，直到返回变化数量少于请求 limit。
- 对同一记录只应用比本地已确认服务端版本更高的版本。

### 推荐循环

```text
读取安全存储中的 Token、已提交 cursor 和待上传队列
  -> 拉取 changes
  -> 校验完整性、解密、迁移 schema
  -> 事务性应用记录或 tombstone
  -> 提交新 cursor
  -> 加密本地待上传修改
  -> 用 baseVersion + Idempotency-Key 执行 PUT/DELETE
     -> 超时/传输错误/5xx：有界指数退避并用原幂等键重试
     -> 409：读取当前版本，合并或请求用户选择，使用新幂等键重试新逻辑写入
     -> 401/403：停止自动重试，提示重新登记或检查权限
     -> 400/422：修正输入后才可重试
  -> 保存服务端确认版本
```

重试必须有上限、抖动、超时和取消。不得因为重试而自动覆盖更新的服务端内容。

首次登记的安全顺序：

1. 管理员在 Sync Hub 创建应用。
2. 需要设备级审计时创建设备。
3. 签发应用或设备 Token；密文只显示一次。
4. MyShell 将 Token 写入系统安全凭据存储。
5. 首次拉取变更。
6. 以 `baseVersion: 0` 上传本地独有记录。
7. 再拉取一次，覆盖登记期间的竞争窗口。

## 11. 测试验收矩阵

所有测试使用独立测试应用和可丢弃的加密记录，不得首次在唯一生产副本上测试恢复。

| 场景 | 必须验证的结果 |
| --- | --- |
| 空数据首次登记 | 游标可持久化，无虚假记录或错误 |
| 单设备首次上传 | 服务端分配版本，本地保存确认版本 |
| 两设备新增与下载 | 两端最终得到相同业务内容和服务端版本 |
| 顺序修改 | 新版本单调应用，重放旧版本不回滚本地数据 |
| 并发修改 | 产生 `409`，按 collection 策略合并或要求用户选择 |
| 删除传播 | tombstone 到达另一设备，记录不会意外复活 |
| 上传超时 | 使用相同幂等键重试，只产生一次逻辑提交 |
| 下载中途失败 | 不提前提交 cursor，重试不漏数据 |
| MyShell 重启 | cursor、版本、待上传队列和幂等键正确恢复 |
| Sync Hub 重启 | 已提交记录和幂等结果仍然可用 |
| 断网后多次本地修改 | 队列有界且顺序明确，联网后结果符合冲突策略 |
| 无效/撤销 Token | `401` 后停止盲目重试，秘密不出现在错误信息 |
| 跨应用 Token | `403`，不读取或修改其他应用数据 |
| 无效 cursor | 明确处理 `400`，不得自行构造替代 cursor |
| 超大 payload | 客户端预先限制；服务端 `413` 时不盲目提高限制 |
| 非法 ID/资源边界 | 正确处理 `422`，不无限重试 |
| 密文损坏/校验失败 | 不解析、不提交 cursor，给出不泄密的可行动错误 |
| 未知 schema 版本 | 安全拒绝或执行已测试迁移，不破坏原数据 |
| 新设备恢复 | 使用保留的客户端密钥恢复；Sync Hub 不提供恢复密钥 |
| 日志与崩溃报告 | 无 Token、密钥、明文、密文、终端内容或完整响应 |
| 取消与退出 | 网络和后台任务停止，队列状态一致、无资源泄漏 |
| 正式 HTTPS | 通过反向代理可信证书连接，证书校验保持开启 |

## 12. 完成定义

只有同时满足以下条件，才能声明 MyShell 的 Sync Hub 接入完成：

- MyShell 数据范围、映射、schema、稳定 ID、删除和冲突策略已有版本化文档。
- 加密、密钥恢复和系统安全存储方案经过确认。
- Sync Hub 只收到密文和允许的同步元数据。
- 游标、服务端版本、待上传队列和幂等键均可跨重启恢复。
- 单设备、双设备、离线、冲突、删除、撤销和新设备恢复通过测试。
- 所有失败路径有边界、超时、取消和不泄密的错误处理。
- 日志、UI、诊断导出和崩溃报告通过敏感信息检查。
- Sync Hub v0.1.0 契约测试或真实测试环境端到端验证通过。
- 正式 base URL 使用反向代理提供的可信 HTTPS，未关闭证书校验。
- 用户可看见同步状态，并可在不破坏本地数据的情况下停用同步。
- 文档记录实际实现，而不是仍保留“待确认”的核心决策。

## 13. 不确定项与决策记录

不要把未确认事项埋在代码注释或聊天记录中。建议在 MyShell 仓库维护：

```text
docs/SYNC_HUB_DECISIONS.md
```

每项决策使用以下格式：

```markdown
## DEC-YYYYMMDD-NN：简短标题

- 状态：待确认 / 已接受 / 已替代
- 日期：
- Sync Hub 基线：v0.1.0 / 7b5038c...
- 背景与代码证据：
- 备选方案：
- 最终决定：
- 安全影响：
- 数据迁移与兼容影响：
- 测试要求：
- 批准人或确认来源：
- 替代了哪项决策：
```

遇到以下情况必须暂停相关实现并记录决策：

- 无法判断某类数据是否包含秘密或终端内容。
- 需要引入第三方密码学、存储或网络依赖。
- record ID、删除语义或冲突策略会影响既有用户数据。
- 需要迁移、重写或清除本地数据。
- MyShell 需求与 Sync Hub v0.1.0 API 不一致。
- 需要关闭 TLS 校验、提高服务端资源限制或把业务字段加入 Sync Hub。

可以继续完成不依赖该决策的调查、测试支架和接口隔离，但不得用猜测固化数据格式或安全行为。

## 14. 参考契约

本文件只摘录 MyShell 接入所需部分。完整、权威的 v0.1.0 参考资料：

- [`SYNC_INTEGRATION.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/SYNC_INTEGRATION.md)：客户端接入、安全、游标、冲突和故障处理。
- [`API.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/API.md)：稳定端点、认证方式、记录信封和资源边界。
- [`ARCHITECTURE.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/ARCHITECTURE.md)：产品职责、数据边界和部署架构。
- [`DEPLOYMENT.md`](https://github.com/yingshu0218/sync-hub/blob/main/docs/DEPLOYMENT.md)：正式部署与秘密挂载要求。

若文档之间出现差异，先以固定版本的实现和测试确认真实行为，再更新文档和 MyShell 决策记录；不要自行扩展协议。
