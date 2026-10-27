# APPClient V1 MasterGo 效果图

更新日期：2026-10-13。

## 2026-10-13：任务参考资料设计修订

本轮先通过 MCP 修改 MasterGo，随后用户已确认效果图并要求同步 APPClient。Flutter 已接入下述参考资料界面与本地样例交互，工程验证见 [APPClient 说明](../../APPClient/README.md)；原九屏预览、旧基础视觉复核结论不覆盖本轮修订。

- 大厅卡片可选展示截图缩略图、视频封面和附件摘要；只有附件时使用紧凑文件行，纯文字任务不保留空媒体区。
- 任务详情增加参考资料区，与交付成果分开；图片可放大和切换，视频设计播放/暂停、进度、静音、全屏入口，默认不自动播放。
- DOC/DOCX、TXT、MD、XLS/XLSX、CSV、PPT/PPTX、PDF 均属于用户明确要求的预览格式。Word/PDF 按页、表格支持横向浏览和工作表切换（CSV 单表）、PPT 按幻灯片切换，TXT/MD 阅读原文。
- 所有当前有权访问的附件，包括图片、视频和不能预览的其他格式，都提供下载原文件入口。预览准备、预览失败与下载失败分别呈现，下载中可取消、失败可重试、完成可打开。
- 原文件名、客户原文和内容颜色不随界面语言或主题改写。浅深模式改变界面外壳，截图/视频及文档纸张保持原始内容。
- 大厅的资料名称、数量、封面、预览及下载均受当前审核发布版本与访问权限约束，不能把原始私有附件自动公开。权限失效停止查看和新的下载，不声称能收回已下载文件。

本轮合成截图保存在 [task-reference-assets](../task-reference-assets/README.md)；为原创系统界面示意，未使用真实客户资料。视频封面、时长、文件类型、页码及下载进度是设计示例，不代表存在真实视频或转换服务。既有页面修改前快照保存在 `media-revision/snapshot-*.html`；提交后的作者 HTML、MCP 回执与节点记录已保存到 [本轮交接索引](media-revision/canvas-state.json)。

**本轮结果：任务大厅与任务详情的浅深 4 页已通过 MCP 提交修改；新增 9 类 × 浅深两套，共 18 个资料预览与状态画板，运行记录全部为 `completed`。** 修改保留原根画板，大厅参考图示例与详情资料区已加入。用户已确认新稿；Agent 尚未进行这批 MasterGo 生成后的截图视觉复核。画布仍是静态效果图，没有绑定播放、预览或下载交互；APPClient 的交互与设备验证独立记录。

| 新增画板 | 浅色稿 | 暗色稿 |
| --- | --- | --- |
| 参考资料列表 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A1412) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A7515) |
| 图片查看 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A8778) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A9223) |
| 视频播放 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A9647) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A00425) |
| Word 文档预览 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A01139) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A02055) |
| PDF 预览 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A03059) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A03963) |
| Excel / CSV 表格预览 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A04967) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A07173) |
| PPT 幻灯片预览 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A09377) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A10721) |
| TXT / Markdown 文本预览 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A11952) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A12840) |
| 可选资料与下载状态 | [浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A13823) | [暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=21%3A15347) |

原页面：[任务大厅浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=14%3A3483) · [任务大厅暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=14%3A04310) · [任务详情浅色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=14%3A5089) · [任务详情暗色](https://mastergo.com/file/207036955904456?page_id=M&layer_id=14%3A05895)。

预览主画板为 390×844；状态汇总采用 390×1280 长画板，用于展示多个独立场景，不是把它们同时塞进实际产品的一页。Word 示例覆盖 DOC/DOCX；表格示例展示 Excel 工作表并注明 CSV 单表，PPT 示例覆盖 PPT/PPTX，文本示例展示 Markdown 排版及原文入口并注明 TXT 自动换行。并非每种文件扩展名单独生成一个画板。页面文案沿用既有日文稿，简中/日语实现要求不变。

真实文件服务、格式转换与预览引擎尚未选型。Flutter 本地样例已包含图片切换缩放、8 秒 MP4 播放、三页文档/PDF/幻灯片、工作表/CSV 和 TXT/MD 阅读，以及原样例保存/导出；样例时长、页数和大小以实际资源为准，不照搬设计占位值。不得将这些结果写成任意 Office 文件转换或生产文件服务已完成。

**2026-10-12 首轮状态：9 个浅色页面与 9 个对应暗黑页面已创建，均为原生可编辑画板；当时两套实际预览的基础视觉检查完成。** 首轮尚未建立完整交互，此结论不覆盖上方 2026-10-13 的资料修订。用户明确改用 MasterGo 直接制作效果图，原因是 Figma Starter MCP 工具额度受限。已有 [Figma 九屏稿](../app-v1-figma/README.md)保留为设计参考。

[打开 MasterGo 可编辑设计](https://mastergo.com/file/207036955904456?page_id=M&layer_id=14%3A0) · [2026-10-12 浅色九屏总览](overview.png) · [首轮节点记录](canvas-state.json)

[暗黑模式说明与主题规范](dark/README.md) · [2026-10-12 暗黑九屏总览](dark/overview.png) · [暗黑首轮节点记录](dark/canvas-state.json)

文件 ID：`207036955904456`；当前文件名：`OPC-APPClient`；页面 ID：`M`（`2026-10-12初版`）。继续修改时使用此文件与节点记录。下文“第一批九屏”及原有节点表为浅色稿，暗色节点独立记录。

## 已完成与连接记录

- 已在本机 Codex 全局配置中添加 `mastergo` STDIO 服务，使用官方 `@mastergo/vibe-mcp@1.0.31`；未改动其他 MCP 服务。
- 配置地址为 `http://localhost:30678`。已通过 MCP 初始化、工具列表读取和实际画布读写，连接已恢复。
- 本机 Node.js 为 24.11.1，npm 为 11.6.2。用户已安装并登录 MasterGo；检测到客户端 1.11.7.1555 运行。
- 早期曾返回 `no online mg canvas`；用户反馈本次升级订阅后出现 MCP 服务入口，随后实测恢复。本次经历不作为所有用户必须购买某套餐的依据。
- 用户已明确回复“已开启，使用自由绘制”；已按该来源逐页创建九屏，各屏生成 `meta.json` 状态均为 `completed`。

适配器安装到 npm 缓存，不属于 APPClient 或 BackendService 的运行依赖。Codex 配置如下，仅用于维护记录：

```powershell
codex mcp add mastergo -- cmd.exe /d /c npx.cmd -y @mastergo/vibe-mcp@1.0.31 --url=http://localhost:30678
```

已有配置不要重复添加；使用 `codex mcp get mastergo` 查看。Codex 原生工具列表若未更新，可重新加载 MCP 或重启应用。官方 Vibe MCP 使用本地客户端连接，无需提供个人 Token。

## 第一批九屏

| 编号 | 中文说明 | 日文标题 | 主要内容 | 根图层 ID | 实际预览 |
| --- | --- | --- | --- | --- | --- |
| 01 | 登录／注册入口 | ログイン | 客户注册与内部账号登录；具体登录方式仍是设计假设 | `14:0` | [PNG](preview-01.png) |
| 02 | 客户首页 | ご依頼一覧 | 发起开发咨询、本人需求与待回答问题 | `14:959` | [PNG](preview-02.png) |
| 03 | 提交开发需求 | 開発のご相談 | 目标、时间、预算意向、材料、AI 辅助整理 | `14:1066` | [PNG](preview-03.png) |
| 04 | 审核进度 | ご依頼の確認状況 | 人工合规确认、技术整理、补充资料与未公开提示 | `14:2269` | [PNG](preview-04.png) |
| 05 | 任务大厅 | 案件一覧 | 授权内部账号查看已审核、已发布任务 | `14:3483` | [PNG](preview-05.png) |
| 06 | 任务详情 | 案件詳細 | 范围版本、周期、交付物与「案件について相談する」入口 | `14:5089` | [PNG](preview-06.png) |
| 07 | 项目工作台 | プロジェクト | 进度、里程碑、沟通摘要、交付入口 | `14:6319` | [PNG](preview-07.png) |
| 08 | 提交成果 | 成果物の提出 | 固定源码版本、文档、测试材料，提交内部检查 | `14:7535` | [PNG](preview-08.png) |
| 09 | 客户验收 | 納品内容の確認 | 对客交付版本、演示、验收点、修改与验收 | `14:8649` | [PNG](preview-09.png) |

页面内容与视觉约束保存于 [design-brief.json](design-brief.json)，实际画布映射与验证状态见 [canvas-state.json](canvas-state.json)。手机画框 390 × 844；主绿 `#086E61`、深蓝 `#142D36`、薄荷绿 `#D9F7DD`。字体接口返回的团队、企业字体清单均为 0，设计指定 Inter，九屏日文实际通过字体回退显示；未验证具体回退字体，不能认定 Noto Sans JP 已可用。MasterGo 使用上表中的新图层 ID，不复用 Figma 节点、变量或组件 ID。

只开放开发服务；待审需求不进大厅；内部账号不等于正式认证；咨询入口不冻结接单规则；验收不等于付款。不同阶段示例使用不同需求编号。后台人工审核仍在 FrontendAdmin，手机仅呈现结果及补充入口。

## 2026-10-12 首轮验证记录与后续工作

九屏生成记录均为 `completed`，实际画布预览已全部保存并逐图检查，九张 PNG 均为 390 × 844，日文、主按钮与关键状态显示正常。基础视觉复核完成 9/9，不代表交互或 Flutter 真机验证通过，也不继承旧 Figma 的复核结论。

保留两项首轮细化记录：

- 第 02 屏小节标题“進行中のご依頼”换为两行，后续可调整标题宽度或排版。
- 第 06 屏详情末尾辅助说明位于首屏下方。Flutter Mock 需让正文独立滚动、咨询按钮固定，保留完整内容，不以隐藏说明解决布局问题。

2026-10-12 新增暗黑九屏时，已修正暗色第 02 屏标题宽度和第 06 屏局部间距，两项说明在暗色静态预览中均完整显示；当日新增暗色稿时未改写浅色稿。暗色配色、实际预览与验证边界见 [暗黑模式交接](dark/README.md)。

Flutter + Dart Mock 已补齐注册、表单确认、聊天、修改反馈及主要错误／空／处理中状态；实际功能与验证范围见 APPClient 工程说明。

本目录保存设计成果，MasterGo 画布尚未建立完整可点击交互。后续已按本目录浅深稿实现 [APPClient Flutter 工程与交互 Mock](../../APPClient/README.md)，包括 9 屏与辅助流程；工程和设备验证单独记录。后端和真实 API 仍未连接。

参考：[MasterGo Vibe MCP](https://mastergo.com/help/ai-features/vibe-mcp.html)、[客户端下载](https://mastergo.com/resource)、[Codex MCP 配置](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。网页说明与已安装版本的工具名可能不同，执行以实际工具契约为准。
