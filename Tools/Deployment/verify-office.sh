set -eu
docker exec -i opc-test-backend-1 python - <<'PY'
from pathlib import Path
import tempfile
from uuid import uuid4
from zipfile import ZipFile
from app.config import Settings
from app.document_preview import office_pdf

with tempfile.TemporaryDirectory(prefix='opc-deploy-check-') as directory:
    original = Path(directory) / 'deployment.docx'
    with ZipFile(original, 'w') as output:
        output.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        output.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        output.writestr('word/document.xml', f'<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>OPC 文档预览 日本語テスト {uuid4()}</w:t></w:r></w:p><w:sectPr/></w:body></w:document>')
    result = office_pdf(original, 'deployment.docx', Settings())
    assert result.read_bytes().startswith(b'%PDF-') and result.stat().st_size > 100
    print(f'PASS Linux Office conversion as non-root; PDF bytes={result.stat().st_size}')
    result.unlink()
PY
