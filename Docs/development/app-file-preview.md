# 手机正文与附件的预览、保存

更新：2026-10-25。本轮适用于真实 API 模式；覆盖需求原文、范围与合作条款、沟通、交付说明及附件中的平台文件。

## 用户操作

- 点击正文文件卡片或附件进入同一个预览页。图片支持缩放；音频／视频支持播放、暂停与进度定位；PDF 及 Office 的只读页面支持逐页切换、缩放。
- 点击“保存到手机文件”，下载经过授权的原件后打开 Android／iOS 系统位置选择器。选择 Downloads／文件夹并完成保存，才显示保存成功。Office 预览的 PDF 副本不替代原始 Word、Excel、PPT 下载。
- 转换、解码或密码保护导致预览失败时，保留重试和原件保存；权限或安全检查失败时阻止读取和保存。不能通过文件缓存绕过鉴权。
- 中日语言包保持一致；文件名和原文保持原样，白色文档纸张不随主题反色。

## 实现与部署

`BackendService/app/files.py` 对原始字节检查类型，支持 PNG/JPEG/WebP/GIF、MP4/WebM、MP3/M4A/WAV/Ogg/FLAC、UTF-8 文本与 PDF。DOC/DOCX、XLS/XLSX/CSV、PPT/PPTX 通过本机 LibreOffice 转为只读 PDF。Android 使用系统 PdfRenderer，iOS 增加 PDFKit 桥接；没有采用第三方云文档查看服务。

本机已将核对官方 SHA256 的 LibreOffice 26.8.1 解包在 `BackendService/.local/preview-tools/LibreOffice`。其他机器在 BackendService 目录运行：

```powershell
.\scripts\setup-document-preview.ps1
```

也可先从官方镜像下载同版本 MSI，传 `-InstallerPath`。脚本仅建立项目忽略目录内的管理映像；工具、安装包、派生缓存不提交源码。Linux／其他部署可通过 `OPC_OFFICE_BINARY` 指向已安装的 `soffice`。

配置包括 `OPC_PREVIEW_ROOT`（默认 `.local/previews`）与 `OPC_PREVIEW_TIMEOUT_SECONDS`（默认 60 秒）。缓存按原件字节和格式生成，不向客户端暴露缓存路径。转换每次使用独立临时用户配置，最高宏安全级别、禁用文档链接更新，不继承数据库等应用环境变量；同进程仅允许一个转换，超时清理本次子进程树，失败不发布缓存。生产转换进程仍须按部署环境配置独立系统权限与资源隔离。

正文采用平台文件引用 `opc-file:<UUID>`，并兼容 `/api/v1/mobile/files/<UUID>` 的 Markdown 和受限 HTML 媒体引用；渲染后仍经相同文件 API 鉴权。任意第三方 URL、HTML 脚本保持原文，不自动请求或执行。当前数据接口保存的是原文文本，本轮未新增富文本编辑器或外部文件抓取代理。

说明：Office 按只读打印页面预览，不编辑文件、不执行宏，不承诺所有字体／动画／公式效果与原编辑软件一致。文件原件完整保留。既有 `file_previews` 表未写入伪造状态，本轮派生文件直接从私有缓存鉴权返回，没有新增数据库迁移。

工具命令依据 [LibreOffice 官方启动参数](https://help.libreoffice.org/latest/en-GB/text/shared/guide/start_parameters.html?DbPAR=BASIC&System=WIN)，版本校验依据[官方发布镜像信息](https://download.documentfoundation.org/libreoffice/stable/26.8.1/win/x86_64/LibreOffice_26.8.1_Win_x86-64.msi.mirrorlist)。实际验证见[文件预览与手机保存](../testing/app-file-preview-2026-10-25.md)。
