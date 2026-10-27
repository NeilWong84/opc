# FrontendAdmin 真实 API 接入验证

日期：2026-10-22。范围为用户要求的后台真实 API 接入、界面演示文案清理及 TDesign 内置主题保留。本轮未修改后端业务逻辑或数据库迁移。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| `npm run build` | 通过；包含 `vue-tsc --noEmit`，生成真实 HTTP 应用包 |
| `npm test` | 3 个文件、46 项通过：HTTP／会话 23，需求接口及状态 15，运营接口 8 |
| `npx playwright test admin.spec.ts --output=test-results/api-integration-protocol --reporter=list` | 14 项通过；其中 4 项分别遍历十页，覆盖简中／日语 × 明亮／暗黑 40 个页面组合 |
| `OPC_LIVE_SMOKE=1` 下执行 `npx playwright test live-readonly.spec.ts --workers=1 --output=test-results/api-integration-live --reporter=list` | 1 项通过；真实管理员登录、读取十页、对比需求版本及状态未变、刷新回登录、撤销本次会话 |
| `node scripts/check-live-admin.mjs` | 真实服务读取通过：ready、6 条迁移、管理身份、需求／合作详情、账号、会话、文件与审计；最后撤销本次会话 |
| PostgreSQL 只读连接核验 | `current_database() = opc_integration`，`current_user = opc_app`，地址 `127.0.0.1`、端口 `55440` |
| `npm run build:production` | 当前没有显式 HTTPS 生产 API 配置，按预期退出 1；不会把本机配置作为生产产物放行 |
| 运行时源码文案检查 | `src/` 无 Mock、演示环境、合成样例等旧运行时标记；历史文档及测试用语保留 |

## 重点行为

- 非管理身份不能登录；未登录不能请求私有业务。仅质检角色进入交付页，避免首页读取无权访问的需求队列。
- 令牌和密码不写 localStorage／sessionStorage，业务数据不通过浏览器存储保存。退出／401 清理私有数据；旧登录、旧注销、迟到的成功及 401 错误正文均不能覆盖或清除新会话。三类实际发现的竞态已增加回归检查。
- 搜索发送后端真实查询参数；503 和网络失败不回退旧样例记录。
- 发布提交实际 `expected_version`、`scope_version` 和原因。409 保持失败状态；成功后的下架使用服务端新行版本。交付审核须核对清单并提交实际证据，409 不产生伪成功。
- 语言、明暗与系统跟随主题继续可用，1024 宽布局检查通过。组件与业务文案无本轮发现的 Vue／intlify 控制台警告。代表性的简中明亮工作台及日语暗黑交付截图已实际查看。

## 证据位置

- 浏览器协议截图：`FrontendAdmin/test-results/api-integration-protocol/` 下的四个中日亮暗目录，每组含十页。截图中的 `REQ-API-001`、`PRJ-API-001` 和协议测试账号是隔离测试响应，不是持久 PG 数据。
- 真实浏览器验证：`tests/e2e/live-readonly.spec.ts`。关闭 trace、自动截图和视频，避免将登录凭据或 Bearer 收进测试产物；脚本不打印这些值。
- 独立只读检查：`scripts/check-live-admin.mjs`，仅访问明确的本机地址。
- 单测：`tests/unit/api.test.ts`、`requests.test.ts`、`operations.test.ts`。

## 验证边界

协议浏览器测试在网络边界注入按真实契约构造的响应，验证前端实际请求和状态处理；不冒充对持久库写入的验证。真实服务浏览验证只读取业务，登录／退出创建和撤销本次会话；没有改写已有需求、合作、账号授权或文件检查结论。未重新执行后端完整集成测试，因为本轮仅修改前端和文档。

构建有主包超过 500 kB 的体积提醒（主 JS 约 1.34 MB、gzip 约 355 kB），不影响本次构建通过。生产部署、工单服务、AI、支付、邮件推送、自动安全扫描和 Office/PDF 转换不在已接通范围；当前是本机真实 API 与持久 PG。既有 `5432/opc_dev` 和 `Accounts` 未更改。
