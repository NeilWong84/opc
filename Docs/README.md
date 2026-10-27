# OPC 项目文档索引

- [iOS 首次 Codemagic 无签名构建](deployment/ios-codemagic-unsigned.md)：第2次构建以 `f3fc2ea` 完成静态检查、388项云端测试和 release 无签名编译；应用及日志已下载、CRC／SHA256 已核验，Podfile.lock 已取回。未签名、真机验证或提交 TestFlight。

- [OPC 官网首版与部署验证](testing/opc-website-2026-10-26.md)：日中营销站、公开 Android 测试包、正式官网／后管域名、静态构建与分阶段部署；[维护入口](../Website/README.md)。

- [Android 云端测试 APK](testing/app-cloud-apk-2026-10-26.md)：后端 `https://43.165.191.156/`、Release 测试包、签名与校验、构建命令。

- [腾讯云东京线上测试环境](deployment/tencent-compose-test.md)：四容器、IP HTTPS、加密凭据、业务快照迁移、备份和回退。
- [部署与迁移验证](testing/tencent-compose-deployment-2026-10-26.md)：40表／42附件一致性、公网原账号登录、真实预览、恢复与续期演练。
- [承接者工作台与自主承接](development/provider-claim-workflow.md)：首页统计、独立任务大厅、客户先确认范围条款、承接者一键承接与交付入口。
- [承接流程验证](testing/app-provider-claim-2026-10-26.md)：权限及并发、手机回归、Android 真实 HTTP 完整流程与普通安装包。

Docs 保存 OPC 从设计到交付的文档，也是后续 Agent 的上下文入口。**当前首版为日本国内业务，只开放开发服务；需求经后台合规审核和技术整理后发布大厅，当前内部指定账号承接，后续考核认证。**

产品范围确定为 Flutter + Dart 手机端与 Vue.js + TDesign Vue Next 后台管理端，两端共用 BackendService；客户与承接者的完整业务闭环在手机端完成，手机与后台界面均支持简体中文与日语。手机默认日语，在登录页和个人页切换并保存；原文、JPY、JST、业务版本与权限不随语言改变。

## 当前实施资料

| 文档 | 用途 |
| --- | --- |
| [V1 统一落地方案 2.7](planning/opc-v1-unified-implementation-plan.md) | 两端边界、审核发布、开发交付、手机真实 API 与持久 PG 联调、验收和待决项；优先阅读 |
| [项目背景与范围](project-context.md) | 用户明确方向、历史变化、目录与待决事实 |
| [需求期望完成日期选择](testing/app-request-completion-date-2026-10-26.md) | 日历选择、中日浅深主题、日期规范保存、草稿兼容与手机端验证 |
| [手机视频预览播放控件](testing/app-video-controls-2026-10-26.md) | 真实视频全屏、进度、快进退、静音与倍速，权限与播放状态保护及验证 |
| [客户需求双语分类与筛选](testing/app-client-request-classifications-2026-10-26.md) | 开发端／开发类型字典、008增量迁移、草稿及版本持久化、组合筛选、8001真实验证与普通包模拟器安装核对 |
| [客户底栏提交入口](testing/app-client-customer-navigation-2026-10-26.md) | 客户五个底栏入口、中间提交需求快捷按钮、状态列表移除重复卡片、返回保留筛选及中日亮暗回归 |
| [手机详情定向读取与附件卡片](testing/app-detail-loading-and-file-cards-2026-10-25.md) | 修复详情读取账号全部数据和持续转圈，当前需求过滤、彩色类型封面、回归与本机计时 |
| [流程演示数据与多格式附件](testing/opc-process-demo-data-2026-10-25.md) | 55440 持久 PG 新增10条需求、评审与交付版本、82条中日文沟通及真实音视频／Office附件；私有存储、演示路线和实际API验证 |
| [OPC 本机服务监控器设计](planning/opc-service-monitor-design-2026-10-22.md) | 已实现的 Python + PySide6 Windows 运维工具设计；管理 PostgreSQL、BackendService 与 FrontendAdmin 启停和日志，明确排除 Flutter |
| [OPC 本机服务监控器实施计划](planning/opc-service-monitor-implementation-plan-2026-10-22.md) | 测试先行的八阶段实现、Windows 打包与真实本机冒烟步骤 |
| [OPC 本机服务监控器验证](testing/opc-service-monitor-2026-10-22.md) | 源码测试、Windows `onedir` 包、平台插件、依赖边界、界面截图与现有外部实例只读检查证据 |
| [OPC 监控器科技风双主题改版](testing/opc-service-monitor-ui-2026-10-25.md) | 0.2.0 Material／HUD 组件、明亮／暗黑即时切换与持久化、最小窗口排版、Windows 截图与新包验证 |
| [OPC 监控器编码与启停修复](testing/opc-service-monitor-encoding-startup-2026-10-25.md) | 0.2.1 CP936 中文日志、旧索引精确恢复、PowerShell 5.1 启动、Windows 管道关闭和真实前后端启停验证 |
| [OPC 监控器日志详情](testing/opc-service-monitor-log-details-2026-10-25.md) | 0.2.2 单击／Enter 查看完整日志、只读快照、脱敏复制、亮暗弹窗与独立版本包 |
| [OPC 监控器启停开关](testing/opc-service-monitor-power-controls-2026-10-25.md) | 0.2.3 总／单服务状态联动、连体开关灰显、执行中互斥、全部停止跳过外部实例及无监听自有进程停止 |
| [MasterGo 设计到真实 API](planning/v1-design-to-production-workflow.md) | 原型交接、Flutter／Vue Mock、接口契约、真实联调与发布 |
| [APPClient 工程与运行](../APPClient/README.md) | Android/iOS 工程、浅深主题、简中/日语与语言保存、真实 HTTP 数据源、配置门禁及历史 Mock 验证 |
| [客户首页改版验证](testing/app-client-customer-home-2026-10-25.md) | 客户项目总览、审核及项目统计、待办、承接者反馈与需求列表分工；中日双语、浅深主题和模拟器验证 |
| [手机正文与附件预览](development/app-file-preview.md) | 图片／音视频／PDF／Office 的真实预览、正文平台文件引用、保存到手机文件、转换配置及能力边界 |
| [文件预览与手机保存验证](testing/app-file-preview-2026-10-25.md) | 原件下载、文档实际转换、权限撤销、Android 原生 PDF 与手机文件 SHA256 核对 |
| [APP 与后端真实数据联调](development/app-backend-integration.md) | 持久 PG 实例、随机演示账号、手机/后台 API 操作、真实文件、运行与测试命令 |
| [APP 与后端联调验证](testing/app-backend-integration-2026-10-16.md) | 两端测试、Android 真实 HTTP 链路、PG/文件持久化、安装包与平台边界 |
| [BackendService 工程与运行](../BackendService/README.md) | Python + FastAPI + psycopg 统一服务、配置、单测与 PostgreSQL 集成测试、Swagger／ReDoc 启动和浏览 |
| [后端 HTTP API 契约](development/backend-api.md) | 认证用途与角色、版本/幂等、需求双审发布、合作交付验收、文件消息、能力开关及未接服务 |
| [后端 API 验证](testing/backend-api-2026-10-16.md) | 本轮单元测试、隔离 PostgreSQL 18 临时库与受限角色的真实 HTTP 流程验证、文档访问证据；不表示两端或生产已接通 |
| [APPClient Mock 数据契约](development/app-client-mock-contract.md) | 历史内存样例及其测试边界；当前真实数据实现以联调说明和后端 API 为准 |
| [FrontendAdmin 工程与运行](../FrontendAdmin/README.md) | Vue 3 + TypeScript + TDesign Vue Next 十类页面、官方内置亮暗主题、中日业务与组件语言、端口 5180、安装构建与测试命令、生产门禁 |
| [管理后台 API 接入计划](planning/frontend-admin-api-integration-2026-10-22.md) | 管理登录、真实业务页面、文案与验证范围 |
| [管理后台 API 联调](development/frontend-admin-api-integration.md) | 5180 → 8001 → 持久 PG、内存会话、真实错误与未开放能力 |
| [管理后台 API 验证](testing/frontend-admin-api-2026-10-22.md) | 当前类型、构建、协议与浏览器检查、真实服务只读验证 |
| [管理后台等比缩放验证](testing/frontend-admin-scale-2026-10-22.md) | 默认 80%、五档偏好、1920×1080 与 125% 显示空间、中日亮暗、组件与滚动弹层定位 |
| [管理后台内部滚动与提示验证](testing/frontend-admin-scroll-2026-10-25.md) | 列表自适应高度、固定表头／筛选／分页、模块内部滚动、即时反馈关闭、铃铛通知中心、重复校验与窄屏工作台 |
| [历史 FrontendAdmin Mock 数据契约](development/frontend-admin-mock-contract.md) | 2026-10-14 原型阶段的数据与规则；当前实现以 API 联调说明为准 |
| [FrontendAdmin 原型落地验证](testing/frontend-admin-2026-10-14.md) | 十页中日亮暗 40 组合、29 项单测、分批 53 项浏览器用例、重点弹窗截图、构建与 Mock 边界 |
| [APPClient 参考资料同步验证](testing/app-client-reference-2026-10-13.md) | 2026-10-13 参考资料交互、282 项测试、70 张 Android 截图、安装包与文件保存/导出的验证证据和平台边界 |
| [数据库工程与初始化](../DB/README.md) | PostgreSQL 18.4、历史 opc_dev 初始化与新增独立持久 opc_integration 联调库；统一迁移与权限 |
| [数据库结构说明](../DB/docs/schema.md) | 业务表、统一 id/updated_usr/updated_at、中文注释、审核发布、交付验收及数据库与应用鉴权边界 |
| [数据库初始化验证](testing/database-initialization-2026-10-14.md) | 2026-10-14 建库迁移、业务约束、统一维护字段和中文注释全覆盖验证；测试数据回滚，不代表生产部署或 APP 联调完成 |
| [APPClient MasterGo 效果图](../Mockup/app-v1-mastergo/README.md) | 原九屏与浅深主题交接；2026-10-13 大厅/详情及新增 18 个资料预览和状态画板已获用户确认，APPClient 已同步本地样例交互，旧视觉复核不覆盖新增修订 |
| [APPClient 暗黑模式](../Mockup/app-v1-mastergo/dark/README.md) | 2026-10-12 首轮 9 个对应暗色画板；当日九屏视觉检查、主题 token、对比度与总览已保存，不覆盖 2026-10-13 的资料修订 |
| [FrontendAdmin MasterGo 双语后台效果图](../Mockup/admin-v1-mastergo/README.md) | 10 类页面 × 简体中文／日语，共 20 个原生可编辑 TDesign 风格画板已创建；自由绘制而非官方组件库实例，视觉复核收尾中，含组件及国际化交接 |
| [日本本地化](planning/v1-japan-localization.md) | 日本业务下的简中/日语界面、日文交付、开发服务、JPY/JST 与原文及资料处理边界 |
| [三方服务与开通准备](planning/v1-third-party-services.md) | 当前账号、邮件、文件、AI、部署与支付待决；开通和验证顺序 |
| [技术选型与开发流程](planning/v1-tech-delivery.md) | 审核版本、大厅隔离、接单权限、开发交付、工程组织和验证 |
| [项目入口](../README.md) | 快速了解项目和目录 |
| [Agent 工作说明](../AGENTS.md) | 阅读顺序、最新边界及文档维护原则 |

## 竞品参考

| 文档 | 用途 |
| --- | --- |
| [企鹅微单与多多项目竞品调研](refs/competitor-research-2026-10-08.md) | 截图与公开资料分析，属于参考证据，不自动成为当前需求 |
| [竞品截图索引](../Mockup/competitors/2026-10-08/README.md) | 14 张用户提供的页面与海报、原图及校验清单 |

## 历史方案

以下保留当时方案及背景，不能作为当前 P0 或工期。与当前方案冲突时，使用本页上方的实施资料。

| 文档 | 历史范围 |
| --- | --- |
| [APPClient Figma 首轮效果图](../Mockup/app-v1-figma/README.md) | 9 个日文手机核心页面、可编辑设计链接、组件与设计假设；截图复核部分完成，因 Starter MCP 额度限制改用 MasterGo，旧稿保留参考 |
| [统一方案 1.1 快照](planning/opc-v1-unified-implementation-plan-v1.1-history.md) | 中日跨境、五线首版与开放供给；含旧资金和工期假设 |
| [前期首版产品规划](planning/opc-v1-plan.md) | 原产品范围及五线并行建议 |
| [原功能范围与验收](planning/v1-functional-scope.md) | 原跨境公开承接流程及五线验收 |
| [原中日国际化](planning/v1-cn-jp-localization.md) | 中日四种供需组合与跨境规则 |
| [原三方服务方案](planning/v1-third-party-services-2026-10-08-history.md) | 原跨境供应商评估，外部信息需在使用前重新核验 |
| [原技术实施方案](planning/v1-tech-delivery-2026-10-08-history.md) | 原五线与跨境架构、验证及估算 |

历史快照中的相对链接可能指向已更新的当前专项，使用时应同时核对文件版本。目录内未登记的 PDF 等导出文件需核对其实际版本，不能据文件名认定已同步最新边界。

## 归档与维护

- planning 保存规划与实施方案；历史内容须显著标识。
- product、design、development、testing、deployment、git、delivery 可按实际工作建立，分别保存需求、设计、工程、验证、发布与交付资料。
- refs 保存证据；rules 为后续适用规则位置，当前不推定已有规则。
- SQL 放根目录 DB，原型与 MasterGo 链接放 Mockup，历史 Figma 资料保留；长期文档新增后登记本页。
- 项目事实更新 project-context.md，当前整合实施口径更新统一方案；记录建议、已定与已实现之间的差别。
