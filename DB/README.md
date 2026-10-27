# OPC PostgreSQL 数据库

2026-10-26 新增 `007_provider_claim.sql`：客户／承接者独立沟通、发布版本条款提案及客户实际确认后自主承接。新表具有统一维护字段、全中文注释、不可变条款／确认与审计保护，不修改已应用的基线 SQL。见[自主承接说明](../Docs/development/provider-claim-workflow.md)。

2026-10-14 已在本机 PostgreSQL **18.4** 创建数据库并执行迁移。2026-10-16 已基于该结构实现 [BackendService](../BackendService/README.md)，随后 APPClient 接入真实 HTTP；FrontendAdmin Vue 页面仍待接入。

**本轮真实手机联调使用独立、持续保存的 `127.0.0.1:55440/opc_integration`，沿用下述六条迁移和 `opc` schema。** 使用受限 `opc_app`，数据库目录 `BackendService/.local/integration/data`，持久写入开启；合成账号、四阶段业务、消息和文件元数据已按用户最新授权入库，真实文件字节在 `BackendService/.local/files`。重启不清空，重复 seed 不重置已推进场景。命令与凭据位置见 [联调说明](../Docs/development/app-backend-integration.md)，结果见 [验证记录](../Docs/testing/app-backend-integration-2026-10-16.md)。既有 `5432/opc_dev` 和 `Accounts` 没有改写；下文 2026-10-14 连接／数据量描述仍只针对历史 `opc_dev`。

既有 `opc_dev` 的应用连接凭据尚未配置，维护账号不用于运行应用。后端真实迁移、受限应用角色和 HTTP 业务流程的验证使用独立 PostgreSQL 18 临时测试库，结果见[后端验证记录](../Docs/testing/backend-api-2026-10-16.md)，不改写下文 2026-10-14 的本机初始化事实。

## 连接

2026-10-25 已在上述 `55440/opc_integration` 追加10条合成开发需求、16条评审、5个合作、4次交付、20个会话／82条中日文消息和30个真实附件记录；原8条需求及账号密码保留，六条迁移未变。PG保存元数据及业务关联，原件保存在后端私有目录，OSS为后续计划。场景和实际验证见[本批说明](../Docs/testing/opc-process-demo-data-2026-10-25.md)；以下5432连接仍为原开发库。

| 项目 | 值 |
| --- | --- |
| 主机 | `127.0.0.1` |
| 端口 | `5432` |
| 数据库 | `opc_dev` |
| Schema | `opc` |
| 本地维护用户 | `postgres` |
| 密码 | 使用本机已有 PostgreSQL 密码；不写入仓库 |
| 编码 / 排序 | `UTF8` / builtin `C.UTF-8` |
| 数据库时区 | `UTC`；日本业务由界面按 JST 显示 |

在现有数据库管理工具中刷新数据库列表，打开 **opc_dev → Schemas → opc → Tables**，即可看到 37 张表和 2 个视图。SQL 请使用 `opc.accounts` 等完整表名。现有 `Accounts` 数据库未修改。

## 结构与初始化内容

2026-10-26 新增 [008_request_classifications.sql](migrations/008_request_classifications.sql)：5 项开发端、6 项开发类型的中日双语字典，草稿与原文版本新增可空外键分类，原服务线与技术整理的原文 `category` 不变。首次仅向 `55440/opc_integration` 应用008；用户随后要求更新，本轮创建本机备份并补齐007，现001—008均已应用。更新前后18条需求／12个账号、24条原文版本和10个合作数量一致，存量分类不自动补写。已有迁移文件和5432数据库未修改，当前应用账号对新字典仅有SELECT权限。详见[实施与验证](../Docs/testing/app-client-request-classifications-2026-10-26.md)；下文37表等数字仍为2026-10-14的基线历史。

账号和授权、客户需求和原文版本、技术整理和双审核、发布参考资料、合作与承接历史、交付质检和验收、会话消息、文件预览状态、通知、幂等和审计分别存表。详见 [数据结构说明](docs/schema.md)。

2026-10-14 仅初始化 **7 个角色字典项 + 1 个开发服务项**，当次共 6 条迁移记录。业务表为空，没有导入 APP 的演示邮箱/密码、任务或附件；没有创建默认后台管理员。文件表存私有资源元数据；后端当前文件接入能力见本文后续接入段。

## 中文注释与统一字段

37 张表及其 **361 个字段**、2 个视图及其 **26 个字段**均已写入 PostgreSQL 中文注释。注释解释业务用途、状态代码、版本关联、单位和空值含义；在数据库客户端刷新结构后即可查看。

每张表统一具备以下字段，最终名称为 `id`、`updated_usr`、`updated_at`：

| 字段 | 类型与规则 |
| --- | --- |
| `id` | 非空、单列唯一、创建后不可修改；15 张原本没有此字段的表新增 UUID。已有主键和复合业务约束保留，审计表沿用原有自增整数标识 |
| `updated_usr` | 可空 UUID，关联 `accounts.id`；由数据库从可信后端事务的 `opc.actor_id` 自动记录本次写入账号。未指定业务账号的本地维护操作为空，不沿用上次修改人 |
| `updated_at` | 非空带时区时间戳，在新增或更新时由数据库自动写入；既有值保留，原先缺失该列的存量记录以补建时刻初始化 |

业务 SQL 应省略 `updated_usr` 和 `updated_at`，由后端验证身份后设置事务归因。历史版本、审核决定、消息和审计仍遵守只追加限制，新增维护字段不允许改写历史。未来新增表也应遵循这些字段和中文注释要求。

## 可重复执行

从项目根目录 `D:\OPC` 使用 PowerShell：

```powershell
.\DB\scripts\Initialize-Database.ps1 -Verify
```

脚本会安全提示输入本机 PostgreSQL 密码；也支持调用进程已设置的 `PGPASSWORD`，不会把密码放入命令参数或 SQL 文件。默认使用 `C:\Program Files\PostgreSQL\18\bin\psql.exe`。如安装目录不同，可传 `-PsqlPath`；连接固定为本机 `127.0.0.1:5432/postgres`，不用于远程生产部署。

行为：

1. 目标不存在时建立 UTF-8 数据库，并写入 `opc.local-development.v1` 归属标记。
2. 已存在但没有此标记的数据库立即拒绝，不接管、不删库、不覆盖。系统库和 `Accounts` 不允许作为目标。
3. 所有已应用迁移先核对 SHA-256；改变历史文件或缺失历史版本会停止执行。
4. 每个新迁移和迁移记录在同一事务内提交，使用事务锁串行执行；失败回滚该迁移。已经成功的前置迁移保留，下次继续。
5. `-Verify` 在事务中构造测试记录，验证约束后回滚，不留下演示数据。PostgreSQL 序列取号不会随回滚撤销，序列出现空号属正常情况。

首次创建数据库与写标记之间无法共用事务；若进程恰好中断，脚本会拒绝接管无标记库。应先人工核实归属和内容，再恢复，不能通过自动删除重建解决。

## 文件入口

| 文件 | 用途 |
| --- | --- |
| [scripts/Initialize-Database.ps1](scripts/Initialize-Database.ps1) | 本地初始化、校验迁移、可选验证 |
| [bootstrap.sql](bootstrap.sql) | 建库、归属检查、schema 和默认访问限制 |
| [migrate.sql](migrate.sql) | 每次迁移的事务、校验值和版本登记 |
| [migrations/001_core.sql](migrations/001_core.sql) | 表、外键、CHECK、索引 |
| [migrations/002_integrity.sql](migrations/002_integrity.sql) | 发布/交付核心约束、历史保护、审计和大厅视图 |
| [migrations/003_catalog.sql](migrations/003_catalog.sql) | 双语角色与开发服务字典 |
| [migrations/004_scope_activation.sql](migrations/004_scope_activation.sql) | 已激活范围版本防回退，允许待激活整理稿独立存在 |
| [migrations/005_standard_metadata.sql](migrations/005_standard_metadata.sql) | 统一记录标识、更新用户、更新时间及自动维护规则 |
| [migrations/006_chinese_comments.sql](migrations/006_chinese_comments.sql) | 全部表、字段、视图的中文注释与覆盖检查 |
| [tests/verify.sql](tests/verify.sql) | 事务回滚的业务结构验证 |
| [tests/verify_metadata.sql](tests/verify_metadata.sql) | 统一字段、中文注释、更新归因及历史保护验证；`-Verify` 会一并执行 |
| [tests/inspect.sql](tests/inspect.sql) | 只读检查版本、表数量、字典、数据量、PUBLIC 权限及注释覆盖 |
| [验证记录](../Docs/testing/database-initialization-2026-10-14.md) | 本机执行结果与尚未验证范围 |

已有迁移已实际应用，后续升级添加 `007_*.sql` 等顺序文件，不能修改旧文件来更新现有库。

## 后续接入

BackendService 本轮已实现认证、手机/管理用途隔离、对象级授权、事务状态推进、文件和两端 API，采用 FastAPI + psycopg；现有前端仍待接入。既有 `opc_dev` 仍需配置专用最小权限应用身份与连接凭据，不能使用维护账号或把数据库连接信息发给 APP。正式部署、备份恢复与生产供应商另行落实。

当前文件服务可上传下载真实本地字节，安全检查保存人工证据；Office/PDF 转换与生产存储未接入。大厅视图仍只提供发布过滤基线，API 在其上校验受众和对象权限，默认仅内部授权账号可见。接口和配置见[后端 API 契约](../Docs/development/backend-api.md)，结构边界见 [数据结构说明](docs/schema.md#5-审计与身份边界)。
