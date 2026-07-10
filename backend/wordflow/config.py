"""config.json schema and load/save.

The backend reads its config from the path the Swift app hands it on the
command line. Values that the app tunes at runtime (retention, keep-audio, the
active model, idle unload, and the cleanup toggles) live in the settings table
and override what is here, mirroring Polenta.
"""

from __future__ import annotations

import json
from pathlib import Path

from pydantic import BaseModel, Field


class ModelIds(BaseModel):
    parakeet: str = "mlx-community/parakeet-tdt-0.6b-v2"
    whisper: str = "mlx-community/whisper-large-v3-turbo"


class CleanupToggles(BaseModel):
    punctuation: bool = True
    filler: bool = True
    dictionary: bool = True
    british: bool = True
    emdash: bool = True


class Config(BaseModel):
    data_path: str
    backend_port: int = 8770
    active_model: str = "parakeet"
    models: ModelIds = Field(default_factory=ModelIds)
    idle_unload_minutes: int = 0
    text_retention_days: int = 90
    keep_audio: bool = False
    cleanup: CleanupToggles = Field(default_factory=CleanupToggles)
    log_level: str = "info"


def default_config(data_path: Path | str) -> Config:
    return Config(data_path=str(data_path))


def load_config(path: Path) -> Config:
    return Config.model_validate(json.loads(path.read_text()))


def save_config(config: Config, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config.model_dump(), indent=2) + "\n")
