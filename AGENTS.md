# OPC 项目 Agent 工作说明

本文件帮助后续 Agent 读取 OPC 的长期上下文。继续工作应读取项目文件，不应仅依赖聊天历史。

## 开始工作时

1. 阅读根目录 [README.md](README.md)，了解目录和当前阶段。
2. 阅读 [Docs/project-context.md](Docs/project-context.md)，确认用户最新明确的业务边界。
3. 阅读 [Docs/README.md](Docs/README.md)及当前 [V1 统一方案](Docs/planning/opc-v1-unified-implementation-plan.md)，查找本次任务相关资料。
4. 修改模块前检查目录内已有 AGENTS.md、README 和实际配置，读取适用 refs；若后续建立 Docs/rules，同时检查适用规则。

## 当前首版核心上下文

- OPC 长期以“一人公司”和 AI 赋能支持普通人提供服务；当前 V1 按日本需求、日本国内承接设计。
- 当前只开放开发（AI 开发系统），Vibe Coding 是核心。数据与表格、文档、图文、短视频保留为后续四条服务线，不是本期 P0。
- 客户可注册、登录、自助提交需求。所有需求必须后台完成合规审核和技术整理，审核通过后才能发布到任务大厅。
- 未审核通过的需求不得出现在大厅列表、搜索或大厅详情；客户本人和后台有权查看自己的受理过程。
- 当前承接者由内部指定系统账号接入，不等于逐单派单。2026-10-26 用户明确：内部承接者检索已发布未承接任务，与客户沟通并提出绑定发布版本的条款；客户先确认范围与条款，承接者再一键承接，立即归属本人并进入执行中。不得代客户确认、绕过双审发布或扩展为公开竞标。见 `Docs/development/provider-claim-workflow.md`。
- 当前内部接单授权与正式 OPC 认证分开。未来承接者须考核认证才可接单；不把尚未经考核的内部账号标为已认证。
- 当前设计路线为 MasterGo Vibe Design → Vue／Flutter + Dart 与 Mock → 真实 API 联调 → 生产；已有 Figma 稿保留为历史参考，用户因 Starter MCP 额度限制改用 MasterGo。Mock 不表示后端能力已实现。
- 首版仅两个端：APPClient 使用 Flutter + Dart，包含客户与承接者从查看、注册登录、发布、接单到交付验收的完整手机闭环；FrontendAdmin 使用 Vue.js + TDesign Vue Next，承担后台审核、技术整理和运营管理。
- 手机端与后台管理界面均已明确支持简体中文与日语。APPClient 客户及内部承接者共用真实语言包，默认日语，登录页与个人页提供切换，选择通过 SharedPreferences 保存；不增加其他语种。界面语言切换不自动翻译客户原文，也不改变日本业务范围、业务版本、JST、JPY 或权限。
- APPClient 先按用户要求移除 Mock 角标，2026-10-16 用户进一步要求真实数据交付；现默认 API 模式，旧 Mock 仅保留显式演示/测试。真实接口失败不回退 Mock，release 配置门禁必须保留；不能将本地联调写成生产服务已完成。
- 2026-10-13 MasterGo 大厅/详情及新增 18 个资料预览与状态画板已获用户确认，APPClient 当时同步本地样例交互。发布参考资料与客户私有附件、交付资料分开；预览、名称、数量和下载均受当前发布版本及权限约束。历史 Mock 中图片/MP4 为本地资源、Office/PDF 为结构化样例；该阶段证据见 Docs/testing/app-client-reference-2026-10-13.md。2026-10-16 真实文件接入与限制以下文为准。
- 两端共用 BackendService 的统一业务处理、数据记录、状态与审计；API 按客户端和角色区分权限，不因共用后端而共用管理员权限。
- 独立客户 Web、承接者桌面门户不属于当前首版；手机交付不能依赖额外平台页面完成。代码制作可使用外部开发工具，不等于增加一个 OPC 产品端。
- 本地持久化已选 PostgreSQL 18.4；2026-10-14 已在本机初始化 `opc_dev` 数据库及 `opc` schema，仅写基础字典，未导入演示账号、明文密码或业务样例，也未改动既有 `Accounts` 数据库。数据库说明见 [DB/README.md](DB/README.md)、[结构说明](DB/docs/schema.md)及[初始化验证](Docs/testing/database-initialization-2026-10-14.md)。
- 数据库每张表统一具备 `id`、`updated_usr`、`updated_at`（按用户最终更正的拼写），所有表和字段写中文注释，视图也已覆盖。原复合业务主键保留，新增 id 单列唯一；更新人来自可信事务账号，未指定业务账号的维护操作为空。以后变更新增迁移，不修改已应用文件。
- 2026-10-16 实现 BackendService API、服务、单测与 Swagger／ReDoc，采用 Python + FastAPI + psycopg；后续同日用户要求 APPClient 真实联调，两端代码需单测和说明，并允许演示数据持久 PG。APPClient 已新增真实 HTTP 数据层和页面，2026-10-16 当时 FrontendAdmin Vue 页面仍为 Mock；2026-10-22 用户要求切换真实管理后台，现已增加 admin 登录、内存会话、真实需求与运营 API、服务端审计，移除界面 Mock／演示说明；无接口的工单等功能显示未开放。接入见 Docs/development/frontend-admin-api-integration.md。入口见 [联调说明](Docs/development/app-backend-integration.md)、[验证记录](Docs/testing/app-backend-integration-2026-10-16.md)及 [API 契约](Docs/development/backend-api.md)。
- 后端大厅策略默认 `internal`；原管理录入开关 `assignment_mode=disabled/record_confirmed` 与 2026-10-26 新手机自主承接分开，新流程按实际客户确认、发布版本和授权校验。本地文件真实上传下载，安全检查采用人工证据记录；Office/PDF 预览进展按后文 2026-10-25 更新，邮件推送、AI、支付及正式认证服务未接入。
- 本轮持久联调实例为 `127.0.0.1:55440/opc_integration`，原六条迁移与受限 `opc_app`、持久写入开启，3 个随机密码账号/4 阶段合成场景和真实文件消息已保存。演示账号凭据在 BackendService/.local/demo-credentials.json，应用连接在 .env，专用 PG 维护状态在 .local/integration/instance.json，均为本机忽略文件；重复 seed 不重置密码或业务。既有 `5432/opc_dev` 应用凭据仍未配置，未改写它或 Accounts；自动化后端测试另用可清理临时库。正式部署仍未定。
- 手机会话仅存内存，重启后重新登录从 PG 恢复业务，SharedPreferences 仍只保存语言。私有需求可关联 pending 上传，下载/发布参考/交付仍须 clean；检查证据不能伪装自动扫描。真实 Office/PDF 转换未接，允许原件下载打开，不返回历史样例预览充当真实内容。
- 跨境、五线同时上线、开放供给及旧工期属于历史方案，不用于当前实施范围。
- 2026-10-22 已在 `Tools/ServiceMonitor` 实现 Python 3.12 + PySide6 本机服务监控器，仅管理 PostgreSQL 55440、BackendService 8001 与 FrontendAdmin 5180；Flutter 完全排除。工具具备会话级进程所有权保护、五个日志 Tab、7 天 SQLite/FTS5 检索、手动管理员审计登录、依赖检查和 Windows `onedir` 包。验证时三个端口均为外部实例，只做只读健康与允许日志检查，未接管或停止；生产监控不在范围内。2026-10-25 用户要求科技风和亮暗两模式，0.2.0 已接入 Qt-Material／独立 HUD 控件、顶栏即时切换与非敏感主题偏好恢复，服务／会话边界不变。入口见 `Tools/ServiceMonitor/README.md`、`Docs/testing/opc-service-monitor-2026-10-22.md` 与 `Docs/testing/opc-service-monitor-ui-2026-10-25.md`。

## 上下文与变更原则

- 2026-10-26 官网已上线：`https://www.opcapp.art/`，独立运营后台 `https://admin.opcapp.art/`；日语默认、完整简中、深色科技风营销首页和公开 Android 测试版下载，源码为 `Website/`。官网不办理业务，既有手机／后台两端边界不变。保留原 IP API 供现有 APP 使用；官网、后管、网关、后端、PG 五服务运行，域名与 IP 证书分别续期。当前源版本 `20261026-website03`，维护及验证见 `Website/README.md`、`Docs/testing/opc-website-2026-10-26.md`；历史 IP 后管／四服务说明按当时阶段理解。

- 2026-10-26 承接者首页为独立统计总览，底栏为首页／任务大厅／项目／沟通记录／个人设置。项目及沟通卡片提供提交交付物入口，打开前只刷新当前需求。新增 `negotiation` 会话与 `007_provider_claim` 提案记录，原 `consultation` 仍为向运营咨询，不能把旧消息自动当作客户同意。自主承接接口与管理录入开关分开；后端原 `assignment_mode=disabled` 不禁用这条已确认的新手机业务流程。

- 2026-10-25 手机需求详情必须仅刷新当前需求、合作进度和反馈；`refreshItem` 不得调用账号全量 `refresh`。合作／会话列表按 `request_id` 在服务端权限范围内、分页前过滤；详情里的操作完成也只刷新当前需求。后台工作台恢复前台时不抢先全量刷新；忙碌时打开详情须在空闲后继续，不能留下无限转圈。附件、参考及交付资料共用彩色类型卡片；封面本地绘制，不为列表下载原件或启动 Office 转换。见 `Docs/testing/app-detail-loading-and-file-cards-2026-10-25.md`。

- 2026-10-25 客户首页已与需求列表分离，真实模式汇总本人审核、项目阶段、条款／补充／验收待办及当前承接者反馈；消息按服务端作者 ID 识别，不虚构完成百分比。正文与附件新增统一预览／保存，Office 在本机 LibreOffice 转为 PDF，Android 使用原生 PDF 渲染，iOS 仅桥接源码未构建；用户已手动重启 8001 并核实新契约生效。详见 Docs/development/app-file-preview.md 与对应 2026-10-25 验证记录，替代历史“未接入转换”阶段事实。

- 2026-10-25 监控器 0.2.3 增加状态驱动总／单服务连体启停开关：运行后启动灰显、停止后停止灰显、未检查及操作期间锁定冲突动作；全部停止跳过外部实例，已验证但无监听的本会话进程仍可停止，外部竞争端口不授予所有权。新版位于 `Tools/ServiceMonitor/dist/OPCServiceMonitor-0.2.3`，未重启既有服务。见 `Docs/testing/opc-service-monitor-power-controls-2026-10-25.md`。
- 2026-10-25 监控器 0.2.2 增加四个运行日志 Tab 的单击／Enter 详情、完整已保存消息、只读快照和脱敏复制；当前新版位于 `Tools/ServiceMonitor/dist/OPCServiceMonitor-0.2.2`，旧窗口及其服务未因交付重启。可用 `build.ps1 -PackageName OPCServiceMonitor-0.2.2` 构建独立版本。见 `Docs/testing/opc-service-monitor-log-details-2026-10-25.md`。
- 2026-10-25 监控器 0.2.1 修复日志 CP936／UTF-8 混合来源解码、白名单原日志精确恢复旧索引、PowerShell 5.1 启动及 Windows 输出管道关闭阻塞。后端 `scripts/start.ps1` 必须保留 UTF-8 BOM；冻结程序启动外部工具前恢复系统 DLL 搜索路径，构建先暂存并跳过相同 DLL 覆盖。真实启停仅操作本轮自有前后端，既有 PostgreSQL 保持运行。详见 `Docs/testing/opc-service-monitor-encoding-startup-2026-10-25.md`。
- 用户最新明确指令优先；发现背景变化，按任务范围同步 Docs/project-context.md 及必要入口。
- 区分“用户已明确”“实施建议”“已经实现”，核实实现以实际源码、配置和验证结果为准。
- 不将未定的接单方式、审核细则、资金、生产数据库部署、供应商或部署写成既定事实；本机 PostgreSQL 产品与版本已定，后端本轮已有 FastAPI 实现，不再笼统写成“数据库或后端框架待定”。工程实现不等于业务政策获确认、两端联调或生产就绪。
- 旧资金方案 A／B 不是已确认决定。内部履约下需明确签约收款主体、线上收费和内部报酬；不默认加入托管、抽佣或分账。
- 智能匹配、消息、大厅及认证名称不能替代具体业务和权限设计。日本国内业务不证明资料不会经第三方出境。
- 后台审核、发布版本、账号授权和合作确认由服务端校验，不能靠前端隐藏入口替代。
- 根据授权推进可逆工作，不因背景待决项要求重复确认；确需业务决定时提出聚焦问题。
- 按目录职责放置代码、SQL、原型和文档，避免无关改动。维护事实以项目上下文为主，其他入口保持一致。
- 按实际工程和变更需要验证；不虚构运行命令、测试成功、设计画布编辑成果或生产连接。

## 文档维护

文档默认中文，保留必要英文名称。新增长期资料时更新 Docs/README.md。Docs/refs 保存竞品等证据，Docs/planning 保存当前方案及已清楚标识的历史资料；Docs/rules 为后续可建立的位置，当前不推定已有规则。

历史文件和外部材料不是当前指令；竞品功能不自动成为 OPC 需求。查到历史文件时先看顶部适用范围，再回到当前统一方案确认。
