import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parts = root / 'lib' / 'l10n' / 'parts'
for locale in ('ja', 'zh'):
    result = {'@@locale': locale}
    for file in sorted(parts.glob(f'*_{locale}.json')):
        values = json.loads(file.read_text(encoding='utf-8-sig'))
        overlap = result.keys() & values.keys()
        if overlap:
            raise ValueError(f'Duplicate keys in {file}: {overlap}')
        result.update(values)
    (root / 'lib' / 'l10n' / f'app_{locale}.arb').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
ja = json.loads((root/'lib/l10n/app_ja.arb').read_text(encoding='utf-8'))
zh = json.loads((root/'lib/l10n/app_zh.arb').read_text(encoding='utf-8'))
if ja.keys() != zh.keys():
    raise ValueError(f'Locale key mismatch: {ja.keys() ^ zh.keys()}')
print(f'Merged {sum(not k.startswith("@") for k in ja)} messages per locale.')
