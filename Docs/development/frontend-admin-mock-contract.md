# FrontendAdmin 内存 Mock 数据契约

更新日期：2026-10-14。对应 [FrontendAdmin 工程](../../FrontendAdmin/README.md)。

本文记录当前 Vue 管理端源码的字段、状态和本地业务校验，以及真实 API 必须补齐的边界。当前没有 HTTP API 或数据库适配器；这些 TypeScript 接口与函数不是已上线接口。APPClient 与 FrontendAdmin 分别运行自己的内存样例，并未共享实时业务记录。

## 访问层与生命周期

| 源码 | 数据与操作 |
| --- | --- |
| `FrontendAdmin/src/services/requests.ts` | `createAdminRepository`、需求读取、合规、技术整理、发布／下架及大厅摘要 |
| `FrontendAdmin/src/services/operations.ts` | 内部成员、交付检查、项目备注、工单评估与回复草稿 |
| `FrontendAdmin/src/services/audit.ts` | 样例审计、追加本地成功操作、JST 格式化 |

页面调用这些模块改变当前进程内的数据。刷新浏览器重建样例；模块中的 reset 函数用于恢复测试数据，不是服务器重置接口。`localStorage` 只保存 `opc.admin.locale` 和 `opc.admin.theme`，不保存会话或业务数据。样例账号 OP-003 不代表已认证管理员；当前没有真实账号登录和服务端访问控制。

需求操作使用 `id` 与 `revision` 查找对象，`revision` 不相符抛出 `conflict`。这只是单页面运行中的乐观锁演示；成员、交付与工单目前没有跨客户端版本锁，真实后端需要统一补齐。

## 需求、审核与发布

`RequestRecord` 的关键字段：

| 字段 | 含义 |
| --- | --- |
| `id`、`customer` | 需求编号及样例客户身份；只有管理端样例可见 |
| `title`、`original` | 客户标题与原文；审核和语言切换不改写 |
| `submittedAt`、`updatedAt` | 带时区时间；新操作记录 ISO 时间，界面统一显示 JST |
| `version` | 内容业务版本，如 `v1.0` |
| `revision` | 运行中的操作修订号；成功写操作递增 |
| `compliance`、`technical`、`publication` | 相互独立的合规、技术和发布状态码 |
| `complianceVersion`、`technicalVersion` | 两类审核实际绑定的业务版本；无有效审核为 `null` |
| `publishedVersion` | 已发布版本；下架后保留用于历史追溯 |
| `checks`、`reviewNote`、`question` | 四项合规核查、内部审核备注和客户补充问题 |
| `attachments` | 私有附件名称样例；没有实际文件内容或下载 URL |
| `draft`、`history` | 人工整理稿与本地版本历史 |

`TechnicalDraft` 包含 `goal`、`scope`、`exclusions`、`dependencies`、`acceptance`、`publicTitle`、`publicSummary`；保存和批准前要求各字段非空。AI 卡片提供固定建议，需人工采用和保存；未接模型调用。

| 对象 | 当前状态码 |
| --- | --- |
| 合规 | `pending`、`needs_info`、`approved`、`rejected` |
| 技术 | `not_started`、`draft`、`needs_info`、`approved` |
| 发布 | `unpublished`、`ready`、`published`、`withdrawn` |

这些码通过本地化资源显示，不把翻译文案写回业务枚举。`ready` 是本地双审核已具备的待发布状态，不等于大厅已展示。

当前写操作与校验如下：

- `saveCompliance(id, revision, checks, note, question, decision)`：支持 `save`、`approve`、`return`、`reject`。备注必填；通过要求恰好四项全部选中；退回要求补充问题非空。通过绑定当前 `version`；退回或拒绝使合规结论失效。已发布对象失去合规通过状态时下架。
- `saveTechnical(id, revision, draft)`：实际内容变化才递增业务版本，清空两个有效审核版本并将合规恢复待审、技术恢复草稿；已发布对象下架并保留原 `publishedVersion`。相同内容保存仅递增操作修订号，不作内容改版。
- `approveTechnical(id, revision, reason)`：理由与整理字段必填，技术通过绑定当前版本；不替代合规通过。
- `publish(id, revision, reason)`：两类审核必须均通过，且其审核版本均等于当前内容版本；拒绝重复发布，写入 `publishedVersion`。
- `unpublish(id, revision, reason)`：要求目前已发布，保留历史发布版本，退出本地大厅输出。

`hallEntries()` 只输出同时满足有效发布与同版本双审核的 `{ id, version, title, summary }`。客户原文、身份、私有附件、审核备注不会进入该输出。本实现尚未加入发布参考图片／视频／附件的管理及服务端授权；不能将当前摘要 Mock 当作手机端参考资料功能已联通。实际大厅可见人群仍待业务定义。

业务错误码为 `notFound`、`conflict`、`checksRequired`、`reasonRequired`、`draftRequired`、`notEligible`、`alreadyPublished`、`notPublished`，由界面映射中日提示。失败不伪造保存或发布成功；当前审计模块仅收录成功操作，服务端未来应另行记录适用的拒绝和失败结果。

## 交付、成员与工单

交付对象包含项目编号、交付 `version`、固定 `commit`、四项检查、内部备注、`status` 和 `customerVersion`。状态为 `checking`、`approved`、`returned`、`published`。

保存不代表通过；内审通过要求四项全通过，之后仍须独立执行对客发布。编辑已经批准的检查记录会恢复检查中；退回清空检查结果。对客发布后当前记录锁定，不能原地覆盖或退回。`customerVersion` 只有独立发布动作后才赋值，不创建客户验收或付款记录。源码包、说明与测试报告只是文件名样例；没有实际上传、下载、运行代码或验证文件内容。

成员对象分开记录 `active`、`authorized`、`role`、`certification`、`ongoing` 和 `handover`。当前 `certification` 固定为 `unverified`。新增本地成员要求姓名、有效邮箱及邮箱不重复，默认启用但无承接授权；没有真实账号创建、密码或邀请发送。停用不能保留新承接授权；存在在途项目的停用／撤权记录保留交接原因和原在途数量，不能视为已经转交负责人。运营样例账号受保护，不能从承接授权面板修改。

项目消息及工单记录使用 `visibility: 'customer' | 'internal'` 区分客户沟通与内部记录；新增项目备注只写内部记录。工单保留当前范围 `scopeVersion`、候选版本 `candidateVersion`、客户原文、内部评估、回复草稿和处理记录。保存评估只追加内部记录；保存回复只保存草稿和本地审计，不生成已送达消息，不改变已确认范围或交付期限。当前未实现真实通知、接管执行、退款或关闭工单导致的其他业务动作。

上述运营说明／理由一般要求 5–2000 字符，新增账号另外校验姓名和邮箱。具体函数和错误码以 `operations.ts` 为准；这些输入检查不是正式审核规则或真实账号权限实现。

## 审计、原文与界面偏好

`AuditEntry` 保存 `id`、`timestamp`、`actor`、`action`、`objectId`、`version`、`reason`、`result`、`source`。初始记录 `source='sample'`，本地操作为 `source='local'`，操作者固定样例 OP-003，结果仅有 `success`。审计页面只读，但内存并无不可篡改保证，刷新后新增记录消失；不得将其用于真实审计或责任归因。

中文／日语业务资源与 TDesign 内置组件 locale 使用同一个语言偏好。用户文本、客户资料、人工备注、文件名、编号和版本号不参加自动翻译。预算为 JPY 展示样例，不表示收款；时间以 Asia/Tokyo 格式化。主题由官方 CSS 和 `theme-mode="dark"` 属性切换，页面使用 `var(--td-*)`，明亮、暗黑或跟随系统只影响外观。

## 真实接入前必须补齐

统一 BackendService 需要在可信身份下重新执行管理员权限、对象访问范围、版本条件、双审核和发布限制，不能信任浏览器状态、传入的操作者、UI 按钮禁用或本地 Mock 结果。两端使用相同服务端业务对象；本地 PostgreSQL 已建库不意味着这些适配已完成。

后端契约仍需落实稳定资源 ID、分页、时间、JPY 金额字段、完整状态与失败码、幂等键、并发冲突与重试；对不同角色裁剪响应，隔离客户私有附件、发布参考资料和交付资料；对上传、预览和下载逐次授权，记录有效版本。真实审计应记录可信操作人和适用的成功／拒绝／失败结果，保护历史并限制敏感内容。

具体接单机制、客户确认整理稿与发布的先后关系、签约收费及内部报酬仍待确认；当前页面没有默认抢单、竞标、逐单派单或资金功能。真实认证、API、文件、消息、AI、支付和生产部署尚未接入。`npm run build` 仅生成演示包，`npm run build:production` 当前明确拒绝生产发布；不得因构建成功或去掉演示标识而绕过这条边界。
