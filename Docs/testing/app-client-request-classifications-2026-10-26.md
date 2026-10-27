# 客户需求中日双语分类与筛选

日期：2026-10-26。用户要求客户需求按开发端、开发类型检索，并明确询问数据库持久化及中日文支持。本轮修改 Flutter、BackendService 和增量 SQL，未修改 MasterGo 画布。

## 分类与数据规则

| 维度 | 稳定代码 | 简体中文 | 日语 |
| --- | --- | --- | --- |
| 开发端 | web | Web开发 | Webアプリ開発 |
| 开发端 | website | 网站开发 | Webサイト制作 |
| 开发端 | android | Android开发 | Androidアプリ開発 |
| 开发端 | ios | iOS开发 | iOSアプリ開発 |
| 开发端 | desktop | 桌面开发 | デスクトップアプリ開発 |
| 开发类型 | crm | CRM | 顧客管理（CRM） |
| 开发类型 | hr | HR人力系统 | 人事管理システム（HR） |
| 开发类型 | vehicle | 车辆管理系统 | 車両管理システム |
| 开发类型 | pos | 收银销售 | レジ・販売管理 |
| 开发类型 | oa | OA系统 | オフィス業務システム（OA） |
| 开发类型 | general | 通用信息化系统 | 汎用業務システム |

- 以两个独立字典保存代码、中日名称、排序和启用状态；每条需求可选择一个主要开发端及一个开发类型，两项均可不选。没有从客户原文推断分类，也不把原有服务线 `development` 或技术整理原文 `category` 当成这两项字典。
- `008_request_classifications.sql` 新增两张字典，草稿和不可变原文版本增加可空外键。所有新表及字段均有中文注释，保留统一 `id/updated_usr/updated_at` 和数据库维护触发器。
- 提交及草稿保存由后端校验字典有效性；分类与原文同事务保存。澄清创建新版本时复制原分类，原文修订省略分类字段时保留，显式 null 才清空，历史分类仍可追溯。停用字典不会删除既有版本关联。
- 客户需求页提供两个下拉筛选，可与原状态筛选组合，保留“全部”“未分类”与清除分类入口。进入／返回提交表单保留筛选，从首页统计进入状态列表时清除分类以对应首页统计范围。
- 表单选项和筛选选项从服务端取中日字典；切换语言仅改变显示名称，提交代码、客户原文和权限不变。字典读取失败显示真实错误和重试入口。

## 接口与查询

- `GET /api/v1/mobile/request-classifications`：移动会话读取字典，返回 `platforms/development_types`，每项含 `code/name_zh/name_ja/enabled`。停用项可供历史检索，不能作为新增选择。
- 客户草稿、提交及原文修订使用 `platform_code/development_type_code`；草稿、详情原文、版本历史和本人需求列表返回相应代码。
- `GET /api/v1/mobile/requests?platform_code=web&development_type_code=crm`：按当前客户权限及当前原文版本，在分页前组合过滤并计算 total。查询保留值 `unclassified` 匹配 NULL，不作为字典代码写入。
- Flutter 沿用已经完整分页加载的本人需求快照进行即时分类和状态筛选；不会截取服务器一页后把它当成全部数据，也不因选择分类重新读取所有项目及消息。后台对应 API 过滤同样已实现与验证。
- `/health/ready` 新增 008 迁移检查；缺少分类表时不会把新代码宣称为数据库就绪。Swagger／ReDoc 契约和离线 OpenAPI 已同步，当前源码 74 个路径、90 个操作。

## 本机持久化

执行 `BackendService/.venv/Scripts/python.exe scripts/apply-request-classifications.py`，只向已标记的 `127.0.0.1:55440/opc_integration` 应用 008 并给予应用账号字典 SELECT 权限。脚本校验实例、数据库标记及所有已应用迁移 SHA256，迁移与登记共用事务，不输出凭据、不重启服务、不顺带应用其他待上线迁移，可重复检查。

本轮核实：字典为 5 个开发端、6 个开发类型；18 条需求、12 个账号数量不变，24 条既有原文版本仍为未分类。新字典字段中文注释缺失数为 0，`opc_app` 无字典 INSERT／UPDATE 权限。原 5432 数据库及历史迁移文件未修改。

通过当前源码的 FastAPI TestClient 连接同一持久 PG，使用已忽略文件中的演示客户凭据验证后撤销本次会话；没有新建真实业务需求。字典读取 200，当前客户有 14 条未分类需求，Web＋CRM 为 0 条。这是验证时的真实快照，不以合成标签补齐旧数据；该验证不表示运行中的 8001 已加载新代码。

## 验证与安装包

| 检查 | 结果 |
| --- | --- |
| `flutter analyze --no-pub --no-fatal-infos` | 最终无问题 |
| 分类 widget、分类 HTTP、API UI、API Repository 四个测试文件 | 42 项全部通过；含组合筛选、未分类、草稿中日切换恢复、提交、合作合并后代码保留及 320px／1.4 倍字体中日浅深布局 |
| 后端非 integration 单元测试 | 121 项通过 |
| 隔离 PostgreSQL：分类、原需求流程、需求单元及 API 文档四个测试文件 | 最终 80 项通过；含所有权、分页计数、非法代码拒绝、版本与澄清分类保留 |
| `ruff check app tests scripts` | 通过 |
| 普通 `lib/main.dart` Android debug APK | 构建成功，API 配置为本机 8001，未使用管理测试入口 |

普通包独立快照：`APPClient/test_artifacts/request-classifications/app-classifications-debug.apk`。首次交付没有替换模拟器；用户随后要求更新，完成情况见后文。iOS 未构建。

完整 Flutter 回归本轮采样为 373 项通过、2 项失败：承接者新首页不再直接是大厅、承接者从四项改为五项导航，与两条既有旧断言不符，均不属于分类逻辑。首次全量后端也发现承接流程 `test_claims.py` 的两条状态码断言问题；未在本任务中改动该分支。不能把分类相关测试通过写成整个工作区全量回归通过。日志位于忽略的 `APPClient/test_artifacts/classifications-*.log`。

## 初次交付状态（历史）

首次交付时8001仍运行旧代码，007尚未应用；用户当时选择先交付代码和安装包，后续明确要求“更新下”。该要求已授权本轮运行环境更新，下述补充替代原“待更新”的当前状态。

## 后续更新：数据库与真实8001

- 更新前重新执行静态检查与全量回归：Flutter analyze无问题，375项测试全部通过；隔离PostgreSQL完整后端154项全部通过，包含007与008。此前旧断言失败已由对应模块维护修正，不再沿用原失败快照作为当前结论。
- 更新前对专用55440数据库创建551115字节custom备份，保存于忽略的 `.local/integration/backups/before-runtime-update-20261026T040238Z.dump`。此文件及维护凭据不作为对外交付内容。
- 核对归属标记、原迁移SHA256后补齐007，001—008均已应用。仅迁移前后核对时，18条需求、12个账号、24条原文和10个合作数量一致；没有改写存量分类、密码或业务进度。后续另一路已获授权的端到端测试会新增其自己的合成业务记录，不能把上述数量写成永远不变的现值。
- 复核旧8001监听PID及父进程命令行后重启相同项目后端，新监听PID23272；启动记录和输出保存在 `.local/runtime-updates/latest-backend-8001.json` 及其引用日志。未重启PostgreSQL或5180前端，也没有改变监控器的会话所有权规则。
- 对实际HTTP地址 `127.0.0.1:8001` 验证：就绪为ready／8条迁移，OpenAPI包含分类与承接接口，未登录分类读取返回401；客户鉴权后双语字典为5／6项，本人未分类为14条、Web＋CRM为0条。测试会话已撤销；未用Mock或进程内TestClient替代此次监听接口验证。
- 更新模拟器期间与另一聊天的集成测试产物发生冲突，实际检查发现了测试入口；该产物已移出交付路径并清理，未将其作为普通包完成交付。已根据用户明确授权协调独占模拟器，承接者完整流程完成后由该聊天统一构建、核验并安装包含两边源码的普通 `lib/main.dart` 安装包，最终结果见下节。

## 最终普通包核对

协调后普通交付快照已更新为 `APPClient/test_artifacts/request-classifications/app-classifications-debug.apk`，175015551字节，SHA256为 `a80611410db67783664c727a23063fbb5004bfd8a4a65fe299bfd0c58d230813`。独立入口检查通过：存在普通 `package:opc_app/main.dart`；没有 integration_test 入口、flutter_test实际实现、provider_claim_flow_test.dart，且对应测试凭据检查通过。SDK注释可能包含 `package:flutter_test/` 文档示例，不能仅凭这个宽泛字符串误判；工具检查具体实现URI和入口。旧的错误测试包已清理。

- 本聊天再次执行 `tool/verify_normal_apk.py` 对上述分类交付快照检查，普通入口和测试凭据检查通过；证据为 `test_artifacts/request-classifications/apk-entry-check.json`。
- 只读获取 `emulator-5554` 已安装 `base.apk` 的SHA256，与上述快照完全一致。APP进程29407正在运行，8001再次核对为ready／8条迁移；证据为 `test_artifacts/request-classifications/installed-package-verification.json`。没有再覆盖安装或重启承接者流程使用的APP。
- 对应聊天最终记录：Flutter analyze无问题，380项Flutter测试、154项后端测试通过；承接者完整真机模拟器流程及首页状态统计通过，最终普通APP已登录原承接者账号，显示沟通2／进行4／已交付3，与8001实际快照一致，截图在 `test_artifacts/provider-claim/ordinary-provider-home.png`。8004自有测试服务和临时管理会话已清理。
- 当前模拟器保留承接者首页。客户需要切换为客户账号，进入“需求”查看两个分类筛选；本轮没有把承接者账号显示成客户，也没有给存量需求虚构分类。
