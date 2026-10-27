from __future__ import annotations

from collections.abc import Callable

from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QSpinBox,
    QTableWidgetItem,
    QVBoxLayout,
)

from opc_service_monitor.dependencies import DependencyCheck, check_dependencies
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.supervisor import SupervisorTimeouts
from opc_service_monitor.ui.components import (
    ConsoleButton as QPushButton,
    ConsoleLineEdit as QLineEdit,
    ConsoleTable as QTableWidget,
)


DirectorySelector = Callable[[], str]
DependencyChecker = Callable[[ProjectLayout], tuple[DependencyCheck, ...]]


class SettingsDialog(QDialog):
    def __init__(
        self,
        layout: ProjectLayout,
        timeouts: SupervisorTimeouts,
        *,
        directory_selector: DirectorySelector | None = None,
        dependency_checker: DependencyChecker = check_dependencies,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._project_layout = layout
        self._initial_root = layout.root
        self._directory_selector = directory_selector or self._select_directory
        self._dependency_checker = dependency_checker
        self._dependency_results: tuple[DependencyCheck, ...] = ()
        self.setWindowTitle("监控器设置与依赖检查")
        self.resize(900, 570)

        root_row = QHBoxLayout()
        root_row.setSpacing(10)
        self.root_edit = QLineEdit(str(layout.root))
        self.root_edit.setReadOnly(True)
        self.browse_button = QPushButton("更改项目目录", icon="folder")
        self.browse_button.clicked.connect(self._browse)
        root_row.addWidget(self.root_edit, 1)
        root_row.addWidget(self.browse_button)

        self.error_label = QLabel("")
        self.error_label.setProperty("tone", "danger")
        self.error_label.setWordWrap(True)
        self.error_label.hide()
        self.restart_label = QLabel("项目目录变更将在重启监控器后生效；依赖检查已针对新目录刷新。")
        self.restart_label.setWordWrap(True)
        self.restart_label.setProperty("tone", "muted")
        self.restart_label.hide()

        timeout_form = QFormLayout()
        timeout_form.setSpacing(12)
        self.postgres_timeout = _timeout_spinbox(timeouts.postgres)
        self.backend_timeout = _timeout_spinbox(timeouts.backend)
        self.frontend_timeout = _timeout_spinbox(timeouts.frontend)
        timeout_form.addRow("PostgreSQL 启停超时（秒）", self.postgres_timeout)
        timeout_form.addRow("BackendService 启停超时（秒）", self.backend_timeout)
        timeout_form.addRow("FrontendAdmin 启停超时（秒）", self.frontend_timeout)

        self.dependency_table = QTableWidget(0, 4)
        self.dependency_table.setHorizontalHeaderLabels(("依赖", "状态", "路径", "说明"))
        self.dependency_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.dependency_table.setWordWrap(False)
        self.dependency_table.horizontalHeader().setStretchLastSection(True)
        self.dependency_table.verticalHeader().setDefaultSectionSize(36)
        self.dependency_table.verticalHeader().hide()
        for column, width in enumerate((155, 75, 285)):
            self.dependency_table.setColumnWidth(column, width)

        buttons = QDialogButtonBox()
        buttons.addButton(QPushButton("保存设置", icon="settings", variant="primary"), QDialogButtonBox.AcceptRole)
        buttons.addButton(QPushButton("取消"), QDialogButtonBox.RejectRole)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)

        outer = QVBoxLayout(self)
        outer.setContentsMargins(24, 22, 24, 22)
        outer.setSpacing(14)
        title = QLabel("环境与依赖")
        title.setObjectName("sectionTitle")
        outer.addWidget(title)
        outer.addWidget(QLabel("OPC 项目根目录"))
        outer.addLayout(root_row)
        outer.addWidget(self.error_label)
        outer.addWidget(self.restart_label)
        outer.addLayout(timeout_form)
        outer.addWidget(QLabel("只读依赖检查（不会自动安装或执行命令）"))
        outer.addWidget(self.dependency_table, 1)
        outer.addWidget(buttons)
        self._refresh_dependencies()

    @property
    def project_layout(self) -> ProjectLayout:
        return self._project_layout

    @property
    def dependency_results(self) -> tuple[DependencyCheck, ...]:
        return self._dependency_results

    @property
    def selected_timeouts(self) -> SupervisorTimeouts:
        return SupervisorTimeouts(
            postgres=float(self.postgres_timeout.value()),
            backend=float(self.backend_timeout.value()),
            frontend=float(self.frontend_timeout.value()),
        )

    def _select_directory(self) -> str:
        return QFileDialog.getExistingDirectory(self, "选择 OPC 项目根目录", str(self._project_layout.root))

    def _browse(self) -> None:
        selected = self._directory_selector()
        if not selected:
            return
        try:
            layout = ProjectLayout.validate(selected)
        except (OSError, ValueError) as exc:
            self.error_label.setText(str(exc))
            self.error_label.show()
            return
        self._project_layout = layout
        self.root_edit.setText(str(layout.root))
        self.error_label.hide()
        self.restart_label.setVisible(layout.root != self._initial_root)
        self._refresh_dependencies()

    def _refresh_dependencies(self) -> None:
        self._dependency_results = self._dependency_checker(self._project_layout)
        self.dependency_table.setRowCount(len(self._dependency_results))
        for row, result in enumerate(self._dependency_results):
            values = (result.name, "通过" if result.ok else "缺失", result.display_path, result.message)
            for column, value in enumerate(values):
                self.dependency_table.setItem(row, column, QTableWidgetItem(value))


def _timeout_spinbox(value: float) -> QSpinBox:
    spinbox = QSpinBox()
    spinbox.setRange(5, 120)
    spinbox.setValue(int(value))
    return spinbox
