# APPClient V1 Figma 效果图

日期：2026-10-12  
状态：**首轮高保真设计稿已创建；视觉复核部分完成。不是可运行 Mock，也不是已冻结的完整需求规格。**

[打开 Figma 可编辑设计](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=4-51) · [共用组件](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=4-52)

本稿依据 [V1 统一落地方案 2.1](../../Docs/planning/opc-v1-unified-implementation-plan.md)，只设计 APPClient 手机端。客户和内部承接者共用 APP；后台审核动作仍由 FrontendAdmin 处理，两端共用 BackendService。

## 页面与入口

| 编号 | 页面 | 角色与重点 | Figma |
| --- | --- | --- | --- |
| 01 | 登录／注册入口 | 客户可注册；内部账号从同一登录入口进入 | [Screen 01](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-27) |
| 02 | 客户首页 | 发起开发咨询、个人需求与待回答问题 | [Screen 02](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-36) |
| 03 | 提交开发需求 | 自然语言目标、时间、预算意向、参考材料、AI 辅助整理 | [Screen 03](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-45) |
| 04 | 审核进度 | 人工合规确认、技术整理、补充问题、非公开提示 | [Screen 04](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-58) |
| 05 | 任务大厅 | 授权内部承接者查看已审且已发布的开发任务 | [Screen 05](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-67) |
| 06 | 任务详情 | 整理稿版本、范围、开发周期、交付物与咨询入口 | [Screen 06](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-76) |
| 07 | 项目工作台 | 开发进度、里程碑、站内沟通摘要与提交入口 | [Screen 07](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-89) |
| 08 | 提交成果 | 源码 ZIP／固定仓库版本入口、文档、测试材料、内部检查 | [Screen 08](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-98) |
| 09 | 客户验收 | 已对客发布的版本、系统演示、验收点、修改与验收 | [Screen 09](https://www.figma.com/design/lswOlwmfmkw3rhbmcfiVCR?node-id=7-107) |

画布分为三组，附中文评审说明；手机内使用日文。系统演示预览也是原生可编辑图层，不是嵌入的整屏图片。

## 视觉基线

- 手机画框：390 × 844，浅色主题；正文 Noto Sans JP，中文批注 Noto Sans SC，品牌英文及数字 Plus Jakarta Sans。
- 深蓝 `#142D36`、主绿 `#086E61`、薄荷绿 `#D9F7DD`；正文使用深色，待审核使用琥珀色，开发中使用蓝色，状态同时有文字标识。
- 40 个本地变量，包含基础色、语义色、间距和圆角；8 个排版样式。
- 10 个本地主组件：3 种按钮、输入字段、4 种状态、任务卡、底部导航。导航的消息和用户图标复用 Material 3 图标实例。
- 已检索 Material 3 库并检查 Button、Text field 属性和 Roboto 字体。OPC 的日文排版与业务组件使用本地组件，避免修改远程库；当前不建立完整通用设计系统。

## 业务约束与设计假设

1. 当前只开放开发（AI 开发系统），其余四条服务线不在页面中作为可下单服务出现。
2. 待审需求仅出现在客户自己的需求页；大厅示例全部为已审核并发布的任务。两项人工检查完成后才可通过，AI 不能批准发布。
3. “内部アカウント”表示当前账号来源，不是“OPC 认证”。认证考核为未来版本。
4. 任务详情使用“案件について相談する”。最终直接领取、申请确认或其他规则仍待决，未通过按钮文案定案。
5. 当前账号样例、REQ／OPC 编号、12 件任务、日期、进度和文件名都是演示内容。不同页面展示不同阶段，不表示同一需求同时处于多个状态。
6. 客户何时确认整理后的范围与报价仍待定义；本稿没有用原型连线固定该顺序。
7. 邮箱密码表单是设计假设；实际身份服务与登录方式未选。提交页含预算意向，但不表示平台已确定在线支付。
8. 验收完成不表示付款完成，没有钱包、托管、结算与认证标章。

## 验证与限制

已完成结构检查：9 个手机画框均为 390 × 844；最后一次完整内容边界检查中，9 个页面的内容均在正文区域内。字体检查未发现非预期字体，主画布没有 IMAGE 填充，页面由原生文本、布局、实例和矢量组成。

已查看第一组三屏的实际 Figma 渲染，并修正了卡片横向对齐、返回图标及部分文字。**最终对齐调整之后的截图复核尚未完成；第二、三组及组件展示未完成视觉截图复核。** Figma MCP 返回 Starter 套餐工具调用额度耗尽；浏览器备用访问遇到人机验证，未代用户完成验证或购买升级。

[第一组三屏预览](preview-a-before-alignment.png)生成于最后一次对齐调整之前，仅作首轮效果参考，云端 Figma 为当前设计版本。

本轮没有创建 Flutter 工程、后端接口、真实账号、付款流程或 Figma 点击连线。注册完整表单、发送确认、聊天详情、修改反馈表单、空／错／加载状态、权限与异常状态仍需在 Mock 开发前按批次补齐，不能将本稿当作完整交互验收。

## 本地交接资料

| 文件 | 用途 |
| --- | --- |
| [figma-state.json](figma-state.json) | 当前文件、页面、画框和组件 ID，完成与待验证状态；继续工作优先读取 |
| [foundations.json](foundations.json) | 创建时返回的变量和排版样式 ID |
| [components.json](components.json) | 主组件映射与创建记录 |
| [screens.json](screens.json) | 9 个手机画框、正文与底部动作容器 ID；尺寸记录为创建时快照，当前状态以 Figma 和 figma-state 为准 |
| [design-helpers.js](design-helpers.js) | 此次 Figma Plugin API 构建辅助片段；不是 APPClient 生产代码或可独立运行脚本 |
| [screen-helpers.js](screen-helpers.js) | 使用本文件组件 ID 的屏幕构建辅助片段 |

2026-10-12，用户因 Figma Starter MCP 额度限制，决定后续改用 [MasterGo 制作效果图](../app-v1-mastergo/README.md)。本文件及云端 Figma 稿保留作历史参考；后续视觉复核与设计交接在 MasterGo 重新执行，再依据 [设计到生产流程](../../Docs/planning/v1-design-to-production-workflow.md)进入 Flutter + Dart Mock。真实审核和权限限制最终必须由统一后端执行。
