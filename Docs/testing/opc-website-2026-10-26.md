# OPC 官网首版验证（2026-10-26）

## 当前状态

本轮已完成官网实现并部署上线：官网 [www.opcapp.art](https://www.opcapp.art/)，运营后台 [admin.opcapp.art](https://admin.opcapp.art/)。已通过真实公网 HTTPS、浏览器访问、后台登录和下载验证。业务后台仍为既有线上测试环境。

当前官网镜像 `opc-website:20261026-website03`、管理镜像 `opc-admin:20261026-website02`，当前源目录 `/opt/opc/releases/20261026-website03`。首次双域名发布包 SHA-256 为 `55fd8c2d7193494a1033c5c6746f247fa8d23919d99f1868619a7fbac10b042c`；随后仅更新官网镜像修复平板宽度下样例说明被视觉容器裁切的问题，最终 CSS SHA-256 为 `327869658aa3572b82a4be0a931cb0141f0ab61bc441b30b6cd8cade18a49271`。原 `20261026-02`、两个官网版本与各次环境备份均保留供回退。

用户最终指定官网 `https://www.opcapp.art/`、后管 `https://admin.opcapp.art/`，替代本轮较早讨论的 IP 根目录与 `/admin/`。已配置对应域名、正式 canonical／hreflang／sitemap 和下载二维码；原 Android APK 仍连接 `https://43.165.191.156/` 的 API。

## 已完成的本地验证

- 静态生成 4 个内容页面以及语言入口、404；两套文案键集合一致，所有相对资源与页内锚点存在，无路径越界。
- QR 使用实际输出 SVG 栅格化并由 ZXing 解码，分别匹配日语／中文下载说明页。
- 云端测试 APK `0.1.0 (3)`，57,297,543 bytes，SHA-256 `631b96d803c0cf62eb6de6e623038a6603135edad4574702bc3d124e301d81a4`；构建时以原验证记录核对后复制，网页版本与校验信息从同一元数据生成。
- 通过 CUA 在 360／768／1440 三档宽度检查日中首页及下载页，共 12 组，无横向页面溢出、无缺图。
- 实际操作手机菜单展开／Escape 关闭、语言切换及根目录记忆、下载页保持页面类型切换、资料画面切换、FAQ Enter 展开、SHA-256 复制反馈。
- 使用独立只读 `emulator-5570` 安装普通云端 APK，登录已有合成客户并读取真实 PG 业务，采集两种语言的当前深色界面。截图均为合成资料；网页标注样例。视觉复核发现两张中文截图曾停在加载状态，已重采，并给素材准备脚本增加 XML 完成状态检查。
- 模拟器首次软件渲染器产生黑屏；更换为 SwiftShader、关闭 Vulkan 并重新连接本模拟器 AndroidWifi 后正常。不将初次失败计作验证通过，不修改既有 AVD 持久安装。
- 管理前端生产配置门禁、Vue／TypeScript 类型检查与正式域名构建通过。仅加入可配置静态 base 与 Docker 构建参数，未更改管理业务逻辑。
- 东京服务器上用隔离、无网络、无公网端口的官网镜像检查通过：Nginx 配置、日中页面、真实 CSP／缓存响应、APK MIME、HTTP 206 Range 的 1024 bytes 和镜像内 APK SHA-256。首次 BusyBox wget 将合法 206 视为失败，改用容器内 HTTP 原始请求检查后通过；隔离检查容器已清理，未操作现有服务。

命令及维护入口见 [Website README](../../Website/README.md)。原始 UI、浏览器与发布检查证据保存在忽略的 `Website/test_artifacts/`，不会放到公开网站。

## 发布验证

用户修正主机记录后，两台权威 DNS 均返回两个域名的 A 记录 `43.165.191.156`。通过原 ACME HTTP-01 签发 `opc-domains` 证书，SAN 同时包含 `www.opcapp.art`、`admin.opcapp.art`，到期 UTC `2027-01-24 09:54:38`。原 `opc` IP 证书保留；原六小时续期 timer 为 active，两个域名的真实配置 `certbot renew --cert-name opc-domains --dry-run` 成功。

`Website/scripts/verify_live.py` 完成 67 项公网检查：四个内容页及全部资源、canonical／hreflang／sitemap、HTTPS 跳转、404 与私有目录边界、APK 实际 57,297,543 bytes 和预期 SHA-256、下载 MIME／不可变缓存、HTTP 206 Range、后台独立域名及资源、旧 IP `/admin` 跳转、原 IP API、原管理员／客户／承接者登录、真实数据读取和 audience 隔离。脚本创建的三个验证会话均已撤销，没有提交需求、发送消息、确认条款或改动业务状态。

另通过浏览器真实填写并提交管理员登录表单，工作台成功加载，显示 API 已连接；验证标签页随后被浏览器会话关闭，不保留管理员登录页作为交付物。正式官网已在浏览器通过日语默认入口与中文页面检查，并保存公开页面截图。

Android 独立只读模拟器通过 Java `HttpsURLConnection` 使用系统默认信任，从正式官网直接下载 APK 到 Download 目录，大小和 SHA-256 与网页一致；未使用自定义信任管理器、跳过验证或弱化网络配置。随后从设备下载文件复制到本模拟器临时安装目录，`pm install -r` 返回 Success，普通 APP 成功启动。设备侧校验源码为 `Website/scripts/WebsiteDownloadCheck.java`；编译的 DEX/JAR、下载包与设备记录均保存在忽略目录或可丢弃模拟器，不进入官网发布包。

部署后官网、后管、网关、后端、PG 五个服务健康。首次切换只重建两个前端与网关，后端与 PG 的容器 ID 和启动时间逐字一致；后续说明裁切修复只更新官网容器。

最终通过浏览器 DOM 验证 830px 当前视口下样例说明完整处于视觉容器内、页面无横向溢出，并核对公网 CSS 与本机源码逐字节相同。后端启动时间仍为 UTC `2026-10-26T08:33:33.35788717Z`，PG 为 UTC `2026-10-26T07:58:06.829165767Z`；源码、域名入口和五服务健康状态再次核实。

Android 验证使用模拟器，未执行实体手机验收。当前 APK 继续使用测试签名、连接 IP 测试 API；正式商店签名、iOS 安装、支付、邮件和平台 AI 服务不在本轮范围内。

此前 DNS 阻塞曾分别用本机递归 DNS、东京服务器解析、Google 公共 DNS，以及直接查询 DNSPod 的 biscuit／julius 权威服务器核实，两条目标名称当时均为 NXDOMAIN。未绕过证书验证或将测试证书用于上线。

18:49 进一步定位到实际原因：直接查询权威 DNS 时，`www.opcapp.art.opcapp.art`、`admin.opcapp.art.opcapp.art` 均有 A 记录并指向 `43.165.191.156`，而目标子域名没有记录。已请求用户把主机记录缩为 `www`／`admin`，避免 DNSPod 自动追加域名后的重复后缀。

18:52 权威 DNS 已返回更正后的两条 A 记录，随后签证书并完成切换。现场发布验证中的 `curl | grep -q` 曾因 grep 提前结束输出 curl 23 提示；后续完整公网验证成功，已将发布脚本改为保存检查响应后再匹配，避免该提示。
