# OPC Docker Compose 部署

当前为 2026-10-26 东京线上测试环境。实际执行证据见 [部署验证](../Docs/testing/tencent-compose-deployment-2026-10-26.md)，运行说明见 [云测试环境](../Docs/deployment/tencent-compose-test.md)。

官网及域名后续已上线：[官网](https://www.opcapp.art/)、[运营后台](https://admin.opcapp.art/)。官网、后管与网关的本轮发布见 [官网验证](../Docs/testing/opc-website-2026-10-26.md)与 [Website 维护](../Website/README.md)。现有 Android 测试包继续使用 IP API；IP 页面跳转对应正式域名。

## 五个常驻服务

| 服务 | 镜像 | 用途 |
| --- | --- | --- |
| website | `opc-website:20261026-website03` | 原生双语官网与公开 APK，独立非 root Nginx 提供内部 8080 |
| admin | `opc-admin:20261026-website02` | Vue/TDesign 静态管理应用；由独立非 root Nginx 提供内部 8080 |
| nginx | `nginx:1.28-alpine` | 唯一公网入口，80 跳转 HTTPS、ACME 验证及 443 反向代理 |
| backend | `opc-backend:20261026-02` | Python 3.14/FastAPI、真实私有文件与 Linux LibreOffice |
| postgres | `postgres:18.4-bookworm` | 独立持久 PostgreSQL 18.4 测试库，应用使用 `opc_app` |

`migrate` 是 tools profile 中复用后端镜像的一次性初始化命令，不属于常驻服务。Certbot 仅签发／续期时短暂运行，不挂载 Docker socket。

后端 Dockerfile 在 `BackendService/`，构建上下文为项目根目录，以纳入不可变的 DB 迁移；后管 Dockerfile 的上下文为 `FrontendAdmin/`，官网为 `Website/`。构建均排除密钥、本机环境与业务数据；官网仅复制 `dist/` 公开文件。生产管理构建继续强制显式 HTTPS API 地址，不复制本机 `.env.local`。`IMAGE_TAG` 继续选择原后端版本，`ADMIN_IMAGE_TAG`、`WEBSITE_IMAGE_TAG` 分别选择前端版本，`ADMIN_PUBLIC_ORIGIN` 为独立后管同源 API。

## 常用命令

在服务器执行：

```bash
cd /opt/opc/current
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml ps
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml logs --tail 100 backend nginx
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml config --quiet
```

显式初始化／迁移（先备份；检查标记、历史校验值与顺序，不重置已有管理员或数据库密码）：

```bash
docker compose --env-file /opt/opc/shared/site.env -f Deploy/compose.yaml --profile tools run --rm --no-deps --interactive=false -T migrate
```

手动一致备份会短暂停止此部署的 API，结束后自动启动；不停止 PG，不自动清理旧备份：

```bash
bash Tools/Deployment/backup.sh
bash Tools/Deployment/verify-restore.sh
```

不要运行 `docker compose down -v`，它会删除持久 PG 数据卷。不要把 `shared/secrets`、本机 `.local` 或数据库原目录打入镜像／源码发布包。服务器只公开 80／443，PG、后端与管理静态服务均无宿主机端口映射。云控制台的防火墙也需要允许 TCP 80／443。

## 凭据与 HTTPS

服务器连接信息和迁移后的原管理员凭据在本机 `D:\OPC\.local\deployment\` 的两个 JSON 中；密码使用 Windows DPAPI 机器绑定加密，文件 ACL 仅授予本机管理员、SYSTEM 与任务执行身份。本机正常用户解密检查通过，复制到其他机器不能直接解密；不要将整个忽略目录共享给其他人。

读取脚本返回 `PSCredential`，默认不显示密码。需要登录时，用户可在本机主动运行以下命令，分别复制邮箱与密码，再粘贴到登录表单：

```powershell
& D:\OPC\Tools\Deployment\Copy-LoginField.ps1 -Kind Admin -Field UserName
& D:\OPC\Tools\Deployment\Copy-LoginField.ps1 -Kind Admin -Field Password
```

上述命令只有用户主动执行时才更改本机剪贴板，本轮没有自动复制密码。服务器的随机 PG 密码和首次初始化管理员文件置于 `/opt/opc/shared/secrets`；目录 0700，文件 0400，后端常驻容器只挂载应用数据库密码。迁移后使用原本地账号密码；首次初始化管理员只属于保留的旧空测试库，原加密凭据另存 `admin-credentials.pre-migration.json`，不能用于当前业务库。

2026-10-26 已迁移本机 `55440/opc_integration` 的快照至独立 `opc_migrated_20261026`。`site.env` 的 `DATABASE_NAME` 和 `FILES_ROOT` 决定当前数据库与附件目录；备份脚本读取这两个配置。40 张表、18 个账号、21 条需求、12 个合作、93 条消息、42 个附件均已核对。原本地服务继续使用本地库，后续写入不会自动同步；云端旧 `opc_test`、旧附件和 `site.pre-migration.env` 保留供回退。

当前使用 Let's Encrypt 的 IP 地址短期证书（`shortlived`）。`opc-certificate-renew.timer` 每六小时检查一次，主机随机错峰最多15分钟，续期命令关闭 Certbot 自带额外随机等待，成功后检查并平滑重载 Nginx。80 端口须持续供 ACME HTTP-01 使用；证书私钥不进入镜像。

```bash
systemctl list-timers opc-certificate-renew.timer
systemctl status opc-certificate-renew.service
journalctl -u opc-certificate-renew.service --since today
```

域名已解析并签发独立 `opc-domains` 证书，官网与管理域名按 SNI 分流，管理端使用同源 API；原 `opc` IP 证书和手机 IP API 保留。原续期任务的 `certbot renew` 自动覆盖两个证书，域名证书模拟续期成功。官网本轮公开的是已生成的云端测试 APK，没有更改其签名或 API 地址。
