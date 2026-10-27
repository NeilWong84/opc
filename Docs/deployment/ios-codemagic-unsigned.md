# OPC iOS 首次无签名云构建

更新：2026-10-27。用户已选择 Codemagic，先验证 APPClient 的 iOS 原生编译。当前完成本地配置准备，**尚未启动或通过 Codemagic 构建，也未生成 iOS 应用包**。

账号接入进展：用户已登录 GitHub `NeilWong84`，并明确同意 Codemagic 身份授权；网页已进入登录后的个人项目接入流程。GitHub App 安装页已选择“Only select repositories”，尚未提交仓库访问授权。现待确定既有私有仓库或新建 `opc-mobile`，没有上传源码或启动云构建。

最小源码已独立暂存至 `C:\Users\Administrator\Documents\Codex\2026-10-08\d\work\opc-ios-upload-20261027`：153 文件、2,283,846 字节，其中152个复制文件逐项SHA256与本地源文件一致，另加根README。该目录尚未初始化Git。清单与校验报告位于同工作区的 `outputs/opc-ios-upload-20261027-manifest.json` 和 `outputs/opc-ios-upload-20261027-SHA256SUMS.txt`，不进入待上传源码。实际上传前仍需确认仓库目的地及暂存后源文件是否变化。

## 当前配置

- 入口：仓库根目录 `codemagic.yaml`，工作流 `opc-ios-unsigned`，工作目录 `APPClient`。
- 云端环境：Mac mini M2、Flutter 3.35.5、Xcode 26.3、CocoaPods 1.16.2；保持现有 `pubspec.lock`，不自动升级依赖。
- 手动启动，最长 60 分钟，没有自动触发、代码签名、邮件通知或发布步骤。
- 构建普通入口 `lib/main.dart`，真实 API 模式，地址沿用现有线上测试环境 `https://43.165.191.156/`。编译不需要业务账号、管理令牌或数据库凭据，不调用生产业务流程。
- 显式补充 Flutter CocoaPods 的 `ios/Podfile` 及 Debug/Release xcconfig include。保留当前 iOS 13.0 最低版本和已有 PDFKit／QuickLook／文件导出桥接；是否需要平台调整以实际 Xcode 日志为准。

构建顺序：记录工具版本与 commit → 下载 iOS Flutter 引擎 → 按锁文件恢复依赖 → 合并双语并生成本地化 → Dart 静态检查和测试 → `pod install` → `flutter build ios --release --no-codesign --no-pub` → 压缩未签名应用。

## 用户需要准备的内容

1. 登录或注册 [Codemagic](https://codemagic.io/)。首次构建不要求本机安装 Xcode，也不要求 Apple Developer 会员、签名证书、描述文件或 App Store Connect API Key。
2. 提供存放 OPC 手机端源码的私有 GitHub／GitLab／Bitbucket 仓库。2026-10-27 检查时，`D:\OPC` 和 `APPClient` 都没有 `.git`，已连接 GitHub 的可见仓库中也未找到 OPC；不据此假定用户其他账号没有仓库。
3. 在 Codemagic 添加该仓库的应用并授予访问所需仓库的权限；使用账号内可用的构建额度。额度、付款或团队限制以账号页面为准，本次尚未开通收费项目。

若首次新建专用手机构建仓库，保留以下层级，使本地配置可直接使用：

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

这份最小构建源码不需要 BackendService、DB、部署备份、账号资料或数据库数据。同步前应核对实际提交清单；不把整个本地 OPC 目录直接上传。不得包含 `.env`、`.local`、签名私钥、`build/`、`.dart_tool/`、`test_artifacts/`、本机 `Generated.xcconfig`、Pods 或 SDK 路径。后续如使用全项目仓库，应先补全各模块忽略规则并审查提交内容。

## 在 Codemagic 启动

1. 将审查过的源码和配置提交到已选私有仓库。
2. 在 Codemagic 的 **Add application** 中连接仓库；按实际页面选择使用 `codemagic.yaml` 的配置方式。
3. 选择有该配置文件的分支，检查配置，选中 `opc-ios-unsigned`，手动开始一次构建。
4. 成功后下载 `OPC-ios-unsigned.app.zip`、`SHA256SUMS.txt`、日志及 `Podfile.lock`；记录构建 URL、commit、工具版本及实际结果。失败时保留失败阶段日志后修复，不能把 Dart 测试通过当成 iOS 构建通过。
5. 第一次成功后，将实际生成的 `ios/Podfile.lock` 带回源码并提交，以固定 CocoaPods 原生依赖。当前 Windows 没有生成该锁文件，不手工伪造。

产物是 `Runner.app` 的 ZIP 归档，**不是可直接安装到 iPhone 的签名 IPA**，也未提交 TestFlight／App Store。后续真机分发需单独完成签名与分发配置。

## 已完成的本地验证

2026-10-27，Windows 上执行：

- Codemagic 官方 JSON schema 校验：0 个错误；不代表账号额度、版本可用性或云端构建成功。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：388 项通过。
- 原生工程只读审查未发现确定的 Swift 编译错误；实际 Swift、Pods 和 Xcode 编译仍未验证。

本机分析与测试日志位于忽略目录 `APPClient/test_artifacts/codemagic-2026-10-27/`。Codemagic 已登录，目前下一步是确定私有仓库并完成限定范围的仓库授权。

## 官方依据

- [Codemagic Flutter 构建与无签名应用说明](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/)
- [连接源码仓库](https://docs.codemagic.io/getting-started/adding-apps/)
- [YAML、工作目录和产物路径](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)
- [Xcode 26.3 构建镜像](https://docs.codemagic.io/specs-macos/xcode-26-3/)
