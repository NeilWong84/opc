# 腾讯云东京 OPC 线上测试环境

更新：2026-10-26。用户已购买并授权部署到东京轻量应用服务器 `lhins-1nxj2eln`，官网和独立运营域名现已启用；业务系统继续用于线上测试。官网上线与业务正式发行分别记录，当前 APK 为测试签名。

## 入口与运行结构

2026-10-26 后续已按用户要求生成指向此 HTTPS 服务的 [Android 云端测试 APK](../testing/app-cloud-apk-2026-10-26.md)；现有手机／模拟器不会自动覆盖安装。

- 官网入口：[www.opcapp.art](https://www.opcapp.art/)，默认日语、支持简中；独立 Android 下载说明页和公开测试 APK。
- 后管入口：[admin.opcapp.art](https://admin.opcapp.art/#/login)，真实管理 API 同源位于 `/api/v1`。
- 原手机 API：`https://43.165.191.156/api/v1`，就绪检查 `/health/ready`；公网文档关闭，IP 普通页面跳转正式域名。
- `FrontendAdmin/Dockerfile` 构建独立 Vue 管理镜像；`BackendService/Dockerfile` 构建非 root FastAPI 镜像，包含 Linux LibreOffice 和中日文字体。
- Compose 的五个常驻服务为 website、admin、nginx、backend、postgres。只有网关公开 80/443；其余服务只走 Docker 网络。PG 使用命名卷 `opc-test-pg18-data`，应用仅使用受限 `opc_app`。
- 后端镜像版本 `20261026-02`，管理前端 `20261026-website02`，官网 `20261026-website03`；PG `18.4-bookworm`，Nginx `1.28-alpine`。后端 Python 3.14，管理前端构建 Node 22；官网为静态文件。资源额度和日志轮转见 [Compose](../../Deploy/compose.yaml)。

实际检查的主机为 Ubuntu 26.04、2 CPU、约 3.65 GiB 内存、2 GiB swap、60 GB 磁盘。Docker 29.9.2 / Compose v5.6.1 已安装；五个服务已健康运行。腾讯云入站 443 初始未放行，用户添加规则后浏览器和公网 API 验证通过；后续域名切换及检查见 [官网验证](../testing/opc-website-2026-10-26.md)。

## 文件、数据库和配置

| 位置 | 当前内容 |
| --- | --- |
| `/opt/opc/current` | 指向 `/opt/opc/releases/20261026-website03` 的运行版本链接 |
| `/opt/opc/shared/site.env` | 非敏感站点、镜像版本、数据库名、附件根路径；权限 0600 |
| `/opt/opc/shared/secrets` | PG 随机维护／应用密码及首次初始化管理员文件；目录 0700，文件 0400 |
| `/opt/opc/shared/migration-20261026/files` | 当前迁移附件及新上传的持久目录，归容器 uid 10001 |
| `/opt/opc/shared/previews` | 派生 PDF 缓存，不代替原附件 |
| `/opt/opc/shared/letsencrypt` | `opc` IP 与 `opc-domains` 双域名证书和私钥；私钥不进入镜像 |
| `/opt/opc/backups` | 一致性数据库／附件备份、配置、计数与 SHA256SUMS；不自动删除旧备份 |

当前 PG 数据库为 `opc_migrated_20261026`，标记 `opc.cloud-test.v1`。`site.env` 中 `DATABASE_NAME` 与 `FILES_ROOT` 同时选定相应数据集。初始化命令检查既有迁移的版本／checksum，仅应用缺失迁移，不重置已有账号和密码。8 条 SQL 历史未修改。

服务器登录与管理员凭据在本机 `D:\OPC\.local\deployment\server-credentials.json`、`admin-credentials.json` 中使用 Windows DPAPI 机器绑定加密；目录 ACL 限定管理员、SYSTEM 和执行身份，正常管理员会话解密已验证。文件均在忽略目录内。不要将这些文件放入源码包或发送给他人。需要登录时主动执行 [凭据复制命令](../../Deploy/README.md#凭据与-https)，终端不打印明文；本轮未自动修改剪贴板。

迁移后使用原本地管理员账号，首次初始化的云端管理员只属于保留的旧空测试库。其加密凭据留在 `admin-credentials.pre-migration.json` 供回退；不要用服务器 root 密码登录 OPC 后管。

## 2026-10-26 业务快照迁移

源为本机原生 PostgreSQL `127.0.0.1:55440/opc_integration` 与 BackendService 的私有文件目录，并非一套 Docker 数据卷。`5432/opc_dev` 与 `Accounts` 未改动。

在 UTC `2026-10-26T08:25:17.512300Z` 建立只读 REPEATABLE READ 快照，将同一快照交给 `pg_dump -Fc --snapshot`；导出全部 40 张表并计算排序后的逐行 SHA-256。文件按数据库 storage_key、大小及 SHA-256 检查，导出打包时再次核对字节。

| 记录 | 快照数量 |
| --- | ---: |
| 账号 | 18 |
| 需求 | 21 |
| 合作 | 12 |
| 消息 | 93 |
| 私有附件 | 42 |
| 原件总字节 | 2,186,382 |

先恢复至独立云库，40 张表校验值全部一致，42 个文件全部一致后才切换。保留密码哈希、角色授权、审核与版本、沟通、交付和审计；撤销复制来的 29 条未撤销会话，不迁移本机 Token 的登录效力。随后真实验证原管理员／客户／承接者密码和身份、公网鉴权、全部 42 个下载及真实文档预览。验证只登录、读取和退出，没有在迁移业务库新增合成客户或需求。

本机数据继续保留，原本地服务地址和 APP 配置未改变。此次是快照迁移，切换之后两处新增或修改不会自动同步。既有合成业务的性质仍为合成场景，不因迁移成为真实客户授权。

## 日常检查、备份与续期

常用 Compose 命令、凭据读取和备份入口见 [Deploy/README](../../Deploy/README.md)。`backup.sh` 读取当前数据库和文件目录，短暂停止 API，导出 DB 和附件，写配置及校验值，退出时重启 API。`verify-restore.sh` 只创建独立临时库，对备份执行实际恢复并检查计数／附件归档，随后仅删除自己的临时库。

迁移后已验证备份 `/opt/opc/backups/20261026T083331Z`。同时保留迁移前备份 `/opt/opc/backups/20261026T083036Z` 和原始本机导出；详细验证见 [记录](../testing/tencent-compose-deployment-2026-10-26.md)。备份目前在本机／该服务器持久目录，没有配置定时异地备份或告警。

IP HTTPS 使用 Let's Encrypt `shortlived` 证书，有效期约 160 小时，当前到期 UTC `2026-11-01 22:52:32`。`opc-certificate-renew.timer` 每 6 小时运行，systemd 最多随机延后 15 分钟；Certbot 额外随机等待已关闭。已成功执行真实配置的 `renew --dry-run`，续期服务结果 success，Nginx 配置检查与重载成功。80 端口须保持可达供 HTTP-01；仅开放 443 会影响续期。

域名 `www`、`admin` 的默认线路 A 记录均为 `43.165.191.156`；不要在主机记录栏再次填写完整域名。`opc-domains` 同时覆盖两个域名，到期 UTC `2027-01-24 09:54:38`，域名模拟续期通过，原 timer 自动处理两个证书。后台 `ADMIN_PUBLIC_ORIGIN=https://admin.opcapp.art/`，使用同源 API，无需扩展浏览器跨域访问。原 APP 包继续通过 IP 测试 API 工作。

## 回退边界

迁移前 `opc_test` 数据库及 `/opt/opc/shared/files` 原样保留，配置在 `site.pre-migration.env`，旧版本 `20261026-01` 也保留。若确认需要回退，先备份当前数据，短暂停止 backend，用旧配置恢复 `site.env`、将 current 指向旧版本，再执行 Compose `up -d --wait`。这是切回迁移前空测试数据集，切换后云端新写入不会自动合并到旧库；应先决定这些写入的保留方式。

不要使用 `docker compose down -v`，不要对在线 PG 目录直接打包当作逻辑备份，不要将数据、密码或私钥带入镜像。当前没有自动更新镜像、自动删库、自动清理备份或任意客户代码执行功能。
