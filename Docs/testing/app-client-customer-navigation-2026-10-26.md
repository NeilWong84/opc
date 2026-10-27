# APPClient 客户底栏提交需求入口

日期：2026-10-26。本轮按用户提供的状态列表和底栏截图直接修改 Flutter 真实模式，未修改 MasterGo 画布或历史 Mock 页面。

## 行为

- 客户登录后的底栏按“首页／需求／提交需求／沟通记录／个人设置”排列；日文中间入口使用“依頼する”。
- 中间加号入口直接打开原有 `ApiRequestPage`，不会选中一个空白页或清除原来的状态筛选。返回、成功提交后回到来源页签；沿用原有返回刷新逻辑。
- 全部需求、审核中、进行中、待验收和已完成等状态列表不再显示“提交开发需求”卡片。审核及私有附件说明保留在表单里。
- 首页的“新需求／继续草稿”快捷入口保留；两个入口共用同一表单和服务端草稿。
- 承接者底栏保持原四项；没有新增客户提交入口、后台审核能力或接单政策。
- 使用原有导航组件与主题；新文案维护在中日 JSON 资源，重新合并 ARB 和生成本地化 Dart，中日各 616 条。

## 验证

- `flutter test --no-pub --reporter expanded`：353 项全部通过。新增 6 项覆盖客户五项顺序、各状态列表无重复卡片、返回保留状态筛选、沟通／设置索引正确、草稿保存恢复及正式提交返回、承接者四项导航，以及 320px／1.4 倍字体的中日双语浅深主题布局。
- `flutter analyze --no-pub`：首次发现本轮移除卡片后遗留的 theme import，已删除。复查 `flutter analyze --no-pub --no-fatal-infos` 无错误和警告，退出码 0；仍有 `api_file_page.dart` 和 `api_media_player.dart` 中既有的 4 条 `curly_braces_in_flow_control_structures` 格式提示，未修改相关文件。
- `flutter build apk --debug --no-pub --target=lib/main.dart --dart-define=OPC_API_BASE_URL=http://127.0.0.1:8001`：成功，普通应用 APK 为 `APPClient/build/app/outputs/flutter-apk/app-debug.apk`，没有使用集成测试入口或管理令牌。
- `adb -s emulator-5554 install -r .../app-debug.apk` 返回 `Success`，已更新当前模拟器；登录会话按既有规则仅存内存，应用重新启动后需重新登录。

本轮表单回归使用可控 Repository，不新增真实业务记录；Android 构建不替代 iOS 构建或生产部署验证。
