# 任务资料原创参考资源

生成日期：2026-10-13。用于 MasterGo 手机端任务大厅与任务详情中的可选截图、视频封面视觉设计。本目录不表示 APPClient 已实现媒体上传、预览或播放。

所有图像均由 `generate_assets.py` 使用 Pillow 绘制原创的日文咨询管理系统 UI，未使用客户截图、外部品牌图片或真实个人资料。页面中的案件、日期、计数、文件名称和大小均为合成示例。字体使用本机 Windows Yu Gothic，不复制字体文件。

| 文件 | 尺寸 | 大小 | 用途 |
| --- | --- | --- | --- |
| inquiry-overview.png | 1200 × 750 | 137,755 bytes | 日文咨询管理列表，作为需求参考截图 |
| inquiry-detail.png | 1200 × 750 | 163,141 bytes | 咨询详情与处理记录，作为第二张截图 |
| workflow-poster.png | 1200 × 750 | 137,668 bytes | 操作演示的封面效果；静态图片，无视频文件或可播放时长 |

三张最终 PNG 均已逐张实际打开检查：日文显示完整、导航和文字未越界、下拉箭头及文件图标改用矢量绘制，避免字体缺字。图像以 2 倍尺寸绘制后缩至目标尺寸，以改善边缘清晰度。

复现：在已安装 Pillow 的 Python 环境执行 `python Mockup/task-reference-assets/generate_assets.py`。默认 Python 未安装 Pillow 时可使用工作区附带的 Python 运行时；无需安装新依赖。

用户确认新稿后，三张 PNG 已原样复制到 `APPClient/assets/references/` 用于 Flutter 交互；未修改本目录原图，也未对外上传。APPClient 另有 8 秒本地 MP4 及有效的 Office/PDF/文本样例文件，生成与格式清单见其 `tool/generate_reference_samples.py` 和 `assets/references/manifest.json`。本目录仍是设计资源，真实远程媒体与文件转换服务尚未接入。
