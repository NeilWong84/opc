from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="OPC_", env_file=".env", extra="ignore")
    database_url: str = "postgresql://opc_app@127.0.0.1:5432/opc_dev"
    hall_audience: Literal["internal", "authenticated", "disabled"] = "internal"
    assignment_mode: Literal["disabled", "record_confirmed"] = "disabled"
    storage_root: Path = Path(".local/files")
    preview_root: Path = Path(".local/previews")
    office_binary: str = ""
    preview_timeout_seconds: int = Field(default=60, ge=1, le=120)
    docs_enabled: bool = True
    cors_origins: list[str] = ["http://localhost:5180", "http://127.0.0.1:5180"]
    session_hours: int = Field(default=12, ge=1, le=168)
    upload_limit_bytes: int = Field(default=25 * 1024 * 1024, ge=1, le=100 * 1024 * 1024)
