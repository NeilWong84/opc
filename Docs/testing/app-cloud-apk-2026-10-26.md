# Android 云端测试 APK（2026-10-26）

用户要求重新打包 Android，后端地址为 `https://43.165.191.156/`。本次只生成安装包和说明，没有重启服务器、修改数据库或覆盖现有模拟器安装。

## 交付

- APK：`APPClient/build/packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk`。
- 同目录附 `.apk.sha256` 校验文件与 `.apk.json` 构建信息。
- 包名 `jp.opc.opc_app`，版本 `0.1.0`／versionCode `3`，Android 7.0（API 24）及以上；通用包包含 ARM64、ARMv7 与 x86_64。
- 普通 `lib/main.dart` 的 Release／API 模式；源地址固定为用户指定的 HTTPS origin，由数据层添加 `/api/v1`。不需要 ADB reverse，也不依赖本机8001服务。
- 复用工程现有 Android Debug 签名，可供安装测试；组织的应用商店正式签名仍未配置。本次没有创建或更换密钥。

## 实际验证

- 构建完成：Flutter 报告 `app-release.apk (54.6MB)`。
- Android `aapt` 核对包名、版本、SDK及三个架构，未出现 `application-debuggable`。
- `apksigner verify --verbose --print-certs` 返回 `Verifies`，APK Signature Scheme v2 验证通过。
- 三个架构的 AOT `libapp.so` 均包含 `https://43.165.191.156/`；包内无 debug kernel、`.env` 或演示凭据JSON文件。
- 使用标准证书信任链访问远程 `/health/ready`，HTTPS验证通过、HTTP200、`status=ready`。没有绕过TLS或添加信任所有证书代码。
- 本轮未在Android设备安装、登录或操作云端业务；以上服务器就绪检查不等于手机全部业务验收。

首次 `--no-pub` 构建遇到旧集成测试插件注册残留。重新运行锁定依赖的 `flutter pub get`，由Flutter重新生成普通插件注册，并在本次进程禁用Kotlin增量缓存后成功；没有修改业务源码或删除旧APK。

构建命令：

```powershell
Set-Location D:\OPC\APPClient
flutter pub get
flutter build apk --release --target=lib/main.dart --build-number=3 --dart-define=APP_ENV=api --dart-define=OPC_API_BASE_URL=https://43.165.191.156/
```

日志位于忽略目录 `APPClient/test_artifacts/cloud-apk/`。本机开发运行仍可显式传原本地地址；云端与本地两处数据后续写入不会自动同步。
