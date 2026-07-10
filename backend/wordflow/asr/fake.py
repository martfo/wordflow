"""A fake engine for the fast gate: it loads and unloads instantly, records how
many times each happened, and returns a canned transcript (optionally keyed by a
per-utterance marker so ordering tests can tell dictations apart). The real MLX
models run only in the pipeline tier."""

from __future__ import annotations

import numpy as np


class FakeEngine:
    def __init__(self, name: str = "fake", transcript: str = "hello world", delay: float = 0.0):
        self.name = name
        self.transcript = transcript
        self.delay = delay
        self._loaded = False
        self.load_count = 0
        self.unload_count = 0
        self.transcribe_count = 0

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    def load(self) -> None:
        self.load_count += 1
        self._loaded = True

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        if not self._loaded:
            raise RuntimeError("transcribe called before load")
        self.transcribe_count += 1
        if self.delay:
            import time

            time.sleep(self.delay)
        return self.transcript

    def unload(self) -> None:
        self.unload_count += 1
        self._loaded = False
