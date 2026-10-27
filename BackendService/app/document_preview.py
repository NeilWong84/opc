"""本机 Office → PDF 预览；不修改原件，不向外部服务发送客户文件。"""
import hashlib
from contextlib import contextmanager
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

from .errors import DomainError

OFFICE_EXTENSIONS = {".doc", ".docx", ".xls", ".xlsx", ".csv", ".ppt", ".pptx", ".odt", ".ods", ".odp"}
_conversion_lock = threading.Lock()


@contextmanager
def _conversion_slot():
    if not _conversion_lock.acquire(timeout=1):
        raise DomainError(503, "PREVIEW_BUSY", "文档预览正在处理其他文件，请稍后重试")
    try:
        yield
    finally:
        _conversion_lock.release()


def _run_conversion(args, work, env, timeout):
    child = subprocess.Popen(args, cwd=work, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                             start_new_session=os.name != "nt")
    try:
        child.communicate(timeout=timeout)
        return child.returncode
    except subprocess.TimeoutExpired:
        # 只终止本次独立配置启动的子进程树，防止超时后遗留 soffice.bin。
        if child.poll() is None:
            if os.name == "nt":
                subprocess.run([str(Path(os.environ["SYSTEMROOT"]) / "System32/taskkill.exe"),
                                "/PID", str(child.pid), "/T", "/F"], capture_output=True,
                               creationflags=subprocess.CREATE_NO_WINDOW, timeout=5, check=False)
            else:
                import signal
                os.killpg(child.pid, signal.SIGKILL)
        child.communicate(timeout=5)
        raise


def office_binary(settings):
    candidates = [settings.office_binary, shutil.which("soffice.com"), shutil.which("soffice")]
    if os.name == "nt":
        candidates += [str(Path(".local/preview-tools/LibreOffice/program/soffice.com")),
                       r"C:\Program Files\LibreOffice\program\soffice.com"]
    return next((str(Path(value).resolve()) for value in candidates if value and Path(value).is_file()), None)


def office_pdf(path, name, settings):
    """只接收服务端已鉴权、clean 的本地原件；缓存路径不可作为公开 URL。"""
    suffix = Path(name).suffix.lower()
    if suffix not in OFFICE_EXTENSIONS:
        raise DomainError(422, "PREVIEW_UNSUPPORTED", "文件格式不支持文档转换")
    binary = office_binary(settings)
    if not binary:
        raise DomainError(503, "PREVIEW_CONVERTER_NOT_CONFIGURED", "文档预览服务尚未配置")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    root = settings.preview_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    # 同字节不同后缀必须分别转换，避免缓存命中另一种输入解释。
    target = root / f"{digest}-{suffix[1:]}-v1.pdf"
    with _conversion_slot():
        if target.is_file():
            return target
        with tempfile.TemporaryDirectory(prefix="convert-", dir=root) as temp:
            work = Path(temp)
            source = work / ("source" + suffix)
            shutil.copyfile(path, source)
            profile = work / "profile"
            user = profile / "user"
            user.mkdir(parents=True)
            # 独立临时配置：最高宏安全级别、禁止更新外部链接；不复用桌面用户配置。
            (user / "registrymodifications.xcu").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
<item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop></item>
<item oor:path="/org.openoffice.Office.Calc/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>2</value></prop></item>
<item oor:path="/org.openoffice.Office.Writer/Content/Update"><prop oor:name="Link" oor:op="fuse"><value>2</value></prop></item>
</oor:items>''', encoding="utf-8")
            args = [binary, f"-env:UserInstallation={profile.as_uri()}", "--headless", "--nologo",
                    "--nodefault", "--norestore", "--convert-to", "pdf", "--outdir", str(work), str(source)]
            # 子进程不继承应用数据库凭据或业务令牌。
            child_env = {key: value for key, value in os.environ.items()
                         if key.upper() in {"PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "COMSPEC",
                                            "PROGRAMFILES", "PROGRAMFILES(X86)", "APPDATA", "LOCALAPPDATA", "USERPROFILE"}}
            try:
                returncode = _run_conversion(args, work, child_env, settings.preview_timeout_seconds)
            except subprocess.TimeoutExpired:
                raise DomainError(503, "PREVIEW_TIMEOUT", "文档转换超时，请重试或下载原件") from None
            except OSError:
                raise DomainError(503, "PREVIEW_FAILED", "文档预览服务不可用") from None
            pdf = work / "source.pdf"
            if returncode != 0 or not pdf.is_file() or pdf.stat().st_size > 50 * 1024 * 1024:
                raise DomainError(422, "PREVIEW_FAILED", "文档无法预览，请下载原件检查文件或密码保护")
            with pdf.open("rb") as stream:
                if not stream.read(5) == b"%PDF-":
                    raise DomainError(422, "PREVIEW_FAILED", "转换结果不是有效 PDF")
            # 唯一临时目录 + 原子替换，未完成文件不会作为成功缓存。
            pdf.replace(target)
    return target
