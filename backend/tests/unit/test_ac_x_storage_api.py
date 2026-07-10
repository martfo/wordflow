"""The SQLite migration runner and the FastAPI surface end to end (with a fake
engine). Exercises the backend half of the core loop: transcribe -> cleanup ->
history, plus the dictionary, cleanup, and model endpoints."""

import numpy as np

from wordflow.storage.db import MIGRATIONS, open_db, schema_version
from tests.conftest import make_wav_base64


def test_migration_runner(tmp_path):
    conn = open_db(tmp_path / "index.sqlite")
    assert schema_version(conn) == len(MIGRATIONS)
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    assert {"dictations", "dictionary_entries", "settings"} <= tables
    # Re-opening applies nothing new and does not error.
    conn.close()
    conn2 = open_db(tmp_path / "index.sqlite")
    assert schema_version(conn2) == len(MIGRATIONS)
    conn2.close()


def test_health(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["active_model"] == "parakeet"


def test_ac_1_1_b_transcribe_end_to_end_writes_history(client, speech):
    response = client.post("/transcribe", json={"audio_base64": speech, "target_app": "Notes"})
    body = response.json()
    assert body["nothing_heard"] is False
    assert body["text"] == "Hello world"  # fake transcript, punctuation-capitalised
    assert body["raw"] == "hello world"
    # AC-4.6: it landed in history.
    history = client.get("/history").json()
    assert len(history) == 1
    assert history[0]["target_app"] == "Notes"
    assert history[0]["cleaned_text"] == "Hello world"


def test_ac_2_6_a_silence_through_api_writes_nothing(client, wav):
    silent = make_wav_base64(np.zeros(16_000, dtype=np.float32))
    body = client.post("/transcribe", json={"audio_base64": silent}).json()
    assert body["nothing_heard"] is True
    assert body["dictation_id"] is None
    assert client.get("/history").json() == []


def test_dictionary_endpoints(client):
    client.post("/dictionary", json={"canonical": "mieliepap", "hints": ["melly pap"]})
    entries = client.get("/dictionary").json()
    assert entries[0]["canonical"] == "mieliepap"
    assert entries[0]["hints"] == ["melly pap"]
    client.delete("/dictionary/mieliepap")
    assert client.get("/dictionary").json() == []


def test_cleanup_toggle_endpoint_persists(client):
    client.put("/cleanup", json={"toggles": {"british": False}})
    assert client.get("/cleanup").json()["british"] is False


def test_ac_5_2_correct_offers_dictionary_entry(client, speech):
    did = client.post("/transcribe", json={"audio_base64": speech}).json()["dictation_id"]
    # "hello world" -> "hello mieliepap": a single word change offers an entry.
    body = client.post(f"/history/{did}/correct", json={"text": "Hello mieliepap"}).json()
    assert body["offer"] == {"heard": "world", "corrected": "mieliepap"}


def test_model_switch_validates(client):
    assert client.post("/model", json={"name": "whisper"}).status_code == 200
    assert client.post("/model", json={"name": "nonsense"}).status_code == 422
