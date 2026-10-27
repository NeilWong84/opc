# APPClient 工程说明

先遵循根 AGENTS.md，并读本目录 README.md、Docs/development/app-backend-integration.md、后端 API 和当前 MasterGo 交接。Mock 契约仅用于历史演示实现与回归。

- 产品端仅 Android/iOS。不要因本机方便而增加 Web 或桌面产品端。
- UI 支持简体中文/日语，默认日语，客户与内部承接者范围一致；登录页与个人页提供切换，SharedPreferences 保存选择。客户原文、消息、附件名不随语言或主题翻译，JPY、JST、业务状态、版本和权限不变。
- 界面文案维护于 `lib/l10n/parts/*_{ja,zh}.json`；先运行 `python tool/merge_l10n.py`，再运行 `flutter gen-l10n`。两种语言的键及占位符保持一致，不用控件内临时替换充当语言包，不手改生成的本地化 Dart 文件。
- 浅深主题用 core/theme.dart 的语义颜色。语言设置只持久化 locale，不保存账号凭证或业务资料；构造 AppController 不调用平台插件，生产入口显式恢复设置。
- 页面经 OpcRepository 读写；模拟业务放 `data/mock_repository.dart`，参考资料合成内容集中在 `data/reference_samples.dart`。Mock 与真实 API 边界必须明确。
- 默认真实模式使用 ApiOpcRepository / RemoteOpcRepository 和 features/api_* 页面；HTTP token仅内存，真实业务持久PG。同步读方法是已加载快照，进入/返回前台/刷新要重新请求服务端；失败不可返回Mock成功或继续展示另一账号数据。未配置要停在配置页，debug本地HTTP与release HTTPS分别校验。
- 真实需求表单用设备文件上传后的file ID，允许私有pending原文提交，文件读取/参考发布/交付仍受clean条件。正文、条款、完整范围、通知模板、文件状态均使用真实API；未接入的AI/恢复/转换不能用模拟内容替代。源码固定版本、双审、条款双方确认与客户验收在服务端校验。
- 已发布任务参考资料使用 `data/reference_models.dart`、`reference_samples.dart` 和 repository 的资料访问方法，与需求/交付表单的模拟附件名称分开。查询、名称、计数、缩略图、预览、读取字节、保存、完成、打开和导出都必须按当前身份与当前发布版本重新校验，不能只依赖进入页面时的检查。
- `assets/references/` 的样例是可打开的真实文件，Office/PDF/表格/文本应用内预览仍来自结构化 fixture；不声称支持任意文件解析/转换、宏、公式执行或生产视频服务。`manifest.json` 的大小、尺寸、页数与时长须取实际资源值。不得改动 `Mockup/task-reference-assets` 原图或伪造 DOC/XLS/PPT 二进制。
- 下载经可注入 `ReferenceFileStore` 分块写应用专属目录，取消/失败清理未完成文件，仅真实完成后置成功。Android `FileProvider` 只授权专属参考文件目录；原生平台在系统选择目标后复核 authorize，iOS 使用 security-scoped 文件夹导出。权限变化不能宣称收回已导出的副本；不要扩大存储权限或开放任意路径。
- 移动端没有正式后台审核权。真实界面不提供模拟审核和演示凭据；历史开发场景只能在显式Mock模式。保持 release 的显式演示门禁、真实HTTPS要求和未配置页。Android E2E 的管理令牌仅在测试入口临时注入、运行后撤销；交付APK必须重新构建 lib/main.dart，不能使用测试包。
- 未审核或未发布需求不能进入大厅；内部授权不等于认证；咨询不确定接单；内部检查不等于客户验收或付款。
- 变更关键状态时运行对应 tests；完成前运行 flutter analyze 与 flutter test。原生构建/设备检查分别记录平台与实际结果。
- iOS 构建需 macOS + Xcode，不能把 Windows 下 Dart/widget 测试当成 iOS 构建通过。
- 保留 pubspec.lock；不提交 build、.dart_tool、IDE缓存、本机SDK路径或签名密钥。
