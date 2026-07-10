"""The speech-to-text engine interface. Two real implementations (Parakeet and
Whisper via MLX) and a fake for the fast gate all satisfy it."""

from __future__ import annotations

from typing import Protocol

import numpy as np


class ASREngine(Protocol):
    name: str

    @property
    def is_loaded(self) -> bool: ...

    def load(self) -> None:
        """Construct and warm the model so the first transcription carries no
        lazy-load penalty (AC-2.1)."""
        ...

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        """Transcribe float32 mono samples. The manager only ever passes
        16 kHz, so engines need no resampling."""
        ...

    def unload(self) -> None:
        """Release the model so backend memory drops (AC-2.4)."""
        ...
