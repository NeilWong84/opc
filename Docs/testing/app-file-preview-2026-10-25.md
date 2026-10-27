# 手机文件预览与保存验证

日期：2026-10-25。实现、部署及格式边界见[手机正文与附件预览](../development/app-file-preview.md)。本轮不新增数据库表，也不修改原六条迁移。

## 结果

- 后端 Ruff 通过；121 项非集成单测通过。随后 `scripts/test-postgres.ps1` 使用独立 `55439/opc_test_*` 临时实例，全量 **144 项通过**。包含真实 DOCX／XLSX／PPTX／CSV／PDF 预览、WAV 实际字节、原件下载、pending 拒绝、陌生账号隔离和缓存生成后安全状态撤销。
- 另将已知合成的 DOCX／XLSX／PPTX 样例实际导出为 DOC／XLS／PPT，再通过预览转换器转为 PDF，三类均成功。Word、表格和幻灯片的实际页面已渲染为 PNG 并检查，没有使用历史结构化样例替代真实文件内容。
- Flutter 最终静态检查无问题，全量 **333 项测试通过**。覆盖客户首页、消息身份区分、正文平台引用、PDF 页数与关闭、未授权及会话失效等回归。
- `file_preview_smoke_test.dart` 在 Android 实际使用原生 PdfRenderer 打开三页 PDF，切换第一页／第二页，完成系统文件选择器保存。手机 Downloads 取回 **55,365 字节**原件，与输入文件 SHA256 一致。
- 新增音频的 Android 验证在独立无窗口设备 `emulator-5556` 完成：实际 WAV 初始化、播放、暂停断言通过。验证中发现并修复临时目录的创建方式；完成后已关闭并清理此验证设备。
- 普通 `lib/main.dart` 的真实 API APP 已重新安装到用户可见的 `emulator-5554`；后续验证不覆盖该设备。最终普通调试包位于 `APPClient/build/packages/OPC-0.1.0-android-20261025-api-debug.apk`，附 `.sha256`。
- 另从可见模拟器取回实际已安装的 base.apk，核实包含 `ApiCustomerHome`、手机保存和 `opc-media-` 临时目录修复，并且不含 `PdfPhoneRepository` 验证入口；普通包与旧 2026-10-16 包的 SHA256 不同，交付包已确认包含新 PDF 原生桥接。
- 用户手动重启 8001 后，已核对 `/health/ready` 为 ready（6 条迁移），当前 OpenAPI 声明 `application/pdf` 与 `audio/wav` 的预览响应，确认服务加载新版。

## 复核入口

- Flutter：`flutter analyze --no-pub`、`flutter test --no-pub`。
- Android 文件保存测试：使用专门验证设备运行 `flutter drive --no-pub -d <设备> --driver=test_driver/integration_test.dart --target=integration_test/file_preview_smoke_test.dart`。在原生文件选择器保存专用样例，或同时运行 `python tool/save_preview_validation.py --device <设备>`，助手只处理名称形如 `OPC-preview-validation-<时间>.pdf` 的验证文件并比对 SHA256。
- 测试安装包必须与普通入口区分。主模拟器及交付包均使用 `lib/main.dart` 重新构建；验证入口没有管理员凭据。
- 忽略目录中的日志：`BackendService/.local/preview-postgres-tests.log`、`APPClient/test_artifacts/final-mobile-tests-20261025.log`、`native-file-preview-20261025.log`、`native-audio-20261025.log`、`native-save-helper.log`。
- 已查看 PDF 原生截图 `test_artifacts/android/file-preview-pdf-page-{1,2}.png`，以及已知合成 Office 文件的 `test_artifacts/office-render/` 页面。

首次 Excel 冷启动转换超过原 20 秒限制，现服务端转换上限默认 60 秒，客户端该预览请求为 90 秒；其他 API 保留原 30 秒限制。转换失败仍允许有权用户保存原件；未通过安全检查或权限失效时不放行。

iOS PDFKit 及文件保存桥接源码已更新，但本机 Windows 未执行 Xcode 构建。Office 为只读页面预览，字体、动画、宏和复杂公式与原编辑软件的完整兼容不在本次验证结论内。
