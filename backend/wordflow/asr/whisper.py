"""Whisper large-v3-turbo via mlx-whisper, the alternative model selectable in
Settings for A/B comparison. Imported lazily; runs only in the pipeline tier and
the installed app."""

from __future__ import annotations

import numpy as np


class WhisperEngine:
    name = "whisper"

    def __init__(self, repo: str, revision: str | None = None):
        self.repo = repo
        self.revision = revision
        self._loaded = False

    @property
    def is_loaded(self) -> bool:
        return self._loaded

    def load(self) -> None:
        # mlx-whisper loads the weights on the first transcribe and caches them
        # per repo. Touch the module here so a missing install fails at load,
        # and prime the cache with a short silent buffer so the first real
        # dictation is inference only (AC-2.1).
        import mlx_whisper  # noqa: F401

        self._transcribe = mlx_whisper.transcribe
        self._transcribe(np.zeros(16_000, dtype=np.float32), path_or_hf_repo=self.repo)
        self._loaded = True

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        if not self._loaded:
            self.load()
        result = self._transcribe(
            np.ascontiguousarray(samples, dtype=np.float32),
            path_or_hf_repo=self.repo, language="en",
        )
        return (result.get("text", "") or "").strip()

    def unload(self) -> None:
        self._loaded = False
        try:
            import mlx.core as mx

            mx.clear_cache()
        except Exception:
            pass
