"""Logging that a person can read. Ported from Polenta.

A rotating file at data/logs/backend.log: ISO timestamp, level, and a plain
message. A companion backend.jsonl holds the same records as one JSON object
per line for later searching. Logs carry identifiers and error detail only;
never transcribed text.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path

LOG_NAME = "backend.log"
JSON_LOG_NAME = "backend.jsonl"


def _timestamp(record: logging.LogRecord) -> str:
    return datetime.fromtimestamp(record.created).astimezone().isoformat(timespec="seconds")


class HumanFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        dictation = getattr(record, "dictation_id", None)
        context = f" [dictation {dictation}]" if dictation else ""
        return f"{_timestamp(record)} {record.levelname}{context} {record.getMessage()}"


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": _timestamp(record),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        dictation = getattr(record, "dictation_id", None)
        if dictation:
            entry["dictation_id"] = dictation
        return json.dumps(entry)


def configure_logging(
    logs_dir: Path, level: str = "info",
    max_bytes: int = 1_000_000, backup_count: int = 3,
) -> logging.Logger:
    """Set up the wordflow logger tree to write both files. Safe to call again
    (say, after a config change): handlers are replaced, not stacked."""
    logs_dir.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("wordflow")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    for handler in list(logger.handlers):
        logger.removeHandler(handler)
        handler.close()

    human = RotatingFileHandler(
        logs_dir / LOG_NAME, maxBytes=max_bytes, backupCount=backup_count
    )
    human.setFormatter(HumanFormatter())
    machine = RotatingFileHandler(
        logs_dir / JSON_LOG_NAME, maxBytes=max_bytes, backupCount=backup_count
    )
    machine.setFormatter(JsonFormatter())
    logger.addHandler(human)
    logger.addHandler(machine)
    return logger
