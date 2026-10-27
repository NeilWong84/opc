# OPCServiceMonitor 0.2.0 科技风双主题验证

日期：2026-10-25。适用范围：`Tools/ServiceMonitor` 本机桌面监控器；不涉及 Flutter、生产部署、远程运维或对象存储。

## 用户要求与实现

用户要求更换界面组件、采用更有科技感的视觉，并支持明亮／暗黑两种模式。现采用 `qt-material==2.17` 提供 Material 基础样式与资源，配合项目独立的 `ConsoleButton`、`ConsoleLineEdit`、`ConsoleComboBox`、`ConsoleTable`、`ConsoleTabs`、`ThemeSwitch`、`TelemetryStrip` 等 HUD 控件；不是 QFluentWidgets，也不是新增一个 Web 产品端。

- 深色采用深蓝底和青色强调，浅色采用白色卡片与蓝色强调；矢量图标、静态网格、服务节点编号和真实健康指示统一。
- 顶栏分段开关即时切换，默认暗黑；`settings.json` 白名单新增 `theme: dark | light`，兼容旧配置，非法值回退暗黑。保存项目根和超时时保留主题，切换主题时保留其他设置。
- 主题覆盖输入、下拉、日志表、审计、设置、菜单、提示与禁用态；切换不会重新创建日志工作区、清空检索或管理员内存会话，不调用服务启停。
- 主题资源加载失败会恢复原选项并显示错误；主题偏好保存失败时明确提示“已切换但未保存”。
- 日志筛选拆为两行，服务信息压缩为紧凑卡片；最小 1024×740 窗口仍显示多条日志。审计登录内容按需滚动，不挤压邮箱、密码和按钮。
- 日志时间列以完整紧凑 UTC 格式显示；导出格式与原检索／脱敏流程不变。

三个服务、固定五个 Tab、外部进程只读保护、7 天脱敏 SQLite/FTS5 和管理员手动登录边界不变。本轮 UI 验收不读取真实业务凭据，不启动、停止或接管真实服务。

## 验证结果

在 Windows 10 AMD64、Python 3.12.7、PySide6/Qt 6.10.3 上完成：

| 项目 | 实际结果 |
| --- | --- |
| 完整自动化测试 | `254 passed in 52.64s` |
| Ruff：src、tests、packaging、preview-ui.py | 通过 |
| compileall：src | 通过 |
| 锁文件依赖安装及 pip check | 通过，无依赖冲突 |
| Windows onedir 构建 | 通过，版本 0.2.0 |
| 独立工作目录运行打包 EXE | 通过，`platform_plugin: windows` |
| 打包资源／主题切换 | theme=true，light 和 dark 均成功；3 张服务卡与固定 5 个 Tab |
| 独立只读代码复核 | 未发现可复现的中／高风险问题 |

新增测试覆盖主题保存、重启恢复、非法与旧配置、完整颜色 token、控件主题刷新、检索／选中行／审计会话保留、无服务启停、保存和加载失败提示、两种尺寸下日志可见空间及表单无重叠／滚动可达。此前源码及进程安全、脱敏、检索等回归测试一并通过。

最初截图暴露最小窗口中日志区过小和登录表单重叠；已压缩顶部信息并为审计加入滚动容器，随后强化布局断言并重新测试、截图。

复现命令：

```powershell
cd D:\OPC\Tools\ServiceMonitor
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check src tests packaging scripts/preview-ui.py
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m pip check
.\build.ps1
.\scripts\smoke-package.ps1 -ProjectRoot D:\OPC
.\.venv\Scripts\python.exe scripts/preview-ui.py --platform windows --output D:/OPC/Docs/testing/artifacts/opc-service-monitor-ui-2026-10-25
```

## Windows 视觉证据

18 张图位于 [截图目录](artifacts/opc-service-monitor-ui-2026-10-25/)。均是实际 Qt Windows 窗口渲染，显示明确标注的合成 UI 验收数据，不代表真实进程或业务状态。截图脚本禁用真实服务操作和网络访问，使用临时 SQLite 和假审计客户端。

检查覆盖两主题 × 主窗口／审计登录／审计事件／设置 × 1280×860 与 1024×740，另有最小窗口的登录滚动截图。当前 Windows DPI 为 125%，对应 PNG 像素尺寸分别为 1600×1075 和 1280×925；固定尺寸仅用于验收脚本，正式主窗可缩放。

- [暗黑主窗口](artifacts/opc-service-monitor-ui-2026-10-25/dark-main-1280x860.png)
- [明亮主窗口](artifacts/opc-service-monitor-ui-2026-10-25/light-main-1280x860.png)
- [最小暗黑窗口](artifacts/opc-service-monitor-ui-2026-10-25/dark-main-1024x740.png)
- [最小明亮审计登录滚动](artifacts/opc-service-monitor-ui-2026-10-25/light-audit-login-scrolled-1024x740.png)
- [明亮设置](artifacts/opc-service-monitor-ui-2026-10-25/light-settings-1024x740.png)

## 交付包与资源边界

入口：`D:\OPC\Tools\ServiceMonitor\dist\OPCServiceMonitor\OPCServiceMonitor.exe`。移动到其他目录时须复制整个 `OPCServiceMonitor` 文件夹，不能仅复制 EXE。

- EXE 大小：6,080,566 字节。
- EXE SHA256：`27AB6F9003EB71A228A30705EA22A4B4ED035D7E212177D1637C3BE4D07B74BA`。
- onedir 共 339 个文件、148,041,779 字节。
- 保留 Qt Windows 平台插件、Material 模板／XML／SVG／字体与新增依赖许可；排除另一 Qt binding、QML／QtQuick／WebEngine。
- 包内扫描未发现 `.env`、演示凭据、`.local`、Flutter APP、Node 依赖、后端虚拟环境或非 Qt 未版本化 ICU DLL。
- Material 生成图标使用每进程、每主题独享临时目录；样式内转换为该主题的绝对资源路径，避免亮暗缓存串色与并行实例覆盖。
- 第三方许可见 [声明](../../Tools/ServiceMonitor/THIRD_PARTY_NOTICES.md)，随包保存到 `_internal`。

历史 0.1.0 的大小／哈希与首次真实服务只读检查保留在 [2026-10-22 记录](opc-service-monitor-2026-10-22.md)，不替代本次新包数据。生产就绪与远程监控不在本次验收范围。
