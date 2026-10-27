# OPC 管理后台

更新日期：2026-10-26。

基于 [admin-v1-mastergo 原型](../Mockup/admin-v1-mastergo/README.md)实现的 Vue 3 + TypeScript + TDesign Vue Next 管理端。当前默认使用 BackendService 的真实管理 API，包含管理员登录、需求审核与发布、项目交付、成员授权和服务端审计，支持简体中文／日语及官方内置明亮／暗黑／跟随系统主题。

## 启动与登录

线上测试入口：[腾讯云东京 OPC 后管](https://admin.opcapp.art/#/login)，官网为 [www.opcapp.art](https://www.opcapp.art/)。管理端以根路径构建，API 地址为 `https://admin.opcapp.art/`，由网关同源转发；原 IP API 供现有 APP 保留。[Dockerfile](Dockerfile) 使用 Node 22 构建生产资源，再由独立非 root Nginx 提供内部 8080；公网网关负责 HTTPS。当前业务数据已从本机快照迁移，使用原有管理员账号密码；凭据加密读取与部署回退见[部署说明](../Deploy/README.md)。原本地开发环境与手机配置继续保留，不自动同步后续写入。

本机后端已使用 `http://127.0.0.1:8001`，由后端连接持久 PostgreSQL `127.0.0.1:55440/opc_integration`。这属于本地真实联调，生产部署尚未配置。既有 `5432/opc_dev` 和 `Accounts` 不在本次变更范围。

```powershell
Set-Location D:\OPC\FrontendAdmin
npm ci
npm run dev
```

打开 [管理后台](http://127.0.0.1:5180/#/login)，使用已获管理角色的账号登录。本机联调账号保存在忽略的 `BackendService/.local/demo-credentials.json` 的 `accounts.admin` 中；勿将凭据复制到源码、环境变量 `VITE_*`、截图或日志。

接口地址可在 `.env.local` 设置 `VITE_API_BASE_URL`，格式见 `.env.example`。配置变更后重启 Vite。默认地址为 `http://127.0.0.1:8001`；跨域由后端 CORS 配置允许本机 5180。前端只保存 API 地址，不保存数据库连接串或数据库密码。

会话仅保存在当前页面内存，刷新、关闭或到期后重新登录；业务记录保存在后端 PG，重新登录继续读取。语言、主题和界面缩放偏好保存在 localStorage。退出会撤销管理会话，401 会清理会话并返回登录页；没有权限、并发版本变化或服务中断会显示真实错误，不返回样例数据。

## 界面缩放

针对 1920×1080 屏幕，默认以 **80%** 等比显示。顶栏放大镜旁可选择 75%、80%、85%、90%、100%，刷新后保留选择；100% 恢复原组件比例。字体、图标、按钮、内外间距、表格、表单、下拉菜单、弹窗和抽屉统一跟随，内容区使用剩余屏幕宽度，长表单仍可正常滚动。

缩放使用文档级 CSS `zoom`，与 TDesign 内置亮暗主题和中日语言独立。`src/utils/scaled-popup.ts` 通过 TDesign 的 `popupProps.popperOptions` 修正 Popper 在非整数比例及滚动时的定位；新增下拉或日期组件应沿用 `scaledPopupProps`，表格分页通过 `selectProps.popupProps` 传入。日期面板内部年月下拉没有透传接口，`main.ts` 在挂载前设置导出 Popup 组件的 Vue prop 默认值；该适配基于锁定的 TDesign 1.20.9，升级组件库时必须运行嵌套日期弹层回归。缩放记录键为 `opc.admin.scale`，异常值回到 80%。实际检查见[缩放验证记录](../Docs/testing/frontend-admin-scale-2026-10-22.md)。

## 页面及实际能力

后台页面固定在视口内：标题和顶部提示、筛选／标签、分页保持可见，需求、成员、审计、文件队列等主表格使用剩余高度并在列表内滚动。合规、技术整理、发布、项目、交付等长内容使用模块内部滚动区；窄屏工作台在内容区内滚动，浏览器页面不整体滚动。

需要即时处理的警告、错误、前置条件和操作成功信息放在内容上方，支持鼠标或键盘关闭；关闭后释放列表高度。审核归档、资料权限、发布／交付边界、认证与筛选口径等说明收进右上角现有铃铛的通知中心，不占用列表高度。弹窗／抽屉内的确认和校验提示留在该容器顶部。关闭只影响本次展示，权限与业务校验继续执行，再次校验失败或发生新错误会重新提示。

页面消息、弹窗内提示与通知中心说明使用约 200 毫秒的淡入／淡出和高度收起过渡，父级关闭回调在淡出完成后执行，避免截断动画或误关重新出现的提示。系统设置为减少动态效果时即时切换。

通知中心包含“页面说明”和“业务通知”：前者随当前页面及语言更新，可逐项关闭，角标表示当前说明条数；后者继续读取真实站内通知 API，并通过服务端标为已读。页面说明及关闭状态只存当前页面会话内存，路由切换会清理旧页面说明，刷新或注销不持久化私有内容。业务通知读取失败不影响页面说明。

新增页面沿用 `module-page` 布局、`list-card` 卡片与 `ScrollTable.vue`，详情使用 `module-scroll`；列表不得通过隐藏外层溢出裁切内容。提示使用 `PageNotice.vue`，即时反馈默认进入头部 `#page-notices`，一般说明传 `notification` 进入铃铛；弹窗或抽屉传 `inline`，同步重复校验可用 `reset-key` 标识新一轮检查。说明见[内部滚动与提示验证](../Docs/testing/frontend-admin-scroll-2026-10-25.md)。

| 页面 | 路由 | 数据与操作 |
| --- | --- | --- |
| 运营工作台 | `/#/dashboard` | 真实需求与状态；统计口径按页面标注 |
| 需求审核 | `/#/reviews` | 服务端搜索／分页、真实客户原文、私有附件与审核记录 |
| 合规审核 | `/#/reviews/{UUID}` | 当前整理版本的人工合规结论、澄清问题、不可覆盖记录 |
| 技术整理 | `/#/technical` | 建立新范围版本、公开摘要、交付／验收条件、技术审核与澄清 |
| 发布管理 | `/#/publishing` | 同版本双审核后发布、下架、发布历史；服务端最终校验 |
| 项目协作 | `/#/projects` | 合作与确认记录、交付、项目和内部会话 |
| 交付检查 | `/#/delivery` | 交付版本、文件下载、人工检查证据、内审和对客发布／撤回 |
| 成员权限 | `/#/members` | 真实账号创建、状态、provider 角色及内部承接授权；与正式认证分开 |
| 异常工单 | `/#/tickets` | 工单服务未开放提示与项目沟通入口 |
| 操作审计 | `/#/audit` | 服务端真实审计，按游标加载历史 |

不存在的工单、AI 建议、邮件、支付、自动安全扫描及 Office/PDF 转换不显示模拟成功。客户原文、业务标题、文件名、消息和版本保持 PG 中实际保存的内容，界面语言切换不翻译业务数据。原有联调库中合成场景的名称保留，移除界面演示标识不改变这些记录的来源。

## 验证与构建

| 命令 | 用途 |
| --- | --- |
| `npm run typecheck` | Vue／TypeScript 类型检查 |
| `npm test` | HTTP 会话、异常、版本与接口适配单测 |
| `npm run test:e2e` | Edge 浏览器隔离协议及界面检查 |
| `node scripts/check-live-admin.mjs` | 使用本机账号只读检查真实 API，最后退出会话 |
| `npm run build` | 生成当前配置的静态应用包 `dist/` |
| `npm run preview` | 在 `127.0.0.1:4173` 预览；登录需后端 CORS 允许该源 |
| `npm run build:production` | 要求显式 HTTPS 生产 API 地址，再检查类型并构建 |

生产 API 地址通过 `.env.production.local` 或构建环境配置，不能沿用 localhost。构建不部署服务，也不等于数据库、CORS、证书与生产权限已经配置完成。运行结果见[本轮验证](../Docs/testing/frontend-admin-api-2026-10-22.md)。

## 主题与代码入口

`src/composables/preferences.ts` 在暗色时为 `<html>` 设置 `theme-mode="dark"`，亮色移除属性；颜色全部沿用 TDesign `--td-*` token。跟随系统监听 `prefers-color-scheme`。业务文案和 TDesign ConfigProvider 同步切换简中／日语；时间始终使用 JST、金额 JPY。

- `src/services/api.ts`：管理身份、HTTP、错误、取消与会话隔离、文件下载。
- `src/services/requests.ts`：需求、范围版本、审核与发布接口。
- `src/services/operations.ts`、`audit.ts`：合作、交付、成员、文件、消息与真实审计。
- `src/App.vue`、`router.ts`、`views/LoginView.vue`：公共框架、路由守卫与登录。
- `src/locales/`：简中／日语资源；`tests/`：单元与浏览器验证。

权限、审核规则、row_version、私有资料访问和审计均由后端执行，前端显示状态不能替代服务端校验。接单默认策略与能力从后端读取，不能把内部授权等同正式认证或推定逐单派单。

历史原型阶段的契约与验证保留在 [2026-10-14 验证](../Docs/testing/frontend-admin-2026-10-14.md)和[历史 Mock 契约](../Docs/development/frontend-admin-mock-contract.md)，不代表当前运行时。当前接入说明见[管理后台 API 联调](../Docs/development/frontend-admin-api-integration.md)。
