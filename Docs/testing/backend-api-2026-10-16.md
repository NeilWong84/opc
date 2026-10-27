# BackendService API 与服务验证记录

日期：2026-10-16。实现入口：[后端 README](../../BackendService/README.md)、[API 契约](../development/backend-api.md)。

> 本文保留同日较早的后端初版验证。随后 APPClient 已接入真实 API，并增加持久联调库、演示数据与测试；最新结果见 [APP／后端真实数据联调验证](app-backend-integration-2026-10-16.md)。本文的 121 项、82 操作、8000 未就绪及手机仍 Mock 仅代表初版当时状态。

## 实现与验证结果

本轮在原本空的 BackendService 建立 Python + FastAPI + psycopg 3 服务，复用 DB 的既有 PostgreSQL 结构。OpenAPI 导出 **68 个路径、82 个 HTTP 操作**，覆盖身份授权、需求双审发布、合作交付验收、私有文件、会话通知和审计；文档提供请求字段、响应结构、中文合成示例及错误模型。

最终执行：

```powershell
Set-Location D:\OPC\BackendService
.\.venv\Scripts\python.exe scripts/test_database.py -- -q
.\.venv\Scripts\python.exe -m ruff check app tests scripts
.\.venv\Scripts\python.exe scripts/export_openapi.py
```

| 验证 | 实际结果 |
| --- | --- |
| 单元、输入/权限规则及文档契约 | 108 项通过 |
| 真实 PostgreSQL HTTP 集成与并发 | 13 项通过 |
| 全套 | **121 passed, 1 warning，12.27 秒**（不含临时实例初始化/停止时间） |
| Ruff 静态检查 | `All checks passed!` |
| OpenAPI 导出 | `68 paths / 82 operations`，保存 `BackendService/docs/openapi.json` |

单个 warning 来自 Starlette 测试客户端对 httpx 的弃用提示，建议未来迁移 httpx2；此次 HTTP 测试均真实执行并通过，未把警告屏蔽。锁文件记录本次安装版本。实际环境为 Windows、Python 3.14、PostgreSQL 18.4。

## 数据库隔离与权限

测试脚本使用本机 PostgreSQL 18 `initdb/pg_ctl` 建立临时实例，监听 127.0.0.1 的非 5432 端口（本轮 55439），使用随机 `opc_test_*` 数据库和专用归属标记。真实执行 001–006 迁移及校验，不以 SQLite、内存 Repository 或模拟触发器替代。

HTTP 使用 `opc_test_app` 非超级用户角色，核验无 createdb/createrole，无改写迁移/字典/审计历史权限；业务行锁与写入依靠限定权限和既有触发器。普通集成用例在真实连接的外层事务中逐请求 savepoint，强制检查延迟约束，最终回滚。并发测试另建带标记的临时数据库，每个 HTTP 请求独立连接、真实提交，由临时实例生命周期清理合成数据。

对既有 `127.0.0.1:5432/opc_dev` 只尝试过不提供密码的连接，结果为需密码，未执行任何 SQL 或写入。没有更改既有 `opc_dev` 或 `Accounts`，没有向它们写入合成账号、密码或业务数据。专用应用角色创建与首个管理员 CLI 已提供，但未在既有库执行，需用户在本机提供连接凭据。

本轮最终测试实例已停止并清理。首轮调试留下一个已停止目录：`BackendService/.test-postgres/967aa245bb23419586c32781e2fd7c00`。自动审批审查拒绝了清理命令，仅给出 `blocked by policy`；未绕过，目录仍保留在忽略范围内，不是运行中的生产/开发数据库。

## 实际覆盖

| 场景 | 证据与断言 |
| --- | --- |
| 身份用途与权限 | mobile/admin token 不互通；客户无后台角色；内部授权撤销立即拒绝承接操作；账号停用撤会话并阻止登录 |
| 私有需求与发布 | 未审需求列表、搜索及大厅详情不可见；他人不能读原文；同范围两类审核后可发布，客户内部审核理由被剔除 |
| 原文/澄清改版 | 新原文使当前scope清空、旧发布失效；回答保留原文并创建新版本，不能覆盖历史问答或审核 |
| 幂等 | 相同键同内容返回相同结果；不同内容重用键409；数据库只存一次 |
| 完整履约 | 已确认关系录入→双方条款确认→负责人交付→内部质检→对客发布→要求修改→新交付→明确验收完成；旧版/内部稿/他人验收拒绝 |
| 文件真实字节 | 上传计算大小/哈希，pending不能下载；记录检查后可下载原字节；跨客户UUID无权限；仅显式发布参考可给承接者及本人客户访问，原始私有文件不公开 |
| 会话通知 | 咨询不确定承接；内部会话不对客户开放；跨线程复用client_message_id被拒；站内通知只归本人 |
| 并发需求 | 两个真实连接同键同时创建，两个响应相同，数据库仅一个需求/一条幂等结果 |
| 并发合作 | 同需求不同键同时建立合作，只一个201、另一个409，仅一份活动合作和负责人，大厅退出该需求 |
| 日文文本预览 | 90 KB合法UTF-8日文截断为64 KiB预览时保留完整字符，不误报unsupported；中间非法字节仍拒绝 |
| 会话分页 | 最近咨询下架后，`limit=1`第一页仍返回较早有效会话，权限过滤在分页之前执行 |
| OpenAPI | 响应不为空schema，组件引用可解析，合成示例类型与契约匹配，binary/206/多类型预览及统一错误结构正确 |

本轮审查并修复了账号停用仍保留内部接单授权、消息写入前业务关系复核与加锁、文件元数据及下载授权一致性、长UTF-8文本边界和会话分页等问题；最终测试在这些修改后执行。

## 浏览器验证

服务在 `127.0.0.1:8000` 本地启动，已实际打开并查看：

- [Swagger APIDocs](http://127.0.0.1:8000/docs)：六类分组、Bearer Authorize、参数/响应模型可见，`Try it out → Execute` 调用 `/health/live` 返回 HTTP 200，正文 `{"status":"ok","service":"opc-backend"}`。
- [ReDoc](http://127.0.0.1:8000/redoc)：搜索、分组、字段及响应示例实际渲染正常。
- [OpenAPI JSON](http://127.0.0.1:8000/openapi.json)：HTTP 200，健康响应正确引用 `DocHealthLive`，已导出离线快照。

Swagger 最后留在浏览器作为交付入口。文档可访问不代表现有业务库已连接：当前 `/health/ready` 实际返回 **503**（缺专用连接配置）；无令牌访问 `/api/v1/mobile/auth/me` 返回 **401**，不因数据库缺配置错误地返回成功或Mock。

## 尚未验证与未接入

APPClient 和 FrontendAdmin 仍为原内存 Mock，未进行 HTTP Repository 替换、登录恢复或两端真实设备联调。没有生产部署、日本网络/设备验证、容量压测、文件/数据库备份恢复演练或完整跨进程故障测试。

文件字节是本地私有存储；安全检查结论来自人工证据，不是自动杀毒。Office/PDF/表格转换、云存储、邮件恢复/验证、外部通知worker、AI、支付和正式OPC认证未接入。默认接单策略disabled；record_confirmed仅供显式配置后录入已经确定的关系，测试启用该配置不表示业务机制已冻结。

13个集成场景和两个双连接竞争断言不是全量状态空间、所有并发组合或安全渗透测试。外部服务与正式业务边界仍按项目上下文落实。
