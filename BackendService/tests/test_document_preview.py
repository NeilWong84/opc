import subprocess

import pytest

from app.config import Settings
from app.document_preview import office_pdf
from app.errors import DomainError


def test_conversion_uses_isolated_profile_and_does_not_inherit_credentials(tmp_path, monkeypatch):
    from app import document_preview
    source = tmp_path / 'original'
    source.write_bytes(b'original-office-bytes')
    binary = tmp_path / 'soffice.exe'
    binary.touch()
    settings = Settings(office_binary=str(binary), preview_root=tmp_path / 'cache')
    monkeypatch.setenv('OPC_DATABASE_URL', 'sensitive')
    calls = []
    def convert(args, work, env, timeout):
        calls.append(args)
        assert 'OPC_DATABASE_URL' not in env
        assert any(arg.startswith('-env:UserInstallation=file:') for arg in args)
        assert (work / 'source.docx').read_bytes() == source.read_bytes()
        profile = (work / 'profile/user/registrymodifications.xcu').read_text(encoding='utf-8')
        assert 'MacroSecurityLevel' in profile
        (work / 'source.pdf').write_bytes(b'%PDF-test-result')
        return 0
    monkeypatch.setattr(document_preview, '_run_conversion', convert)
    output = office_pdf(source, '客户原文.docx', settings)
    assert output.read_bytes() == b'%PDF-test-result'
    assert source.read_bytes() == b'original-office-bytes'
    assert office_pdf(source, '客户原文.docx', settings) == output
    assert len(calls) == 1
    assert not list(settings.preview_root.glob('convert-*'))


@pytest.mark.parametrize('failure', ['timeout', 'corrupt'])
def test_failed_conversion_never_caches_a_successful_result(tmp_path, monkeypatch, failure):
    from app import document_preview
    binary = tmp_path / 'soffice.exe'
    binary.touch()
    source = tmp_path / 'source'
    source.write_bytes(b'office')
    settings = Settings(office_binary=str(binary), preview_root=tmp_path / 'cache')
    def convert(args, work, env, timeout):
        if failure == 'timeout':
            raise subprocess.TimeoutExpired(args, timeout)
        (work / 'source.pdf').write_bytes(b'not-a-pdf')
        return 0
    monkeypatch.setattr(document_preview, '_run_conversion', convert)
    with pytest.raises(DomainError) as error:
        office_pdf(source, 'test.xlsx', settings)
    assert error.value.code in {'PREVIEW_TIMEOUT', 'PREVIEW_FAILED'}
    assert list(settings.preview_root.iterdir()) == []
