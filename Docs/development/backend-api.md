# BackendService API 与业务服务契约

2026-10-26 新增客户与承接者独立 `negotiation` 沟通、发布版本条款提案、客户实际确认、承接者一键承接五个接口；承接后立即进入执行中、建立本人归属，服务端保证唯一合作及幂等。原管理 `assignment_mode` 开关仅控制管理录入，不限制此条已经用户确认的新手机流程。具体路径、权限与版本规则见[承接者工作台与自主承接](provider-claim-workflow.md)。下文涉及“接单尚未决定”的表述为历史阶段。

更新：2026-10-16。适用范围为 FastAPI 真实后端。APPClient 本轮切换到 HTTP 数据源，FrontendAdmin 仍为内存 Mock；[手机 Mock 契约](app-client-mock-contract.md) 和 [后台 Mock 契约](frontend-admin-mock-contract.md) 保留历史设计及阶段事实。实际联调使用独立持久 PostgreSQL `opc_integration`，连接与种子流程见 BackendService README。

## 访问与工程入口

2026-10-26 需求分类扩展：`GET /api/v1/mobile/request-classifications` 返回 `platforms` 与 `development_types`，每项包含 `code/name_zh/name_ja/enabled`。草稿及提交原文新增可空 `platform_code`、`development_type_code`，服务端核对有效字典并由外键约束；读取草稿、详情原文及版本历史均返回代码。新增原文版本时，省略字段保留当前分类，显式 null 才清空；答复澄清复制原分类。`GET /mobile/requests` 同名查询参数在本人权限条件内、分页前组合过滤并计算 total；查询值 `unclassified` 匹配空分类，不允许作为持久化字典代码。该分类独立于 `service_code=development` 和技术整理原文 `category`。用户随后要求更新，本机001—008已应用，8001已重启，真实鉴权与分类组合检索验证通过，见[分类记录](../testing/app-client-request-classifications-2026-10-26.md)。

2026-10-25 文件预览契约已扩展到音频、PDF 与本机 Office 转换，手机保存原件使用既有鉴权下载接口。新增 MIME 与错误状态以 OpenAPI 快照及[文件预览说明](app-file-preview.md)为准；下文 2026-10-16 的转换未接入描述为历史阶段。

- [工程、启动与数据库配置](../../BackendService/README.md)
- [Swagger APIDocs](http://127.0.0.1:8000/docs)、[ReDoc](http://127.0.0.1:8000/redoc)、[OpenAPI JSON](http://127.0.0.1:8000/openapi.json)
- [可离线导入的 OpenAPI 快照](../../BackendService/docs/openapi.json)
- [本轮验证记录](../testing/backend-api-2026-10-16.md)

正式契约由已注册路由和 Pydantic 输入模型生成，文档补充返回对象、示例及统一错误结构。服务以参数化 SQL 使用现有 `opc` schema，保留所有既有数据库版本约束、只追加历史、中文注释和维护字段。本次没有改写已应用的六条迁移，也没有建立第二套业务库模型。

## 认证、角色与错误

2026-10-25 手机 `GET /mobile/engagements`、`GET /mobile/threads` 及管理 `GET /admin/threads` 增加可选 UUID 查询参数 `request_id`：在既有账号／角色权限条件内、分页前按当前需求过滤，不扩大权限。手机详情使用该参数查当前需求的合作与反馈，不通过账号全量刷新组装详情。

手机先调用 `POST /api/v1/mobile/auth/login`，后台调用 `POST /api/v1/admin/auth/login`；请求体为 `email/password`。成功返回 `access_token/token_type/audience/expires_at`，后续发送 `Authorization: Bearer <access_token>`。Swagger 的 Authorize 输入令牌原值即可；从手机切到管理操作时应换用管理会话。

所有身份均来自服务端验证的会话；客户端不能提交 `actor_id/updated_usr/customer_id` 伪造操作者。注册禁止额外字段，只授予客户角色。密码 Argon2id 加盐哈希，令牌使用随机 48 字节、数据库仅存 SHA-256 摘要；当前没有刷新令牌或邮箱恢复服务，到期重新登录。账号状态、角色和内部接单授权每次请求重新查询并在事务中加锁。

| 角色 | 主要能力 |
| --- | --- |
| customer + mobile 会话 | 自己的草稿、需求、澄清、合作、对客交付与验收 |
| provider + mobile 会话 + 有效内部授权 | 默认大厅访问、本人当前合作、条款确认与交付；不是正式认证 |
| compliance_reviewer + admin 会话 | 合规审核、需求资料和澄清 |
| technical_reviewer + admin 会话 | 技术整理、技术审核、需求资料、合作阅读 |
| quality_reviewer + admin 会话 | 合作/交付阅读及内部质检 |
| operator + admin 会话 | 发布/下架、合作事实、改派/取消、条款、对客交付发布、文件检查、运营会话 |
| administrator + admin 会话 | 以上管理能力、账号角色授权、启停与审计 |

管理员角色不把 mobile 令牌变成 admin 令牌。停用账号撤销所有会话与内部接单授权，重新启用不会自动恢复接单资格；管理权限不能由本人撤销。首个管理员通过本地 CLI 显式创建；授权的本地演示种子可在标记开发库中建立独立演示管理员，随机凭据只写忽略文件。没有固定默认密码或公开超级用户注册入口。

错误结构：

```json
{
  "error": {"code": "VERSION_CONFLICT", "message": "记录已变化，请刷新后重新操作"},
  "request_id": "服务端生成的请求编号"
}
```

| HTTP | 语义 |
| --- | --- |
| 401 | 缺凭证、会话用途不符、已撤销、到期或停用 |
| 403 | 当前角色或内部授权不满足 |
| 404 | 对象不存在或不属于当前访问范围，避免 UUID 探测泄漏 |
| 409 | 版本冲突、不同载荷重用幂等键、重复决定或业务状态不满足 |
| 413 / 422 | 请求/文件过大，或字段/格式不符合契约 |
| 429 | 登录/注册频率限制；当前限流为单进程内存实现 |
| 503 | 数据库、存储不可用或功能策略关闭 |

校验错误只包含字段位置与错误类别，不回显密码、令牌或原始请求载荷。稳定错误码用于中日语言包映射；客户正文、文件名、消息与交付原文保持原样。通知使用 `template_key + parameters`，客户端应按语言包呈现模板，不能把界面语言当作原文翻译开关。

## 并发、版本和事务

需求/合作/账号/文件修改时发送最新返回的 `row_version` 作为 `expected_version`。需求原文版本、技术范围版本、条款版本、负责人版本和交付版本是不同计数，不可拿它们替代行版本。首次草稿使用 `expected_version=0`；删除草稿通过查询参数传入期望版本。

创建需求、创建合作、提交交付及验收要求 `Idempotency-Key`（1–200 字符，不含空白空键）。键按账号、会话用途和操作隔离，同事务 advisory lock 串行化，同键同载荷返回首次结果，不执行第二次状态变化；同键不同载荷返回 409。消息的 `client_message_id` 为 UUID，在同账号下不能跨会话复用为不同内容。当前幂等结果保留，不自动按七天删除，`expires_at` 只供后续保留策略。

每个请求在独立数据库事务中执行，失败回滚。版本写入、状态变化、通知和 outbox 同事务保存。需求/合作写操作按需求 → 合作 → 交付顺序加锁；数据库触发器与唯一约束继续保护重复合作、历史版本、审核引用与交付验收。连接设置 15 秒语句超时、5 秒锁等待超时；死锁/锁冲突返回可识别 409，客户端刷新或用原幂等键重试。

事务设置可信 `opc.actor_id` 及 `opc.correlation_id`。数据库自动维护 `id/updated_usr/updated_at`；API 不从请求体接收这些审计字段。结构审计不保存密码、token 或消息正文；人工业务原因只在对应历史记录/业务审计中保留。

## 接口分组

完整请求/响应字段以 OpenAPI 为准。路径均以 `/api/v1` 开始。

| 模块 | 路径入口 | 说明 |
| --- | --- | --- |
| 认证 | `/mobile/auth/*`、`/admin/auth/*` | 注册（仅mobile）、登录、me、注销、修改密码 |
| 内部账号 | `/admin/accounts`、`/{id}/roles`、`/{id}/provider-authorization`、`/{id}/status` | 角色与授权分开，保留撤销证据 |
| 草稿/原文 | `/mobile/draft`、`/mobile/requests`、`/{id}/revisions`、`/{id}/withdraw` | 客户本人私有原文与附件 |
| 澄清 | `/admin/requests/{id}/clarifications`、`/mobile/requests/{id}/clarifications/{cid}/answer` | 问答一次答复，后续新增问题；答复生成新原文版本并使旧审核发布失效 |
| 整理/审核 | `/admin/requests/{id}/scopes`、`/{id}/reviews` | 每次改稿新增范围，每范围每类审核一条决定 |
| 发布 | `/admin/requests/{id}/publish`、`/{id}/publication/withdraw` | 同当前范围双审通过，原文私有附件不自动公开 |
| 大厅 | `/mobile/hall`、`/mobile/hall/{id}` | 搜索、计数、详情、参考资料均按当前有效发布过滤 |
| 合作 | `/admin/engagements`、`/{id}/agreements`、`/{id}/reassign`、`/{id}/cancel` | 显式启用后记录已确认负责人；改派必须新条款重新确认 |
| 手机合作 | `/mobile/engagements`、`/{id}/agreements/{version}/confirm` | 客户/负责人逐版本确认后进入执行 |
| 交付 | `/mobile/engagements/{id}/deliveries` | 当前负责人，固定源码包或 HTTPS 仓库+完整commit+归档证据 |
| 质检/对客发布 | `/admin/engagements/{id}/deliveries/{did}/review`、`publish`、`withdraw` | 内部质检与对客发布分开 |
| 验收 | `/mobile/engagements/{id}/deliveries/{did}/acceptance` | 本人对最新合法公开交付明确接受或要求修改 |
| 文件 | `/mobile/files`、`/admin/files`、`/{id}`、`/{id}/download`、`/{id}/preview` | POST 上传；GET 列表：手机只看本人上传，管理运营检查队列；支持 scan_status/limit/offset；元数据/下载/预览逐次授权；运营 `/admin/files/{id}/inspection` 记真实检查结论 |
| 沟通 | `/mobile/requests/{id}/consultation`、`/admin/threads`、两端`/threads/{id}/messages` | 咨询不决定承接；内部会话不对客户开放；参与身份由服务推导 |
| 通知/运营 | 两端`/notifications`、`/{id}/read`、`/admin/dashboard`、`/admin/audit-events` | 站内持久化、运营计数、受限审计 |

分页列表上限 100；需求/大厅含 `total/limit/offset`，其他列表按实际接口返回 `items/limit/offset`，审计按 `before_id` 翻页。不会查询全表后直接返回给手机。

授权会话的消息列表提供 `author_id` 与 `author_name`（发送者当前显示名）；客户端展示名称，原文消息保持不变。不因此开放邮箱、角色或内部账号资料，未获会话访问权限的调用仍返回 404。

## 一条真实业务调用顺序

1. 配置 `opc_app` 并创建首个管理员；客户注册并登录手机会话，指定内部账号通过管理接口创建并分别授予 provider 角色/内部授权。
2. 客户可保存草稿；可选上传资料，pending 原件可以关联私有草稿及 `POST /mobile/requests`，提交此时只有本人及有权后台可见，文件仍不可预览下载。运营从检查队列发现上传并记录实际证据；rejected/failed 不能新增关联。
3. 后台技术整理创建 scope，显式选择拟发布参考资料。合规与技术角色各记录当前 scope 的审核结论；要求补充时创建对客问题，客户答复后新版本重新整理审核。
4. 运营发布当前双审通过版本。授权内部账号查询 hall，只能取得公开整理内容和当前发布参考文件。大厅受众默认内部是本轮开发策略，不是已冻结的公开范围。
5. `OPC_ASSIGNMENT_MODE=record_confirmed` 经显式配置后，运营录入已确认负责人及条款，同一事务自动建立双方可访问的 `customer_project` 会话；再次管理创建同一合作项目会话会返回已有 ID。客户与负责人分别确认最新条款。合作详情包含 `engagement.customer_id` 及每版 `agreements[].scope.reference_files`；引用资料按已审核条款范围和当前文件状态过滤，双方可取得约定范围的原件，原始私有附件不泄漏。`quoted_amount` 返回 JSON 整数 JPY 或 null。没有 `/claim` 抢单或公开竞价接口。
6. 当前负责人提交交付。仓库交付需无凭据 HTTPS URL、40/64 位小写完整 commit 和可取用归档说明；平台不自动抓取/执行仓库，也不由字符串格式证明代码可用。
7. 质检填写真实证据并通过后，运营发布最新交付；客户此时才可读取该交付和文件。未发布内部稿、内部质检证据与运营备注不进入客户视图。
8. 客户明确 accepted 后完成合作并关闭需求；revision_requested 必填反馈，进入修改，再提交新的连续交付版本。旧交付不能代替新版本验收；不存在自动超时通过或付款。

例如客户提交（登录后在 Swagger 输入 Bearer，使用新的幂等键）：

```json
{
  "service_code": "development",
  "original_description": "日本国内向けの予約管理システムを作りたいです。",
  "timing_text": "希望一か月以内",
  "budget_text": "要相談（JPY）",
  "file_ids": []
}
```

前端应从每次返回重新读取 `row_version`，不把示例中的版本写死。完整合成测试调用见 `BackendService/tests/test_integration.py`，这些测试数据仅在隔离测试库构造。用户授权的持久演示数据由 `scripts/seed-demo.py` 显式写入有标记的本机开发库；重复执行不重置密码、权限或业务进度，也不会修改运行服务的接单策略。

## 与数据库及现阶段的边界

37 张表继续分别保存身份、版本、双审、发布、文件关系、合作、交付质检、验收、消息、通知、outbox、幂等和审计。文件字节由本地私有存储保存，数据库只存元数据；Office/PDF 转换尚未运行，因此 `file_previews` 不伪造 ready。站内通知可读取，outbox 尚未有外部发送 worker。

没有新增跨境、其他四条服务线、托管分账、公开供给或认证考核。AI建议、客服工单、外部通知、邮件找回密码、云存储和转换的 Mock 展示不自动成为已实现接口。资金、接单正式机制、正式部署与供应商仍需业务和上线决策。

既有 5432 的 `opc_dev` 未配置或改动；本轮另建受限身份访问的持久 `127.0.0.1:55440/opc_integration` 给手机联调使用。自动后端集成测试仍使用独立临时 PostgreSQL 18，非 sqlite/fake 数据库。手机设备证据由本轮联调记录列明；Vue 管理端联调、生产备份恢复及日本网络验收仍未完成。
