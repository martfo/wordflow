"""Builds a speech engine by name from the configured repo ids and the pinned
revisions written by the downloader. The real engines are constructed here so
the manager stays independent of MLX."""

from __future__ import annotations

import json
from pathlib import Path

from wordflow.asr.base import ASREngine
from wordflow.config import Config

LOCK_NAME = "models.lock.json"


def pinned_revisions(models_dir: Path) -> dict[str, str]:
    """The commit revisions the downloader resolved, or empty when a machine has
    not downloaded yet (the fast gate and switching by name still work)."""
    lock = models_dir / LOCK_NAME
    if not lock.exists():
        return {}
    try:
        return json.loads(lock.read_text())
    except json.JSONDecodeError:
        return {}


def build_engine(name: str, config: Config, revisions: dict[str, str] | None = None) -> ASREngine:
    revisions = revisions or {}
    repos = {"parakeet": config.models.parakeet, "whisper": config.models.whisper}
    if name not in repos:
        raise ValueError(f"unknown model {name!r}")
    revision = revisions.get(name)
    if name == "parakeet":
        from wordflow.asr.parakeet import ParakeetEngine

        return ParakeetEngine(repos["parakeet"], revision)
    from wordflow.asr.whisper import WhisperEngine

    return WhisperEngine(repos["whisper"], revision)
