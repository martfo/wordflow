"""History: every completed dictation, with its raw and cleaned text, stored in
SQLite. Cancelled and silently-discarded dictations are never written here
(AC-6.1-b); the caller only records completed ones. Audio is not kept unless the
debug keep-audio toggle is on, in which case its path is stored and removed with
the entry (AC-6.4)."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from wordflow.storage.db import utcnow


def create_dictation(
    conn: sqlite3.Connection, *, model: str, raw_text: str, cleaned_text: str,
    target_app: str | None = None, target_bundle_id: str | None = None,
    inserted: bool = False, audio_path: str | None = None, created_at: str | None = None,
) -> int:
    cursor = conn.execute(
        "INSERT INTO dictations(created_at, target_app, target_bundle_id, model, "
        "raw_text, cleaned_text, char_count, inserted, audio_path) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (created_at or utcnow(), target_app, target_bundle_id, model,
         raw_text, cleaned_text, len(cleaned_text), 1 if inserted else 0, audio_path),
    )
    conn.commit()
    return cursor.lastrowid


def get_dictation(conn: sqlite3.Connection, dictation_id: int) -> dict:
    row = conn.execute("SELECT * FROM dictations WHERE id = ?", (dictation_id,)).fetchone()
    if row is None:
        raise KeyError(dictation_id)
    return dict(row)


def list_dictations(conn: sqlite3.Connection, query: str | None = None, limit: int = 200) -> list[dict]:
    if query:
        like = f"%{query}%"
        rows = conn.execute(
            "SELECT * FROM dictations WHERE cleaned_text LIKE ? OR raw_text LIKE ? "
            "ORDER BY id DESC LIMIT ?",
            (like, like, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM dictations ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [dict(r) for r in rows]


def correct_dictation(conn: sqlite3.Connection, dictation_id: int, new_text: str) -> dict:
    row = get_dictation(conn, dictation_id)  # KeyError if absent
    conn.execute(
        "UPDATE dictations SET cleaned_text = ?, char_count = ? WHERE id = ?",
        (new_text, len(new_text), dictation_id),
    )
    conn.commit()
    return {**row, "cleaned_text": new_text, "char_count": len(new_text)}


def delete_dictation(conn: sqlite3.Connection, dictation_id: int) -> None:
    row = conn.execute(
        "SELECT audio_path FROM dictations WHERE id = ?", (dictation_id,)
    ).fetchone()
    if row and row["audio_path"]:
        Path(row["audio_path"]).unlink(missing_ok=True)
    conn.execute("DELETE FROM dictations WHERE id = ?", (dictation_id,))
    conn.commit()


def clear_all(conn: sqlite3.Connection) -> int:
    rows = conn.execute("SELECT audio_path FROM dictations WHERE audio_path IS NOT NULL").fetchall()
    for row in rows:
        Path(row["audio_path"]).unlink(missing_ok=True)
    count = conn.execute("SELECT COUNT(*) FROM dictations").fetchone()[0]
    conn.execute("DELETE FROM dictations")
    conn.commit()
    return count
