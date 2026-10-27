# APPClient Mock 数据契约与业务边界

> 历史 Mock 契约。2026-10-16 APPClient 已另加默认真实 API 模式，下文仅说明显式 Mock 实现，不代表当前手机运行的数据源。真实模式见 [APP 与后端联调](app-backend-integration.md) 和 [后端 API](backend-api.md)。

更新日期：2026-10-13。适用范围：`APPClient` 当前 Flutter + Dart 移动端原型实现。

**当前已实现纯 Dart repository 接口与内存 Mock，供 Android／iOS 目标工程的页面和交互使用。未接入真实后端，也未实现与 FrontendAdmin 的审核联动。** 本文记录实际源码中的字段、校验和自动化测试，不将模拟审核、文件标签或验收状态视为真实业务完成。

业务范围仍以 [项目背景](../project-context.md) 和 [V1 统一方案](../planning/opc-v1-unified-implementation-plan.md) 为准。仅开放开发服务；内部授权与未来正式 OPC 认证不同；咨询不决定最终承接；验收不触发支付。

## 1 源码与接口层次

| 文件 | 职责 |
| --- | --- |
| [models.dart](../../APPClient/lib/data/models.dart) | 纯 Dart 模型、枚举、`RepositoryException` |
| [repository.dart](../../APPClient/lib/data/repository.dart) | 可替换的 `OpcRepository` 数据访问接口 |
| [mock_repository.dart](../../APPClient/lib/data/mock_repository.dart) | `MockOpcRepository` 内存实现、合成样例、Mock 场景控制 |
| [reference_models.dart](../../APPClient/lib/data/reference_models.dart) / [reference_samples.dart](../../APPClient/lib/data/reference_samples.dart) | 发布资料元数据、结构化预览、与本地样例原文件对应的合成内容 |
| [reference_download.dart](../../APPClient/lib/core/reference_download.dart) | 可注入文件存储、真实字节保存、分块进度、取消与原生打开/导出 |
| [repository_test.dart](../../APPClient/test/repository_test.dart) | 权限、状态、版本、私有资料与失败重试测试 |

当前契约是 **Dart 方法和返回类型**，没有冻结 HTTP 路由、请求 JSON、分页、认证令牌或后端框架。读取列表及详情为同步读取当前内存状态，写入及登录等操作返回 `Future`。未来真实适配器需要明确异步加载、缓存失效及服务端错误映射，不能把本接口文档当作已上线 API。

数据层不依赖 Flutter 的 `ChangeNotifier`；页面状态更新由 UI 层负责。模型字段不可变，列表是不可修改的快照。对返回对象使用 `copyWith` 不会修改仓库内部记录。

## 2 数据对象

| 对象 | 当前字段与用途 |
| --- | --- |
| `UserSession` | `id`、`name`、`email`、`role`、`active`、`authorized`；`role` 为 `customer` 或 `provider`；`authorized` 仅表示内部承接授权 |
| `RequestDraft` | `description`、`timing`、`budget`、`attachmentNames`；用于提交前的描述、期望、预算意向和附件名称标签 |
| `WorkItem` | `id`、`title`、`description`、`category`、`duration`、`status`、`ownerId`、可空 `providerId`、`version`、可空 `publishedVersion`、两类审核布尔结果、可空 `question`／`latestNote`、`budget`、`createdAt`、附件名称、交付与消息列表 |
| `Delivery` | 整数 `version`、`sourceName`、`sourceRef`、`guideName`、`testName`、`note`、`published`；记录模拟的固定源码标识、操作说明和测试材料名称 |
| `ChatMessage` | `author`、`text`、`sentAt`；当前为纯文本消息，无真实 IM 通道或推送 |
| `TaskReference` | 资料 ID、文件名、类型、实际字节数、asset 路径、可选缩略图、发布版本、预览状态、视频时长和只读页面/工作表/文本内容；独立于私有附件名称与交付材料 |
| `RepositoryException` | 稳定的 `code` 和仓库诊断 `message`；界面通过错误码映射到中日语言包，不直接展示诊断文案，不包含 HTTP 状态含义 |

`WorkItem.version` 是需求范围版本，`Delivery.version` 是交付版本，两者独立。`WorkItem.isPublished` 只表示两类审核通过且 `publishedVersion == version`；是否能进入大厅还需检查状态为 `published` 且尚无负责人。

当前 `budget`、`duration` 是展示与意向字符串，不是金额计算、报价协议或合同期限模型。新记录时间使用 UTC `DateTime`；实际服务端的时间传输及日本时区展示契约尚需真实联调时确定。

需求提交和交付表单的附件保存的是 **名称及标识字符串**，没有上传字节或云端 URL。Mock 会保留本人提交的附件名称，但不会因发布大厅而向未分配承接者暴露这些名称。明确发布的 `TaskReference` 另有真实本地 asset 原文件，可在当前会话权限和发布版本校验后查看、保存或导出；这不是服务端文件授权或云存储实现。

## 3 身份与数据可见范围

| 身份或关系 | 当前可见／可操作范围 |
| --- | --- |
| 未登录 | 不得读取本人列表、大厅或任务详情 |
| 活跃客户 | 查看本人全部受理进度；提交和保存本人需求、回答问题、发送任务消息；对本人最新已公开交付申请修改或验收 |
| 自助注册客户 | 固定创建为 `customer` 且 `authorized=false`，不能通过注册取得内部身份 |
| 活跃且授权的内部承接者 | 浏览双审通过、当前版本已发布且无负责人的大厅摘要；查看本人已分配项目；对已分配项目提交交付和消息 |
| 未分配的内部承接者 | 可对大厅案件咨询；咨询消息按账号与案件隔离；咨询不修改负责人或执行状态 |
| 停用账号 | 阻止业务读取、写入与再次登录 |
| 撤销授权的内部账号 | 阻止大厅、受限详情、已分配项目读取和成果提交；不会冒充正式认证状态 |

所有普通业务方法在 repository 内再次检查身份、归属、状态和版本。详情拒绝与不存在使用 `not_found`；无内部授权时先验证权限再查找 ID，避免通过不同错误推断案件是否存在。

客户读取详情和本人列表时会过滤 `published=false` 的交付。大厅列表、搜索和未分配详情会过滤私有附件、问题、进度备注和普通任务消息；只有咨询发起人能在该案件详情读取自己的咨询记录。任务内普通消息仅允许所属客户或已分配承接者发送。

模拟延迟期间会话发生改变时，旧操作返回 `session_changed`，避免将旧账号表单写到新账号。真实服务端还必须校验令牌、账号停用与授权撤销，不能依赖 UI 隐藏按钮或本地状态。

## 4 状态与主要方法

| `WorkStatus` | 当前含义 |
| --- | --- |
| `needsInfo` | 等待客户补充 |
| `reviewing` | 等待后台用途合规确认与技术整理 |
| `published` | 当前范围版本已通过双审并发布大厅 |
| `developing` | 已确定负责人、开发中；当前来自合成样例 |
| `internalReview` | 承接者已提交交付，等待内部检查 |
| `awaitingAcceptance` | 最新交付已对客户公开，等待客户验收 |
| `revision` | 客户提交了对当前公开交付的修改反馈 |
| `completed` | 客户已完成指定最新公开版本的验收 |

| 方法 | 实际行为与限制 |
| --- | --- |
| `login(email,password)`／`register(name,email,password)` | 返回 `Future<UserSession>`；Mock 邮箱不区分大小写；注册密码至少 8 字符，仅为演示校验 |
| `logout()` | 清除当前会话；同一仓库实例中的账号、业务记录与草稿仍保留 |
| `myRequests()` | 客户读取本人记录；承接者读取已分配且发布版本有效的项目 |
| `hall({query,category})` | 在审核、版本和发布状态过滤后执行搜索／分类；未审记录不出现在结果或计数中 |
| `detail(id)` | 返回经过角色和关系过滤的单条记录；无权访问时抛异常 |
| `references(taskId)` / `reference(taskId,referenceId)` | 先检查任务可见性，再只返回与当前有效发布版本一致的资料；不存在、未公开、旧版资料统一不可读，不泄漏名称、计数和缩略图 |
| `prepareReference(taskId,referenceId)` | 按 Mock 延迟演示资料准备/重试；等待前后复核资料访问权限，不执行任意 Office/PDF 原文件转换 |
| `saveDraft(request)` | 按客户 ID 暂存；允许不完整描述；最多 4,000 字、5 个非空附件名称 |
| `submitRequest(request)` | 要求 10–4,000 字描述、非空期望时间与预算意向；从第一句生成短标题；创建 `reviewing` 记录并清除该客户草稿，不直接公开 |
| `answerQuestion(id,text)` | 仅本人 `needsInfo` 记录可提交；范围版本加一，撤销审核与发布结果，进入 `reviewing` |
| `consult(id,text)` | 仅当前有效内部账号对大厅案件发送咨询；不领取、不分配、不改变执行状态 |
| `sendMessage(id,text)` | 仅所属客户或已分配承接者可发送；文本 1–4,000 字 |
| `submitDelivery(id,delivery)` | 仅活跃授权且已分配的承接者，在 `developing`／`revision` 状态提交；版本必须为上一交付加一；必填源码、固定标识、说明、测试材料与备注；强制 `published=false`，进入 `internalReview` |
| `requestRevision(id,version,text)` | 仅本人 `awaitingAcceptance` 项目，匹配最新已公开交付版本，进入 `revision` |
| `acceptDelivery(id,version)` | 同样检查归属、状态及最新公开版本；完成后进入 `completed`，不执行付款、退款、托管或分账 |
| `reset()` | 恢复初始合成数据并退出登录；清除注册账号、业务变更、草稿、咨询和失败注入状态 |

`sourceRef` 当前只检查非空，并拒绝单独的 `main`、`master`、`HEAD`、`latest` 标识；这不是对真实仓库提交、源码包完整性或校验值的验证。提交的 `published=true` 不会绕过内部检查。旧交付不会替代新版本通过；修正或内部检查期间不能继续验收此前公开版本。

当前没有从新发布需求自动进入 `developing` 的普通业务方法。已分配项目由合成样例提供，避免把咨询入口或内部账号授权擅自实现为抢单、竞标或逐单派单规则。后续确认承接机制后再补正式操作。

## 5 稳定错误码

以下是当前 Mock 实际抛出的代码。UI 可按代码处理状态，但不应把日文错误文案当作机器协议。

| 错误码 | 含义 |
| --- | --- |
| `unauthenticated` | 当前没有登录会话 |
| `session_changed` | 操作等待期间会话发生变化，需在当前账号重新发起 |
| `account_inactive` | 账号已停用 |
| `customer_required` | 该操作要求客户身份 |
| `provider_required` | 该操作要求有效的内部身份和授权 |
| `not_found` | 记录不存在，或当前账号不能访问 |
| `invalid_credentials` | Mock 邮箱或密码错误 |
| `invalid_name` | 注册姓名为空或超过 80 字 |
| `invalid_email` | 注册邮箱格式不符合当前检查 |
| `invalid_password` | 注册密码不足 8 字符 |
| `email_exists` | 规范化邮箱已存在 |
| `invalid_description` | 描述不满足当前长度限制 |
| `invalid_request` | 提交时缺少期望时间或预算意向 |
| `invalid_attachments` | 附件名称数量超限或含空名称 |
| `invalid_message` | 消息或补充内容为空／超过 4,000 字 |
| `invalid_delivery` | 交付所需字段不完整 |
| `source_not_fixed` | 使用了单独的可变分支／最新版标识 |
| `state_conflict` | 当前状态不允许该操作，含重复提交／重复验收 |
| `version_conflict` | 提交版本不是下一版本，或验收／修改版本已过期 |
| `network_unavailable` | 人工触发的一次 Mock 失败；没有发生真实网络请求 |

## 6 演示账号、数据与生命周期

| 账号 | 密码 | 角色 |
| --- | --- | --- |
| `customer@opc.demo` | `demo1234` | 客户：田中 |
| `member@opc.demo` | `demo1234` | 活跃且具有内部授权的承接者：佐藤；不是 OPC 正式认证 |

合成记录为 `REQ-1042` 待补充、`OPC-1028` 开发中、`OPC-1017` 待客户验收，以及大厅案件 `DEV-1036`、`DEV-1039`。这些编号分别展示不同阶段，不代表一笔需求同时具有多个状态。

Mock 构造默认延迟 350 毫秒，测试可设置 `delay: Duration.zero`。设置 `failNext=true` 后，下一个异步操作在写入前抛出一次 `network_unavailable`，随后可重试。读取本地列表／详情不会制造真实网络行为。

业务数据只存在于当前仓库实例内。退出登录不会删除同一实例的草稿；重启进程、创建新仓库实例或执行 `reset()` 会恢复初始状态。APP 尚未连接业务数据库或跨设备同步服务；2026-10-14 已另行建立[本地 PostgreSQL 结构](../../DB/README.md)，但本 Mock 的读写仍不使用它。语言设置通过 SharedPreferences 单独持久化，保存的样例文件在设备文件区或用户选择的导出位置，不表示业务数据已在后端持久化。账号密码保存在演示内存结构中，不能用于真实身份系统。

以下方法只存在于 `MockOpcRepository`，**不属于普通业务 `OpcRepository` 的审核接口**：

| 开发场景方法 | 模拟效果 |
| --- | --- |
| `simulateReview(id,{approve})` | 对待审／待补充记录同时模拟两类审核通过并发布，或退回补充 |
| `simulateDeliveryPublication(id)` | 对内部检查中的最新交付模拟检查完成并向客户发布 |
| `simulateAccountAccess({active,authorized})` | 改变当前样例账号的活跃／授权状态，供停用及撤权测试 |

这些方法没有真实管理员身份、人工审核、审核记录或管理端联动，只能用于清楚标识的开发演示。真实适配器必须将管理权限、审核人、审核版本、发布与审计留在服务端实现。

## 7 已执行验证

验证日期：2026-10-12。运行环境：Windows、Flutter 3.35.5、Dart 3.9.2。命令在 `APPClient` 目录执行。

```powershell
flutter test test/repository_test.dart
dart analyze lib/data test/repository_test.dart
```

首轮 **19 项仓库测试全部通过**；随后针对撤权账号的 ID 存在性泄漏及异步会话切换补充 2 项测试，最终运行结果为 **21／21 通过**。同一范围的 `dart analyze` 返回 `No issues found!`。

覆盖内容包括匿名访问、自助注册身份、客户数据隔离、未审记录的大厅列表／搜索／详情隔离、双审与发布版本、私有附件过滤、草稿隔离、补充后复审、咨询不接单、未发布交付隐藏、内部检查后公开、修改后新版本验收、旧版本拒绝、重复并发提交、停用与撤权、会话切换、错误重试、不可变返回值和重置。

这些是本地仓库自动化测试，不证明 Android／iOS 真机、渠道签名、真实文件收发、FrontendAdmin 联动、生产权限或日本网络验证通过。应用整体构建与界面验证以对应工程说明和实际执行记录为准。

## 8 真实接入时必须落实

正式后端需要重新校验角色、归属、账号状态、双审有效版本、发布可见范围、负责人、交付发布和验收版本，并保存审计证据。读取大厅、搜索和详情必须一致过滤，不能只在手机 UI 中隐藏待审记录。

需求原文、技术整理稿、审核历史、公开摘要、私有材料和内部备注需要形成明确的服务端对象与访问策略。当前紧凑的 `WorkItem` 并不代表已完成这些生产对象的存储设计。

真实业务文件仍需要上传、服务端授权下载、固定版本可取得、检查与校验、授权失效和保留规则；当前本地样例保存与导出不能代替这些能力。真实消息需要持久记录和传递状态；异步提交及多设备并发需要服务端幂等与事务保障。当前内存中的重复状态检查不能替代这些能力。

真实认证、持久化、通知、管理端联动、付款及最终承接方式都未由本 Mock 实现或定案。后续以统一后端契约与业务确认推进，不从模拟成功反推生产能力已经存在。

## 9 参考资料预览与原文件边界

参考资料页面可查看 PNG 原图并播放真实本地 MP4。文档、PDF、演示文稿、工作表和文本的应用内内容来自 repository 提供的只读结构化 fixture，与本轮样例文件内容对应；没有从任意原文件解析、执行宏/公式或调用转换服务。DOC/XLS/PPT 类型可用 fixture 测试，但未伪造其二进制样例，生产转换方案仍待选型。

`assets/references/manifest.json` 记录实际字节、SHA-256、图片尺寸、页数、工作表及视频时长。本轮样例文档/PDF/幻灯片各 3 页、字段表 3 个工作表；视频是由两张原创截图组成的 8 秒操作示例，不是网络视频或真实业务录屏。报价表包含可由表格软件计算的原生公式，应用内 fixture 仅显示已知样例结果。资源不含真实客户资料；原图复制自 `Mockup/task-reference-assets`，未修改原图。

`ReferenceDownloadController` 注入字节读取函数、文件名、MIME、`authorize` 与 `ReferenceFileStore`，暴露 `idle/loading/completed/cancelled/failed`、进度、保存句柄和错误。读取前后、每块写入、原子完成前后及打开/导出都复核权限；取消或异常会清理未完成文件，不能返回不存在文件的成功句柄。状态成功表示应用私有文件真实落盘，不表示用户已导出到文件应用。

Android 原生 channel 用应用专属目录与 `.part` 文件，完成长度校验后原子改名。`FileProvider` 只暴露该参考文件目录并授予临时读取权；系统 `ACTION_VIEW` 打开资料，`ACTION_CREATE_DOCUMENT` 由用户选位置后再次向 Dart 复核权限，再复制实际字节。没有查看器或取消选择均不能显示打开/导出成功。

iOS 原生实现使用 QuickLook 打开本地文件；选择文件夹后再次复核权限，通过 security-scoped URL 写入临时文件并原子改名，保留原文件名、避免覆盖重名文件。当前 Windows 环境没有执行 Xcode 构建或 iOS 设备验证。已经导出到其他应用的文件副本不受本地权限撤销控制，不能宣称撤权后已回收副本。

本轮资源渲染已检查表格、幻灯片与内嵌日文字体 PDF；DOCX 专用渲染器因缺少 LibreOffice 未完成视觉检查。下载控制器的可注入存储测试不能代替 Android/iOS 系统文件选择器与真实设备验证，最终执行结果应查对应验证记录。
