"""The personal dictionary: a plain, human-editable file that is the source of
truth for entries, plus a small SQLite table that records which dictation
taught an entry, so the two cross-link (AC-5.5, AC-8.3-c).

File format, one entry per line:

    canonical
    canonical = sounds-like one, sounds-like two

Lines starting with # are comments. External edits are picked up on the next
read (AC-5.3), because entries are read from the file each dictation.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

from wordflow.dictionary.apply import DictEntry
from wordflow.storage.db import utcnow


def parse_dictionary_text(text: str) -> list[DictEntry]:
    entries: list[DictEntry] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            canonical, _, rest = line.partition("=")
            hints = [h.strip() for h in rest.split(",") if h.strip()]
        else:
            canonical, hints = line, []
        canonical = canonical.strip()
        if canonical:
            entries.append(DictEntry(canonical=canonical, hints=hints))
    return entries


def read_entries(path: Path) -> list[DictEntry]:
    if not path.exists():
        return []
    return parse_dictionary_text(path.read_text())


def _format_entry(entry: DictEntry) -> str:
    if entry.hints:
        return f"{entry.canonical} = {', '.join(entry.hints)}"
    return entry.canonical


HEADER = (
    "# WordFlow personal dictionary. One entry per line.\n"
    "# A canonical spelling on its own, or  canonical = sounds-like, another\n"
    "# Lines starting with # are comments.\n"
)


def write_entries(path: Path, entries: list[DictEntry]) -> None:
    body = "\n".join(_format_entry(e) for e in entries)
    path.write_text(HEADER + (body + "\n" if body else ""))


def add_entry(path: Path, canonical: str, hints: list[str] | None = None) -> DictEntry:
    """Add or merge an entry (case-insensitive on the canonical), keeping the
    file the source of truth. Merging folds new hints into an existing entry."""
    entries = read_entries(path)
    hints = hints or []
    for existing in entries:
        if existing.canonical.lower() == canonical.lower():
            for hint in hints:
                if hint and hint.lower() not in {h.lower() for h in existing.hints}:
                    existing.hints.append(hint)
            write_entries(path, entries)
            return existing
    entry = DictEntry(canonical=canonical, hints=[h for h in hints if h])
    entries.append(entry)
    write_entries(path, entries)
    return entry


def remove_entry(path: Path, canonical: str) -> bool:
    entries = read_entries(path)
    kept = [e for e in entries if e.canonical.lower() != canonical.lower()]
    if len(kept) == len(entries):
        return False
    write_entries(path, kept)
    return True


# --- Link provenance in SQLite (which dictation taught an entry) ---

def record_link(conn: sqlite3.Connection, canonical: str, source_dictation_id: int | None,
                hints: list[str] | None = None) -> int:
    row = conn.execute(
        "SELECT id FROM dictionary_entries WHERE lower(canonical) = lower(?)", (canonical,)
    ).fetchone()
    if row is not None:
        if source_dictation_id is not None:
            conn.execute(
                "UPDATE dictionary_entries SET source_dictation_id = ? WHERE id = ?",
                (source_dictation_id, row["id"]),
            )
            conn.commit()
        return row["id"]
    cursor = conn.execute(
        "INSERT INTO dictionary_entries(canonical, hints, enabled, created_at, source_dictation_id) "
        "VALUES (?, ?, 1, ?, ?)",
        (canonical, json.dumps(hints or []), utcnow(), source_dictation_id),
    )
    conn.commit()
    return cursor.lastrowid


def entry_source_dictation(conn: sqlite3.Connection, canonical: str) -> int | None:
    row = conn.execute(
        "SELECT source_dictation_id FROM dictionary_entries WHERE lower(canonical) = lower(?)",
        (canonical,),
    ).fetchone()
    return row["source_dictation_id"] if row else None


def entries_taught_by(conn: sqlite3.Connection, dictation_id: int) -> list[str]:
    rows = conn.execute(
        "SELECT canonical FROM dictionary_entries WHERE source_dictation_id = ? ORDER BY id",
        (dictation_id,),
    ).fetchall()
    return [r["canonical"] for r in rows]


def forget_link(conn: sqlite3.Connection, canonical: str) -> None:
    conn.execute("DELETE FROM dictionary_entries WHERE lower(canonical) = lower(?)", (canonical,))
    conn.commit()
