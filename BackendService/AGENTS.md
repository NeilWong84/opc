# BackendService 工作约定

先阅读根 AGENTS.md、Docs/project-context.md、本目录 README 和 Docs/development/backend-api.md。

- 当前工程为 Python/FastAPI + psycopg 3，同步参数化 SQL；复用 DB 中六条已应用迁移。APPClient 与 FrontendAdmin 均已接入真实 HTTP，生产部署未完成。
- 不改写旧 SQL。新增结构放 DB/migrations，补中文表/字段注释和 id/updated_usr/updated_at；实际维护字段由可信事务及数据库触发器处理。
- 手机/admin 凭证用途隔离，角色和对象访问每次核对。不得将客户端 actor/owner/updated_usr 作为身份。
- 同事务维护不可变版本、双审发布、双方确认、内部质检和客户验收；请求→合作→交付为业务锁顺序。操作 expected_version，不伪造 row_version。
- customer 私有原文附件、显式发布参考和对客交付不同。元数据/名称/计数/下载同权限，不返回本地存储键。
- 大厅默认 internal。2026-10-26 用户已明确新手机流程：按发布版本沟通、客户实际确认范围条款、该承接者一键承接并执行；与管理录入开关 assignment_mode 分开。record_confirmed 仍仅供管理录入既有事实。新流程见 Docs/development/provider-claim-workflow.md，不能把客户确认写成承接者代确认。
- 后续不接入的外部服务返回真实能力边界；不自动完成审核、扫描、转换、通知投递或付款。
- 凭据只放忽略的 .env/环境变量，不输出完整连接串。初始化 CLI 无默认管理员密码。自动测试仍只用隔离库；用户已授权持久演示数据，seed-demo 只操作有标记的本机 opc_dev/opc_integration，不触碰 Accounts，不重置现有密码/角色/业务。
- 修改业务规则后运行相关单元与 scripts/test-postgres.ps1；该脚本仅使用有标记、非5432的临时PostgreSQL18实例。新增API后同步文档响应映射并运行 scripts/export_openapi.py。
- 本地服务默认127.0.0.1:8000，/docs、/redoc和/openapi.json可浏览。生产公开部署需另行配置。
