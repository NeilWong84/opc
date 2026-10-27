# OPCServiceMonitor 0.2.1：中文日志与启停修复

日期：2026-10-25。针对用户提供的 PostgreSQL 中文乱码截图及“全部启动”后后端 `ParserError / UnexpectedToken` 截图。

## 原因与修复

1. 本机 ANSI／OEM 代码页均为 936。`postgres.log` 和 `provision.log` 的中文实际为 CP936 字节，原文件未出现 UTF-8 替代字符；监控器原先固定 `UTF-8 + errors=replace`，导致中文在入库前被破坏。现在先缓存有上限的完整原始行，严格尝试 UTF-8，再尝试 Windows 本机 ANSI／OEM 编码，CP936 映射为 GB18030。支持同一管道不同编码的行、中文跨分块、CRLF／未结束行与有界截断；输出继续经过原有脱敏流程。
2. `BackendService/scripts/start.ps1` 原为 UTF-8 无 BOM。Windows PowerShell 5.1 按 ANSI936 读取后，在第 9 行第 39 列复现 `UnexpectedToken`；PowerShell 7 无此错误。现为该脚本保留 UTF-8 BOM，两个 host 均正确解析，中文错误字面量保留。
3. 真实启停测试发现 Windows 匿名管道存在关闭阻塞：停止调用线程同步 `pipe.close()`，会在等待另一线程的阻塞读取时卡住，后续强制停止无法执行。现在每个自有进程只创建一个可复用 daemon 管道关闭线程，关闭与读线程 join 共用截止时间；所有权和进程树核验规则不变。
4. 冻结程序的 DLL 搜索目录会传给外部服务。实际 PostgreSQL 正在引用旧监控器包中的 `VCRUNTIME140.dll`，导致直接清理旧包失败。现在在 Qt 和原生模块加载后恢复系统 DLL 搜索路径，并从外部子进程 PATH 中精确移除冻结包目录；方案依据 [PyInstaller 官方说明](https://pyinstaller.org/en/stable/common-issues-and-pitfalls.html#launching-external-programs-from-the-frozen-application)。构建先写独立暂存包，再同步到 `dist`，相同哈希的运行库不覆盖，既有 PostgreSQL 无需为本次更新停止。

## 历史日志恢复

只允许从原白名单文件中核对原始字节并进行无歧义替换。修复使用 `source + stream=file + 完整旧 message` 精确匹配，保留 ID、时间、PID 和文件游标；FTS 由原有 UPDATE trigger 同步。文件读取和记录数有上限，多目标歧义、原文件已含替代字符及不可恢复条目保持原样。

真实索引修复前先使用 SQLite backup 保存到 `%LOCALAPPDATA%/OPC/ServiceMonitor/runtime-logs.before-encoding-fix-20261025T091815327383Z.sqlite3`。当次结果：

- 135 条 PostgreSQL 文件记录中，85 条包含替代字符；85 条已全部恢复，损坏计数降为 0。
- 全部记录 ID／时间／PID 与两个游标逐项比对保持一致，没有清空或重复导入。
- 中文 FTS 查询“日志”得到 81 条匹配。
- 后端此前 stderr 有 6 条已被替代字符破坏的旧记录，因没有保存原始字节而保留；新后端输出使用修复后的解码路径。不能从替代字符推测丢失的原文。
- 原始日志文件和 PostgreSQL 业务数据未因历史索引修复被改写。

打开新版时，在主窗口及首次历史查询之前执行恢复；后续轮询保留一次性、有界的恢复机制。

实际 Qt Windows 日志显示证据：[修复后 PostgreSQL 中文日志](artifacts/opc-service-monitor-encoding-fixed-2026-10-25.png)。这是本机已脱敏真实历史日志渲染，文件记录替代字符计数为 0。

## 验证

| 检查 | 结果 |
| --- | --- |
| 监控器最终全量自动化测试 | 281 passed in 62.80s |
| 后端启动脚本 AST 回归 | Windows PowerShell 5.1／PowerShell 7 两项通过 |
| Ruff、compileall、pip check | 通过 |
| 真实全部启动 | 两次成功，PostgreSQL、后端和前端均就绪 |
| 最新真实前端停止 | 成功，6.22 秒 |
| 最新真实后端停止 | 成功，6.17 秒 |
| 既有 PostgreSQL | PID 21176 前后一致，保持运行 |
| Windows onedir EXE 冒烟 | 版本 0.2.1，windows 平台插件，亮暗两主题、3 卡／5 Tab 正常 |
| 冻结外部进程 DLL 环境 | 打包 EXE 报告 `system_dll_search=true` |
| 暂存包与交付包逐文件 SHA256 | 339 个文件，0 项不一致 |

真实验证通过监控器相同的 `ServiceSupervisor.start_all()` 路径启动服务，后端必须通过存活和就绪 HTTP 检查，前端必须返回可用页面。验证结束仅停止本轮具有可验证所有权的前后端，既有数据库保持运行；不做 seed、迁移或业务数据写入。最初停止卡住的测试进程也已按记录的父链、身份及命令行核验清理，随后才进行修复后的完整复验。

## 交付

入口：`D:\OPC\Tools\ServiceMonitor\dist\OPCServiceMonitor\OPCServiceMonitor.exe`，须保留整个 onedir 目录。

- EXE：6,087,877 字节。
- SHA256：`F19325A616A400E2743E6AB2A6A9C71F6A7FBC37128310051BB0F5F241377F2C`。
- 本轮完整暂存包：`Tools/ServiceMonitor/build/package-staging-90e475eaaa91425b94881981c855a647/OPCServiceMonitor`。
- 历史 0.2.0 的界面及包证据仍见 [双主题记录](opc-service-monitor-ui-2026-10-25.md)，不能作为当前 EXE 哈希。

复现检查：

```powershell
cd D:\OPC\Tools\ServiceMonitor
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m ruff check src tests packaging
.\.venv\Scripts\python.exe -m compileall -q src
.\.venv\Scripts\python.exe -m pip check
.\build.ps1
.\scripts\smoke-package.ps1 -ProjectRoot D:\OPC
```
