# 腾讯云 Compose 部署及业务迁移验证

日期：2026-10-26。目标：用户已授权的东京线上测试实例 `lhins-1nxj2eln` / `43.165.191.156`。本记录不包含密码、令牌、消息正文或附件名称。

## 构建与主机

- SSH/SFTP 使用本机 DPAPI 凭据与已记录的 ED25519 主机密钥；后续连接校验 known_hosts。
- Docker 官方仓库安装 Docker 29.9.2，Compose v5.6.1。部署前主机没有既有业务容器。
- 后端与管理端均实际在目标 Linux 构建成功，当前版本 `20261026-02`；管理构建执行生产 HTTPS 配置门禁、vue-tsc 和 Vite。
- 修复原 package-lock 中缺失 version 的 Darwin rolldown 可选依赖条目；补入与现有 rolldown 一致的 1.2.14，不升级其他依赖。Linux `npm ci` 随后成功。
- 本机前端单测 46 项通过；BackendService 正确工作目录执行非集成单测 121 项通过、33 项排除，保留已有 Starlette 警告。
- Compose 配置校验、应用受限 PG 角色、8 条历史迁移 checksum 通过；postgres/backend/admin/nginx 均 healthy，只有 nginx 映射公网 80/443。

## 公网和权限

首次签发 Let's Encrypt IP 证书，HTTPS 通过客户端信任校验。服务器本机正常后，公网 443 起初不可达；用户添加腾讯云防火墙规则后，公网 HTTPS 就绪返回 200，用户浏览器确认登录页，浏览器读取 API 状态成功。

迁移前隔离空测试库验证 15 项：就绪、JPY 与 ja/zh、管理端独立登录、管理／手机凭证互斥、客户注册仅授予 customer、内部大厅拒绝普通客户、真实上传 SHA-256、pending 文件下载返回 409、真实管理需求 API。合成客户已停用，文件保留 pending；没有伪造安全检查。该数据集保留于旧 `opc_test`，没有混入迁移后的 18 个账号。

Linux 非 root LibreOffice 使用含中日文的真实 DOCX 生成 PDF 成功，合成输入和其缓存验证后移除。

## 业务迁移

用户明确范围为 OPC 现有业务数据。实际源为本机 PG 18.4 `55440/opc_integration` 与私有文件，不是 Docker 卷。原本地数据库、5432 其他库与原文件未改动。

- 只读一致性快照 UTC `2026-10-26T08:25:17.512300Z`，40 张表、18 账号、21 需求、12 合作、93 消息、42 文件、2,186,382 原件字节。
- `pg_dump` 与计数／摘要共用同一导出快照。传输归档 SHA-256：`2c16586fe7ceb496e0e664e309ba054f3845f1b799c9248022e586d4c49c6417`，云端校验通过。
- 独立恢复至 `opc_migrated_20261026`；以 UTC 序列化、按 id 排序、长度前缀的行摘要逐表比较，40 张表全部完全一致。42 个文件数据库元数据、实际大小和 SHA-256 全部一致。
- 校验后撤销复制来的 29 条未撤销会话，保留会话历史与密码哈希。重新赋予当前云端受限应用角色所需权限，校验迁移 checksum，无新增基础业务账号。
- 迁移前云端需求数仍为 0；备份旧测试环境后才切换配置和 current，失败路径可切回旧环境。实际切换成功，四容器 healthy。
- 原管理员／客户／内部承接者用原密码公网登录成功，账号 ID 一致；手机 Token 访问管理接口被拒绝，管理 Token 访问手机接口被拒绝。
- 管理 API 返回全部 18 账号、21 需求与42文件；42 个鉴权公网下载逐个匹配源文件大小和 SHA-256。
- 真实迁移 DOCX、XLSX、PPTX 预览返回 PDF；原 PDF 与 PNG 预览成功。客户及承接者各自视角的合作／沟通 API 返回成功。检查结束退出验证会话，未在业务库新增测试需求或客户。
- 原管理员凭据已使用 Windows DPAPI 机器加密保存，旧云初始化管理员加密文件另存。正常 Windows 管理员身份解密两类凭据检查均为 true；未输出明文。

首次导入校验因容器去掉 DAC 权限而不能用 root 读取 uid10001 的 0400 密钥，改为原 uid10001 与只读挂载后成功。第一次公网承接者合作检查遗漏 `perspective=provider`，补齐既有 API 参数后全部通过；无需修改业务权限。

## 备份与 HTTPS 续期

迁移前备份：`/opt/opc/backups/20261026T083036Z`。迁移后备份：`/opt/opc/backups/20261026T083331Z`，包含自定义格式 DB dump、42 文件归档、计数、site.env 和 SHA256SUMS。后者哈希校验通过，在独立临时 PG 库实际恢复成功，8 迁移／18账号／21需求／93消息／42文件计数一致，归档文件数42；仅删除本次临时恢复库。

当前 IP 证书到期 UTC `2026-11-01 22:52:32`；`opc-certificate-renew.timer` 已启用，每6小时检查。已关闭 Certbot 内置随机等待，`renew --dry-run` 返回 all simulated renewals succeeded。systemd 续期服务 Result=success、ExecMainStatus=0，Nginx 检查及重载成功。首次旧脚本演练因额外随机等待超时，不计为通过；最终无额外等待演练已通过。

私有证据：本机 `.local/deployment/migration-20261026/manifest.json`、`public-verification.json` 与原 dump；服务器 `/opt/opc/shared/migration-20261026/verification.json`。这些包含内部标识／业务快照，不打入源码包。

## 验证边界

线上测试环境已部署和迁移；原本地服务和 APP 安装包配置未改，后续两地写入不自动同步。本轮没有安装新手机包，也没有完成日本各运营商真实网络、负载容量、外部支付／邮件／AI、生产业务与定时异地灾备验收。正式发布条件仍单独核对。
