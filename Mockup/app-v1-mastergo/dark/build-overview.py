"""Compose actual MasterGo exports; does not generate or alter UI artwork."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent
state = json.loads((root / 'canvas-state.json').read_text(encoding='utf-8'))
font_path = 'C:/Windows/Fonts/msyh.ttc'
font_bold = 'C:/Windows/Fonts/msyhbd.ttc'
def font(size, bold=False):
    return ImageFont.truetype(font_bold if bold else font_path, size)

labels = ['登录 / 注册入口', '客户需求首页', '提交开发需求', '审核进度 / 补充',
          '内部任务大厅', '开发任务详情', '项目工作台', '成果提交 / 内审', '客户验收']
width, height = 1258, 2808
canvas = Image.new('RGB', (width, height), '#0E1718')
draw = ImageDraw.Draw(canvas)
draw.text((24, 20), 'OPC / DARK MODE', font=font(30, True), fill='#EAF4F1')
draw.text((24, 64), 'APPClient · 9 个日文可编辑画板 · MasterGo 实际预览', font=font(16), fill='#A4BBB4')
manifest = []
for index, page in enumerate(sorted(state['screens'], key=lambda x: x['id'])):
    path = root / page['preview']
    with Image.open(path) as screenshot:
        screenshot.load()
        assert screenshot.size == (390, 844), (path, screenshot.size)
        col, row = index % 3, index // 3
        x, y = 24 + col * 416, 126 + row * 886
        draw.text((x, y - 30), f"{page['id']}  {labels[index]}", font=font(17, True), fill='#A4BBB4')
        canvas.paste(screenshot.convert('RGB'), (x, y))
        draw.rectangle((x-1, y-1, x+390, y+844), outline='#33494B', width=1)
    manifest.append({'id': page['id'], 'nodeId': page['nodeId'], 'file': page['preview'],
                     'size': [390, 844], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
draw.text((24, 2761), '2026.10.12 · 示例数据 · 原生可编辑效果图，尚未实现交互与 Flutter 主题切换', font=font(15), fill='#A4BBB4')
canvas.save(root / 'overview.png')
(root / 'preview-manifest.json').write_text(json.dumps({'source': 'actual MasterGo canvas PNG exports', 'count': len(manifest), 'screens': manifest}, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'verified': len(manifest), 'overview': str(root / 'overview.png'), 'size': canvas.size}, ensure_ascii=False))
