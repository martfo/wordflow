"""Pipeline tier: the real MLX models against the user's recorded fixtures, on
the reference machine (Mac Studio M3 Ultra). Skipped unless the models extra is
installed and the fixtures exist. Run with: make pipeline."""

import time
from pathlib import Path

import pytest

pytestmark = pytest.mark.pipeline

FIXTURES = Path(__file__).resolve().parents[2].parent / "fixtures" / "audio"


def _require(name: str) -> Path:
    path = FIXTURES / name
    if not path.exists():
        pytest.skip(f"missing voice fixture {name}; record it with make_fixtures")
    return path


def _load_engine():
    try:
        from wordflow.asr.parakeet import ParakeetEngine
    except ModuleNotFoundError:
        pytest.skip("models extra not installed (uv sync --extra models)")
    engine = ParakeetEngine("mlx-community/parakeet-tdt-0.6b-v2")
    engine.load()
    return engine


def _transcribe_seconds(engine, wav_path: Path) -> float:
    import wave

    import numpy as np

    with wave.open(str(wav_path), "rb") as w:
        rate = w.getframerate()
        samples = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
    start = time.monotonic()
    engine.transcribe(samples, rate)
    return time.monotonic() - start


@pytest.mark.parametrize("name,budget", [
    ("utt_10s.wav", 1.0),
    ("utt_30s.wav", 2.0),
    ("utt_60s.wav", 2.0),
])
def test_ac_2_2_latency_budget(name, budget):
    wav_path = _require(name)
    engine = _load_engine()
    engine.transcribe(__import__("numpy").zeros(16000, dtype="float32"), 16000)  # warm
    elapsed = _transcribe_seconds(engine, wav_path)
    assert elapsed <= budget, f"{name}: {elapsed:.2f}s over the {budget}s budget"
