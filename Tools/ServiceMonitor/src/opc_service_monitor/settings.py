from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from opc_service_monitor.supervisor import SupervisorTimeouts


@dataclass(frozen=True, slots=True)
class MonitorSettings:
    project_root: Path | None = None
    timeouts: SupervisorTimeouts = field(default_factory=SupervisorTimeouts)
    theme: str = "dark"


class SettingsStore:
    """Persist the small allow-listed, non-sensitive monitor configuration."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path).expanduser().resolve()

    def load(self) -> MonitorSettings:
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (FileNotFoundError, OSError, ValueError):
            return MonitorSettings()
        if not isinstance(payload, dict):
            return MonitorSettings()

        raw_root = payload.get("project_root")
        project_root = Path(raw_root).expanduser().resolve() if isinstance(raw_root, str) and raw_root else None
        raw_theme = payload.get("theme")
        theme = raw_theme if isinstance(raw_theme, str) and raw_theme in ("dark", "light") else "dark"
        raw_timeouts = payload.get("timeouts")
        if not isinstance(raw_timeouts, dict):
            return MonitorSettings(project_root=project_root, theme=theme)
        values = (
            raw_timeouts.get("postgresql"),
            raw_timeouts.get("backend"),
            raw_timeouts.get("frontend"),
        )
        if any(isinstance(value, bool) or not isinstance(value, (int, float)) for value in values):
            return MonitorSettings(theme=theme)
        try:
            timeouts = SupervisorTimeouts(
                postgres=float(values[0]),
                backend=float(values[1]),
                frontend=float(values[2]),
            )
        except (TypeError, ValueError):
            return MonitorSettings(theme=theme)
        return MonitorSettings(project_root=project_root, timeouts=timeouts, theme=theme)

    def save(self, settings: MonitorSettings) -> None:
        if not isinstance(settings.theme, str) or settings.theme not in ("dark", "light"):
            raise ValueError("theme must be 'dark' or 'light'")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        project_root = settings.project_root.expanduser().resolve() if settings.project_root is not None else None
        payload = {
            "project_root": str(project_root) if project_root is not None else None,
            "theme": settings.theme,
            "timeouts": {
                "postgresql": _json_number(settings.timeouts.postgres),
                "backend": _json_number(settings.timeouts.backend),
                "frontend": _json_number(settings.timeouts.frontend),
            },
        }
        temporary = self.path.with_name(f".{self.path.name}.tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, self.path)


def _json_number(value: float) -> int | float:
    return int(value) if float(value).is_integer() else float(value)
