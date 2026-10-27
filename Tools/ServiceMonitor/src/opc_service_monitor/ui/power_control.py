from __future__ import annotations

from PySide6.QtWidgets import QFrame, QHBoxLayout, QSizePolicy

from opc_service_monitor.ui.components import ConsoleButton
from opc_service_monitor.ui.service_actions import ServiceActions


class _PowerButton(ConsoleButton):
    def nextCheckState(self) -> None:  # noqa: N802
        """Only an observed service state may change the selected segment."""


class PowerControl(QFrame):
    """Two actions sharing one observed ON/OFF state, without optimistic toggles."""

    def __init__(self, start_text: str = "启动", stop_text: str = "停止", parent=None) -> None:
        super().__init__(parent)
        self.setObjectName("powerControl")
        self.setProperty("powerControl", True)
        self.setAccessibleName("服务启停开关")
        self.setSizePolicy(QSizePolicy.Maximum, QSizePolicy.Fixed)
        self._start_text = start_text
        self._stop_text = stop_text
        self.start_button = _PowerButton(start_text, icon="play", variant="power-start")
        self.stop_button = _PowerButton(stop_text, icon="stop", variant="power-stop")
        row = QHBoxLayout(self)
        row.setContentsMargins(2, 2, 2, 2)
        row.setSpacing(0)
        for button in (self.start_button, self.stop_button):
            button.setCheckable(True)
            button.setEnabled(False)
            row.addWidget(button)

    def set_actions(self, actions: ServiceActions) -> None:
        self.setProperty("powerState", "on" if actions.power_on is True else "off" if actions.power_on is False else "unknown")
        self.setAccessibleDescription(actions.reason)
        for button, selected, enabled, text, transition in (
            (self.start_button, actions.power_on is True, actions.can_start, self._start_text, "starting"),
            (self.stop_button, actions.power_on is False, actions.can_stop, self._stop_text, "stopping"),
        ):
            button.setChecked(selected)
            button.setEnabled(enabled)
            button.setText(f"{text}中…" if actions.transition == transition else text)
            state_text = "当前已启动" if actions.power_on is True else "当前已停止" if actions.power_on is False else "状态尚未确定"
            description = f"{state_text}；{actions.reason}"
            button.setToolTip(description)
            button.setAccessibleName(button.text())
            button.setAccessibleDescription(description)
            button.style().unpolish(button)
            button.style().polish(button)
            button.refresh_theme()
        self.style().unpolish(self)
        self.style().polish(self)
