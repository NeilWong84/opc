# APPClient／BackendService 真实数据联调验证

日期：2026-10-16。实施与重跑入口：[联调说明](../development/app-backend-integration.md)、[APPClient](../../APPClient/README.md)、[BackendService](../../BackendService/README.md)。本文接续同日较早的后端初版记录，区分代码测试、真实 HTTP／PG、Android 页面操作及生产部署。

## 本轮实现

APPClient 默认连接真实 HTTP Repository，客户与内部承接者从认证、草稿、需求、澄清、发布大厅、条款确认、消息到交付、修改及验收均有服务端实现和手机入口；使用真实文件字节与鉴权访问。默认 API 无 Mock 失败回退，历史 Mock 仅显式演示／回归。Vue 后台页面仍为 Mock，本轮后台审核与发布通过真实管理 API 完成。

后端补齐手机所需的文件清单、pending 私有附件受理、合作项目会话、客户身份与绑定范围、消息显示名等契约。所有规则继续在服务端执行，六条已有 SQL 迁移未修改；不把内部授权说成正式认证，不加入自动抢单、竞标、支付或自动文件安全扫描。

## 实际环境与结果

Windows；Flutter 3.35.5／Dart 3.9.2；Python 3.14；PostgreSQL 18.4；Android Emulator `Medium_Phone_API_36.1`，设备 `emulator-5554`。这是 Android 模拟器验证，没有 iOS 或实体手机验证。

| 验证 | 最终结果 |
| --- | --- |
| Flutter 静态检查 | `flutter analyze --no-pub`，0 issues |
| APP 全量 Dart／widget 测试 | **318 passed**，含 16 项真实 HTTP 适配器测试、真实页面及历史回归 |
| 后端单元／契约 | **115 passed** |
| 后端隔离真实 PG 集成／并发 | **16 passed**；合计 **131 passed** |
| 后端 Ruff | `All checks passed!` |
| OpenAPI 导出 | **68 paths / 84 operations** |
| Android＋真实 HTTP＋持久 PG | **1 个完整业务场景通过**，最新 run `114e574e86f9`，约 60 秒设备测试（不含构建安装） |
| PG 正常停止／重启 | 前后只读业务与文件快照完全相同，`verified=true` |
| 普通 `lib/main.dart` APK | 已构建并保留；签名校验通过，无测试入口标识及凭据文件；最终自动安装受限，见后文 |

Flutter 日志中的 `+2` 包含 `tearDownAll`，不计为两个业务场景。后端测试使用独立临时 PG；Android 测试使用下面的持久联调库，两类验证相互独立。

## Android 实际覆盖

测试源码：[real_api_smoke_test.dart](../../APPClient/integration_test/real_api_smoke_test.dart)。真实管理步骤仅存在于测试入口，使用本轮临时管理会话。普通 APP 不具有管理权限。

| 阶段 | 实际操作与断言 |
| --- | --- |
| 认证与草稿 | 在设备上调用真实注册，UI 登录；真实上传 pending 私有文件并保存草稿，新 Repository 登录能恢复 PG 草稿及附件 |
| 提交与私有性 | UI 读取草稿并提交；未审核需求不在内部大厅、他人无法查看详情或私有文件；pending 下载被拒 |
| 文件 | 管理端记录已知合成字节的检查证据后，真实下载／文本预览逐字节比较；客户 UI 保存文件至原生私有目录，出现打开入口 |
| 澄清与发布 | 客户答复第一次澄清，原文升 v2；管理员显式选择参考文件、双审并发布，内部账号能见参考资料，原始私有附件仍不可见 |
| 合作 | 咨询不创建合作；测试进程录入合成已确认关系，客户通过 UI 二次确认，承接者通过真实 Repository 确认 |
| 合作中澄清 | 已执行合作仍展示后台问题，客户通过 UI 答复，原文升 v3；旧大厅发布失效，合作继续绑定已确认范围 |
| 消息与交付 | 项目消息持久化；承接者提交实际源码字节与说明／测试材料，未发布交付对客户不可见；质检后对客发布 |
| 修改与验收 | 客户要求修改，承接者交付 v2；旧版验收被拒，客户通过 UI 对 v2 二次确认验收，合作完成 |
| 恢复与通知 | 新 Repository 重新登录后仍见完成状态和 v2，可下载相同源码；通知已读持久化；退出后回登录 |

这是完整真实 API 业务链路与关键 UI 路径的组合测试：承接者确认／交付、部分上传和反馈由设备上的真实 Repository 调用；并非所有步骤都自动点击页面按钮，也没有自动操作系统文件选择器或完成全部系统打开／导出交互。这些界面分支另由 widget／下载控制器测试覆盖，不能等同设备原生交互验收。

最新结果：

- request：`ed8b456c-54a9-4c0f-b984-8b56d0076aa4`，原文 v3、最终 closed。
- engagement：`0b23e0de-1a29-4e68-bec6-ed868dfcfdfe`，最终 completed。
- 已验收 delivery：`d37c5039-9bd5-43ac-a499-d08777bddeda`，v2；v1 保留 revision_requested。

日志与截图位于忽略目录 `APPClient/test_artifacts/real-api/`：`android-e2e.log`、`backend-stdout.log`、`flutter-tests.log`、`integration_response_data.json` 和四张 `api-*.png`。已查看首页、真实文件保存、条款确认与完成状态截图，无测试捕获的 Flutter 布局异常；长页面截图只代表当前可见区域。

首轮发现并修复测试导航使用标准 BackButton 与现有自定义返回按钮不匹配；收尾修复报告赋值覆盖截图数据的问题。过程中发现的合作澄清覆盖、文件 401 根页面未通知、草稿被完整提交校验阻止、下载授权 await 时序问题均已修复并回归。失败日志保留，不计入通过数量。

## 持久 PG 与演示数据

持久实例为 `127.0.0.1:55440/opc_integration`，schema `opc`，数据库标记 `opc.local-integration.v1`，磁盘目录 `BackendService/.local/integration/data`。`opc_app` 为非超级用户，无 createdb／createrole／replication／bypassrls；`fsync=on`、`synchronous_commit=on`。实际校验 PostgreSQL 180004 和六条迁移的 SHA-256。既有 5432/opc_dev 与 Accounts 未改写。

演示 seed 已真实执行并重复校验：三个随机密码账号、四阶段合成需求／合作、真实 MD／源码 ZIP、消息与通知写入 PG／私有文件目录；重复初始化不重置密码、角色或已推进业务。密码变更后的重复 seed 也不覆盖现有密码。账号在本机忽略文件 `BackendService/.local/demo-credentials.json`，不在本文件披露。

本轮执行以下命令正常停启 PG，并比较同一个 Android run 的只读快照：

```powershell
Set-Location D:\OPC\BackendService
.\.venv\Scripts\python.exe scripts/verify-mobile-persistence.py --input ../APPClient/test_artifacts/real-api/integration_response_data.json --output ../APPClient/test_artifacts/real-api/persistence-before.json
.\.venv\Scripts\python.exe scripts/provision-local-integration.py stop
.\.venv\Scripts\python.exe scripts/provision-local-integration.py start
.\.venv\Scripts\python.exe scripts/verify-mobile-persistence.py --input ../APPClient/test_artifacts/real-api/integration_response_data.json --compare ../APPClient/test_artifacts/real-api/persistence-before.json --output ../APPClient/test_artifacts/real-api/persistence-after.json
```

重启前后两版交付／验收、2 条消息、24 条通知及已读时间、绑定范围的历史参考发布、3 个原文件大小／SHA-256 完全相同。合作中原文变更已使旧大厅发布失效，因此参考资料按照合作约定范围的历史双审发布验证，不要求仍在大厅公开。

这是正常 PG 停启的持久化验证，未模拟断电或数据库／文件备份灾难恢复。文件原字节保存在磁盘，PG 保存元数据和业务记录，并不声称将文件字节存为 PG 大对象。

## 普通安装包与本机服务

交付包：[OPC-0.1.0-android-20261016-api-debug.apk](../../APPClient/build/packages/OPC-0.1.0-android-20261016-api-debug.apk)。普通入口 `lib/main.dart`，`APP_ENV=api`，API `http://127.0.0.1:8001`；Android 包名 `jp.opc.opc_app`，versionName 0.1.0／versionCode 2，minSdk 24／targetSdk 36，大小 175,015,551 bytes。

SHA-256：`2e9db92c006482a453014772d208976a7d2fee42775648e5c661b3d968f6c8b2`。`apksigner verify --verbose` 验证 v2 签名通过（debug 签名）；APK 中没有 `.env`、演示凭据、专用 PG 状态或测试 define 文件，普通 Dart kernel 未包含测试管理令牌定义或 E2E 入口。不能作为商店生产发行包。

该普通包在最后一次仅修改测试截图保存逻辑的运行前已独立构建并保存，其后 `lib` 未变。测试使用的临时管理 token 已撤销、忽略 define 文件中的原 token 已移除。测试 APK 与普通交付 APK 分开。

收尾时，自动审批审查以 `blocked by policy` 拒绝了旧 8001 服务重启、新 8003 后台服务启动，以及最后普通 APK 重建／模拟器替换的组合命令，未绕过。因此现有 8001 保留运行，`/health/ready` 返回 ready／6 migrations；最新补充的消息 `author_name` 源码在真实测试进程验证通过，现有常驻服务需重启才能载入。模拟器最后安装的是已撤销测试会话的测试包，不能声称普通交付包已完成最终安装。

PG 重启后又通过 8001 实际验证三个演示账号均可登录、读取各自身份并退出，普通服务仍为 hall internal／assignment disabled，结果保存 `ordinary-service-check.json`。首轮只读身份断言误将管理员角色码写为 admin，修正为契约的 administrator 后通过；每次校验会话均已退出。

手动查看或继续演示时，先在终端停止旧服务并按联调说明启动当前源码，再安装上面的普通 APK，执行 `adb reverse tcp:8001 tcp:8001`。这不需要改动数据库或再次 seed。已保存的 APK 是可安装文件，普通服务不能获得测试管理令牌。

## 保留边界

Vue 后台页面真实适配、iOS／实体机／日本网络、生产 HTTPS／签名／部署、容量压测与完整备份恢复未验证。Office/PDF 任意转换、邮件验证与密码恢复、外部推送、自动文件安全扫描、AI、支付和正式认证未接入。安全检查仅记录实际人工证据；测试中的 clean 只用于可核对的合成字节。默认大厅 internal、接单 disabled，测试临时 record_confirmed 不代表正式接单政策。
