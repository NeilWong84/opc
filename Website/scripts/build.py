"""Build a dependency-free bilingual static site; publish only explicit public files."""
from __future__ import annotations

import argparse
from datetime import datetime
from hashlib import sha256
from html import escape
import json
from pathlib import Path
import shutil
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

import qrcode
from qrcode.image.svg import SvgPathImage

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
APK = REPO / 'APPClient/build/packages/OPC-0.1.0-build3-android-cloud-20261026-release.apk'
ICONS = {
    'arrow': '<path d="M5 12h14m-5-5 5 5-5 5"/>',
    'download': '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
    'web': '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M7 6.5h.01M10 6.5h.01M8 13l-2 2 2 2m8-4 2 2-2 2m-3-5-2 6"/>',
    'system': '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    'mobile': '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 5h4m-3 14h2"/>',
    'automation': '<path d="m13 2-9 12h7l-1 8 10-13h-8l1-7Z"/>',
}


def icon(name):
    return f'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>'


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8', newline='\n')


def build():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--public-url')
    parser.add_argument('--admin-url')
    parser.add_argument('--indexable', action='store_true', help='Only use after the real domain is live')
    args = parser.parse_args()
    config = json.loads((ROOT / 'site.json').read_text(encoding='utf-8'))
    public = (args.public_url or config['public_url']).rstrip('/') + '/'
    admin = args.admin_url or config['admin_url']
    indexed = args.indexable or config['indexable']
    for url in (public, admin):
        parsed = urlparse(url)
        if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password:
            raise ValueError('Public URLs must be explicit HTTPS URLs without credentials')
    if indexed and urlparse(public).hostname == '43.165.191.156':
        raise ValueError('The temporary IP site must not be indexed')
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    shutil.copytree(ROOT / 'assets', output / 'assets', dirs_exist_ok=True)
    meta = json.loads(APK.with_suffix('.apk.json').read_text(encoding='utf-8-sig'))
    digest = sha256(APK.read_bytes()).hexdigest()
    if digest != meta['sha256'] or APK.stat().st_size != meta['bytes']:
        raise ValueError('APK differs from the verified cloud release')
    release = {key: meta[key] for key in ('version_name', 'version_code', 'package_name', 'bytes', 'sha256', 'min_android_sdk', 'architectures')}
    release.update({'date': meta['date'], 'stage': 'test', 'signing': 'test', 'file': APK.name, 'url': f'packages/{APK.name}', 'android_min': '7.0'})
    write(output / 'release.json', json.dumps(release, ensure_ascii=False, indent=2) + '\n')
    package_dir = output / 'packages'
    package_dir.mkdir(exist_ok=True)
    shutil.copy2(APK, package_dir / APK.name)
    write(package_dir / (APK.name + '.sha256'), f'{digest}  {APK.name}\n')

    for locale in ('ja', 'zh'):
        t = json.loads((ROOT / f'content/{locale}.json').read_text(encoding='utf-8'))
        other = 'zh' if locale == 'ja' else 'ja'
        for download_page in (False, True):
            depth = '../../' if download_page else '../'
            path = locale + ('/download/' if download_page else '/')
            download_url = './' if download_page else 'download/'
            home = '../' if download_page else './'
            alternate = depth + other + ('/download/' if download_page else '/')
            title = t['downloadPageTitle'] if download_page else t['title']
            description = t['downloadPageDescription'] if download_page else t['description']

            def image(name, cls='', lazy=True):
                return f'<img class="{cls}" src="{depth}assets/screens/{locale}-{name}.webp" width="450" height="960" alt="{t["previewAlt"]}" {"loading=\"lazy\"" if lazy else "fetchpriority=\"high\""} decoding="async">'

            def button(label=None, href=None, cls='primary'):
                return f'<a class="button {cls}" href="{href or download_url}">{icon("download" if cls == "primary" else "arrow")}<span>{label or t["download"]}</span></a>'

            def qr():
                return f'<div class="qr"><img src="{depth}assets/qr-{locale}.svg" width="132" height="132" alt="{t["qrAlt"]}"><span>{t["qrLabel"]}</span></div>'

            links = ''.join(f'<a href="{home}#{target}">{label}</a>' for target, label in zip(('services', 'process', 'app', 'about'), t['nav']))
            header = f'''<a class="skip" href="#main">{t['skip']}</a><header class="header"><div class="shell nav-shell">
<a class="brand" href="{home}" aria-label="OPC"><span class="brand-mark" aria-hidden="true">◈</span>OPC<span class="brand-dot">.</span></a>
<nav class="desktop-nav" aria-label="{'メイン' if locale == 'ja' else '主导航'}">{links}</nav>
<div class="nav-actions"><a class="admin-link" href="{escape(admin)}" target="_blank" rel="noopener noreferrer">{t['admin']} ↗</a><a class="language" data-locale="{other}" lang="{'zh-CN' if other == 'zh' else 'ja'}" href="{alternate}" aria-label="{'切换至简体中文' if other == 'zh' else '日本語に切り替え'}">{'中文' if other == 'zh' else '日本語'}</a><a class="nav-download" href="{download_url}">{t['downloadShort']} <span aria-hidden="true">↗</span></a><button class="menu-toggle" aria-expanded="false" aria-controls="mobile-nav" aria-label="{t['menu']}"><span></span><span></span></button></div>
</div><nav id="mobile-nav" class="mobile-nav" aria-label="{'モバイル' if locale == 'ja' else '手机导航'}" hidden>{links}<a href="{escape(admin)}" target="_blank" rel="noopener noreferrer">{t['admin']} ↗</a></nav></header>'''
            footer = f'''<footer class="footer shell"><div><a class="brand" href="{home}"><span class="brand-mark" aria-hidden="true">◈</span>OPC<span class="brand-dot">.</span></a><p>{t['footerLine']}</p></div><div class="footer-links"><a href="{download_url}">{t['downloadShort']} ↗</a><a href="{escape(admin)}" target="_blank" rel="noopener noreferrer">{t['admin']} ↗</a><a data-locale="{other}" href="{alternate}">{'简体中文' if other == 'zh' else '日本語'}</a></div><div class="footer-bottom"><span>© {datetime.now().year} OPC</span><span>{t['footerRegion']}<br>{t['footerTest']}</span><span>IDEAS INTO REALITY.</span></div></footer>'''

            if not download_page:
                services = ''.join(f'<article class="service reveal"><div class="service-top"><span>{row[0]}</span>{icon(row[4])}</div><h3>{row[1]}</h3><p>{row[2]}</p><small>{row[3]}</small></article>' for row in t['services'])
                steps = ''.join(f'<li class="reveal"><span class="step-number">0{i+1}</span><div><h3>{row[0]}</h3><p>{row[1]}</p></div></li>' for i, row in enumerate(t['steps']))
                features = ''.join(f'<button class="feature {"active" if i == 0 else ""}" data-screen="{i}" aria-pressed="{"true" if i == 0 else "false"}"><span class="feature-index">0{i+1}</span><span><strong>{row[0]}</strong><span>{row[1]}</span></span><span class="feature-arrow" aria-hidden="true">↗</span></button>' for i, row in enumerate(t['features']))
                screens = ''.join(f'<figure class="app-shot" {"hidden" if i else ""} data-shot="{i}">{image(name)}<figcaption>{t["productTabs"][i]}</figcaption></figure>' for i, name in enumerate(('home', 'project', 'files')))
                faq = ''.join(f'<details><summary>{row[0]}<span aria-hidden="true">+</span></summary><p>{row[1]}</p></details>' for row in t['faqs'])
                future = ''.join(f'<span>{item}</span>' for item in t['futureItems'])
                main = f'''<main id="main">
<section class="hero shell"><div class="hero-copy"><p class="eyebrow"><span class="status-dot"></span>{t['eyebrow']}</p><h1>{t['hero']}</h1><p class="hero-text">{t['heroText']}</p><div class="hero-actions">{button()}<a class="text-link" href="#services">{t['explore']} <span aria-hidden="true">↘</span></a></div><p class="availability"><span class="tiny-tag">{t['test']}</span>{t['availability']}</p></div>
<div class="hero-visual" aria-label="{t['screenLabel']}"><div class="orbit orbit-one"></div><div class="orbit orbit-two"></div><div class="orbit-point"></div><span class="visual-coordinate">35°40′ N / 139°45′ E<br>BUILT AROUND YOUR IDEA</span><div class="phone phone-back">{image('project',lazy=False)}</div><div class="phone phone-front">{image('home',lazy=False)}</div><div class="floating-note"><span class="status-dot"></span>{t['signal']}<span class="note-line"></span></div><p class="screen-caption">{t['screenNote']}</p></div></section>
<div class="service-strip"><div class="shell"><span class="strip-label">IDEA → PRODUCT</span>{''.join(f'<span>{item}</span>' for item in t['strip'])}<span class="strip-end" aria-hidden="true">↗</span></div></div>
<section id="services" class="section shell"><div class="section-head reveal"><p class="eyebrow">{t['servicesTag']}</p><h2>{t['servicesTitle']}</h2><p class="section-intro">{t['servicesIntro']}</p></div><div class="services-grid">{services}</div><p class="scope-note">{t['scope']}</p></section>
<section id="process" class="section process-section"><div class="shell process-grid"><div class="process-heading reveal"><p class="eyebrow">{t['processTag']}</p><h2>{t['processTitle']}</h2><p class="section-intro">{t['processIntro']}</p><div class="process-art" aria-hidden="true"><span>IDEA</span><i></i><span>PRODUCT</span><b>↗</b></div></div><ol class="timeline">{steps}</ol></div></section>
<section id="app" class="section shell product-section"><div class="product-visual reveal"><div class="product-ring" aria-hidden="true"></div><div class="product-screens">{screens}</div><p class="screen-caption">{t['screenNote']}</p></div><div class="product-copy"><p class="eyebrow">{t['productTag']}</p><h2>{t['productTitle']}</h2><p class="section-intro">{t['productIntro']}</p><div class="features">{features}</div><a class="text-link" href="{download_url}">{t['downloadShort']} <span aria-hidden="true">↗</span></a></div></section>
<section id="about" class="section about-section"><div class="shell about-grid"><div class="about-symbol" aria-hidden="true"><span>1</span><i>×</i><span>AI</span><small>LESS LIMITS.<br>MORE POSSIBILITIES.</small></div><div class="about-copy reveal"><p class="eyebrow">{t['aboutTag']}</p><h2>{t['aboutTitle']}</h2><p>{t['aboutText']}</p><p class="muted">{t['aboutSecondary']}</p><div class="future"><small>{t['future']}</small><div>{future}</div><small class="muted">{t['futureNote']}</small></div></div></div></section>
<section class="section shell"><div class="cta reveal"><div class="cta-copy"><p class="eyebrow">YOUR NEXT STEP</p><h2>{t['ctaTitle']}</h2><p>{t['ctaText']}</p>{button()}<span class="cta-test">{t['test']}</span></div>{qr()}<span class="cta-orbit" aria-hidden="true"></span></div></section>
<section id="faq" class="section shell faq-section"><div><p class="eyebrow">{t['faqTag']}</p><h2>{t['faqTitle']}</h2></div><div class="faq-list">{faq}</div></section></main>'''
            else:
                values = [f'{release["version_name"]} ({release["version_code"]})', release['date'], f'{release["bytes"] / 1024 / 1024:.1f} MiB · {release["bytes"]:,} bytes', 'Android 7.0+ (API 24)', release['package_name'], t['test']]
                facts = ''.join(f'<div><dt>{label}</dt><dd>{value}</dd></div>' for label, value in zip(t['releaseLabels'], values))
                install = ''.join(f'<li><span class="step-number">0{i+1}</span><h3>{row[0]}</h3><p>{row[1]}</p></li>' for i, row in enumerate(t['installSteps']))
                main = f'''<main id="main" class="download-main"><section class="shell download-hero"><div class="download-copy"><a class="text-link back-link" href="{home}">← {t['back']}</a><p class="eyebrow"><span class="status-dot"></span>OPC FOR ANDROID</p><h1>{t['downloadTitle']}</h1><p class="section-intro">{t['downloadIntro']}</p><span class="tiny-tag">{t['test']}</span><div class="apk-action">{button(t['apkButton'],depth+release['url'])}<p>{t['apkNote']}</p></div><p class="test-notice">{t['testNotice']}</p><p class="muted requirements">{t['requirements']}</p></div><div class="download-visual"><div class="orbit"></div><div class="phone">{image('home',lazy=False)}</div>{qr()}<p class="screen-caption">{t['screenNote']}</p></div></section>
<section class="shell release-section"><div><p class="eyebrow">RELEASE / {release['version_name']}</p><h2>{t['releaseTitle']}</h2></div><div><dl class="release-facts">{facts}</dl><div class="checksum"><div><label for="checksum">{t['checksum']}</label><button class="copy-button" data-copy="checksum" data-copied="{t['copied']}" data-error="{t['copyFailed']}">{t['copy']}</button></div><textarea id="checksum" rows="2" readonly spellcheck="false">{digest}</textarea><p class="copy-status" role="status" aria-live="polite"></p><a href="{depth}packages/{APK.name}.sha256" download>SHA-256 .txt ↗</a></div></div></section>
<section class="section shell install-section"><p class="eyebrow">GET STARTED</p><h2>{t['installTitle']}</h2><ol>{install}</ol><p class="scope-note">{t['installCaution']}</p></section></main>'''

            canonical = f'<link rel="canonical" href="{public}{path}">' if indexed else ''
            if indexed:
                canonical += ''.join(f'<link rel="alternate" hreflang="{code}" href="{public}{loc}{"/download/" if download_page else "/"}">' for loc, code in (('ja', 'ja'), ('zh', 'zh-CN'), ('ja', 'x-default')))
            # The same stylesheet/script works with /site/ now and a domain root later.
            html = f'''<!doctype html><html lang="{t['lang']}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{escape(title)}</title><meta name="description" content="{escape(description)}"><meta name="robots" content="{'index,follow' if indexed else 'noindex,nofollow'}"><meta name="theme-color" content="#091512">{canonical}<meta property="og:type" content="website"><meta property="og:site_name" content="OPC"><meta property="og:title" content="{escape(title)}"><meta property="og:description" content="{escape(description)}"><meta property="og:url" content="{public}{path}"><meta property="og:image" content="{public}assets/share.png"><meta property="og:locale" content="{'ja_JP' if locale == 'ja' else 'zh_CN'}"><meta name="twitter:card" content="summary_large_image"><link rel="icon" href="{depth}assets/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="{depth}assets/site.css"><script src="{depth}assets/site.js" defer></script></head><body data-locale="{locale}">{header}{main}{footer}</body></html>'''
            html = html.replace('35°40′ N / 139°45′ E', 'OPC / MOBILE WORKSPACE')
            write(output / path / 'index.html', html)
        qr_image = qrcode.make(public + locale + '/download/', image_factory=SvgPathImage, border=4, box_size=6)
        qr_image.save(str(output / f'assets/qr-{locale}.svg'))

    redirect = '<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>OPC</title><script src="assets/redirect.js" defer></script></head><body><noscript><a href="ja/">日本語</a> · <a href="zh/">简体中文</a></noscript></body></html>'
    redirect = redirect.replace('<html lang="ja">', '<html lang="ja" data-admin-url="' + escape(admin) + '">')
    write(output / 'index.html', redirect)
    write(output / '404.html', '<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>404 | OPC</title><link rel="stylesheet" href="' + escape(public) + 'assets/site.css"></head><body><main class="shell section"><p class="eyebrow">404 / OPC</p><h1>ページが見つかりません。</h1><p>页面不存在。</p><a class="text-link" href="' + escape(public) + '">OPC →</a></main></body></html>')
    write(output / 'robots.txt', 'User-agent: *\n' + ('Allow: /\nSitemap: ' + public + 'sitemap.xml\n' if indexed else 'Disallow: /\n'))
    if indexed:
        urlset = ET.Element('urlset', xmlns='http://www.sitemaps.org/schemas/sitemap/0.9')
        for path in ('ja/', 'zh/', 'ja/download/', 'zh/download/'):
            ET.SubElement(ET.SubElement(urlset, 'url'), 'loc').text = public + path
        write(output / 'sitemap.xml', ET.tostring(urlset, encoding='unicode'))
    else:
        (output / 'sitemap.xml').unlink(missing_ok=True)
    write(output / 'build.json', json.dumps({'public_url': public, 'admin_url': admin, 'indexable': indexed, 'release_sha256': digest}, indent=2))
    print(f'Built 4 bilingual pages, public release {release["version_name"]} ({release["version_code"]}), SHA-256 verified. URL: {public}')


if __name__ == '__main__':
    build()
