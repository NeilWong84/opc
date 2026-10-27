# OPC 本机服务监控器

这是 OPC 开发与联调环境的 Windows 桌面工具，使用 Python 3.12、PySide6、Qt-Material 与可复用的 HUD 控件，当前源码版本 0.2.3。它只管理以下三个本机目标：

- PostgreSQL `127.0.0.1:55440/opc_integration`
- BackendService `127.0.0.1:8001`
- FrontendAdmin `127.0.0.1:5180`

Flutter APP 完全不在本工具范围内；程序没有 Flutter、ADB、设备、移动端构建或移动日志入口。

## 功能

- Material + HUD 科技风界面：矢量图标按钮、服务节点卡片、真实进程／端口／就绪指示、分区日志检索栏与审计登录卡片。
- 顶栏“明亮／暗黑”即时切换，默认暗黑，重启恢复选择；主题覆盖表格、输入框、菜单、设置与错误提示。切换不重建日志或审计会话，不启停服务。
- 日志筛选拆为两行，最小窗口 1024×740；审计登录内容不足时滚动，不压缩或重叠表单。
- 按 PostgreSQL → BackendService → FrontendAdmin 顺序全部启动，反向安全停止。
- 总启停与单服务启停采用连体开关：已运行禁用启动、已停止禁用停止，状态尚未检查及操作期间禁用冲突动作。选择态只反映实际观察，不随点击提前切换；操作完成／失败后重新计算，不统一恢复可点。全部启动只在存在待启动服务且三个目标均已检查时启用；全部停止只在存在可停止的本会话进程时启用。
- 全部停止会只读跳过外部实例，并明确保留其运行；不会因外部 PostgreSQL 无停止权限而把本会话前后端已安全停止报为失败。单独停止外部实例仍拒绝。已核验的本会话进程尚未监听／失去监听时仍可停止，外部竞争端口不因此获得所有权。
- 区分进程存在、端口监听、HTTP 存活和服务就绪；不会仅凭端口宣称业务链路成功。
- 当前会话只停止自己创建且再次核验过 PID、创建时间、可执行文件和命令行的进程树；wrapper 早退时必须通过父链与逐节点身份复核才能恢复 listener 所有权。启动前已存在或身份不可验证的监听标为“外部实例”，不接管、不停止。
- 端口检查区分“空闲”“已占用但 PID 不可识别”和“已识别监听者”；`0.0.0.0`/`::` 通配监听同样视为占用，无法证明所有权时一律阻止接管。
- 固定提供“全部日志、前端、后端、PostgreSQL、业务审计”五个 Tab。
- “全部日志／前端／后端／PostgreSQL”中单击任意日志单元格，或选中后按 Enter，弹出只读详情：采集时间（UTC）、来源、级别、stream、PID、记录 ID 和完整已保存消息。支持自动换行、滚动、复制消息／全部、Esc 关闭，亮暗主题同步；实时日志追加不改变已打开的详情快照。采集时已经截断的记录会明确提示。
- 运行日志在脱敏后写入本机 SQLite/FTS5，可按关键词、时间、级别、来源、大小写和正则检索，默认保留 7 天；密码、Token、Authorization、带前缀环境变量秘密与 API Key 命令行/请求头形式均会遮盖。
- 检索和导出在后台工作线程执行；持续日志经有界队列批量写入，实时显示使用有界队列与单飞批量 Qt 通知，不因同步 SQLite 提交、逐行跨线程事件或重建整张表阻塞子进程输出读取。
- 文件日志每轮最多生成 10,000 条完整记录并精确续读；普通/正则检索有扫描行数、取消、总时限和默认 8 Mi 字符结果预算。正则在编译前做复杂度及计数量词上限预检，历史和实时匹配均有硬超时；达到边界时界面明确提示结果可能不完整。
- PostgreSQL 只增量读取 `.local/integration/postgres.log` 与 `provision.log`。
- 日志先按完整原始行严格解码 UTF-8，再兼容 Windows ANSI／OEM 编码（本机 CP936／GB18030）。打开程序前从允许的原日志恢复可核对的旧乱码，保留记录时间、ID 和游标；原始字节已不存在的历史输出保留原样。
- 业务审计需要每次手动使用管理员账号登录；Token 和审计页只保存在内存，不写 SQLite、设置或导出。
- “设置”可重新检查项目根和外部依赖，并调整 5–120 秒启动超时；项目根变更在重启监控器后生效。

## 源码运行

在 `D:\OPC\Tools\ServiceMonitor` 使用明确的 Python 3.12：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --require-hashes -r requirements-dev.lock.txt
.\.venv\Scripts\python.exe -m pip install --no-deps -e .
.\run.ps1
```

监控器调用项目已有依赖，不会自动安装 BackendService、Node.js、前端依赖或 PostgreSQL。首次使用前应已具备：

- `BackendService\.venv\Scripts\python.exe`
- `FrontendAdmin\node_modules` 与可用的 `npm.cmd`
- PostgreSQL 18 工具及现有持久联调实例脚本

启动 PostgreSQL 会调用现有 `scripts\provision-local-integration.py start`，可能进行首次初始化或迁移；定时健康检查不会调用 `start`。程序不会自动 seed。

启动任一服务前都会执行只读依赖检查。PostgreSQL 检查与现有 helper 一致，要求 `C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe`；检查不会启动程序、读取 `.env` 或读取演示账号文件。

## 本机数据

以下非业务数据保存到 `%LOCALAPPDATA%\OPC\ServiceMonitor`：

- `settings.json`：项目根路径、启停超时与 `dark`／`light` 主题偏好；不含密码或 Token。旧配置缺少主题时默认暗黑。
- `runtime-logs.sqlite3`：已脱敏运行日志和允许日志文件游标。
- `monitor.log` 及轮转文件：已脱敏的监控器自身诊断。
- `exports\`：用户显式导出时的默认目录。

删除 SQLite 只会清空本工具的运行日志索引，不会修改 OPC PostgreSQL 业务数据。损坏索引会先以 `.corrupt-*` 改名隔离，再建立空索引。

日志默认保留 7 天：应用启动时立即清理一次，持续运行时每小时再次清理超期记录。

Material 图标缓存在每进程独享的系统临时目录 `opc-monitor-theme-*` 中，正常退出时清理；不写入安装目录，也不使用库默认共享缓存。新界面依赖的许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，构建时随包保留。

## 测试与静态检查

```powershell
$env:QT_QPA_PLATFORM='offscreen'
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check src tests packaging
.\.venv\Scripts\python.exe -m compileall -q src
```

## Windows onedir 构建

```powershell
.\build.ps1
.\scripts\smoke-package.ps1 -ProjectRoot D:\OPC
```

输出目录为 `dist\OPCServiceMonitor`，入口为 `OPCServiceMonitor.exe`。这是 `onedir + windowed + noupx` 包，只包含监控器及其 Python/Qt 运行时；不会打包 OPC 仓库、后端虚拟环境、Node.js、PostgreSQL、`.env`、`.local` 或业务文件。

当前 0.2.3 交付到 `dist\OPCServiceMonitor-0.2.3\OPCServiceMonitor.exe`。本次更新未重启既有监控器或服务；可在合适时机退出旧版后使用新版，运行中的旧窗口不会自动加载新代码。保留整个程序目录。

构建独立版本目录及验证：

```powershell
.\build.ps1 -PackageName OPCServiceMonitor-0.2.3
.\scripts\smoke-package.ps1 -ProjectRoot D:\OPC -Executable D:\OPC\Tools\ServiceMonitor\dist\OPCServiceMonitor-0.2.3\OPCServiceMonitor.exe
```

更新同一目标程序目录前退出该监控器；独立版本目录可以保留旧窗口。新包先生成到 `build/package-staging-*`，再更新 `dist`；内容完全相同的运行库不会重复覆盖，允许旧版启动的服务仍占用同一 DLL 时完成更新。完整暂存包保留供核对。后端 `scripts/start.ps1` 使用 UTF-8 BOM，兼容 Windows PowerShell 5.1。

冒烟模式只创建真实主窗口、加载资源并输出不含环境值或凭据的 JSON 报告，不执行服务启停：

```powershell
.\dist\OPCServiceMonitor\OPCServiceMonitor.exe --smoke-test --report C:\Temp\opc-monitor-smoke.json --project-root D:\OPC
```

## 安全边界与排障

- 端口被外部实例、不可识别监听者或通配地址监听占用时，停止按钮禁用。即使 PID 与旧会话相同，也不会根据历史记录接管。
- 所有运行日志在显示、SQLite 和导出之前脱敏；不要把业务密码直接写入普通日志作为调试方式。
- 审计登录 401 会清除内存会话并要求重新登录；403 会保留登录状态并提示需要 `administrator` 角色。
- 本工具面向本机开发联调，不是生产监控、远程运维、容器管理或数据库 SQL 审计平台。

实现与验证证据见 [2026-10-22 验证记录](../../Docs/testing/opc-service-monitor-2026-10-22.md)。

0.2.0 双主题改版与截图见 [2026-10-25 界面验证](../../Docs/testing/opc-service-monitor-ui-2026-10-25.md)。截图使用明确标注的合成 UI 验收数据，不代表真实服务状态。

0.2.1 中文日志、历史恢复、PowerShell 启动和 Windows 停止修复见 [编码与启停验证](../../Docs/testing/opc-service-monitor-encoding-startup-2026-10-25.md)。该轮已实际验证前后端启动与停止，现有 PostgreSQL 保持运行。

0.2.2 日志详情交互与打包验证见 [日志详情验证](../../Docs/testing/opc-service-monitor-log-details-2026-10-25.md)。

0.2.3 状态驱动的启停开关、外部实例跳过及本会话无监听进程停止验证见 [启停开关验证](../../Docs/testing/opc-service-monitor-power-controls-2026-10-25.md)。

重现 UI 验收截图（不访问或操作真实服务）：

```powershell
.\.venv\Scripts\python.exe scripts/preview-ui.py --platform windows --output D:/OPC/Docs/testing/artifacts/opc-service-monitor-ui-2026-10-25
.\.venv\Scripts\python.exe scripts/preview-ui.py --platform windows --power-controls-only --output D:/OPC/Docs/testing/artifacts/opc-service-monitor-power-controls-2026-10-25
```

