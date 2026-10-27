# OPC 交付平台

OPC 以“一人公司”和 AI 赋能为长期理念，帮助用户承接需求、完成服务并积累交付能力。

源码仓库：[NeilWong84/opc](https://github.com/NeilWong84/opc)，主分支为 `main`。仓库保存源码、依赖锁定文件、数据库迁移和项目文档；本机凭据、数据库及附件数据、依赖目录和构建产物通过 `.gitignore` 排除。新环境按各模块 README 配置环境变量和安装依赖。

**当前 V1 按日本需求、日本国内承接设计，仅开放开发（AI 开发系统）服务。** 客户注册登录后提交需求；后台完成合规审核和技术整理，审核通过后才能发布到任务大厅。当前承接者由内部指定系统账号接入；未来引入考核，通过后成为正式 OPC 认证承接方。

指定账号不等于逐单派单。大厅如何确定最终承接者仍需设计，未审核通过的需求不得在大厅出现。五条服务线长期保留，数据与表格、文档、图文、短视频后续开放。

**首版只建设两个端，共用统一后端：** Flutter + Dart 手机端承载客户与承接者的任务查看、注册登录、需求发布、接单、沟通、交付和验收闭环；Vue.js + TDesign Vue Next 后台管理端处理审核、技术整理、发布管理、账号与运营。手机端与后台均支持简体中文、日语界面；手机端默认日语，在登录页与个人页切换并保存语言设置。两端接入 BackendService 的统一业务服务，按角色和数据权限访问同一业务记录。切换语言不翻译客户原文，也不改变日本业务范围、JPY、JST、业务版本或权限。

## 项目目录

| 目录 | 职责 | 已明确的技术或内容 |
| --- | --- | --- |
| APPClient/ | 手机端完整业务闭环 | Flutter + Dart，面向 Android 和 iOS，包含客户与承接者角色 |
| BackendService/ | 两端共用的后端服务与 API | Python + FastAPI + psycopg；APPClient 与 Vue 后台均接入真实 API |
| DB/ | 数据库脚本与结构说明 | 本地 PostgreSQL 18.4，已初始化 `opc_dev` 数据库及 `opc` schema；初始化、增量 SQL 与验证 |
| Docs/ | 项目全流程资料与 Agent 上下文 | 当前方案、需求、设计、开发、测试、发布和参考 |
| FrontendAdmin/ | 后台管理前端源码 | Vue.js + TDesign Vue Next |
| Website/ | 日中双语公开营销官网 | 原生静态首页、Android 测试包下载页、运营入口与独立 Nginx |
| Deploy/ 与 Tools/Deployment/ | 线上测试部署与运维 | Docker Compose、Nginx IP HTTPS、加密凭据、数据库／文件备份与恢复 |
| Mockup/ | 原型和效果图 | MasterGo 链接、设计交接、参考图与必要导出；保留历史 Figma 资料 |
| Tools/ServiceMonitor/ | 本机开发服务监控器 | Python 3.12 + PySide6；安全启停 PostgreSQL、BackendService、FrontendAdmin，运行日志检索与内存审计会话；排除 Flutter |

## 当前流程与阅读入口

界面开发采用 **MasterGo Vibe Design → Flutter + Dart／Vue 界面与 Mock → 测试环境真实 API → 预发布与生产**。按完整业务场景逐批推进。

- [V1 统一落地方案](Docs/planning/opc-v1-unified-implementation-plan.md)：当前范围与实施入口，版本 2.7，客户确认范围条款后自主承接。
- [项目背景与范围](Docs/project-context.md)：用户明确的方向、历史变化和待决事项。
- [设计到生产流程](Docs/planning/v1-design-to-production-workflow.md)：原型、Mock、契约、真实联调与发布。
- [APPClient MasterGo 效果图](Mockup/app-v1-mastergo/README.md)：2026-10-12 首轮浅深共 18 屏已完成基础视觉检查；2026-10-13 大厅、详情及新增 18 个资料预览/状态画板已获用户确认，APPClient 已同步交互。旧[浅色总览](Mockup/app-v1-mastergo/overview.png)与[暗色总览](Mockup/app-v1-mastergo/dark/overview.png)不覆盖本轮修订。
- [FrontendAdmin MasterGo 双语后台效果图](Mockup/admin-v1-mastergo/README.md)：10 类核心页面 × 简体中文／日语，共 20 个原生可编辑 TDesign 风格画板已创建；自由绘制，视觉复核收尾中。
- [历史 APPClient Figma 效果图](Mockup/app-v1-figma/README.md)：9 个日文手机核心页面与设计假设，保留参考和原复核状态。
- [文档索引](Docs/README.md)：当前实施资料与历史方案。
- [Agent 工作说明](AGENTS.md)：进入项目时的阅读顺序和变更规则。
- [本机服务监控器](Tools/ServiceMonitor/README.md)：源码运行、服务所有权边界、五类日志、Windows onedir 构建与冒烟检查。

- [APPClient 工程与运行](APPClient/README.md)：Flutter Android/iOS 工程、简中/日语、浅深主题、真实 HTTP 数据源与配置门禁。
- [APP 与后端真实联调](Docs/development/app-backend-integration.md)：持久化 PG、随机演示账号、启动与文件/审核/交付操作；[验证记录](Docs/testing/app-backend-integration-2026-10-16.md)记录实际检查与平台边界。
- [BackendService 工程与运行](BackendService/README.md)：后端启动、数据库配置、单元与 PostgreSQL 集成测试、Swagger／ReDoc 浏览入口。
- [后端 API 契约](Docs/development/backend-api.md)与[后端验证记录](Docs/testing/backend-api-2026-10-16.md)：身份隔离、需求审核发布、合作交付、文件、消息、当前能力与接入边界。
- [手机端 Mock 数据契约](Docs/development/app-client-mock-contract.md)：角色、审核发布、交付版本、错误码和服务端实现要求。
- [FrontendAdmin 工程与运行](FrontendAdmin/README.md)：Vue 3 + TDesign Vue Next 十类后台页面、内置明亮/暗黑主题、中日双语、5180 端口启动、真实登录与 API 配置门禁。
- [历史后台 Mock 数据契约](Docs/development/frontend-admin-mock-contract.md)：版本与双审核发布、交付检查、成员授权、内外记录隔离及真实后端接入要求。
- [历史后台实现验证](Docs/testing/frontend-admin-2026-10-14.md)：十页中日亮暗、关键交互、29 项单测、分批 53 项浏览器用例及截图；仍为内存 Mock。
- [数据库工程](DB/README.md)与[结构说明](DB/docs/schema.md)：本机 PostgreSQL 初始化、增量迁移、统一 `id/updated_usr/updated_at` 与中文表/字段注释；实际结果见[数据库初始化验证](Docs/testing/database-initialization-2026-10-14.md)。

## 当前阶段

2026-10-26 [OPC 官网](https://www.opcapp.art/)与[运营后台独立域名](https://admin.opcapp.art/)已上线：默认日语、可切简中，深色科技风长首页及独立 Android 测试版下载页。官网、后管、网关、后端和 PG 五个服务健康，67 项公网检查、后台浏览器登录、Android 模拟器官网直接下载安装及域名证书续期演练通过；后端与 PG 未重启。源码维护见 [Website](Website/README.md)，证据见[官网验证](Docs/testing/opc-website-2026-10-26.md)。官网承担介绍和下载，业务操作仍由现有两个端完成。

2026-10-26 已按用户要求部署腾讯云东京线上测试环境，入口为 [OPC 后管](https://43.165.191.156/#/login)。后管、网关、后端、PG 四个 Compose 服务健康运行；现有本机业务快照已迁移，40 张表及42个真实附件校验一致，原账号密码保留。两地后续写入不会自动同步，已另行生成指向云端的 Android 测试 APK，现有本机安装不自动切换。见[手机云端 APK](Docs/testing/app-cloud-apk-2026-10-26.md)、[运行与回退](Docs/deployment/tencent-compose-test.md)、[部署迁移验证](Docs/testing/tencent-compose-deployment-2026-10-26.md)和[部署命令](Deploy/README.md)。

2026-10-26 承接者手机端补齐独立首页统计、可检索任务大厅、客户／承接者独立沟通、客户先确认范围条款后承接者一键承接，以及项目／沟通列表提交交付物入口。自主承接立即归属本人并进入执行中，受服务端发布版本、双方身份、内部授权、幂等和唯一合作约束保护。见[流程与契约](Docs/development/provider-claim-workflow.md)及[验证记录](Docs/testing/app-provider-claim-2026-10-26.md)。

2026-10-25 已向持久 PG 增加10条开发需求及评审、合作、交付修改验收历史，20个会话共82条中日文消息，30个真实附件记录，包含图片、音频、视频和PDF／Word／Excel／PPT。文件暂存后端私有目录，后期OSS另行接入；刷新两端可读取，本轮8001鉴权下载与隔离验证通过。见[演示路线及验证](Docs/testing/opc-process-demo-data-2026-10-25.md)。

2026-10-25 监控器 0.2.3 修复总／单服务启停状态联动，改用连体开关：已运行禁用启动、已停止禁用停止、操作期间禁止重复点击；全部停止安全跳过外部实例，支持停止无监听的本会话进程。新版独立交付，不重启既有服务。见[启停开关验证](Docs/testing/opc-service-monitor-power-controls-2026-10-25.md)。

2026-10-25 监控器 0.2.2 增加日志行单击详情，完整消息可换行、滚动与复制，支持亮暗主题；新版独立目录交付，现有服务保持运行。见[日志详情验证](Docs/testing/opc-service-monitor-log-details-2026-10-25.md)。

2026-10-25 监控器 0.2.1 修复中文日志编码和 Windows PowerShell 启动错误，并恢复可核对的历史数据库日志；真实前后端启停已验证。入口见[编码与启停修复](Docs/testing/opc-service-monitor-encoding-startup-2026-10-25.md)。

2026-10-25 本机服务监控器升级为 0.2.0：采用 Qt-Material 与独立 HUD 控件，提供科技风服务卡片、图标操作、明亮／暗黑即时切换和本机偏好恢复；服务安全边界及 Flutter 排除范围不变。界面和打包验证见[双主题改版记录](Docs/testing/opc-service-monitor-ui-2026-10-25.md)。

2026-10-22 已完成 [OPC 本机服务监控器](Tools/ServiceMonitor/README.md)：Python 3.12 + PySide6 桌面工具统一查看并安全管理本机 PostgreSQL `55440`、BackendService `8001` 与 FrontendAdmin `5180`，提供精确五个日志 Tab、7 天 SQLite/FTS5 检索、手动管理员审计会话、依赖检查和 Windows `onedir` 包。Flutter APP 明确不在工具范围内。自动化与打包冒烟已通过；验证时三个目标均为外部实例，因此只做健康和允许日志的只读验证，未停止或接管。详见[验证记录](Docs/testing/opc-service-monitor-2026-10-22.md)。

2026-10-22 已按用户要求将 FrontendAdmin 切换至真实管理 API，接入管理员登录、需求审核与发布、项目交付、成员授权、文件和审计，保留简中／日语和 TDesign 内置亮暗主题。页面移除 Mock／演示环境说明，工单等无接口能力明确未开放。当前为本机 `5180 → 8001 → 55440/opc_integration` 的持久化业务链路，生产部署尚未配置。见[管理后台联调](Docs/development/frontend-admin-api-integration.md)与[验证记录](Docs/testing/frontend-admin-api-2026-10-22.md)。下文保留历史阶段。

2026-10-16 按用户要求生成后端 API、服务代码、单元测试及可浏览 API 文档。本轮实现采用 Python + FastAPI + psycopg，覆盖身份、需求双审发布、合作交付验收、私有文件、消息通知与审计；Swagger、ReDoc 和 OpenAPI 随服务提供。大厅默认仅内部授权账号可见，接单策略默认 `disabled`，`record_confirmed` 只用于录入已经确认的合作关系，不代表接单机制已定。原文件支持真实本地字节上传下载，安全检查记录人工证据；Office/PDF 转换、邮件推送、AI 和支付未接入。

用户随后明确要求 APPClient 与后端真实联调，并授权持久化演示数据。APPClient 已新增真实 HTTP Repository 与业务页面，默认 API 模式；后台审核通过管理 API／Swagger 执行，FrontendAdmin 的 Vue 页面仍为 Mock。本轮建立独立持久 PostgreSQL 18.4 实例 `127.0.0.1:55440/opc_integration`，使用受限 `opc_app`，演示账号与四阶段业务数据真实落库；既有 `5432/opc_dev` 和 `Accounts` 未改写。启动与操作见[联调说明](Docs/development/app-backend-integration.md)，测试、Android 构建与未完成范围见[本轮验证](Docs/testing/app-backend-integration-2026-10-16.md)。正式部署仍待落实。以下日期段保留当时的设计、前端与建库进展。

截至 2026-10-12，已建立项目资料和竞品归档，并修订当前首版方案；已创建的 APPClient 首轮 Figma 高保真效果图（9 个核心页面，截图复核部分完成）保留为历史参考。因 Figma Starter MCP 调用额度限制，用户已明确改用 MasterGo 直接创建效果图。

2026-10-12 首轮 MasterGo 画布连接恢复，并按用户确认的自由绘制方式创建 9 个可编辑高保真页面。用户反馈本次升级订阅后出现 MCP 服务入口，随后实测可读写画布；这是本次环境记录，不作为通用套餐要求。9 屏生成记录均为 completed，实际预览均已保存并逐屏完成基础视觉检查，日文、主按钮和关键状态显示正常；首页小节标题换行与详情正文滚动两项细化记录见效果图说明。设计稿仍保留为视觉来源。当前已按浅深 18 屏初始化 APPClient 的 Android/iOS 工程并实现 Flutter 交互 Mock；真实接口和生产接入尚未完成，设计基础视觉检查不替代设备验证。

后台已在独立 MasterGo 文件创建 10 类核心页面的中日双语效果图，共 20 屏，生成记录均为 completed。页面围绕日本国内仅开发服务、内部账号和合规及技术审核通过后发布设计，按 TDesign token 自由绘制，未使用官方 TDesign 组件库实例。文字、对齐修订和全量实际预览复核仍在收尾，尚未宣称全部检查通过；设计画布状态与后续工程实现、浏览器验证分别记录。

2026-10-14 已根据该原型建立 [FrontendAdmin](FrontendAdmin/README.md) Vue 3 + TypeScript + TDesign Vue Next 工程，覆盖十类页面及本地审核、技术整理、版本发布、交付检查、成员和工单交互。按用户要求使用 TDesign 内置明亮/暗黑模式，并支持跟随系统；中日业务资源与组件 locale 同步，localStorage 只保存语言和主题偏好。数据仍为可刷新的内存 Mock，未连接真实后端、数据库、认证、文件、支付或通知；普通构建只生成演示包，生产构建门禁保留。手机端 Flutter Mock 的实现与验证单独记录于 APPClient/README.md。

此前中日跨境、五线同时上线和开放供给规划作为历史保留，不用于当前范围及排期。资金、接单机制、生产部署与供应商仍待明确；手机端启动、构建与测试命令已补充到 APPClient/README.md。

2026-10-12 手机端要求为完整简体中文/日语语言包、登录页与个人页切换、通过 SharedPreferences 保存选择，并移除界面 Mock 角标及标记。当时业务仍使用内存 Mock；移除标记不表示接通生产，release 配置门禁保留。该阶段静态检查与 174 项测试、Android 36 屏双语浅深截图和普通 APK 安装／语言冷启动验证通过；后续真实 API 进展以上文和本轮联调记录为准。iOS 尚未在 Xcode 构建。

2026-10-13 已按确认后的 MasterGo 新稿同步参考资料功能：可选图片/视频/附件、大厅与详情资料入口、多格式预览、真实本地样例视频，以及原样例文件保存、取消重试和原生打开/导出。Office/PDF 预览仍使用样例对应的结构化内容，未接任意文件转换或远程存储；当前语言资源为中日各 472 条，最新测试与 APK 见 [APPClient 工程说明](APPClient/README.md)。

2026-10-14 按用户授权选用本机 PostgreSQL 18.4，已在 `127.0.0.1:5432` 创建 `opc_dev` 数据库及 `opc` schema，完成业务表、约束、视图和字典初始化。仅写入基础字典，没有导入演示账号、明文密码或业务样例；验证中的临时业务数据已回滚，既有 `Accounts` 数据库不在本次变更范围。当时 APPClient 使用内存 Mock，BackendService 尚未接入数据库或提供真实 API；详见[当次数据库验证](Docs/testing/database-initialization-2026-10-14.md)。后端的后续实现与当前接入边界见本节 2026-10-16 更新。

