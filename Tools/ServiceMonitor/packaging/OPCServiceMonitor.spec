# -*- mode: python ; coding: utf-8 -*-
from importlib.metadata import distribution
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files


tool_root = Path(SPECPATH).parent
source_root = tool_root / "src"
entrypoint = tool_root / "packaging" / "entrypoint.py"
theme = source_root / "opc_service_monitor" / "ui" / "theme.qss"
third_party_notices = tool_root / "THIRD_PARTY_NOTICES.md"


def distribution_licenses(package_name):
    """Keep the original wheel notices; fail rather than silently omit them."""
    package = distribution(package_name)
    license_files = [
        entry
        for entry in package.files or []
        if entry.parts[0].endswith(".dist-info")
        and entry.name.casefold().startswith(("license", "copying", "notice"))
    ]
    if not license_files:
        raise RuntimeError(f"Missing installed license files for {package_name}")
    return [(str(package.locate_file(entry)), f"licenses/{package_name}") for entry in license_files]


# The library also provides a PyInstaller hook. Explicitly collect the runtime
# inputs here so a hook-discovery change cannot leave the frozen themes incomplete.
material_data = collect_data_files(
    "qt_material",
    includes=[
        "material.qss.template",
        "themes/*.xml",
        "resources/source/*.svg",
        "fonts/roboto/*.ttf",
    ],
)
license_data = []
for package_name in ("qt-material", "Jinja2", "MarkupSafe"):
    license_data.extend(distribution_licenses(package_name))

a = Analysis(
    [str(entrypoint)],
    pathex=[str(source_root)],
    binaries=[],
    datas=[
        (str(theme), "opc_service_monitor/ui"),
        (str(third_party_notices), "."),
        *material_data,
        *license_data,
    ],
    hiddenimports=["PySide6.QtSvg"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # qt-material uses QtUiTools even without loading .ui files, so that module
    # and its native dependencies must remain. This Widgets-only application
    # does not use another Qt binding, QML, Qt Quick, 3D, or Chromium.
    excludes=[
        "PyQt5",
        "PyQt6",
        "PySide2",
        "PySide6.QtQml",
        "PySide6.QtQuick",
        "PySide6.QtQuickWidgets",
        "PySide6.QtQuickControls2",
        "PySide6.QtQuick3D",
        "PySide6.QtWebEngineCore",
        "PySide6.QtWebEngineWidgets",
        "PySide6.QtWebEngineQuick",
    ],
    noarchive=False,
    optimize=0,
)

# Qt 6 on Windows links to the operating-system ICU. A foreign Poppler directory
# on the build host's PATH can otherwise make PyInstaller collect an incompatible
# unversioned icuuc.dll beside the application, shadowing System32 and preventing
# QtCore from loading. Keep ICU only when it is actually shipped by PySide6.
foreign_icu_names = ("icuuc", "icuin", "icudt")
a.binaries = [
    entry
    for entry in a.binaries
    if not (
        entry[0].casefold().endswith(".dll")
        and entry[0].casefold().startswith(foreign_icu_names)
        and "pyside6" not in entry[1].casefold()
    )
]
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="OPCServiceMonitor",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="OPCServiceMonitor",
)

