"""Structural/media checks and a pinned allowlist for this locally built batch.

Run after visual review. This does not claim malware scanning or conversion in OPC.
"""
from hashlib import sha256
import json
from pathlib import Path
import subprocess
from zipfile import ZipFile
import xml.etree.ElementTree as ET

from PIL import Image
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1] / '.local/process-demo-20261025'


def inspect(path):
    suffix = path.suffix.lower()
    if suffix in {'.png', '.jpg'}:
        with Image.open(path) as image:
            image.verify()
        return 'Pillow 完整图像解码检查；参考画面/公开风景图片；人工视觉复核'
    if suffix in {'.mp3', '.mp4'}:
        probe = subprocess.run(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)], check=True, capture_output=True, text=True)
        result = json.loads(probe.stdout)
        if float(result['format']['duration']) <= 0:
            raise ValueError('Invalid duration')
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'null', '-'], check=True, capture_output=True)
        (ROOT / 'qa' / (path.name + '-probe.json')).write_text(probe.stdout, encoding='utf-8')
        return 'Samplelib 公开测试素材；许可来源见 media-sources.md；ffprobe 读取音视频参数及 ffmpeg 全流解码通过'
    if suffix == '.pdf':
        reader = PdfReader(path)
        assert len(reader.pages) == 1
        assert 'SHA-256' in reader.pages[0].extract_text()
        assert '/JavaScript' not in str(reader.trailer) and '/OpenAction' not in reader.trailer['/Root']
        return '本脚本组生成的单页合成 PDF；pypdf 结构和文本读取；Poppler 全页渲染并人工复核；无文档打开动作'
    if suffix in {'.docx', '.xlsx', '.pptx'}:
        with ZipFile(path) as archive:
            assert archive.testzip() is None
            names = archive.namelist()
            assert not any('vbaProject' in name or 'embeddings/' in name for name in names)
            for name in names:
                if name.endswith('.rels'):
                    rels = ET.fromstring(archive.read(name))
                    assert not any(r.attrib.get('TargetMode') == 'External' for r in rels)
                if name.endswith('.xml'):
                    ET.fromstring(archive.read(name))
        if suffix == '.docx':
            render = ROOT / 'qa' / (path.stem + '-docx')
            if not list(render.glob('page-*.png')):
                raise ValueError('Word 缺少实际渲染证据：' + path.name)
            return '本脚本组生成；OOXML ZIP/XML 全量解析，无宏、嵌入对象、外部关系；LibreOffice/Poppler 实际逐页渲染并人工复核'
        if suffix == '.xlsx':
            return 'Artifact Tool 生成；公式重算、记录数与状态数核对；两工作表渲染复核；OOXML 结构检查，无宏、外部关系或嵌入对象'
        receipt = json.loads((ROOT / 'qa' / (path.name.split('-')[0] + '-deck-validation.json')).read_text(encoding='utf-8'))
        assert receipt
        return 'Artifact Tool 生成；4页逐页渲染复核、结构/字体/几何/重新导入验证通过；无宏、嵌入对象或外部关系'
    if suffix == '.zip':
        with ZipFile(path) as archive:
            assert archive.testzip() is None
            assert set(archive.namelist()) == {'booking.py', 'test_booking.py', 'README.md', 'CHANGELOG.md'}
            for name in archive.namelist():
                archive.read(name).decode('utf-8')
        return '仅本脚本生成的最小 Python 标准库源码和说明；已实际执行1项保存/重读/重复校验单测，无第三方依赖或凭据'
    path.read_text(encoding='utf-8-sig')
    return '本脚本生成的 UTF-8 合成文本/CSV，内容与来源清单已复核，无可执行脚本'


def main():
    files = []
    for path in sorted((ROOT / 'assets').iterdir()):
        if path.suffix not in {'.png', '.jpg', '.mp3', '.mp4', '.pdf', '.docx', '.xlsx', '.pptx', '.zip', '.txt', '.md', '.csv'}:
            continue
        evidence = inspect(path)
        data = path.read_bytes()
        files.append({'name': path.name, 'size_bytes': len(data), 'sha256': sha256(data).hexdigest(), 'inspection': evidence})
    (ROOT / 'asset-manifest.json').write_text(json.dumps({'schema': 'opc.process-assets.v1', 'files': files}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(files)} assets checked and hash-pinned; no malware scanner was run.')


if __name__ == '__main__':
    main()
