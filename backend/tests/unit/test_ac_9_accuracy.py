"""Section 9: the bake-off and the accuracy harness."""

import numpy as np
from pytest import approx

from wordflow.accuracy import harness
from wordflow.accuracy.wer import word_error_rate
from wordflow.asr.fake import FakeEngine
from wordflow.asr.manager import ModelManager
from tests.conftest import make_wav_base64


def test_wer_perfect_and_errors():
    assert word_error_rate("the quick brown fox", "the quick brown fox").wer == 0.0
    # One substitution out of four words.
    r = word_error_rate("the quick brown fox", "the quick brown dog")
    assert r.wer == 0.25 and r.substitutions == 1
    # Case and punctuation are ignored.
    assert word_error_rate("Hello, world!", "hello world").wer == 0.0
    # A deletion and an insertion.
    assert word_error_rate("one two three", "one three").wer == approx(1 / 3)
    assert word_error_rate("one two", "one two three").wer == 0.5


def _two_model_manager(parakeet_text, whisper_text):
    engines = {
        "parakeet": FakeEngine(name="parakeet", transcript=parakeet_text),
        "whisper": FakeEngine(name="whisper", transcript=whisper_text),
    }
    return ModelManager(lambda name: engines[name], active="parakeet"), engines


def test_ac_9_3_a_bakeoff_transcribes_both_models():
    manager, engines = _two_model_manager("hello from parakeet", "hello from whisper")
    manager.warm_up()
    samples = np.zeros(16_000, dtype=np.float32)
    results = harness.run_bakeoff(manager, samples, 16_000)
    by_model = {r.model: r.text for r in results}
    assert by_model == {"parakeet": "hello from parakeet", "whisper": "hello from whisper"}
    # The non-active model was loaded transiently and unloaded again, so it is
    # not left resident.
    assert engines["whisper"].unload_count == 1
    assert manager.active_model == "parakeet"


def test_ac_9_5_a_accuracy_scores_and_stores_runs(conn):
    reference = "the quarterly review is on thursday"
    manager, _ = _two_model_manager(
        "the quarterly review is on thursday",   # perfect
        "the quarterly review is on friday")     # one word wrong
    manager.warm_up()
    samples = np.zeros(16_000, dtype=np.float32)
    scores = harness.run_accuracy(conn, manager, reference, samples, 16_000)
    by_model = {s.model: s.wer for s in scores}
    assert by_model["parakeet"] == 0.0
    assert by_model["whisper"] == approx(1 / 6)
    # Runs are stored so they stay comparable over time.
    runs = harness.list_runs(conn)
    assert len(runs) == 2
    assert {r["model"] for r in runs} == {"parakeet", "whisper"}


def test_bakeoff_and_accuracy_endpoints(client):
    # The default fake manager returns "hello world" for the active model and
    # loads a fresh fake for the other (also "hello world" via the fixture
    # factory), which is enough to exercise the endpoints end to end.
    audio = make_wav_base64(np.zeros(16_000, dtype=np.float32))
    body = client.post("/bakeoff", json={"audio_base64": audio}).json()
    assert {r["model"] for r in body["results"]} == {"parakeet", "whisper"}

    acc = client.post("/accuracy", json={"audio_base64": audio, "reference_text": "hello world"}).json()
    assert any(s["model"] == "parakeet" for s in acc["scores"])
    assert client.get("/accuracy").json()  # a run was stored
