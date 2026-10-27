# APPClient 参考资料同步与验证

日期：2026-10-13。来源为用户已确认的 MasterGo 大厅/详情浅深修订及新增 18 个预览与状态画板。本记录区分 Flutter 本地样例交互、Android 设备证据和未接入的生产能力。

## 已实现范围

- 大厅按实际存在的图片、视频和附件展示；只有附件时使用紧凑行，没有资料时不保留媒体空位。详情增加独立参考资料区及完整列表，保留咨询操作与原业务规则。
- 图片双指缩放、未放大时滑动切换、缩略图/前后切换；真实 8 秒 MP4 默认不自动播放，支持播放暂停、定位、静音及全屏，进入后台暂停，权限失效停止和释放播放器。
- Word/PDF 按页查看、页码跳转及缩放；Excel 工作表切换、横向浏览、搜索与单元格查看，CSV 单表；PPT 页码/缩略图切换及全屏；TXT 阅读、Markdown 基础排版/原文及字号调整。
- 预览准备、失败、暂不支持分别显示；可重试的预览重新读取当前权限。下载原样例字节，分块写临时文件后原子完成，支持取消、失败重试、打开和导出。避免重复打开系统保存窗口。
- 界面沿用中日语言包和浅深主题，日语/简体中文各 472 条资源；原文、文件名、截图颜色及文档白纸不随界面语言/主题改写，不添加 Mock 角标。
- 所有资料入口按当前发布版本过滤；私有和旧版资料不进入大厅数量、文件名、封面或预览。打开中的预览和下载弹层在权限失效后清除内容。弹层固定点击时文件和会话，列表复用不使其切换到另一附件。

对应源码入口：[资料预览](../../APPClient/lib/features/reference_preview_page.dart)、[列表与场景](../../APPClient/lib/features/reference_pages.dart)、[展示与下载入口](../../APPClient/lib/features/reference_widgets.dart)、[文件保存](../../APPClient/lib/core/reference_download.dart)、[资料模型](../../APPClient/lib/data/reference_models.dart)。

## 自动化与设备检查

环境：Windows，Flutter 3.35.5 / Dart 3.9.2，Android API 36.1 x86_64 模拟器。没有连接实体手机，也没有 macOS/Xcode。

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze` | 无问题 |
| `flutter test --reporter expanded` | 282 项通过；原 174 项 + 本次资料相关 108 项 |
| 资料 repository | 21 项，包含当前发布版本、私有/旧版过滤、归属、授权撤回、异步重验和不可变快照 |
| 大厅/详情/列表 | 26 项，包含有图/视频、仅附件、无资料、列表与预览路由、中日浅深及窄屏/大字号 |
| 预览页 | 38 项，包含操作、分页/搜索、撤权、视频生命周期、320 宽/1.5 字号 |
| 原文件保存 controller | 17 项，包含分块字节、原子完成、失败/取消/立即重试、销毁、异步权限、平台调用 |
| 下载 widget | 6 项，包含真实 asset 字节、打开导出、取消重试、弹层撤回、行复用、切换图片；最终防重复导出改动后 6 项再次通过 |
| Android 设备集成 | 2 项业务测试通过：真实原生视频初始化/播放/暂停/静音/全屏和样例保存；双语浅深各格式/状态显示 |

设备集成生成 70 张实际截图：中日 × 浅深 × 17 个页面/状态，共 68 张，加原生视频播放和下载完成 2 张。每组含大厅首屏及资料区、详情首屏及资料区、列表、图片/视频/Word/PDF/Excel/PPT/MD/CSV/TXT 和准备中/失败/暂不支持。图片保持原始内容，Word/PDF/PPT 为结构化样例预览。纯文字无资料场景已有 widget 断言，本批没有单独的设备截图。

完成了大厅/详情/列表/异常状态 32 张和各格式代表 12 张的视觉复核。发现并修复 Markdown 空行叠加行高，随后重新运行设备集成刷新全部 70 张截图，并复核修正后的 Markdown。无文字溢出、关键按钮遮挡或暗色反转原始内容的问题。设备截图与测试断言不等于实体手机或 iOS 完整验收。

本机可再生证据：

- [静态检查日志](../../APPClient/test_artifacts/analyze-reference-20261013.log)、[282 项测试日志](../../APPClient/test_artifacts/test-reference-20261013.log)、[最终下载 widget 回归](../../APPClient/test_artifacts/test-reference-download-final-20261013.log)。
- [Android 集成日志](../../APPClient/test_artifacts/integration-reference-20261013.log)，截图位于 `APPClient/test_artifacts/android/reference-*.png`。
- [中文浅色详情资料区](../../APPClient/test_artifacts/android/reference-zh-light-00-detail-references.png)、[日语暗色资料列表](../../APPClient/test_artifacts/android/reference-ja-dark-01-list.png)、[中文 Markdown](../../APPClient/test_artifacts/android/reference-zh-light-08-markdown.png)、[视频实际播放](../../APPClient/test_artifacts/android/reference-native-video-playing.png)。

`test_artifacts` 和 `build` 被工程忽略规则排除，其他机器须按命令重新生成。设备截图驱动运行后输出 APK 使用测试入口；普通应用交付必须重新构建 `lib/main.dart`，不要把测试 APK 作为安装包。正式构建与其他 Flutter 生成/测试命令应串行执行，避免平台插件注册文件被同时重写。

## Android 安装包与系统导出

[下载最新 APK](../../APPClient/build/packages/OPC-0.1.0-android-20261013-media.apk)。包名 `jp.opc.opc_app`，版本 `0.1.0+2`，文件大小 **53,123,062 bytes**（约 50.7 MiB），Android 7.0 / API 24 起，target API 36，含 `armeabi-v7a`、`arm64-v8a` 和 `x86_64`。

```text
APK SHA-256
7453DDEC96E7D617AB4E85FCE5D359D257DB286A88DD99A4AC4AD53E99885740
```

普通入口构建命令：

```powershell
flutter build apk --release --target=lib/main.dart --dart-define=APP_ENV=mock --dart-define=OPC_DEMO=true
```

最终 APK v2 签名检查通过，保留工程已有 debug 测试签名。模拟器安装成功，`am start -W` 返回 `Status: ok` 和 `LaunchState: COLD`；手动使用内置成员账号登录，进入大厅和资料列表，实际文件大小显示为新资源值（PDF 54 KB）。

在该普通 release APK 的 PDF 下载弹层完成原文件保存，点击「書き出す」进入 Android 系统保存对话框，保存到模拟器 Downloads。导出文件 `業務フロー.pdf` 为 **55,365 bytes**，SHA-256 为 `AF3330ED482B0C7B0FF2772CCB38F1E19B9B3DD1B1FBB30EC1A257DF915FF7EF`，与打包原 asset 完全一致。随后「開く」通过系统 PDF 查看器显示三页日文内容。最后强制停止并再次冷启动普通应用成功。

证据：[构建日志](../../APPClient/test_artifacts/build-reference-apk-20261013.log)、[签名](../../APPClient/test_artifacts/signature-reference-apk-20261013.log)、[APK 元数据](../../APPClient/test_artifacts/metadata-reference-apk-20261013.log)、[已安装版本](../../APPClient/test_artifacts/installed-reference-apk-20261013.log)、[冷启动](../../APPClient/test_artifacts/launch-reference-apk-20261013.log)、[导出 SHA-256](../../APPClient/test_artifacts/export-reference-sha256-20261013.log)、[系统 PDF 查看器](../../APPClient/test_artifacts/android/reference-release-open-pdf.png)。

账号：内部成员 `member@opc.demo`，客户 `customer@opc.demo`，密码均为 `demo1234`。旧不带 `-media` 后缀的 APK 保留，版本号为 1，未包含本次参考资料功能。

## 资源与实现边界

12 份有效的本地合成资源和 SHA-256 见 [manifest](../../APPClient/assets/references/manifest.json)。三张 PNG 与设计原图一致，MP4 为两张原创界面组成的 8 秒视频。DOCX/PDF/PPT 各 3 页，字段表 3 个工作表，CSV 单表；报价样例包含有效公式。PDF 内嵌日文字体，PDF、表格和幻灯片已完成独立渲染检查。DOCX 可检查结构与显式分页，但本机缺少 LibreOffice，未宣称 DOCX 原文件视觉渲染通过。

应用内 Office/PDF/文本预览读取 repository 的结构化样例内容，尚未实现任意上传文件解析、Office 转换、OCR、公式/宏执行或云端文件服务。旧 DOC/XLS/PPT 归入对应预览类型，未伪造旧格式二进制文件。

Android 使用限制在应用参考文件目录的 FileProvider 打开，系统文件选择器导出；iOS 已实现 QuickLook 和选择目标文件夹后重新授权再复制，但 **未在 Xcode 编译、签名或运行**。本地访问校验不替代未来服务端权限，已导出的副本不能追回。需求提交/交付中的原有附件标签仍不是实际上传。

release 的 `APP_ENV=mock` 与 `OPC_DEMO=true` 演示配置门禁保持；真实认证、后台、消息和支付未接入。资料预览不改变待决接单机制，不把内部授权标为正式认证。
