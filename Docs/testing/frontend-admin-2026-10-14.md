# FrontendAdmin 原型落地与验证

日期：2026-10-14。范围：`FrontendAdmin/` 的 Vue 3 + TypeScript + TDesign Vue Next 内存 Mock；未改数据库或 APPClient。

## 实现来源与范围

根据 [admin-v1-mastergo](../../Mockup/admin-v1-mastergo/README.md) 本地 `native-current` 内容、预览 PNG、组件映射及当前项目业务边界实现十类后台页面。使用原型的 232px 侧栏、56px 顶栏、卡片和表格结构；原型演示数字改为根据当前样例状态计算。当前未重新编辑 MasterGo 画布，也不将浏览器验证记为 MasterGo 全量验收。

后台使用 TDesign Vue Next 1.20.9 官方 CSS。暗黑模式通过 `html[theme-mode="dark"]` 启用，明亮模式移除该属性；页面颜色使用 `--td-*` token，没有维护独立的暗色调色表。跟随系统监听 `prefers-color-scheme`。实现依据为[官方 Starter 主题设置](https://github.com/Tencent/tdesign-vue-next-starter/blob/develop/src/store/modules/setting.ts)及实际安装包中的主题 CSS。

业务语言与 TDesign `zh_CN`／`ja_JP` 同步；仅语言和主题偏好保存到 localStorage。客户原文、人工备注、文件名、业务版本、JPY 和 JST 不随界面语言改变。

## 实际验证结果

环境：Windows，Node.js 24.11.1，npm 11.6.2，本机 Microsoft Edge，Playwright 1.64.0。

| 验证 | 结果 |
| --- | --- |
| `npm run typecheck` | 通过；包含 TDesign 全局组件类型及 Vue 模板属性检查 |
| `npm run build` | 通过，生成 `FrontendAdmin/dist/` Mock 演示包 |
| 构建包预览 | `npm run preview` 的 4173 服务可加载运营工作台，4 个指标卡正常，无页面脚本错误；验证后停止预览服务 |
| `npm test` | 2 个文件，29 项通过 |
| 浏览器验证 | 分批累计 53 个不同 E2E 用例通过，包括初始页面矩阵及修复后的定向复验；不是声称最终一次全量重跑 |
| 双语与主题矩阵 | 10 页 × 简中／日语 × 明亮／暗黑，共 40 个页面组合通过，均生成整页截图 |
| 窄桌面 | 1024 × 900 日文暗色下十页均无文档级横向溢出；宽表在自身区域内滚动 |
| 运行时控制台 | 两种语言共 20 个页面无 Vue、intlify、图标或 TDesign 警告 |
| 主题与偏好 | 官方 Card 实际背景随系统主题变化；手动语言／主题切换及刷新恢复通过 |
| 生产门禁 | `npm run build:production` 按预期输出未接真实服务原因并返回退出码 1 |

单测覆盖同版本双审核才可发布、旧审核失效、技术内容变更递增版本并撤销发布、大厅输出不泄露私有资料、重复发布、过期 revision、下架、检查项及原因必填。另覆盖内部授权与认证独立、停用保留在途项目、内审与对客发布分离、发布后锁定、内外消息隔离及 JST。

浏览器交互覆盖列表筛选／无结果／重置、摘要抽屉、中文与日文完整合规审核→技术审核→发布→下架、发布原因校验、已发布内容变更后的审核失效、成员停用确认、交付内审与对客发布的两个独立弹窗、审批后编辑需重审，以及只读审计抽屉。

## 复核发现与修复

- 合规详情属于审核导航的当前项，TDesign Menu 的 `change` 不会在再次点击同一项时触发。导航改为逐项点击跳转，已验证可从详情返回列表并继续双审核流程。
- Drawer 显式开启关闭按钮，验证摘要及运营详情可以关闭。
- 日文工单时间线的完整 JST 时间和操作者在原 label 栏重叠。已改为正文独立灰色行，更新浅深及双语截图。
- 修正交付导航不存在的图标名；补充组件类型声明后处理官方 locale 的 readonly 类型与表格只读数据兼容问题。

对默认页面和重点弹窗进行截图复核；没有宣称完成所有浏览器、屏幕阅读器、手机浏览器或完整无障碍验收。

## 保存的证据

[证据清单](frontend-admin-2026-10-14/evidence.json)记录本次保留的 7 张代表截图：

| 页面或状态 | 截图 |
| --- | --- |
| 运营工作台，简中明亮 | [查看](frontend-admin-2026-10-14/screenshots/01-dashboard-zh-light.png) |
| 运营工作台，简中暗黑 | [查看](frontend-admin-2026-10-14/screenshots/01-dashboard-zh-dark.png) |
| 需求审核，日文明亮 | [查看](frontend-admin-2026-10-14/screenshots/02-reviews-ja-light.png) |
| 技术整理，日文暗黑 | [查看](frontend-admin-2026-10-14/screenshots/04-technical-ja-dark.png) |
| 工单时间线修复后，日文暗黑 | [查看](frontend-admin-2026-10-14/screenshots/09-tickets-ja-dark.png) |
| 对客交付发布确认，日文暗黑 | [查看](frontend-admin-2026-10-14/screenshots/07-delivery-publish-ja-dark.png) |
| 只读审计抽屉，日文暗黑 | [查看](frontend-admin-2026-10-14/screenshots/10-audit-detail-ja-dark.png) |

完整运行截图与中间失败追踪保留于 `FrontendAdmin/test-results/`；修复后的定向记录在 `final-recheck/`，成员等运营截图在 `operations-check/`，控制台检查在 `console-recheck/`。这些目录可被下次测试覆盖，长期证据以上表为准。测试源码位于 `tests/unit/` 和 `tests/e2e/`，运行说明见 [FrontendAdmin README](../../FrontendAdmin/README.md)。

## 当前边界

真实登录、服务端角色权限、数据库/API、云端文件、AI、消息和支付均未接入。页面中的审核、发布和成员操作仅修改本地内存，刷新后重置；样例审计不是可信生产审计。APPClient 与后台尚未共享真实业务数据，原型文件列表不能当作实际文件服务。

构建存在主 JavaScript chunk 超过 500 kB 的体积提示，当前全局注册 TDesign 组件与图标；功能构建成功，后续真实接入时可按需引入并拆包。未对首次加载性能、真实网络或生产部署作通过声明。正式服务端权限、并发和文件授权须重新验证，不能依赖前端禁用按钮。
