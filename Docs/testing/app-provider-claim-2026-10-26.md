# 承接者首页、任务大厅、自主承接与交付验证

日期：2026-10-26。范围为本机 Flutter Android 模拟器与 FastAPI／PostgreSQL 联调；业务按用户明确选择“客户先确认范围条款，承接者再一键承接”。实现及 API 见[流程说明](../development/provider-claim-workflow.md)。未编辑 MasterGo 画布，未构建 iOS，不表示生产或真实客户验收。

## 实现

- 承接者五个底栏：首页、任务大厅、项目、沟通记录、个人设置。首页汇总本人沟通中、进行中、已交付并可跳到筛选列表；各阶段保留真实状态，提交不等于完成。
- 大厅检索当前审核发布且尚无有效合作的任务，详情读取完整发布范围及有权访问的参考；不开放原始私有材料。
- 新 `negotiation` 独立客户／承接者沟通与发布版本条款提案；不同承接者隔离。客户本人先确认范围、条款、可选 JPY 报价和期限，承接者再承接，项目归属本人并进入 `executing`。
- 当前项目／沟通卡片与详情提供“提交交付物”，列表打开前只刷新该需求。提交后进入 `internal_review`，仍需后台质检及对客发布后客户验收。
- 新增 `007_provider_claim`，历史迁移不改写；001—008 已在已标记的 `55440/opc_integration` 应用。原管理录入开关与新手机流程分别处理。

## 自动化

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze --no-pub` | 无问题 |
| `flutter test --no-pub` | 380 项全部通过，包含共享工作区同期客户分类及视频改动 |
| `ruff check app tests scripts` | 通过 |
| `scripts/test-postgres.ps1 -q` | 154 项全部通过，包含独立 PostgreSQL 18、真实 HTTP 和双连接并发 |
| `scripts/export_openapi.py` | 已导出 74 个路径／90 个操作，包含新增五个沟通承接接口 |
| 承接权限与状态 | 客户不能承接，承接者不能代客户确认，陌生账号／管理 token 不能越权使用手机沟通 |
| 版本与并发 | 旧提案不能确认，下架后不能承接；两名获客户确认的承接者同时操作只有一人成功；同幂等键重试返回同一合作 |
| 手机入口与首页 | 320px 中日浅深统计／筛选／大厅检索，交付入口及过期状态、读取失败／重试与返回不反复打开 |

日志位于忽略目录 `APPClient/test_artifacts/provider-claim-widget-tests.log`、`APPClient/test_artifacts/real-api/`。旧阶段其他记录中的失败数量不代表此轮最终结果。

## Android 真实完整流程

执行：

```powershell
# BackendService 目录，8004 为本轮独立且空闲的测试端口
.\scripts\run-mobile-integration.ps1 -Port 8004 -Target integration_test/provider_claim_flow_test.dart
```

测试使用新增随机密码客户／内部账号及合成需求；后台测试令牌仅在集成入口临时注入，结束已注销并从本机 define 文件移除。脚本停止自己的 8004 服务，保留合成业务记录作为证据，不重置既有需求、密码、成员授权或其他服务。

首轮被另一聊天同时覆盖安装中断，Android 事件明确为 `installPackageLI`，没有当作通过。用户授权协调模拟器顺序后，重新执行完整流程通过；随后增强计数断言并保留截图的最终运行也通过（63 秒）。

最终运行 `916a569b3697`，需求 `b09b771e-ee0a-4966-b684-e75523ec492b`，合作 `11f1c8ef-6e3d-4372-9245-732aa37be8b4`：

1. 内部账号从真实登录页登录，首页三项初始均为 0。
2. 打开独立大厅，以运行标识检索出已发布测试需求，进入完整范围详情并发起沟通。
3. 发送沟通消息，填写条款及 JPY 120000 报价，请客户确认；此时无可执行承接按钮。
4. 切换客户手机界面，进入对应承接者沟通，查看范围并显式确认条款。
5. 承接者首页沟通中为 1；进入沟通点击“承接项目”，归属实际当前账号且状态 `executing`，从大厅移除。首页变为沟通中 0／进行中 1。
6. 从项目卡片点击“提交交付物”，填写固定仓库 SHA、归档证据、说明、测试材料和交付说明，提交进入 `internal_review`；首页进行中 0／已交付 1，已交付列表可找到该需求。
7. 直接读取持久 PG 核对：当前负责人正确，1 份交付、2 条双方确认、大厅 0 行；提案确认人为实际需求客户。结果保存在 `provider-claim/database-verification.json`。

此流程使用明确标记的合成仓库归档证据，只验证提交与状态链路，不声称测试链接代表真实客户源码，未执行的客户源码测试没有记录为通过。源码包上传检查与预览沿用既有真实文件流程及其单独验证范围。

9 张实际截图保存在 `APPClient/test_artifacts/real-api/claim-*.png`，分别为初始首页、大厅搜索、等待客户、客户确认、承接详情、进行中统计、提交结果、已交付首页及已交付列表。已检查首页、客户确认和提交后截图，无布局异常。

## 普通包与本机服务

完整流程测试后独占重新构建 `lib/main.dart` 普通 debug 包，URL 为 `http://127.0.0.1:8001`，不使用测试 define 文件。新增 `tool/verify_normal_apk.py` 校验普通入口、集成测试实现／具体测试入口及本轮测试凭据未包含在 kernel 内。Flutter SDK 自带 `@docImport package:flutter_test/...` 注释不被误认为实际加载测试库。

独立包：`APPClient/test_artifacts/provider-claim/OPC-20261026-provider-claim-debug.apk`，并同步到另一已协调聊天的分类交付快照 `APPClient/test_artifacts/request-classifications/app-classifications-debug.apk`。

实际大小 175015551 字节，SHA256：`a80611410db67783664c727a23063fbb5004bfd8a4a65fe299bfd0c58d230813`。已 `adb install -r` 成功并启动普通应用，设备 `base.apk` SHA256 与该独立包一致。普通包检查证据位于 `provider-claim/normal-apk-verification.json`。

普通包又使用既有承接者账号完成真实登录，界面切为简中并留在首页，实见沟通中 2／进行中 4／已交付 3；另开只读 HTTP 会话核对相同账号的项目及会话，统计一致，核对会话随后注销。截图、语义树和结果分别位于 `provider-claim/ordinary-provider-home.png`、`ordinary-provider-home.xml`、`ordinary-live-counts.json`。这是既有账号当时的真实快照，与新增合成测试账号的 0→1→1 状态断言分别记录。

当前 8001 实际监听接口已确认数据库 ready／8 条迁移，OpenAPI 包含客户沟通和自主承接接口；本轮没有再停止既有 8001、55440 或 5180。模拟器使用 `adb reverse tcp:8001 tcp:8001`。debug 本机联调不能代替正式 HTTPS、签名或 iOS 验证。
