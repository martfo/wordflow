"""Runtime settings the app tunes without rewriting config.json. Values here
override config.json for retention, keep-audio, the active model, idle unload,
and the per-stage cleanup toggles (Polenta's settings-override pattern)."""

from __future__ import annotations

import json
import sqlite3
from typing import Any


def get(conn: sqlite3.Connection, key: str, default: Any = None) -> Any:
    row = conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
    if row is None:
        return default
    try:
        return json.loads(row["value"])
    except (json.JSONDecodeError, TypeError):
        return row["value"]


def put(conn: sqlite3.Connection, key: str, value: Any) -> None:
    conn.execute(
        "INSERT INTO settings(key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, json.dumps(value)),
    )
    conn.commit()
