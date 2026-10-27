# FrontendAdmin V1 MasterGo 双语后台效果图

更新日期：2026-10-14（补充 Vue 工程交接；原设计生成记录日期保持 2026-10-12）。设计状态：**20 个原生可编辑页面已创建，视觉复核收尾中；尚未宣称全量检查通过。**

本稿为 Vue.js + TDesign Vue Next 后台管理端设计，简体中文 `zh-CN` 与日语 `ja-JP` 各一套对应画板。10 类核心页面 × 2 种语言，共 20 屏均已有 `completed` 生成记录。当前正在修订文字与对齐、清理失败稿并复核全量实际预览；生成完成不等于视觉复核全部通过。

[打开后台 MasterGo 文件](https://mastergo.com/file/207044528770731?page_id=M) · [组件与国际化映射](component-map.json)

后台文件 ID 为 `207044528770731`，页面 ID 为 `M`，与 [APPClient 设计文件](../app-v1-mastergo/README.md)分开。后续以实际画布、最终 `canvas-state.json` 和对应预览记录为准；本页不以提交请求数推算完成数量。

## 设计方式与视觉基线

使用 MasterGo 自由绘制，参考 [TDesign Starter 官方 CSS](https://tdesign.tencent.com/starter/vue-next/assets/index-xROm5G_T.css)中的设计 token，并按 TDesign Vue Next 的后台布局和组件职责组织页面。**当前未使用 MasterGo 内的原生 TDesign 组件库实例**；图层中的按钮、表格、表单等外观不等于已绑定官方组件或已生成可运行 Vue 代码。

当前绘制基线为 1440 × 1000 桌面画框、232 宽侧栏和 56 高顶栏；主色 `#0052D9`，浅灰页面背景、白色内容卡片。字体指定 Inter，中文与日文实际字形及回退效果须按最终预览检查，不能据字体声明认定特定 CJK 字体已验证。

2026-10-14 已根据本目录原型建立 [FrontendAdmin Vue 工程](../../FrontendAdmin/README.md)。用户此次明确要求运行时使用 **TDesign 内置明亮／暗黑模式**；工程采用官方组件 CSS、`theme-mode="dark"` 与 `var(--td-*)`，并支持跟随系统。本目录 `dark/theme-tokens.json` 是原设计的可读性配色参考，不作为工程独立调色方案。Vue 实现和浏览器验证不代表本轮重新生成、修改或验收了 MasterGo 画布。

[component-map.json](component-map.json)记录逐页组件职责及后续实现建议。通用外壳对应 Layout、Menu、Breadcrumb、Select、Card 和 Alert；映射关系不表示这些组件实例已经创建。实际组件 API、属性、主题 token 与导入方式应按 FrontendAdmin 最终安装版本核对。

## 十类核心页面

以下 10 类页面均已创建简体中文与日语画板，视觉复核仍在收尾。本表记录页面范围及实现映射，两种语言应保持相同业务对象、版本和操作语义。

| 编号 | 中文页面 | 日语页面 | 重点 | 主要组件映射 |
| --- | --- | --- | --- | --- |
| ADM-01 | 运营工作台 | 運営ダッシュボード | 审核、整理、发布、内部检查待办与异常 | Card、Table、Tag、Tabs、Alert |
| ADM-02 | 需求审核 | 依頼の審査 | 合规、技术与发布状态分列，获授权的审核队列 | Form、Table、Tag、Tabs、Drawer |
| ADM-03 | 合规审核详情 | 適合性審査の詳細 | 客户原文、私有资料、人工结论与审核版本 | Card、Descriptions、Form、Tabs、Dialog、Alert |
| ADM-04 | 技术整理与澄清 | 技術要件の整理・確認 | 原文、整理稿、澄清、依赖与验收范围 | Form、Tabs、Card、Table、Drawer、Alert |
| ADM-05 | 发布管理 | 案件の公開管理 | 双重审核有效的指定版本发布与下架 | Table、Tag、Descriptions、Drawer、Dialog、Alert |
| ADM-06 | 项目协作 | プロジェクト管理 | 已确认范围、主要负责人、进展及内外沟通隔离 | Descriptions、Steps、Tabs、Table、Drawer、Dialog |
| ADM-07 | 交付内部检查 | 納品物の内部確認 | 固定源码版本、交付清单、实际测试证据与返工 | Descriptions、Table、Form、Tabs、Tag、Dialog、Alert |
| ADM-08 | 内部成员与权限 | 内部メンバー・権限 | 独立账号、启停、角色、内部授权与认证分列 | Table、Tag、Form、Drawer、Dialog、Alert |
| ADM-09 | 异常工单 | 問い合わせ・問題対応 | 范围变化、延期、接管、投诉与处理记录 | Form、Table、Tag、Drawer、Dialog、Alert |
| ADM-10 | 操作审计 | 操作履歴 | 操作者、对象、版本、结果与原因，只读追溯 | Form、Table、Tag、Drawer、Alert |

Drawer、Dialog、异常状态等在此列为实现映射与交接内容，不代表本轮主页面效果图已覆盖所有展开态、弹窗或交互。

## 双语与国际化交接

用户已明确后台支持简体中文与日语。后续实现使用业务国际化资源与 TDesign 组件语言的统一切换状态，不能只翻译菜单而保留另一语言的表格分页、日期选择或校验提示。

| OPC 界面语言 | 业务资源键 | TDesign 组件 locale 映射 |
| --- | --- | --- |
| 简体中文 | `zh-CN` | `zh_CN` |
| 日本語 | `ja-JP` | `ja_JP` |

[TDesign 日语 locale 源码](https://github.com/Tencent/tdesign-vue-next/blob/develop/packages/components/locale/ja_JP.ts)提供组件语言入口；[Starter 国际化源码](https://github.com/Tencent/tdesign-vue-next-starter/blob/develop/src/locales/index.ts)展示业务 `vue-i18n` 与组件 locale 的关联方式，其当前默认支持中文与英文。OPC 的日语业务资源和 `ja_JP` 映射需在实现中明确补齐，不能把 Starter 默认语言范围记为中日双语已实现。具体导入路径以实际安装版本为准。

切换语言只改变导航、标题、标签、状态显示、按钮、帮助及错误等界面文案：

- 客户日文原始需求、消息、已确认范围、对客材料、文件名与代码保持原文。辅助翻译若后续提供，应独立标记译文并保留来源，不在语言切换时自动改写。
- 本稿使用 JPY 与 `Asia/Tokyo`（JST）演示。切换语言不转换币种、不改变金额、税费口径、原始时间点、已确认期限或显示时区；不以演示格式替代待确认的报价与条款规则。
- 需求、审核、发布、交付版本以及业务状态码、权限与数据范围保持一致。状态码通过本地化键显示，不能把译后的显示文案写回业务枚举。
- 当前项目已明确手机客户、内部承接者与后台均支持简体中文／日语；手机双语进展见 [APPClient 工程](../../APPClient/README.md)。本稿只记录后台对应布局，不替代手机端语言包与设备验证。

## 业务与实现边界

仅开放日本国内开发（AI 开发系统）服务。待审或未发布需求不能进入任务大厅；合规与技术审核、发布版本、账号授权均由统一 BackendService 校验，前端隐藏或禁用入口不构成权限实现。

内部授权不等于正式 OPC 认证。具体接单机制、客户确认整理稿与发布的先后关系仍待决定；本稿不固定为抢单、竞标或逐单派单。内审通过、对客发布与客户验收分别记录；验收或页面金额不表示到账，不默认建设钱包、托管、抽佣或分账。演示统计、账号、编号和业务记录不是真实运营数据。

本目录记录后台视觉与交接设计，MasterGo 可点击完整原型与全量视觉复核状态保持独立。2026-10-14 已在 [FrontendAdmin](../../FrontendAdmin/README.md) 建立十类页面、官方亮暗主题、运行中的中日国际化及内存 Mock 交互，包括筛选、表单、抽屉、确认弹窗和业务状态校验；具体实现边界见[后台 Mock 契约](../../Docs/development/frontend-admin-mock-contract.md)。真实 API、认证、数据库、文件、支付和通知尚未接入，工程实现和测试结果不反向证明设计画布已经全部验收。

## 本地资料与后续核对

| 文件 | 用途 |
| --- | --- |
| [component-map.json](component-map.json) | 十类页面与 TDesign 组件职责、国际化映射和业务边界建议 |
| [design-builder.mjs](design-builder.mjs) | 本轮画布绘制辅助代码；不是 FrontendAdmin 生产工程 |
| [work-state.json](work-state.json) | 工作过程快照，包含可能仅为 accepted 的提交回执；不替代最终完成记录 |
| [native-current-manifest.json](native-current-manifest.json) 与 `native-current/` | 原始创建快照按 QA 精确补丁重建的本地 HTML；包含后续文字和样例数据修正，不是重新导出的实时画布 |
| `preview-01` 至 `preview-10` 的两套语言 PNG | 本地实际页面预览；与原始创建代码、QA 修订及画布状态一起核对 |

最终交接应补齐真实节点映射、完成状态与两种语言的实际预览，并逐屏记录版式、中文／日文、关键动作和业务状态的检查结果。基础视觉复核、可点击交互、Vue Mock、真实联调与生产上线分别登记，不相互代替。

范围依据：[项目背景](../../Docs/project-context.md)、[V1 统一方案](../../Docs/planning/opc-v1-unified-implementation-plan.md)、[日本本地化](../../Docs/planning/v1-japan-localization.md)。
