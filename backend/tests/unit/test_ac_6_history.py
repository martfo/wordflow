"""Section 6: history storage, search, retention, and audio deletion."""

from datetime import datetime, timedelta, timezone

from wordflow.history import retention
from wordflow.history import store as history
from wordflow.storage.db import utcnow


def test_ac_6_1_a_records_all_fields(conn):
    did = history.create_dictation(
        conn, model="parakeet", raw_text="raw text", cleaned_text="clean text",
        target_app="Notes", target_bundle_id="com.apple.Notes", inserted=True)
    row = history.get_dictation(conn, did)
    assert row["model"] == "parakeet"
    assert row["target_app"] == "Notes"
    assert row["inserted"] == 1
    assert row["created_at"]


def test_ac_6_1_c_keeps_raw_and_cleaned(conn):
    did = history.create_dictation(
        conn, model="parakeet", raw_text="the color center", cleaned_text="The colour centre")
    row = history.get_dictation(conn, did)
    assert row["raw_text"] == "the color center"
    assert row["cleaned_text"] == "The colour centre"


def test_ac_6_2_a_search(conn):
    history.create_dictation(conn, model="parakeet", raw_text="a", cleaned_text="the quarterly review")
    history.create_dictation(conn, model="parakeet", raw_text="b", cleaned_text="lunch plans")
    hits = history.list_dictations(conn, query="quarterly")
    assert len(hits) == 1
    assert "quarterly" in hits[0]["cleaned_text"]


def test_ac_6_3_a_retention_default_90_days(conn):
    old = (datetime.now(timezone.utc) - timedelta(days=100)).isoformat(timespec="seconds")
    recent = utcnow()
    history.create_dictation(conn, model="parakeet", raw_text="x", cleaned_text="old", created_at=old)
    history.create_dictation(conn, model="parakeet", raw_text="y", cleaned_text="new", created_at=recent)
    removed = retention.purge_old_entries(conn, days=90)
    assert len(removed) == 1
    remaining = [r["cleaned_text"] for r in history.list_dictations(conn)]
    assert remaining == ["new"]


def test_ac_6_4_a_no_audio_kept_by_default(conn, data):
    did = history.create_dictation(conn, model="parakeet", raw_text="x", cleaned_text="y")
    assert history.get_dictation(conn, did)["audio_path"] is None
    # The data folder has no audio files after a normal dictation.
    assert not any(data.audio_dir.glob("*.wav")) if data.audio_dir.exists() else True


def test_ac_6_4_b_kept_audio_removed_with_entry(conn, data, tmp_path):
    audio = tmp_path / "clip.wav"
    audio.write_bytes(b"RIFFfake")
    did = history.create_dictation(
        conn, model="parakeet", raw_text="x", cleaned_text="y", audio_path=str(audio))
    assert audio.exists()
    history.delete_dictation(conn, did)
    assert not audio.exists()


def test_ac_6_5_a_delete_and_clear(conn):
    a = history.create_dictation(conn, model="parakeet", raw_text="1", cleaned_text="one")
    history.create_dictation(conn, model="parakeet", raw_text="2", cleaned_text="two")
    history.delete_dictation(conn, a)
    assert len(history.list_dictations(conn)) == 1
    cleared = history.clear_all(conn)
    assert cleared == 1
    assert history.list_dictations(conn) == []
