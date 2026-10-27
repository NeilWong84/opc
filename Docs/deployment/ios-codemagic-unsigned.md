# OPC iOS 首次无签名云构建

更新：2026-10-27。**OPC iOS 无签名 release 云构建及产物交付已完成。** 第2次构建静态检查无问题、388项测试通过，用户已下载应用 ZIP、日志与汇总包，ZIP 完整性和应用 SHA256 校验通过，云端 Podfile.lock 已取回源工程。尚未签名、真机验证或提交 TestFlight／App Store。

账号与仓库：已连接 [NeilWong84/opc](https://github.com/NeilWong84/opc) 的 `main` 分支；仓库当前实际为 **public（公开）**，不是先前建议的私有仓库。Codemagic GitHub App 已完成安装，仓库访问范围仅选 `opc`。Codemagic 应用 ID 为 `6ae01b17bd00891bf766eb06`，项目路径为 `APPClient`。

前期最小源码暂存仅作为准备记录保留，不是当前构建来源；实际构建从上述 GitHub 仓库拉取。首次提交 `08ef62f263b2e3e277f86ccec9f4e9d96f27441d` 已包含此前清单的152个必需源码及配置，与暂存内容核对一致，未跟踪 iOS 本机生成文件。

## 当前配置

- 入口：仓库根目录 `codemagic.yaml`，工作流 `opc-ios-unsigned`，工作目录 `APPClient`。
- 云端环境：Mac mini M2、Flutter 3.35.5、Xcode 26.3、CocoaPods 1.16.2；保持现有 `pubspec.lock`，不自动升级依赖。
- 手动启动，最长 60 分钟，没有自动触发、代码签名、邮件通知或发布步骤。
- 构建普通入口 `lib/main.dart`，真实 API 模式，地址沿用现有线上测试环境 `https://43.165.191.156/`。编译不需要业务账号、管理令牌或数据库凭据，不调用生产业务流程。
- 显式补充 Flutter CocoaPods 的 `ios/Podfile` 及 Debug/Release xcconfig include。保留当前 iOS 13.0 最低版本和已有 PDFKit／QuickLook／文件导出桥接；是否需要平台调整以实际 Xcode 日志为准。
- 导出修正提交为 `f3fc2ead744590d17246fc146e8ca98d7e0af60f`：日志、应用 ZIP、SHA256 清单及云端生成的 Podfile.lock 直接写入 `$CM_EXPORT_DIR`，`artifacts` 同时引用该绝对变量；不再依赖原 `APPClient/build/ci/*` 相对模式。

构建顺序：记录工具版本与 commit → 下载 iOS Flutter 引擎 → 按锁文件恢复依赖 → 合并双语并生成本地化 → Dart 静态检查和测试 → `pod install` → `flutter build ios --release --no-codesign --no-pub` → 压缩未签名应用。

## 已完成的账号接入与构建边界

1. GitHub 与 Codemagic 已登录，仓库已连接，当前无需再次准备账号或仓库。
2. 本流程不要求本机安装 Xcode，也不要求 Apple Developer 会员、签名证书、描述文件或 App Store Connect API Key。
3. 使用账号内可用构建额度；本次未开通收费项目。后续额度或付款限制以账号页面为准。

现有仓库保留以下手机构建层级；其他模块不参与此工作流：

```text
仓库根目录/
  codemagic.yaml
  APPClient/
    pubspec.yaml
    pubspec.lock
    analysis_options.yaml
    l10n.yaml
    .metadata
    .gitignore
    assets/
    lib/
    test/
    tool/merge_l10n.py
    ios/                  # 保留 .gitignore，排除其中已忽略的生成物
```

手机构建不依赖 BackendService、DB、部署备份、账号资料或数据库数据。后续提交继续排除 `.env`、`.local`、签名私钥、`build/`、`.dart_tool/`、`test_artifacts/`、本机 `Generated.xcconfig`、Pods 或 SDK 路径。仓库当前公开，访问范围限定为一个仓库不改变仓库本身的可见性。

## 已完成的云构建与文件校验

- [第2次构建记录](https://codemagic.io/app/6ae01b17bd00891bf766eb06/build/6ae01d3f4a72334e32e59306)：ID `6ae01d3f4a72334e32e59306`，源码 `f3fc2ead744590d17246fc146e8ca98d7e0af60f`，耗时 **4分41秒**。
- 云端 Dart 静态检查无问题、**388项测试通过**，CocoaPods 安装、Xcode 无签名 release 编译、打包及产物导出通过。
- 用户已将以下文件手动下载至 `D:\Administrator\Desktop`；3个 ZIP 的 CRC 均无错误。

| 文件 | 大小（字节） | 内容 |
| --- | ---: | --- |
| `OPC-ios-unsigned.app.zip` | 9,699,032 | 未签名 Runner.app |
| `opc_2_artifacts.zip` | 8,270 | 构建日志、SHA256 清单、Podfile.lock |
| `opc_2_exported.zip` | 9,640,190 | 完整导出汇总，包含同一应用 ZIP |

应用 ZIP 的 SHA256 与云端清单一致：

```text
ab03629d43a055310bb440c165e4f00fc360c3065bfe85d38086f947e3aaa543
```

完整导出汇总中的应用 ZIP、Podfile.lock 与单独下载／提取的文件一致。包信息核对为 `jp.opc.opcApp`、版本 `0.1.0 (2)`、最低 iOS `13.0`、SDK `iphoneos26.2`、Xcode `2630`；Runner 没有 `LC_CODE_SIGNATURE`，包内没有 mobileprovision，与无签名构建目标一致。

云端生成的锁文件已取回 `APPClient/ios/Podfile.lock`，其 `PODFILE CHECKSUM` 与对应 Git 源码一致。日志保存于忽略目录 `APPClient/test_artifacts/codemagic-2026-10-27/cloud-build-2/`。这些检查确认文件完整性、来源及编译结果，不代表 iPhone 运行或业务功能验证。

维护记录：[首次构建](https://codemagic.io/app/6ae01b17bd00891bf766eb06/build/6ae01b354a72334e32e592a9)（`08ef62f`，4分13秒）已编译23.1 MB的 Runner.app，但原相对模式未收集到产物，显示 `No artifacts were found`；改用 `$CM_EXPORT_DIR` 后第2次构建完成交付。未确认相对路径失配的具体根因，不据此改动项目工作目录。

## 在 Codemagic 启动

1. 后续更新将审查过的源码提交到 `NeilWong84/opc` 的目标分支，当前使用 `main`。
2. 打开已有 Codemagic 应用，检查分支与 commit，选中 `opc-ios-unsigned` 手动构建。
3. 逐项确认编译、打包和产物导出结果；成功收集后下载 `OPC-ios-unsigned.app.zip`、`SHA256SUMS.txt`、日志及 `Podfile.lock`，核对校验值并记录构建 URL、commit 与工具版本。
4. 保留已取回的 `APPClient/ios/Podfile.lock` 并纳入源码版本管理，固定 CocoaPods 原生依赖；后续依赖变更应核对锁文件差异，不手工伪造。

产物是 `Runner.app` 的 ZIP 归档，**不是可直接安装到 iPhone 的签名 IPA**，也未提交 TestFlight／App Store。用户已确认目前只有普通 Apple 账号，尚未付费加入 Apple Developer Program；现已选择 TestFlight 分发路线，下一步先由用户开通开发者会员，生效后配置签名并上传新的构建。目前尚未开通会员、签名或上传。

## 已完成的本地验证

2026-10-27，Windows 上执行：

- Codemagic 官方 JSON schema 校验：0 个错误；不代表账号额度、版本可用性或云端构建成功。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：388 项通过。
- 原生工程只读审查未发现确定的 Swift 编译错误；后续首次云构建已完成实际 Swift、Pods 和 Xcode 编译，见上节。iPhone 运行与文件预览／导出功能仍未验证。

本机分析与测试日志位于忽略目录 `APPClient/test_artifacts/codemagic-2026-10-27/`，第2次云构建日志位于其 `cloud-build-2/` 子目录。首次无签名编译与文件交付目标已完成；后续签名、TestFlight 和真机验证单独记录。

## 后续分发边界

当前未签名 ZIP 不能直接安装。TestFlight 路线需要 Apple Developer Program 会员与已签名构建上传至 App Store Connect；首次向外部测试人员分发需经过测试版审核，见 [Apple 外部测试说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)。

用户另询问蒲公英，尚未选定该路线。蒲公英普通 iOS 托管仍需要有效签名 IPA；Ad Hoc 包必须把目标设备 UDID 纳入描述文件，新增设备后需在 Apple Developer 注册、更新描述文件并重新签名上传。单独上传当前 ZIP 或收集 UDID 不会完成签名。依据见 [蒲公英开发者常见问题](https://static.pgyer.com/doc/view/faq_dev)及 [UDID 管理](https://static.pgyer.com/doc/view/udid_management)。当前未开通会员，也未向任何分发平台上传签名包。

## 官方依据

- [Codemagic Flutter 构建与无签名应用说明](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/)
- [连接源码仓库](https://docs.codemagic.io/getting-started/adding-apps/)
- [YAML、工作目录和产物路径](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)
- [Xcode 26.3 构建镜像](https://docs.codemagic.io/specs-macos/xcode-26-3/)
- [使用 CM_EXPORT_DIR 导出自定义产物](https://docs.codemagic.io/knowledge-others/upload-custom-artifacts/)
