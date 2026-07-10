"""Parakeet TDT 0.6B v2 via parakeet-mlx, the primary model. Imported lazily so
the fast gate never needs MLX; it runs only in the pipeline tier and the
installed app. The model repo and its pinned revision come from the caller."""

from __future__ import annotations

import numpy as np


class ParakeetEngine:
    name = "parakeet"

    def __init__(self, repo: str, revision: str | None = None):
        self.repo = repo
        self.revision = revision
        self._model = None

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def load(self) -> None:
        if self._model is not None:
            return
        from parakeet_mlx import from_pretrained

        # HF_HUB_OFFLINE is pinned by __main__, so this resolves from the local
        # cache; only the onboarding downloader ever reaches the network.
        self._model = from_pretrained(self.repo)

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        if self._model is None:
            self.load()
        import mlx.core as mx

        audio = mx.array(np.ascontiguousarray(samples, dtype=np.float32))
        result = self._model.transcribe(audio)
        return (getattr(result, "text", "") or "").strip()

    def unload(self) -> None:
        self._model = None
        try:
            import mlx.core as mx

            mx.clear_cache()
        except Exception:
            pass
