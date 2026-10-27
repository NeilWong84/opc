"""Resize inspected, synthetic-data APP captures and render a native brand share card."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
screens = ROOT / 'assets/screens'
screens.mkdir(parents=True, exist_ok=True)
for locale in ('ja', 'zh'):
    for name in ('home', 'project', 'files'):
        source = ROOT / f'test_artifacts/android/{locale}-{name}.png'
        if not source.exists():
            raise SystemExit('Missing inspected real APP capture: ' + source.name)
        xml = source.with_suffix('.xml')
        descriptions = ' '.join(n.get('content-desc', '') for n in ET.parse(xml).iter('node'))
        expected = {'home': ('プロジェクトの概要', '我的项目总览'), 'project': ('協業条件', '合作条款'), 'files': ('.docx', '.xlsx')}[name]
        if not any(marker in descriptions for marker in expected):
            raise SystemExit('Capture has not finished loading: ' + source.name)
        image = Image.open(source).convert('RGB')
        # Remove OS navigation/status regions; keep the APP content unchanged.
        image = image.crop((0, 65, image.width, image.height-65))
        if max(image.getextrema()[channel][1] for channel in range(3)) < 15:
            raise SystemExit('Capture is blank: ' + source.name)
        image.resize((450, 960), Image.Resampling.LANCZOS).save(screens / f'{locale}-{name}.webp', quality=86)

canvas = Image.new('RGB', (1200, 630), '#091512')
d = ImageDraw.Draw(canvas)
for inset in (0, 70, 140):
    d.ellipse((740-inset, -40-inset, 1320+inset, 540+inset), outline='#254c32', width=2)
font_path = 'C:/Windows/Fonts/arial.ttf'
bold_path = 'C:/Windows/Fonts/arialbd.ttf'
d.polygon([(100,85),(123,108),(100,131),(77,108)], fill='#94f0bf')
d.text((144,65), 'OPC.', font=ImageFont.truetype(bold_path,70), fill='#eef5ee')
d.text((75,235), 'IDEAS INTO', font=ImageFont.truetype(bold_path,78), fill='#eef5ee')
d.text((75,330), 'REALITY.', font=ImageFont.truetype(bold_path,100), fill='#94f0bf')
d.text((80,520), 'AI DEVELOPMENT, TOGETHER.', font=ImageFont.truetype(font_path,20), fill='#9caea5')
canvas.save(ROOT / 'assets/share.png', optimize=True)
print('Prepared 6 actual APP captures and native OPC share card.')
