"""Restore system DLL lookup before a frozen monitor launches external tools.

PyInstaller documents the inherited Windows DLL search path here:
https://pyinstaller.org/en/stable/common-issues-and-pitfalls.html#launching-external-programs-from-the-frozen-application
"""

from collections.abc import Mapping
import ctypes
import ntpath
import sys


def configure_external_process_runtime() -> bool:
    """Reset the bootloader DLL directory after Qt and native modules are loaded.

    Call once after the main window is shown and before enabling service starts.
    The monitor has no bundled child helpers that require the bootloader path.
    """
    if sys.platform != "win32" or not getattr(sys, "frozen", False):
        return False
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    reset_directory = kernel32.SetDllDirectoryW
    reset_directory.argtypes = [ctypes.c_wchar_p]
    reset_directory.restype = ctypes.c_int
    if not reset_directory(None):
        raise ctypes.WinError(ctypes.get_last_error())
    return True


def sanitized_external_environment(environment: Mapping[str, str]) -> dict[str, str]:
    """Copy a child environment without PATH entries from the frozen bundle."""
    result = dict(environment)
    if sys.platform != "win32" or not getattr(sys, "frozen", False):
        return result
    bundle_root = getattr(sys, "_MEIPASS", None)
    if not isinstance(bundle_root, str) or not bundle_root:
        return result
    normalized_root = ntpath.normcase(ntpath.normpath(bundle_root))
    if not ntpath.isabs(normalized_root):
        return result

    def outside_bundle(value: str) -> bool:
        candidate = value.strip()
        if len(candidate) >= 2 and candidate.startswith('"') and candidate.endswith('"'):
            candidate = candidate[1:-1]
        normalized = ntpath.normcase(ntpath.normpath(candidate))
        if not ntpath.isabs(normalized):
            return True
        try:
            return ntpath.commonpath((normalized_root, normalized)) != normalized_root
        except ValueError:
            return True  # Different drive or UNC share.

    for key, value in result.items():
        if key.casefold() == "path":
            result[key] = ";".join(part for part in value.split(";") if outside_bundle(part))
    return result
