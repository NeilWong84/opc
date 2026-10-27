# OPC 统一后端

2026-10-16 按项目业务和现有 PostgreSQL 结构实现的 **Python + FastAPI + psycopg 3** 后端。手机与 Vue 后台复用同一业务数据库，凭证、角色与对象权限分开。本轮 APPClient 已接入真实 HTTP 数据源，并增加持久 PostgreSQL 演示数据与联调流程；2026-10-22 FrontendAdmin 已接入独立管理登录与真实业务 API，见[后台联调](../Docs/development/frontend-admin-api-integration.md)。当前实现为模块化单体，正式部署尚未选定。

## 启动与 API 文档

2026-10-26 已新增 [Dockerfile](Dockerfile)，构建上下文为项目根目录以纳入 DB 迁移。腾讯云东京线上测试环境已运行非 root 后端与 Linux LibreOffice，共用网关 HTTPS；本机业务快照已迁移到独立云库，原密码保留，后续本地写入不自动同步。运行、受限 PG、私有文件与回退见[部署说明](../Docs/deployment/tencent-compose-test.md)。本机启动方式继续保留。

2026-10-25 文件预览扩展：图片、音视频、文本和 PDF 直接按真实字节预览，Word／Excel／PPT 使用本机 LibreOffice 转为 PDF；原件下载保持独立鉴权。安装、配置和边界见[手机正文与附件预览](../Docs/development/app-file-preview.md)，验证见[本轮记录](../Docs/testing/app-file-preview-2026-10-25.md)。该更新替代下文历史阶段“未接入文档转换”的说明。

从 PowerShell 执行：

```powershell
Set-Location D:\OPC\BackendService
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock.txt
.\scripts\start.ps1
```

本次已经建立 `.venv`。锁文件记录本次实际安装版本；运行验证环境为 Windows、Python 3.14、PostgreSQL 18.4。

| 地址 | 用途 |
| --- | --- |
| [Swagger / APIDocs](http://127.0.0.1:8000/docs) | 分组查看输入、响应、错误码，使用 Try it out 调用 |
| [ReDoc](http://127.0.0.1:8000/redoc) | 阅读式 API 文档 |
| [OpenAPI JSON](http://127.0.0.1:8000/openapi.json) | 导入 API 客户端、生成 SDK |
| [存活检查](http://127.0.0.1:8000/health/live) | 进程是否可用，不证明数据库连接成功 |
| [就绪检查](http://127.0.0.1:8000/health/ready) | 数据库可连接、六条基线迁移及非超级用户身份 |
| [能力说明](http://127.0.0.1:8000/api/v1/capabilities) | 当前策略与未接入的真实能力 |

默认监听 `127.0.0.1:8000`，停止前台服务使用 Ctrl+C。文档页面不依赖数据库；业务接口连接失败会返回明确的 503，不返回 Mock 成功。Swagger/ReDoc 的浏览器脚本使用 FastAPI 默认 CDN，需要网络；OpenAPI JSON 和源码导出不依赖 CDN。关闭文档可设置 `OPC_DOCS_ENABLED=false`。

## 手机真实联调与持久演示数据

2026-10-25 已按用户要求向同一持久 PG 新增 **10 条流程需求、16 条评审、5 个合作、4 次交付、20 个会话／82 条中日文消息、30 个真实附件记录**。文件包含图片、MP3、MP4、PDF、DOCX、XLSX、PPTX、CSV／文本和最小源码 ZIP。使用原演示账号，刷新两端即可读取；本批命令为 `scripts/seed-process-demo.py`，重复执行只核验，不重置进度。附件继续存私有服务器目录，后期 OSS 另行接入；音频及 Office/PDF 当前下载原件打开。详见[场景、存储与验证](../Docs/testing/opc-process-demo-data-2026-10-25.md)。

本轮已建立独立的 **`127.0.0.1:55440/opc_integration`** PostgreSQL 18 持久实例，使用 `opc.local-integration.v1` 标记、六条原有迁移和受限 `opc_app` 应用角色。数据库目录为 `.local/integration/data`，保留默认 `fsync`、`synchronous_commit`，停止服务不会清理数据。`.env` 保存应用连接，`.local/files` 保存私有原件；既有 5432 的 `opc_dev` 与 `Accounts` 未改动。

在 `BackendService` 目录执行：

```powershell
# 首次创建 / 后续启动同一持久实例；拒绝覆盖不属于该实例的 .env
.\.venv\Scripts\python.exe scripts\provision-local-integration.py start

# 显式初始化或检查已有演示场景；不会重置现有密码、业务进度
.\.venv\Scripts\python.exe scripts\seed-demo.py

# 普通联调服务，接单策略仍为 disabled
.\scripts\start.ps1 -Port 8001
```

演示登录信息仅保存在已忽略的 `.local/demo-credentials.json`，包含 `accounts.customer/provider/admin` 的邮箱和随机密码及 `scenarios` 的业务 UUID。不要把该文件加入版本库或普通 APP 安装包。种子账号邮箱使用 `example.com`，不会发送邮件；凭据只在首次初始化生成。用户后续修改密码后再次 seed 不会改回旧密码，因此该文件中的初始密码可能已过期。

| 场景键 | 可验证的结果 |
| --- | --- |
| `pending_review` | 客户可见私有受理和待答澄清；大厅不可见 |
| `published` | 已双审并发布的整理稿；内部授权账号可查看 MD 参考原件 |
| `awaiting_confirmation` | 已记录合成合作、双方待确认条款、共享项目会话 |
| `awaiting_acceptance` | 双方确认、真实 ZIP 源码原件、合成质检和对客发布后待客户验收 |

种子全量数据经真实业务服务写入同一 PostgreSQL 事务。仅本次进程内启用 `record_confirmed` 创建明确标注的合成关系，不修改 `.env` 或运行服务的默认策略。文件为本脚本可审阅的固定 MD／ZIP 字节，检查证据记录实际 SHA-256 及下载字节比对，明确未运行恶意软件扫描；不能用该 fixture 结论处理未知用户附件。演示确认、审核和质检用于合成流程，不代表真实客户授权或生产验收。重复执行保留用户后来推进的业务状态。

Android 调试连接可用 `adb reverse tcp:8001 tcp:8001`，再按 [APPClient README](../APPClient/README.md) 传 `OPC_API_BASE_URL=http://127.0.0.1:8001` 运行。手机只接收 HTTP 地址，不接收数据库连接串或管理员令牌。Swagger 对应 [8001/docs](http://127.0.0.1:8001/docs)，权限和请求体与 8000 完全相同。

完整 Android 联调自动化由 `scripts/run-mobile-integration.ps1` 启动独立测试服务、生成独立测试账号并调用 Flutter `integration_test/real_api_smoke_test.dart`。该测试服务临时允许记录合成合作，退出恢复进程环境并撤销管理测试令牌；数据保留用于检查。测试 APP 必须在交付前用普通 `lib/main.dart` 构建替换。当前设备执行证据见本轮手机联调验证记录，不以脚本存在代替运行通过。

```powershell
# 要求端口 8002 空闲、已连接 Android 设备及 flutter/adb
.\scripts\run-mobile-integration.ps1 -Device emulator-5554 -Port 8002

# 停止或查看独立 PG，不删除数据
.\.venv\Scripts\python.exe scripts\provision-local-integration.py status
.\.venv\Scripts\python.exe scripts\provision-local-integration.py stop
```

## 连接现有 opc_dev（可选）

既有数据库已存在，本次使用上节独立持久库完成联调，**没有修改现有 opc_dev、Accounts**。如后续希望改用 5432 的既有开发库，需要提供已有专用角色连接配置或执行以下显式引导；已存在 `.env` 时不会覆盖。

首次为后端配置专用数据库角色：

```powershell
.\.venv\Scripts\python.exe -m app.cli configure-local-db
```

命令只连接 `127.0.0.1:5432/opc_dev`，安全提示维护账号密码；核对项目数据库标记和迁移后建立 `opc_app`，写入已忽略的 `.env`。不保存 postgres 维护密码、不输出生成的应用密码、不创建默认管理员。`opc_app` 已存在或 `.env` 已存在会停止，避免覆盖现有凭据；这种情况按 `.env.example` 填写已有专用角色连接串。

应用角色仅使用 `opc` schema：读取字典和业务表、写业务数据和审计、使用序列；无建库/建角色/超级用户权限，无结构变更权限，无修改迁移/字典/审计历史权限。历史业务表的 UPDATE 授权用于 PostgreSQL 行锁，历史保护仍由触发器执行。API 不向客户端暴露数据库连接信息。

配置完成后重启后端，再访问 `/health/ready`。创建首个管理员需要显式执行：

```powershell
.\.venv\Scripts\python.exe -m app.cli bootstrap-admin
```

交互输入邮箱、显示名和至少 12 字符密码。已有有效管理员时命令拒绝重复引导。以后由管理员 API 创建内部账号，分别授予 `provider` 角色和内部接单授权；客户自行注册只获得 `customer`。

## 接口范围与关键规则

2026-10-26 新增手机自主承接：内部承接者与需求客户沟通并提出当前发布版本条款，客户先确认范围条款，承接者再一键承接并进入执行中。新增 `007_provider_claim` 与五个真实接口，原 `assignment_mode` 仅管理录入仍保持既有默认，不再代表新手机承接流程禁用。见[自主承接契约](../Docs/development/provider-claim-workflow.md)。

2026-10-26 新增需求开发端及开发类型双语字典接口 `GET /api/v1/mobile/request-classifications`，客户草稿、提交、原文版本及本人需求列表新增 `platform_code`／`development_type_code`。`GET /mobile/requests` 可按两维组合，在本人权限内、分页前筛选，`unclassified` 只作为查询空分类的保留值。字典在数据库持久化，应用账号只读。首次仅应用008；用户随后要求更新，本轮已备份并补齐 `55440/opc_integration` 的001—008迁移，重启8001后就绪及真实分类接口验证通过。见[分类验证](../Docs/testing/app-client-request-classifications-2026-10-26.md)。

已提供账号注册/双用途登录/注销/改密、角色与内部授权、草稿、需求版本、澄清、技术整理、双审核、发布大厅、合作条款和双方确认、改派、固定源码交付、质检、对客发布、修改/验收、私有文件、会话消息、站内通知、审计及运营统计。接口明细和调用顺序见 [后端契约](../Docs/development/backend-api.md)。

- 仅开放 `development`；UI locale 只有 `ja/zh`，默认 `ja`；报价为整数 JPY，时间返回带时区 ISO 8601，客户端按 JST 展示。
- 手机 `/api/v1/mobile/` 与管理 `/api/v1/admin/` 必须分别登录。令牌仅返回一次原值，数据库只存 SHA-256 摘要；密码使用 Argon2id。停用立即撤销会话和内部接单授权，重新启用必须重新显式授权。
- 修改命令携带最新 `row_version` 对应的 `expected_version`；过期版本返回 409。新需求、合作、交付和验收使用 `Idempotency-Key`；相同键不同载荷拒绝。消息使用 `client_message_id`。
- 大厅默认 `OPC_HALL_AUDIENCE=internal`（启用且有效授权的内部承接者），这是开发安全默认，不替代大厅正式受众决策。可配置 `authenticated/disabled`；所有模式仍执行版本、双审和发布过滤。
- `OPC_ASSIGNMENT_MODE=disabled` 默认阻止新合作录入。经业务确认后可配置 `record_confirmed`，仅录入已经确认的负责人事实，双方仍需逐版本确认；不是自动派单、抢单或竞标政策。
- 新整理/原文版本使旧发布失效；客户私有附件与显式送审发布资料分开。客户只能看到最新、合法对客发布的交付。质检不是客户验收，验收不触发付款。
- 每请求一个短事务；可信会话设置 `opc.actor_id` 和关联请求编号，由既有触发器维护 `updated_usr/updated_at`。写操作使用参数化 SQL、对象授权、固定业务锁顺序和数据库约束。

## 文件与外部能力

原文件真实保存在 `OPC_STORAGE_ROOT`（默认 `.local/files`）的随机私有键下，没有公开静态文件目录。上传默认上限 25 MiB，服务端计算字节数及 SHA-256，初始检查状态为 pending。本人可以将 pending 文件保存到私有草稿或提交为私有需求附件，避免等待运营检查时丢失输入；rejected/failed 不得新增关联。`GET /mobile/files` 返回本人上传，`GET /admin/files?scan_status=pending` 提供运营检查队列，包含尚未关联的原件。

发布参考资料、交付、预览和原件下载仍要求 clean。运营使用受控服务端检查流程取得隔离原件并完成实际检查，再通过 `/admin/files/{id}/inspection` 记录**实际完成的安全检查证据**。该 API 不执行恶意软件扫描，也不允许通过普通下载绕过待检查状态；不能把“点击 clean”当成扫描已完成。

同一权限检查保护元数据、名称、预览和下载；PNG/JPEG/WebP/MP4 经头部类型检查后可原生预览，UTF-8 TXT/MD 通过 JSON 返回最多 64 KiB 文本。Office、Excel、CSV、PPT 和 PDF 可保存/下载原件，预览明确返回 `PREVIEW_CONVERTER_NOT_CONFIGURED`，不伪造转换成功。下载和视频支持底层 FileResponse 的 Range 处理，仍需每次 Bearer 鉴权。

邮件找回密码/邮箱验证、邮件与移动推送、自动扫描、Office/PDF 转换、AI 供应商、支付和正式 OPC 认证未接入。通知已在库内持久化并同事务写 outbox；没有外部投递 worker。没有新增资金政策或工单模型。

## 测试与导出

```powershell
# 不需要数据库的单元测试、文档契约检查
.\.venv\Scripts\python.exe -m pytest -q -m 'not integration'

# 独立 PostgreSQL 18 临时实例，六条真实迁移、非超级用户、HTTP 集成及双连接并发
.\scripts\test-postgres.ps1

# 静态检查、从源码导出 OpenAPI
.\.venv\Scripts\python.exe -m ruff check app tests scripts
.\.venv\Scripts\python.exe scripts\export_openapi.py
```

测试脚本需要本机 PostgreSQL 18 的 `initdb/pg_ctl`（默认安装目录已匹配）。端口优先 55439，冲突时选择空闲端口；拒绝 5432 或无测试标记的库。测试结束回滚业务数据、停掉临时实例并清理经过路径/标记验证的临时目录。真实并发用例使用独立临时数据库和独立事务提交。测试不使用 SQLite 代替 PostgreSQL，不重建现有开发库。

初版结果见 [后端初版验证](../Docs/testing/backend-api-2026-10-16.md)，最新 131 项后端测试、318 项 APP 测试、Android 链路和持久 PG 重启结果见 [真实联调验证](../Docs/testing/app-backend-integration-2026-10-16.md)。`scripts/verify-mobile-persistence.py` 可按 Android 结果只读抓取并比较业务／文件快照。`docs/openapi.json` 为可离线导入的源码快照，接口变更后重新导出。

## 目录与后续接入

| 入口 | 职责 |
| --- | --- |
| `app/main.py`、`config.py`、`database.py`、`deps.py` | 应用、配置、事务、当前身份与角色 |
| `app/auth.py`、`cli.py` | 认证、账号授权与显式本地引导 |
| `app/requests.py` | 草稿、原文、整理、审核、发布与大厅 |
| `app/fulfillment.py` | 合作、条款、负责人、交付与验收 |
| `app/files.py`、`communication.py` | 私有文件、会话、通知和审计 |
| `app/common.py`、`idempotency.py`、`errors.py` | 版本校验、事件、幂等和稳定错误 |
| `tests/`、`scripts/` | 单测、独立数据库验证、启动和契约导出 |
| `../DB/migrations/` | 已有 SQL 迁移，未在本次修改历史文件 |

手机端 Repository 已映射到真实 HTTP 契约，网络失败不会回退演示成功；具体构建配置、单测及设备验证见 APPClient README。后台 Vue 已于 2026-10-22 接入管理 API；运行与边界见 FrontendAdmin README。对外部署前需配置 HTTPS、网关流式请求大小限制、共享登录限流、密钥与文件访问保护、监控、数据库/文件一致备份及恢复。当前按请求连接数据库，尚未做容量/连接池压测；本机联调不代替生产部署与日本网络设备验收。

框架参考：[FastAPI 测试](https://fastapi.tiangolo.com/tutorial/testing/)、[OpenAPI 文档配置](https://fastapi.tiangolo.com/tutorial/metadata/)、[psycopg 事务](https://www.psycopg.org/psycopg3/docs/basic/transactions.html)。
