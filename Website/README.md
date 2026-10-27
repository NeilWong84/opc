# OPC 官网

首版为原生 HTML／CSS／JavaScript 静态营销站，无业务登录、表单、数据库或第三方追踪。日语默认，简体中文可切换；注册、需求提交、沟通和交付验收仍在 APP。运营后台使用独立域名与管理身份。

## 入口与结构

- 已上线官网：`https://www.opcapp.art/`；语言页 `/ja/`、`/zh/`，独立下载页 `/ja/download/`、`/zh/download/`。
- 已上线后台：`https://admin.opcapp.art/#/login`。部署与测试证据见 [验证记录](../Docs/testing/opc-website-2026-10-26.md)。
- `site.json`：公开站点地址、后台链接、搜索索引开关。
- `content/ja.json`、`content/zh.json`：完整文案；`assets/`：共享样式、原生交互和公开产品画面。
- `scripts/build.py`：生成四个内容页面、语言入口、404、二维码、SEO、公开版本信息及安装包。
- `dist/`：唯一站点发布内容；`test_artifacts/`：本机忽略的原始截图、检查与发布包。不得把整个项目或业务文件目录作为公开根目录。

## 构建与本地检查

使用 Python 3.14 和隔离环境，安装 `requirements-test.txt`；构建本身只需要 `requirements.txt`。本机已有部署虚拟环境，实际命令：

```powershell
.local/deployment/venv/Scripts/python.exe -m pip install -r Website/requirements-test.txt
.local/deployment/venv/Scripts/python.exe Website/scripts/build.py
.local/deployment/venv/Scripts/python.exe Website/scripts/check.py
.local/deployment/venv/Scripts/python.exe -m http.server 5190 --bind 127.0.0.1 --directory Website/dist
```

打开 `http://127.0.0.1:5190/ja/`。构建会读取 `site.json`，`--public-url`、`--admin-url` 可显式覆盖地址；临时 IP 站点禁止打开索引。正式域名模式生成 canonical、双语 hreflang 和 sitemap；根目录按默认或已选择语言跳转，旧后台 hash 书签转到运营域名。语言偏好仅保存 `opc.site.locale`，不保存会话或私有资料。

## 下载包与公开资料

当前源为 `APPClient/build/packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk` 及其 `.apk.json`。构建核对大小和 SHA-256 后复制至 `dist/packages/`，由真实元数据生成 `release.json` 与下载页，不手填包大小或校验值。测试签名、测试环境、Android 7.0+ 与版本 `0.1.0 (3)`在下载页明确说明。

更新版本时，更换构建器的源 APK 与对应构建记录，必须采用新版本文件名；重新构建并检查四页、版本清单和两张二维码。旧安装包路径保持不变，发布保留旧源目录与镜像。不能把私有需求附件加入公开下载目录。

公开画面来自本轮独立只读 Android 模拟器上安装的云端普通 APK，展示合成测试账号数据，没有公开原始附件、业务 ID 清单或凭据。截图仅移除 OS 状态／导航区域并缩放，不重画功能和项目状态；网页就近标注样例。原始截图不进入公开包。`prepare_assets.py` 用于从已检查截图重新生成 WebP 和原生品牌分享图；`capture_android.py` 仅为本机采集辅助，凭据从忽略文件在内存读取。

## 部署与回退

官网由独立非 root Nginx 容器提供内部 8080，公网网关按主机名分流：`www` → 官网，`admin` → 管理应用及其同源 API，旧 IP `/api/`、`/health/` 保留。IP 页面及 `/admin` 跳转正式域名；不增加 PG／后端公网端口。

```powershell
$websiteReleaseTag = '20261026-website04' # 示例：每次选择新的唯一标签
.local/deployment/venv/Scripts/python.exe Website/scripts/deploy.py --tag $websiteReleaseTag --phase stage
.local/deployment/venv/Scripts/python.exe Website/scripts/deploy.py --tag $websiteReleaseTag --phase publish
```

`stage` 只上传显式公开文件与必要配置，复制旧源码版本、保留环境备份并构建镜像，不切换运行服务。`publish` 复用原发布包，签发包含两个域名的证书、检查 Nginx 后切换官网／管理前端／网关，并核对 PG 与后端容器 ID 和启动时间未变化。不要在阶段间重建或修改发布包；需修改时使用新 tag。

当前 `/opt/opc/current` 为 `/opt/opc/releases/20261026-website03`，官网镜像后缀 `20261026-website03`、后台镜像后缀 `20261026-website02`，后端仍为 `20261026-02`。完整部署包生成器也已纳入官网静态构建内容；调用 `Tools/Deployment/package.py` 前必须先构建并检查官网。旧的首次初始化与旧 IP 后管验证脚本仅用于历史阶段，现有系统更新使用本目录的分阶段发布和 `verify_live.py`，不要重复执行历史数据库初始化。

域名使用独立 `opc-domains` 证书，IP 仍使用原 `opc` 短期证书。原六小时续期任务的 `certbot renew` 会覆盖两个证书并验证、重载网关。正式切换需两个 A 记录均从公网解析到 `43.165.191.156`。

自动切换失败会按前一 Compose 恢复其官网、管理前端及网关，并恢复环境与 `/opt/opc/current`。人工回退时先核对实际前一目录及对应 `/opt/opc/shared/site.before-<tag>.env`，用该环境和前一目录的 Compose 只更新前端和网关：已有官网版本为 `website admin nginx`，首次官网上线前的旧版本为 `admin nginx`。随后恢复当前源码软链接；不执行 `down -v`、数据库迁移、重新 seed 或密码重置。已发行版本不要删除，除非另获明确清理授权。
