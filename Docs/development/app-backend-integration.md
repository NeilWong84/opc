# APPClient 与 BackendService 真实数据联调

更新：2026-10-16。本文用于本机 PostgreSQL 与 Android 联调，验证结果另见 [本次验证记录](../testing/app-backend-integration-2026-10-16.md)。手机接入真实 HTTP 数据源，FrontendAdmin 的 Vue 页面仍为 Mock；本轮审核与运营使用真实管理 API／Swagger，不把后台界面说成已接通。

## 1 本机环境与启动

本轮使用 PostgreSQL 18.4 的独立持久实例 `127.0.0.1:55440/opc_integration`，schema 为 `opc`，沿用 DB 迁移。其数据库标记是 `opc.local-integration.v1`，应用使用受限 `opc_app`；`fsync` 和 `synchronous_commit` 开启。数据库目录在 `BackendService/.local/integration/data`，服务重启不删除数据。既有 `5432/opc_dev` 和 `Accounts` 未被本轮改写。

在 `D:\OPC\BackendService` 执行：

```powershell
# 首次创建或重新启动专用 PG；重复运行检查迁移校验值，保留数据和密码
.\.venv\Scripts\python.exe scripts/provision-local-integration.py start

# 显式初始化合成演示数据；再次运行不重置账号或已推进的业务状态
.\.venv\Scripts\python.exe scripts/seed-demo.py

# 普通业务服务：读取忽略的 .env，默认接单策略 disabled
.\scripts\start.ps1 -Port 8001
```

可浏览 [Swagger](http://127.0.0.1:8001/docs)、[ReDoc](http://127.0.0.1:8001/redoc)、[数据库就绪检查](http://127.0.0.1:8001/health/ready)。旧的 8000 服务可能仍使用旧配置，不能用其存活结果代替 8001 的数据库就绪结果。

`provision-local-integration.py status` 查看实例状态；`stop` 仅正常停止该实例并保留数据。脚本不使用 5432、不删除数据库、不接管无标记目录、不覆盖已有 `.env` 或修改既有密码，后续迁移仍须新建 SQL，不改历史校验值。

若要切到既有 `5432/opc_dev`，按 BackendService README 的 `configure-local-db` 配置专用角色，并使用独立备份保存现有 `.env`。不能把维护账号、PG 密码或连接串放进 APP。当前独立实例是持续联调环境，不是自动清理的 pytest 临时库。

## 2 演示数据与凭据

凭据只保存在本机忽略文件 `BackendService/.local/demo-credentials.json`，密码随机生成，PG 保存 Argon2id 哈希。用编辑器在本机查看该文件，不把完整文件放进文档、截图或提交。手机仅使用 customer/provider 账号，admin 只用于管理 API 登录。

| 场景键 | 用途 |
| --- | --- |
| `pending_review` | 客户查看待补充需求并答复运营问题 |
| `published` | 内部成员查看双审已发布任务、参考资料及咨询 |
| `awaiting_confirmation` | 客户和内部成员分别确认当前条款，然后提交交付 |
| `awaiting_acceptance` | 客户读取已经内审并对客发布的源码、说明、测试材料，提出修改或验收 |

这些记录真实写入 PG，文件字节真实保存在 `.local/files`。场景内容和审核理由明确是合成联调证据，不代表真实客户订单或正式业务审批。脚本只在自身进程临时启用 `record_confirmed` 创建已确认合作样例，不改变 `.env` 的默认策略。内部授权不等于正式 OPC 认证。

## 3 运行手机 APP

在 `D:\OPC\APPClient` 执行，Android 模拟器或 USB 真机先由 `adb devices` 确认：

```powershell
flutter pub get
adb -s emulator-5554 reverse tcp:8001 tcp:8001
flutter run -d emulator-5554 --dart-define=APP_ENV=api --dart-define=OPC_API_BASE_URL=http://127.0.0.1:8001

# 普通入口的本地联调包；不包含测试入口的管理令牌
flutter build apk --debug --target=lib/main.dart --dart-define=APP_ENV=api --dart-define=OPC_API_BASE_URL=http://127.0.0.1:8001
```

USB 实机把 `emulator-5554` 替换为设备 ID；ADB reverse 断开后需要重新建立。模拟器也可使用 `http://10.0.2.2:8001`。本地 HTTP 仅用于 debug，release 真实配置要求 HTTPS；未配置、非法地址和 API 故障均不会回退到 Mock。普通 release 的签名、域名与生产服务需独立配置。

默认 `APP_ENV=api`。历史 Mock 仅在显式 `APP_ENV=mock` 下使用；release 演示还需 `OPC_DEMO=true`。真实模式没有模拟审核、演示密码填充、样例 AI 整理或假附件成功。

界面保持日语／简体中文与浅深主题，语言偏好由 SharedPreferences 保存。密码与 token 不存 SharedPreferences；本轮会话在内存中，进程重启或会话到期后重新登录，重新从 PG 获取本人数据。此行为不丢失服务端草稿、需求、消息、交付或验收。

## 4 手机与后台操作顺序

1. 客户注册或登录，填写目标、期限、预算，选取设备真实文件，保存草稿或提交需求。上传后等待文件检查；私有原文与送审发布参考资料分开。
2. 管理员通过 `/api/v1/admin/auth/login` 登录，在 Swagger Authorize 填入管理 token。查看需求、提出澄清；客户刷新并回答。管理 token 不能作为手机 token 使用。
3. 技术人员新增整理范围，明确选择参考文件。安全检查只允许记录已经实际完成的检查证据；未知上传不能自动标 clean。当前范围分别合规、技术审核通过后，运营显式发布。手机刷新后才会在大厅看到发布版本。
4. 普通配置 `assignment_mode=disabled` 不新增合作。测试脚本仅对明确的合成关系启用 `record_confirmed`；已有演示合作可让双方在手机确认条款。尚未决定的正式领取／申请／确认机制未被擅自实现。
5. 当前承接者提交真实源码包，或 HTTPS 仓库地址、完整 commit 和可取得的归档依据，并填写操作说明与测试材料。原文件须完成检查，平台不执行上传代码。
6. 具有 `quality_reviewer` 权限的后台人员或管理员内审并显式对客发布；客户刷新后取得当前正式交付与文件，填写修改反馈或二次确认验收。验收不执行收费、付款或分账。

需求、合作、交付与验收等版本化业务修改使用服务返回的 `row_version`；认证、上传、消息和通知等接口按各自契约处理。版本冲突后刷新并重新检查内容；创建需求、交付和验收使用幂等键，网络失败重试不会回落为本地成功。列表和详情刷新失败必须展示真实错误；账号变更、退出或会话失效清除旧账号快照。

## 5 文件、消息与能力边界

上传使用 multipart，下载读取认证接口的真实字节。元数据、名称、数量、预览、保存、打开与导出受当前身份和发布版本约束；大厅不显示客户原文私有附件，内部交付未发布时不对客户开放。原文件保存复用 APP 原生私有目录与系统导出流程。

图片／MP4／UTF-8 文本使用后端真实内容。Office、Excel、PPT、PDF 的任意格式转换服务尚未配置，真实模式明确提示不能应用内转换，并提供有权访问的原文件下载／系统打开，不回用历史 fixture 伪装预览成功。文本预览有长度上限，原件下载仍保留完整字节。

消息、会话参与关系和站内通知在 PG 持久化；通知已读也调用接口。外部推送、邮件恢复、AI、支付、自动恶意软件扫描和正式认证服务仍未接入。

## 6 自动化验证

```powershell
# APP 单元、模型、HTTP 适配器、真实页面与历史回归
Set-Location D:\OPC\APPClient
flutter analyze
flutter test

# 后端单元与隔离 PG HTTP/并发测试
Set-Location D:\OPC\BackendService
.\.venv\Scripts\python.exe -m pytest -q -m 'not integration'
.\scripts\test-postgres.ps1
.\.venv\Scripts\python.exe -m ruff check app tests scripts
.\.venv\Scripts\python.exe scripts/export_openapi.py

# Android + HTTP + 持久PG完整链路；选择未占用端口
.\scripts\run-mobile-integration.ps1 -Device emulator-5554 -Port 8002
```

Android 脚本创建独立合成测试账号和记录，管理步骤仅在 `integration_test/real_api_smoke_test.dart` 中运行；生成的测试 define 文件保存在忽略目录。结束后撤销该临时管理会话并停止测试服务，PG 记录保留便于检查。测试 APK 不作为交付包，测试后必须重新构建普通 `lib/main.dart` 入口。

日志／截图位于 `APPClient/test_artifacts/real-api`。测试运行使用模拟器不等于实体机、日本网络或 iOS 验证；iOS 仍需 macOS/Xcode。最终通过数量、实际运行命令和已知限制以 [验证记录](../testing/app-backend-integration-2026-10-16.md) 为准。

`scripts/verify-mobile-persistence.py --input ../APPClient/test_artifacts/real-api/integration_response_data.json --output <本机快照路径>` 通过受限角色只读验证指定 Android run 的业务与原文件哈希；重启专用 PG 后加 `--compare <之前快照路径>` 可核对持久化。该脚本不修改数据库，具体已执行命令与结果见验证记录。

本轮已保存普通入口 [API 调试 APK](../../APPClient/build/packages/OPC-0.1.0-android-20261016-api-debug.apk)。最终进程重启／新进程启动与模拟器普通包替换受到自动审批审查限制；现有 8001 仍数据库就绪，最新消息显示名补充需重启服务后生效，普通包需手动安装。不要把模拟器最后残留的测试入口包作为交付应用使用，详情见验证记录的本机服务段。
