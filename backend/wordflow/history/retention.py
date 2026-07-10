"""Text retention: dictation entries older than the configured number of days
are removed by the retention job; the default is 90 days (AC-6.3). Audio is not
subject to this job because it is deleted immediately after transcription; only
kept-audio debug files ride along and are removed with their entry. The clock is
injected so tests can age entries."""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

SETTINGS_KEY = "text_retention_days"


def retention_days(conn: sqlite3.Connection, default: int) -> int:
    row = conn.execute("SELECT value FROM settings WHERE key = ?", (SETTINGS_KEY,)).fetchone()
    return int(row["value"]) if row is not None else default


def set_retention_days(conn: sqlite3.Connection, days: int) -> None:
    conn.execute(
        "INSERT INTO settings(key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (SETTINGS_KEY, str(days)),
    )
    conn.commit()


def purge_old_entries(
    conn: sqlite3.Connection, days: int, now: datetime | None = None
) -> list[int]:
    """Remove dictations older than the period, deleting any kept audio too.
    Returns the ids removed."""
    now = now or datetime.now(timezone.utc)
    cutoff = now - timedelta(days=days)
    removed: list[int] = []
    for row in conn.execute("SELECT id, created_at, audio_path FROM dictations").fetchall():
        created = datetime.fromisoformat(row["created_at"])
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        if created < cutoff:
            if row["audio_path"]:
                Path(row["audio_path"]).unlink(missing_ok=True)
            removed.append(row["id"])
    if removed:
        conn.executemany("DELETE FROM dictations WHERE id = ?", [(i,) for i in removed])
        conn.commit()
    return removed
