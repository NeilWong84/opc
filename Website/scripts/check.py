"""Verify static publication boundaries, references and release metadata."""
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw
import zxingcpp

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'


class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.ids = set()
        self.lang = None
        self.noindex = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if 'id' in a:
            assert a['id'] not in self.ids, 'Duplicate element id'
            self.ids.add(a['id'])
        if tag == 'html': self.lang = a.get('lang')
        if tag == 'meta' and a.get('name') == 'robots': self.noindex = 'noindex' in a.get('content', '')
        for key in ('src', 'href'):
            if a.get(key): self.references.append(a[key])


def main():
    build = json.loads((DIST / 'build.json').read_text())
    release = json.loads((DIST / 'release.json').read_text())
    package = DIST / release['url']
    assert package.stat().st_size == release['bytes']
    assert sha256(package.read_bytes()).hexdigest() == release['sha256']
    source_locales = [json.loads((ROOT / f'content/{loc}.json').read_text(encoding='utf-8')) for loc in ('ja', 'zh')]
    assert set(source_locales[0]) == set(source_locales[1]), 'Language key mismatch'
    for locale in ('ja', 'zh'):
        svg = ET.parse(DIST / f'assets/qr-{locale}.svg').getroot()
        width, height = map(float, svg.get('viewBox').split()[2:])
        bitmap = Image.new('RGB', (round(width*20), round(height*20)), 'white')
        draw = ImageDraw.Draw(bitmap)
        path = next(iter(svg)).get('d')
        for x, y, right, bottom, left in re.findall(r'M([\d.]+),([\d.]+)H([\d.]+)V([\d.]+)H([\d.]+)z', path):
            draw.rectangle((round(float(x)*20), round(float(y)*20), round(float(right)*20)-1, round(float(bottom)*20)-1), fill='black')
        decoded = zxingcpp.read_barcode(bitmap)
        assert decoded and decoded.text == build['public_url'] + locale + '/download/', 'QR destination mismatch'
    pages = {}
    for file in DIST.rglob('*.html'):
        doc = Document()
        doc.feed(file.read_text(encoding='utf-8'))
        pages[file.resolve()] = doc
        assert doc.lang in ('ja', 'zh-CN')
        if not build['indexable']: assert doc.noindex
    for file, doc in pages.items():
        for ref in doc.references:
            parsed = urlparse(ref)
            if parsed.scheme or parsed.netloc: continue
            assert not ref.startswith('/'), f'Nonportable root reference: {ref}'
            target = (file.parent / unquote(parsed.path)).resolve() if parsed.path else file
            if target.is_dir(): target /= 'index.html'
            assert target.is_relative_to(DIST.resolve()), f'Escaping reference: {ref}'
            assert target.exists(), f'Missing resource: {file.name} -> {ref}'
            if parsed.fragment:
                assert parsed.fragment in pages[target].ids, f'Missing anchor: {ref}'
    for file in DIST.rglob('*'):
        if not file.is_file(): continue
        assert not any(part in ('node_modules', '.local', '__pycache__') for part in file.parts)
        assert file.suffix not in ('.py', '.pem', '.key', '.log', '.env')
        assert 'credential' not in file.name.lower()
    print(f'PASS: {len(pages)} HTML documents; bilingual keys, local links/anchors, SEO settings, 2 decoded QR destinations, package SHA-256, and publication boundaries.')


if __name__ == '__main__':
    main()
