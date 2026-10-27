# OPCServiceMonitor 0.2.3 启停开关验证

日期：2026-10-25。用户要求全部启动成功后禁用“全部启动”，总开关与单服务启停均随真实状态控制，并统一开关样式。

## 修复与边界

原主窗口在操作结束时无条件恢复总启动／总停止可点；现在由统一的 `ServiceActions` 根据最新进程、端口、过渡状态与本会话所有权派生操作，不以按钮点击或操作报告的 success 值冒充服务状态。

| 实际观察 | 启动 | 停止 | 开关选择态 |
| --- | --- | --- | --- |
| 尚未检查 | 禁用 | 禁用 | 无 |
| 已停止，端口未占用 | 可点 | 禁用 | OFF |
| 本会话进程正在运行／已就绪 | 禁用 | 可点 | ON |
| 进程仍在运行但启动未就绪／失败 | 禁用 | 仅已核验自有进程可点 | ON |
| 外部实例 | 禁用 | 禁用 | 已确认运行时 ON |
| 启动中／停止中 | 禁用 | 禁用 | 不提前宣称成功 |

- 总启动：三个目标均已检查，且至少一个目标可以启动时启用；全部已运行后禁用。全部停止：至少一个已核验的本会话进程可停止时启用。混合状态可同时提供“补齐启动”和“停止自有服务”，不会伪装成全开／全关。
- 生命周期操作开始即锁定冲突动作，状态刷新不会提前解锁；结束、部分失败及异常后按实际观察重新计算。按钮之外的处理入口也校验可执行动作，防止重复触发。
- 两个动作使用连体分段控件；灰显段不可点击、没有可点击鼠标或悬停反馈，选择态保留可辨认的灰蓝底。可用启动用主题强调色，可用停止用危险色，亮暗模式一致。
- 选中状态只由观察更新，点击不会提前把 ON／OFF 切换；状态、锁定和外部实例原因提供工具提示及无障碍说明。
- 全部停止仅对自有进程执行操作，外部实例只读跳过并保留运行，不再因外部 PostgreSQL 无停止权限而错误报告整次停止失败。单独停止外部实例仍拒绝。
- BackendService／FrontendAdmin 的已验证自有进程未绑定或失去端口时仍保留停止能力。外部进程竞争端口时继续标为外部，既有 wrapper 清理与失败保护不改变；不按端口或历史 PID 接管进程。
- Flutter、生产监控、管理员审计权限及日志脱敏边界不变。

## 验证

| 检查 | 实际结果 |
| --- | --- |
| 新开关策略／Qt 交互 | `tests/test_power_controls.py`，21 项通过 |
| Supervisor 启停与所有权 | `tests/test_supervisor.py`，26 项通过 |
| 全套源码回归 | **321 passed in 53.93s** |
| Ruff／compileall | src、tests、packaging 与 UI 预览脚本检查通过；源码编译通过 |
| Windows 视觉 | 两种主题下就绪、停止、混合、启动中、未知状态，最小 1024×740；另检查 1280×860 就绪，共 12 张合成截图 |
| Windows 打包冒烟 | 0.2.3、Qt windows 插件，`power_controls=true`、`log_details=true`、两种主题正常 |
| 真实服务操作 | 本轮未启动、停止、接管或重启既有服务 |

首次全套运行发现已有正则超时测试的浮点上界断言：50 ms 剩余预算在大单调时钟相减后为 `0.05000000000291038`。仅将该测试断言增加 1 ns 浮点误差容忍，没有改动日志检索实现；随后重新完整运行 321 项全部通过。

开关交互使用 fake controller 与临时项目，Supervisor 使用 fake process／PostgreSQL 适配器；打包冒烟只构造真实界面、合成日志和合成状态，不访问真实业务服务。测试缓存与 TEMP／TMP 使用新建 workspace 子目录，避免旧缓存 ACL 的影响。

截图均明确标注为合成验收数据，不能作为真实服务启停证据：

- [暗黑：全部就绪](artifacts/opc-service-monitor-power-controls-2026-10-25/dark-ready-1024x740.png)
- [明亮：全部停止](artifacts/opc-service-monitor-power-controls-2026-10-25/light-stopped-1024x740.png)
- [明亮：部分运行](artifacts/opc-service-monitor-power-controls-2026-10-25/light-mixed-1024x740.png)
- [暗黑：启动中](artifacts/opc-service-monitor-power-controls-2026-10-25/dark-starting-1024x740.png)
- [暗黑：尚未检查](artifacts/opc-service-monitor-power-controls-2026-10-25/dark-unknown-1024x740.png)

## 交付

- 入口：`D:\OPC\Tools\ServiceMonitor\dist\OPCServiceMonitor-0.2.3\OPCServiceMonitor.exe`。
- EXE SHA256：`DA80A9AD741F961383781A18E590DE0955C9D2FEC6453014112245D983E67643`。
- [Windows 冒烟报告](artifacts/opc-service-monitor-power-controls-smoke-2026-10-25.json)。

新版位于独立目录，保留整套目录使用。本轮没有退出旧监控器；运行中的旧窗口不会自动加载新代码，需退出旧版后运行上述新版。更新不会迁移或接管旧会话服务所有权。构建、冒烟及重现截图命令见 [工具 README](../../Tools/ServiceMonitor/README.md)。
