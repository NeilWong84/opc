from __future__ import annotations

import shutil
from pathlib import Path

from PySide6.QtCore import Qt

from opc_service_monitor.dependencies import DependencyCheck
from opc_service_monitor.paths import ProjectLayout
from opc_service_monitor.supervisor import SupervisorTimeouts
from opc_service_monitor.ui.settings_dialog import SettingsDialog


def test_settings_dialog_changes_valid_root_rechecks_dependencies_and_bounds_timeouts(
    opc_root: Path, tmp_path: Path, qtbot
) -> None:
    second_root = tmp_path / "OPC moved"
    shutil.copytree(opc_root, second_root)
    checked: list[Path] = []

    def checker(layout: ProjectLayout):
        checked.append(layout.root)
        return (
            DependencyCheck("backend_python", "Backend Python", True, str(layout.backend_python), "依赖文件存在。"),
        )

    dialog = SettingsDialog(
        ProjectLayout.validate(opc_root),
        SupervisorTimeouts(),
        directory_selector=lambda: str(second_root),
        dependency_checker=checker,
    )
    qtbot.addWidget(dialog)

    qtbot.mouseClick(dialog.browse_button, Qt.LeftButton)
    dialog.postgres_timeout.setValue(45)
    dialog.backend_timeout.setValue(50)
    dialog.frontend_timeout.setValue(55)

    assert dialog.project_layout.root == second_root.resolve()
    assert checked == [opc_root.resolve(), second_root.resolve()]
    assert dialog.dependency_table.rowCount() == 1
    assert dialog.selected_timeouts == SupervisorTimeouts(postgres=45, backend=50, frontend=55)
    assert dialog.restart_label.isVisible() is False or "重启" in dialog.restart_label.text()
