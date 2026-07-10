from __future__ import annotations

import base64
import io
import wave
from pathlib import Path

import numpy as np
import pytest

from wordflow.api.app import AppState, create_app
from wordflow.asr.fake import FakeEngine
from wordflow.asr.manager import ModelManager
from wordflow.cleanup.pipeline import default_pipeline
from wordflow.config import default_config
from wordflow.storage.db import open_db
from wordflow.storage.paths import DataFolder

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "fixtures"


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return FIXTURES


@pytest.fixture
def data(tmp_path: Path) -> DataFolder:
    return DataFolder(tmp_path / "data").ensure()


@pytest.fixture
def conn(data: DataFolder):
    connection = open_db(data.db_path)
    yield connection
    connection.close()


@pytest.fixture
def config(data: DataFolder):
    return default_config(data.root)


@pytest.fixture
def fake_engine() -> FakeEngine:
    return FakeEngine(name="parakeet", transcript="hello world")


@pytest.fixture
def manager(fake_engine: FakeEngine) -> ModelManager:
    return ModelManager(factory=lambda name: fake_engine, active="parakeet")


@pytest.fixture
def state(conn, data, config, manager) -> AppState:
    return AppState(conn=conn, data=data, config=config, manager=manager, pipeline=default_pipeline())


@pytest.fixture
def client(state: AppState):
    from fastapi.testclient import TestClient

    return TestClient(create_app(state))


def make_wav_base64(samples: np.ndarray, rate: int = 16_000) -> str:
    """Encode float samples in [-1, 1] as the 16-bit mono WAV the app sends."""
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    return base64.b64encode(buffer.getvalue()).decode("ascii")


@pytest.fixture
def wav():
    """A callable that builds base64 WAV audio, for the transcribe path."""
    return make_wav_base64


@pytest.fixture
def speech(wav):
    """A one-second buffer loud enough to pass the silence gate."""
    rng = np.random.default_rng(0)
    return wav(rng.uniform(-0.3, 0.3, 16_000).astype(np.float32))
