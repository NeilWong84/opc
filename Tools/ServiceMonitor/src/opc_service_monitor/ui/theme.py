from __future__ import annotations

import tempfile
from pathlib import Path
from string import Template

from PySide6.QtGui import QColor, QPalette
from PySide6.QtWidgets import QApplication

# Import after PySide6 so qt-material selects the correct Qt binding.
from qt_material import build_stylesheet


PALETTES = {
    "dark": {
        "background": "#080f1c", "surface": "#101e30", "raised": "#15263b", "field": "#0c1727",
        "text": "#e3edf9", "muted": "#95abc3", "border": "#2a4058", "grid": "#1c2e43",
        "accent": "#54d8f5", "accent_soft": "#163c50", "on_accent": "#071b28",
        "hover": "#1d3850", "selection": "#23536d", "disabled": "#71849a",
        "success": "#63dbaf", "danger": "#ff9da8", "danger_soft": "#3a202e",
        "warning": "#f2c278", "warning_soft": "#3a3022", "stripe": "#132237",
    },
    "light": {
        "background": "#edf3f9", "surface": "#ffffff", "raised": "#f3f7fc", "field": "#f8fbfe",
        "text": "#142d48", "muted": "#536b84", "border": "#c9d8e7", "grid": "#d1dfec",
        "accent": "#006d9a", "accent_soft": "#dff1fc", "on_accent": "#ffffff",
        "hover": "#e8f3fc", "selection": "#c9e7f8", "disabled": "#687e94",
        "success": "#08734e", "danger": "#ac3047", "danger_soft": "#fff0f2",
        "warning": "#8a5707", "warning_soft": "#fff4df", "stripe": "#f3f7fc",
    },
}
_CACHE: dict[str, str] = {}
_ASSETS: tempfile.TemporaryDirectory | None = None


def theme_stylesheet(mode: str) -> str:
    global _ASSETS
    if mode not in PALETTES:
        raise ValueError("不支持的界面主题")
    if mode not in _CACHE:
        if _ASSETS is None:
            _ASSETS = tempfile.TemporaryDirectory(prefix="opc-monitor-theme-")
        # qt-material rebuilds icon directories: give it only our exclusive temp path.
        icon_root = Path(_ASSETS.name) / mode
        base = build_stylesheet(
            theme="dark_cyan.xml" if mode == "dark" else "light_blue.xml",
            invert_secondary=mode == "light",
            parent=str(icon_root),
            extra={"font_family": "Microsoft YaHei UI", "density_scale": "-1"},
        )
        if not base:
            raise RuntimeError("Material 主题资源缺失")
        # Theme-specific absolute paths avoid mutable shared Qt icon search paths.
        base = base.replace("icon:/", icon_root.as_posix() + "/")
        overlay = Path(__file__).with_name("theme.qss").read_text(encoding="utf-8")
        _CACHE[mode] = base + "\n" + Template(overlay).substitute(PALETTES[mode])
    return _CACHE[mode]


def apply_theme(application: QApplication, mode: str) -> None:
    stylesheet = theme_stylesheet(mode)
    palette = PALETTES[mode]
    application.setStyle("Fusion")
    qt_palette = QPalette()
    for role, key in (
        (QPalette.Window, "background"), (QPalette.WindowText, "text"),
        (QPalette.Base, "field"), (QPalette.AlternateBase, "stripe"),
        (QPalette.Text, "text"), (QPalette.Button, "raised"), (QPalette.ButtonText, "text"),
        (QPalette.Highlight, "selection"), (QPalette.HighlightedText, "text"),
        (QPalette.ToolTipBase, "surface"), (QPalette.ToolTipText, "text"),
        (QPalette.PlaceholderText, "muted"), (QPalette.Link, "accent"),
    ):
        qt_palette.setColor(role, QColor(palette[key]))
    for role in (QPalette.Text, QPalette.ButtonText, QPalette.WindowText):
        qt_palette.setColor(QPalette.Disabled, role, QColor(palette["disabled"]))
    application.setPalette(qt_palette)
    application.setProperty("opcTheme", mode)
    application.setStyleSheet(stylesheet)
    from opc_service_monitor.ui.components import ConsoleButton, ConsoleTabs
    for widget in application.allWidgets():
        if isinstance(widget, (ConsoleButton, ConsoleTabs)):
            widget.refresh_theme()
        widget.update()
