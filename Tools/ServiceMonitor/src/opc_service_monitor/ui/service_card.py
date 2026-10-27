from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QVBoxLayout

from opc_service_monitor.models import ServiceDefinition, ServiceId, ServiceState
from opc_service_monitor.supervisor import ServiceObservation
from opc_service_monitor.ui.components import TelemetryStrip
from opc_service_monitor.ui.power_control import PowerControl
from opc_service_monitor.ui.service_actions import ServiceActions, service_actions


_STATE_LABELS = {
    ServiceState.STOPPED: "已停止",
    ServiceState.STARTING: "启动中",
    ServiceState.RUNNING_NOT_READY: "运行但未就绪",
    ServiceState.READY: "已就绪",
    ServiceState.EXTERNAL: "外部实例",
    ServiceState.STOPPING: "停止中",
    ServiceState.FAILED: "失败",
}


class ServiceCard(QFrame):
    start_requested = Signal(object)
    stop_requested = Signal(object)

    def __init__(self, definition: ServiceDefinition, parent=None) -> None:
        super().__init__(parent)
        self.definition = definition
        self.service_id: ServiceId = definition.service_id
        self._busy = False
        self._observation: ServiceObservation | None = None
        self.setObjectName(f"serviceCard-{self.service_id.value}")
        self.setProperty("card", True)
        code = {ServiceId.POSTGRES: "01 / DATA ENGINE", ServiceId.BACKEND: "02 / API SERVICE",
                ServiceId.FRONTEND: "03 / ADMIN WEB"}[self.service_id]
        self.code_label = QLabel(code)
        self.code_label.setObjectName("serviceCode")

        self.title_label = QLabel(definition.display_name)
        self.title_label.setObjectName("serviceTitle")
        self.status_label = QLabel("未检查")
        self.status_label.setObjectName("serviceStatus")
        title_row = QHBoxLayout()
        title_row.addWidget(self.title_label)
        title_row.addStretch(1)
        title_row.addWidget(self.status_label)

        details = QHBoxLayout()
        details.addWidget(QLabel(f"{definition.host}:{definition.port}"))
        details.addStretch(1)
        pid_caption = QLabel("PID")
        pid_caption.setProperty("tone", "muted")
        details.addWidget(pid_caption)
        self.pid_value = QLabel("—")
        details.addWidget(self.pid_value)
        self.health_value = QLabel("尚未检查")
        self.health_value.setProperty("tone", "muted")
        self.health_value.setWordWrap(True)
        self.telemetry = TelemetryStrip()

        self.error_label = QLabel("")
        self.error_label.setObjectName("serviceError")
        self.error_label.setWordWrap(True)
        self.error_label.hide()

        self.power_control = PowerControl()
        self.start_button = self.power_control.start_button
        self.start_button.setObjectName(f"start-{self.service_id.value}")
        self.stop_button = self.power_control.stop_button
        self.stop_button.setObjectName(f"stop-{self.service_id.value}")
        self.start_button.clicked.connect(lambda: self.start_requested.emit(self.service_id))
        self.stop_button.clicked.connect(lambda: self.stop_requested.emit(self.service_id))
        buttons = QHBoxLayout()
        self.ownership_label = QLabel("未检查")
        self.ownership_label.setProperty("tone", "muted")
        buttons.addWidget(self.ownership_label)
        buttons.addStretch(1)
        buttons.addWidget(self.power_control)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 9, 14, 9)
        layout.setSpacing(6)
        layout.addWidget(self.code_label)
        layout.addLayout(title_row)
        layout.addLayout(details)
        layout.addWidget(self.health_value)
        layout.addWidget(self.telemetry)
        layout.addWidget(self.error_label)
        layout.addLayout(buttons)
        self._update_buttons()

    def set_observation(self, observation: ServiceObservation) -> None:
        if observation.service_id is not self.service_id:
            raise ValueError("服务状态与卡片不匹配")
        self._observation = observation
        self.status_label.setText(_STATE_LABELS[observation.state])
        self.status_label.setProperty("state", observation.state.value)
        self.status_label.style().unpolish(self.status_label)
        self.status_label.style().polish(self.status_label)
        reliable_pid = observation.pid if observation.process_running and observation.pid is not None else None
        self.pid_value.setText(str(reliable_pid) if reliable_pid is not None else "—")
        self.health_value.setText(observation.summary)
        self.telemetry.set_values(observation.process_running, observation.port_open, observation.ready)
        self.ownership_label.setText("外部 · 只读保护" if observation.external else "本会话管理" if observation.owned else "未托管")
        self.error_label.setText(observation.last_error or "")
        self.error_label.setVisible(bool(observation.last_error))
        self._update_buttons()

    def set_busy(self, busy: bool) -> None:
        self._busy = busy
        self._update_buttons()

    def _update_buttons(self) -> None:
        self.power_control.set_actions(self.actions)

    @property
    def actions(self) -> ServiceActions:
        return service_actions(self._observation, busy=self._busy)

