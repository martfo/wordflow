"""SQLite store with a small append-only migration runner. No server.

The schema is pinned in DESIGN.md. Migrations are append-only; the runner
applies whatever is newer than the database's user_version. Copied from
Polenta's proven pattern.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

MIGRATIONS: list[str] = [
    # 1: the Phase 1 schema — dictations, the dictionary link table, and the
    # settings overrides table.
    """
    CREATE TABLE dictations(
        id INTEGER PRIMARY KEY,
        created_at TEXT NOT NULL,
        target_app TEXT,
        target_bundle_id TEXT,
        model TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        cleaned_text TEXT NOT NULL,
        char_count INTEGER NOT NULL DEFAULT 0,
        inserted INTEGER NOT NULL DEFAULT 0,
        audio_path TEXT
    );
    CREATE TABLE dictionary_entries(
        id INTEGER PRIMARY KEY,
        canonical TEXT NOT NULL,
        hints TEXT NOT NULL DEFAULT '[]',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        source_dictation_id INTEGER REFERENCES dictations(id) ON DELETE SET NULL
    );
    CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    """,
    # 2: accuracy-harness runs, stored so word-error-rate runs stay comparable
    # over time (AC-9.5).
    """
    CREATE TABLE accuracy_runs(
        id INTEGER PRIMARY KEY,
        created_at TEXT NOT NULL,
        model TEXT NOT NULL,
        wer REAL NOT NULL,
        reference_words INTEGER NOT NULL,
        transcript TEXT NOT NULL
    );
    """,
]


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def open_db(path: Path | str) -> sqlite3.Connection:
    # The API thread and the worker thread share this connection; WAL plus
    # SQLite's own serialisation make that safe for our short writes.
    conn = sqlite3.connect(str(path), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    migrate(conn)
    return conn


def migrate(conn: sqlite3.Connection) -> None:
    current = conn.execute("PRAGMA user_version").fetchone()[0]
    for version, sql in enumerate(MIGRATIONS, start=1):
        if version > current:
            conn.executescript(sql)
            conn.execute(f"PRAGMA user_version = {version}")
    conn.commit()


def schema_version(conn: sqlite3.Connection) -> int:
    return conn.execute("PRAGMA user_version").fetchone()[0]
