# OPC APPClient

2026-10-27：[Codemagic iOS 无签名构建](../Docs/deployment/ios-codemagic-unsigned.md) 已完成。公开仓库 `NeilWong84/opc` 的 main 已接入，GitHub App 仅授权 opc；第2次构建 `6ae01d3f4a72334e32e59306` 使用 `f3fc2ea`，4分41秒完成静态检查、388项云端测试、Xcode release 无签名编译及导出。用户已下载应用 ZIP 与日志包至 `D:\Administrator\Desktop`，CRC／SHA256 核验通过，`ios/Podfile.lock` 已取回；应用为 `jp.opc.opcApp`、`0.1.0 (2)`、最低 iOS 13.0。尚未签名、真机验证或 TestFlight 分发。

Flutter + Dart 手机端，包含客户与内部承接者完整移动业务入口，支持日语／简体中文和系统／浅色／深色主题。视觉继续沿用 [MasterGo V1](../Mockup/app-v1-mastergo/README.md) 的语义配色、卡片、导航与资料浏览设计。

**2026-10-16 起默认使用真实 BackendService HTTP API。** 注册登录、需求草稿与提交、运营澄清、发布大厅、合作条款确认、消息、固定版本交付、修改与验收、通知和文件均通过受权限控制的后端访问；业务记录持久化 PostgreSQL。网络或权限失败不会回退到模拟成功。FrontendAdmin 尚未接入真实服务，联调运营步骤使用 Swagger／管理 API。

## 启动真实应用

工程使用 Flutter 3.35.5 stable、Dart 3.9.2；依赖以 `pubspec.lock` 为准。新增 `http`、`file_picker`、`path_provider`，继续使用官方 `shared_preferences` 与 `video_player`。仅有 Android／iOS 产品端。

1. 按 [BackendService README](../BackendService/README.md) 启动持久 PostgreSQL、初始化演示场景并启动普通 API 服务：`scripts/start.ps1 -Port 8001`。
2. 本地演示账号及随机密码从已忽略的 `BackendService/.local/demo-credentials.json` 读取。真实登录页不填入账号或密码；这个文件不得放入安装包或提交 Git。
3. 在 Android 模拟器或 USB 连接的调试设备执行：

```powershell
Set-Location D:\OPC\APPClient
flutter pub get
python tool/merge_l10n.py
flutter gen-l10n
adb reverse tcp:8001 tcp:8001
flutter run -d emulator-5554 --dart-define=OPC_API_BASE_URL=http://127.0.0.1:8001
```

`APP_ENV` 默认 `api`；`OPC_API_BASE_URL` 是服务 origin，适配器添加 `/api/v1`。未配置、错误环境或非法地址停留在配置提示页。普通 release 只接受不含凭据的 HTTPS 地址；debug 仅为 localhost、127.0.0.1、10.0.2.2、IPv6 loopback 放行 HTTP 地址。Android 原生 debug 网络规则限定 IPv4 loopback、localhost 和模拟器宿主地址；默认 release 不开放明文流量。真机远程联调应使用 HTTPS。

```powershell
# 普通应用入口的本地调试安装包；不是 integration_test 入口包
flutter build apk --debug --target=lib/main.dart --dart-define=OPC_API_BASE_URL=http://127.0.0.1:8001

# 有正式 HTTPS 服务地址后才能构建对应的 release；签名仍需正式配置
flutter build apk --release --target=lib/main.dart --dart-define=OPC_API_BASE_URL=https://your-api.example.jp
```

Android 工程标识 `jp.opc.opc_app`；iOS 为 `jp.opc.opcApp`。Android release 模板当前仍使用调试签名，不能作为商店发行配置。iOS 需要 macOS + Xcode；2026-10-27 已在 Codemagic 完成无签名 release 编译，未做签名、iPhone 真机验证或 TestFlight／App Store 分发。

2026-10-26 已按用户要求生成云端 Android Release 测试包，后端为 `https://43.165.191.156/`，版本 `0.1.0 (3)`。安装包及 SHA256 位于 `build/packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk`；沿用现有测试签名，未覆盖本机模拟器。构建命令与实际验证见[云端 APK 记录](../Docs/testing/app-cloud-apk-2026-10-26.md)。

## 真实业务操作

- 2026-10-26 客户提交需求的“期望完成时间”改为日历选择；字段不再自由输入，点击字段或图标选择日期，新选值按 `YYYY-MM-DD` 保存。旧草稿文字保留，正式提交前提示选择具体日期；中日显示及取消恢复见[日期选择验证](../Docs/testing/app-request-completion-date-2026-10-26.md)。

- 2026-10-26 承接者采用首页／任务大厅／项目／沟通记录／个人设置五个底栏：独立汇总本人沟通中、进行中、已交付项目；大厅检索当前审核发布且未被承接的任务。与客户独立沟通，提出发布版本条款，客户先确认后承接者一键承接并进入执行中。项目及沟通卡片提供“提交交付物”，先定向刷新再打开。详见[流程与契约](../Docs/development/provider-claim-workflow.md)及[验证记录](../Docs/testing/app-provider-claim-2026-10-26.md)。

- 2026-10-26 新增客户需求“开发端／开发类型”组合筛选，与首页进入的状态筛选共同生效；提交表单可选择一个主要开发端及一个开发类型，草稿保存、恢复及正式提交保留稳定代码。选项来自服务端中日双语字典，界面切换不翻译客户原文，旧需求显示未分类。用户随后要求更新，现已加载新版8001，并协调安装包含客户／承接者两边源码的普通APP到模拟器，包哈希与分类交付快照一致。源码、真实接口及安装核对见[分类记录](../Docs/testing/app-client-request-classifications-2026-10-26.md)。

- 2026-10-26 客户底栏为“首页／需求／提交需求／沟通记录／个人设置”，中间“提交需求”直接进入现有表单，返回保留当前页签与需求筛选。各状态需求列表移除重复提交卡片；首页保留新需求／继续草稿快捷入口；承接者仍为四个页签。见[本轮验证](../Docs/testing/app-client-customer-navigation-2026-10-26.md)。

- 2026-10-25 详情仅重取当前需求、当前合作进度与会话反馈，相关操作后也仅更新当前需求；进入详情和恢复前台不触发后台工作台的账号全量刷新。附件、参考及交付资料统一彩色类型卡片，封面不会触发原文件预览。问题定位、接口采样和验证见[本轮记录](../Docs/testing/app-detail-loading-and-file-cards-2026-10-25.md)。

- 2026-10-25 客户“首页”已独立为项目总览，汇总本人需求审核、合作进度、待验收及完成数量，集中展示补充／条款／验收待办和当前承接者反馈；统计可跳到“需求”对应筛选。需求页保留完整列表；刷新及返回详情后重取服务端快照。见[改版验证](../Docs/testing/app-client-customer-home-2026-10-25.md)。

- 客户注册仅创建客户账号；内部人员由后台授权，与正式 OPC 认证分开。登录令牌只保存在进程内存，应用重启需重新登录；未将账号密码或业务记录写入 SharedPreferences。
- 客户底栏“提交需求” → 填写原始描述、期望时间与预算。可将未完整填写的内容保存为服务端草稿；正式提交校验必填与长度。需求进入后台审核，未审核发布内容不进入大厅。
- 附件通过系统文件选择器读取实际字节并上传，不再选择合成文件名称。单次选择一个、客户端最多 20 MiB，服务端仍独立限制大小与格式。私有草稿／需求允许 pending 安全检查附件；预览、下载、公开参考资料及交付要求 clean。未知文件不会由手机端自动标记为已检查。
- 客户可在详情答复运营澄清；合作执行期间新增的澄清仍走正式答复接口。普通消息与澄清答复分开记录。
- 内部授权账号可查看服务端实际发布的大厅、当前发布版本资料与本人合作。咨询不领取任务或创建合作；普通服务接单策略保持 `disabled`，不引入抢单或竞标。
- 已记录合作的双方在手机详情核对完整范围、排除项、交付物、验收标准、修改约定、报价与期限，并逐版本确认条款。后台修改条款后双方需重新确认。
- 承接者提交固定源码交付：选择已检查的源码包，或者填写仓库 HTTPS 地址、完整小写 40／64 位 commit SHA 及客户可取得源码的归档证据；同时填写实际操作说明、测试命令与结果、交付说明。客户只看到后台检查后已对客发布的版本。
- 客户可对当前已发布交付申请修改或二次确认验收；验收记录与付款无关。版本冲突显示错误并保留表单输入，刷新后核对最新记录再操作。
- 站内通知取自服务端记录，可标记已读；没有模拟通知计数、自动生成聊天回复或推送成功假象。列表／详情有刷新入口，恢复应用前台时重新读取或复核权限。

## 真实资料与下载

2026-10-26 视频预览已增加全屏、当前时间／总时长、进度拖动、前后跳转10秒、静音、倍速及结束后重播；全屏复用同一个控制器，返回保留位置。音频共用播放控制；后台暂停及恢复权限复核保持有效。见[实现和验证](../Docs/testing/app-video-controls-2026-10-26.md)。

客户私有附件、当前大厅明确发布的参考资料及有权读取的交付文件分别来自服务端。文件名称、元数据、原件与预览都通过 Bearer 身份及服务端对象权限校验；不根据本地 fixture 生成结果。

- PNG/JPEG/WebP 使用真实图片字节，支持缩放；MP4 从鉴权接口取得真实字节后使用专属临时文件播放、暂停和定位。应用转入后台时暂停，恢复时先复核权限。TXT/MD 显示服务端返回的原文，服务端截断时明确提示下载完整文件。
- 2026-10-25 已加入真实 PDF 逐页查看与缩放、Word／Excel／CSV／PPT 的本机只读转换、音频播放，以及正文平台文件卡片。“保存到手机文件”直接下载原件并调用系统位置选择器；转换或解码失败仍可保存原件。详见[正文与附件预览](../Docs/development/app-file-preview.md)。
- 下载沿用 `ReferenceDownloadController` 的分块写入、取消、失败清理、完整完成和原生打开／导出流程。真实模式增加异步服务端权限复核，系统保存位置选择结束后再次请求授权；未完成或被拒绝的操作不会显示保存成功。
- 文件页监听账号变化，身份失效立即清除名称与预览、暂停播放；文件 HTTP 401 会同步根页面并返回登录。权限变化可以阻止后续读取／打开／导出，不能收回此前用户导出的副本。
- Android 复用受限 FileProvider 和系统保存对话框，未新增通用外部存储权限。iOS 原生 QuickLook／PDFKit／安全域导出已通过 Xcode 云端编译，预览与导出功能仍待真机验证。

## 代码与测试入口

| 文件 | 责任 |
| --- | --- |
| `lib/core/app_config.dart`、`lib/main.dart` | 默认 API 模式、地址与 release 门禁、显式历史 Mock 注入 |
| `lib/data/api_client.dart`、`api_repository.dart` | HTTP、会话、错误／幂等、服务端快照与业务命令 |
| `lib/data/repository.dart`、`models.dart` | RemoteOpcRepository 与纯 Dart 数据模型 |
| `lib/features/auth_page.dart` | 真实注册登录、双语切换、密码校验 |
| `lib/features/api_workspace.dart` | 工作台、大厅／项目、通知、设置、网络异常与刷新 |
| `lib/features/api_work_page.dart` | 当前范围、合作确认、澄清／消息、成果与验收 |
| `lib/features/api_forms.dart` | 需求／草稿、固定版本交付、真实文件选择上传 |
| `lib/features/api_file_page.dart`、`core/reference_download.dart` | 真实预览、权限恢复、原件保存与原生打开导出 |
| `test/api_repository_test.dart` | 真实适配器 HTTP 契约、服务错误、幂等与权限测试 |
| `test/api_ui_test.dart` | API 模式表单、范围确认、验收、消息、双语主题、离线、会话失效测试 |
| `integration_test/real_api_smoke_test.dart` | Android 真实 HTTP／PostgreSQL 业务闭环 |
| `integration_test/provider_claim_flow_test.dart` | 承接者首页计数、大厅检索、客户确认条款、一键承接与提交交付物的 Android 真实全流程 |
| `tool/verify_normal_apk.py` | 普通 debug 包入口及测试代码／测试凭据排除检查；避免集成包误交付 |

```powershell
flutter analyze
flutter test

# 后端目录执行，使用独立8002测试API进程和持久PG
Set-Location D:\OPC\BackendService
.\scripts\run-mobile-integration.ps1 -Device emulator-5554 -Port 8002
```

测试服务仅在本次测试进程内允许记录合成合作关系，测试会使用独立账号和 UUID；管理凭据不进入普通 APP 入口包。运行结束后必须重新构建 `lib/main.dart` 普通安装包，不能将带管理测试流程的 integration_test APK 当作应用交付。

2026-10-16 本轮静态检查无问题；全量 318 项 Dart／widget 测试通过，包含文件 HTTP 401 返回登录与远端撤权保存／打开／导出检查。最新汇总数量、Android 实测结果及普通 APK 以 [真实联调验证](../Docs/testing/app-backend-integration-2026-10-16.md) 为准。日志位于被忽略的 `test_artifacts/real-api/`，源码克隆后可重跑。设备验证不等于 iOS 或生产验收。

## 双语维护

`lib/l10n/parts/*_{ja,zh}.json` 是唯一界面文案源，当前中日各 616 条。运行 `python tool/merge_l10n.py`、`flutter gen-l10n` 后提交生成结果，不手工修改生成的 Dart 文件。登录页／个人设置的语言选择通过 SharedPreferences 保存；默认日语，退出与重启后保留语言。切换界面语言不翻译客户原文、聊天、文件名和条款，也不改变 JST、JPY、权限或业务版本。

## 历史 Mock 与旧设备证据

2026-10-12～13 的九屏、参考资料结构化预览与本地样例资源仍保留在旧 `features/*`、`data/mock_repository.dart`、`data/reference_samples.dart` 和 `assets/references/`，供历史回归测试与明确请求的演示使用。其单测／截图和旧媒体 APK 仅证明当时的内存 Mock 功能，不代表当前 API 连接或真实文件转换。

只有显式 `--dart-define=APP_ENV=mock` 才进入旧界面；release 还须显式 `--dart-define=OPC_DEMO=true`。旧 `customer@opc.demo`／`member@opc.demo` 与 `demo1234` 仅供该历史数据源，真实 API 不使用这些凭据，也不显示填入按钮。旧 AI 整理、演示审核、假文件标签与本地情景控制不会出现在默认真实模式。

历史资料：[Mock 数据契约](../Docs/development/app-client-mock-contract.md)、[参考资料验证](../Docs/testing/app-client-reference-2026-10-13.md)、`test_artifacts/android/`。旧 174／282 项测试和旧 APK 记录不能替代本轮真实 HTTP＋PG 验证。

## 仍未接入的能力

邮件验证／找回密码、推送、自动文件扫描、AI、支付、正式认证及生产部署尚未完成。FrontendAdmin 已接入真实管理 API，Office/PDF 预览进展以上文 2026-10-25 说明为准。当前数据服务是真实持久化的开发联调环境；正式身份恢复策略、供应商、签名与部署仍需按生产要求落实。
