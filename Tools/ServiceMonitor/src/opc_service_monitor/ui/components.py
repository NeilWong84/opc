"""Reusable Material/HUD controls; decoration never represents synthetic telemetry."""
from __future__ import annotations

from PySide6.QtCore import QEvent, QPointF, QRectF, QSize, Qt, Signal
from PySide6.QtGui import QColor, QIcon, QPainter, QPen, QPixmap, QPolygonF
from PySide6.QtWidgets import (
    QApplication, QButtonGroup, QComboBox, QFrame, QHBoxLayout, QLabel,
    QLineEdit, QPushButton, QTableWidget, QTabWidget, QWidget,
)


def colors() -> dict[str, str]:
    from opc_service_monitor.ui.theme import PALETTES
    app = QApplication.instance()
    return PALETTES.get(app.property("opcTheme") if app else "dark", PALETTES["dark"])


def console_icon(name: str, color: str | None = None) -> QIcon:
    """Original vector glyphs, rendered at 2x for Windows display scaling."""
    pixmap = QPixmap(40, 40)
    pixmap.fill(Qt.transparent)
    pixmap.setDevicePixelRatio(2)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setPen(QPen(QColor(color or colors()["accent"]), 1.5, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
    def line(points):
        painter.drawPolyline(QPolygonF([QPointF(x, y) for x, y in points]))
    if name == "play":
        line([(6, 4), (15, 10), (6, 16), (6, 4)])
    elif name == "stop":
        painter.drawRoundedRect(QRectF(5, 5, 10, 10), 1, 1)
    elif name == "pause":
        painter.drawLine(7, 5, 7, 15)
        painter.drawLine(13, 5, 13, 15)
    elif name == "search":
        painter.drawEllipse(QRectF(3, 3, 10, 10))
        painter.drawLine(12, 12, 17, 17)
    elif name == "refresh":
        painter.drawArc(QRectF(4, 4, 12, 12), 40 * 16, 280 * 16)
        line([(12, 3), (16, 4), (16, 8)])
    elif name in {"external", "logout"}:
        line([(9, 4), (4, 4), (4, 16), (16, 16), (16, 11)])
        painter.drawLine(9, 11, 16, 4)
        line([(11, 4), (16, 4), (16, 9)])
    elif name == "settings":
        for x, y in ((5, 7), (10, 13), (15, 8)):
            painter.drawLine(x, 3, x, 17)
            painter.setBrush(QColor(colors()["surface"]))
            painter.drawEllipse(QPointF(x, y), 2, 2)
    elif name in {"download", "latest"}:
        painter.drawLine(10, 3, 10, 13)
        line([(6, 9), (10, 13), (14, 9)])
        painter.drawLine(4, 17, 16, 17)
    elif name == "copy":
        painter.drawRoundedRect(QRectF(7, 7, 10, 10), 1, 1)
        line([(12, 4), (3, 4), (3, 13)])
    elif name == "clear":
        painter.drawLine(4, 5, 16, 5)
        painter.drawRoundedRect(QRectF(6, 5, 8, 12), 1, 1)
        painter.drawLine(8, 2, 12, 2)
    elif name == "lock":
        painter.drawRoundedRect(QRectF(5, 9, 10, 8), 1, 1)
        painter.drawArc(QRectF(7, 3, 6, 11), 0, 180 * 16)
    elif name == "sun":
        painter.drawEllipse(QRectF(6, 6, 8, 8))
        for a, b, c, d in ((10, 1, 10, 3), (10, 17, 10, 19), (1, 10, 3, 10), (17, 10, 19, 10),
                           (3, 3, 4, 4), (16, 16, 17, 17), (3, 17, 4, 16), (16, 4, 17, 3)):
            painter.drawLine(a, b, c, d)
    elif name == "moon":
        painter.drawArc(QRectF(3, 3, 14, 14), 80 * 16, 290 * 16)
        painter.drawArc(QRectF(8, 1, 10, 12), 110 * 16, 200 * 16)
    elif name == "database":
        painter.drawEllipse(QRectF(4, 3, 12, 5))
        painter.drawLine(4, 5, 4, 15)
        painter.drawLine(16, 5, 16, 15)
        painter.drawArc(QRectF(4, 12, 12, 5), 180 * 16, 180 * 16)
        painter.drawArc(QRectF(4, 7, 12, 5), 180 * 16, 180 * 16)
    elif name == "code":
        line([(6, 5), (2, 10), (6, 15)])
        line([(14, 5), (18, 10), (14, 15)])
        painter.drawLine(12, 3, 8, 17)
    else:
        painter.drawRoundedRect(QRectF(3, 4, 14, 12), 2, 2)
        painter.drawLine(3, 8, 17, 8)
    painter.end()
    return QIcon(pixmap)


class ConsoleButton(QPushButton):
    def __init__(self, text: str = "", parent=None, *, icon: str = "", variant: str = "default") -> None:
        super().__init__(text, parent)
        self.icon_name = icon
        self.setProperty("variant", variant)
        self.setCursor(Qt.PointingHandCursor)
        self.setMinimumHeight(32)
        self.setIconSize(QSize(16, 16))
        self.refresh_theme()

    def refresh_theme(self) -> None:
        if self.icon_name:
            palette = colors()
            variant = self.property("variant")
            if variant in {"power-start", "power-stop"}:
                color = (
                    palette["muted"] if self.isChecked()
                    else palette["disabled"] if not self.isEnabled()
                    else palette["danger"] if variant == "power-stop"
                    else palette["accent"]
                )
            elif not self.isEnabled():
                color = palette["disabled"]
            elif variant == "primary":
                color = palette["on_accent"]
            else:
                color = palette["danger"] if variant == "danger" else palette["accent"]
            icon = console_icon(self.icon_name, color)
            # Keep the factually selected segment visible even though it cannot be clicked.
            if variant in {"power-start", "power-stop"}:
                pixmap = icon.pixmap(self.iconSize())
                icon.addPixmap(pixmap, QIcon.Disabled, QIcon.Off)
                icon.addPixmap(pixmap, QIcon.Disabled, QIcon.On)
            self.setIcon(icon)

    def changeEvent(self, event: QEvent) -> None:  # noqa: N802
        super().changeEvent(event)
        if event.type() == QEvent.EnabledChange:
            self.setCursor(Qt.PointingHandCursor if self.isEnabled() else Qt.ArrowCursor)
            self.refresh_theme()


class ConsoleLineEdit(QLineEdit):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.setMinimumHeight(32)
        self.setClearButtonEnabled(not self.isReadOnly())

    def setReadOnly(self, read_only: bool) -> None:  # noqa: N802
        super().setReadOnly(read_only)
        self.setClearButtonEnabled(not read_only)


class ConsoleComboBox(QComboBox):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.setMinimumHeight(32)
        self.setMinimumContentsLength(8)
        self.setSizeAdjustPolicy(QComboBox.AdjustToContents)


class ConsoleTable(QTableWidget):
    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.setAlternatingRowColors(True)
        self.setShowGrid(False)
        self.verticalHeader().hide()
        self.verticalHeader().setDefaultSectionSize(30)
        self.horizontalHeader().setMinimumHeight(32)
        self.setSelectionBehavior(QTableWidget.SelectRows)
        self.setCornerButtonEnabled(False)


class ConsoleTabs(QTabWidget):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setDocumentMode(True)
        self.setIconSize(QSize(16, 16))

    def refresh_theme(self) -> None:
        for index, name in enumerate(("code", "external", "code", "database", "lock")):
            if index < self.count():
                self.setTabIcon(index, console_icon(name))


class ThemeSwitch(QFrame):
    theme_selected = Signal(str)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("themeSwitch")
        self.setAccessibleName("界面主题")
        group = QButtonGroup(self)
        row = QHBoxLayout(self)
        row.setContentsMargins(3, 3, 3, 3)
        row.setSpacing(2)
        self.buttons: dict[str, ConsoleButton] = {}
        for mode, title, icon in (("light", "明亮", "sun"), ("dark", "暗黑", "moon")):
            button = ConsoleButton(title, icon=icon, variant="segment")
            button.setObjectName(f"theme-{mode}")
            button.setCheckable(True)
            button.setAccessibleName(f"切换{title}主题")
            button.clicked.connect(lambda _checked=False, selected=mode: self.theme_selected.emit(selected))
            group.addButton(button)
            row.addWidget(button)
            self.buttons[mode] = button

    def set_theme(self, mode: str) -> None:
        self.buttons[mode].setChecked(True)


class ConsoleSurface(QWidget):
    """Static engineering grid; no animations or fake readings."""
    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        palette = colors()
        painter.fillRect(self.rect(), QColor(palette["background"]))
        painter.setPen(QPen(QColor(palette["grid"]), 1))
        for x in range(0, self.width(), 28):
            for y in range(0, self.height(), 28):
                painter.drawPoint(x, y)
        painter.end()


class BrandMark(QWidget):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setFixedSize(54, 54)

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor(colors()["accent"]), 2))
        painter.setBrush(QColor(colors()["accent_soft"]))
        painter.drawPolygon(QPolygonF([QPointF(27, 3), QPointF(49, 15), QPointF(49, 39),
                                     QPointF(27, 51), QPointF(5, 39), QPointF(5, 15)]))
        painter.setPen(QPen(QColor(colors()["accent"]), 2.5))
        painter.drawPolyline(QPolygonF([QPointF(15, 28), QPointF(22, 28), QPointF(26, 18),
                                      QPointF(30, 36), QPointF(34, 26), QPointF(40, 26)]))
        painter.end()


class TelemetryStrip(QFrame):
    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("telemetryStrip")
        row = QHBoxLayout(self)
        row.setContentsMargins(8, 4, 8, 4)
        self.labels = [QLabel(title) for title in ("进程 · 未检查", "端口 · 未检查", "就绪 · 未检查")]
        for label in self.labels:
            label.setProperty("telemetry", True)
            row.addWidget(label, 1)

    def set_values(self, process: bool, port: bool, ready: bool | None) -> None:
        for label, title, value in zip(self.labels, ("进程", "端口", "就绪"), (process, port, ready)):
            label.setText(f"{title} · {'正常' if value else '未通过' if value is False else '未检查'}")
            label.setProperty("tone", "success" if value else "muted")
            label.style().unpolish(label)
            label.style().polish(label)
