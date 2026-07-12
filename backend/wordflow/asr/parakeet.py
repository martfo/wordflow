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
        from parakeet_mlx.audio import get_logmel

        # parakeet-mlx's own transcribe() loads audio by shelling out to ffmpeg,
        # which the PRD forbids (AC-12.2). We already have decoded 16 kHz mono
        # PCM, so we feed the model's front end directly: the same get_logmel ->
        # generate path transcribe() uses, minus the file load. get_logmel's
        # byte-view trick needs float32 input.
        from wordflow.asr.audio import normalise_peak

        target_rate = self._model.preprocessor_config.sample_rate
        audio = np.ascontiguousarray(samples, dtype=np.float32)
        if sample_rate != target_rate and audio.size:
            positions = np.linspace(0, len(audio) - 1, int(round(len(audio) * target_rate / sample_rate)))
            audio = np.interp(positions, np.arange(len(audio)), audio).astype(np.float32)
        if audio.size == 0:
            return ""
        audio = normalise_peak(audio)
        mel = get_logmel(mx.array(audio), self._model.preprocessor_config)
        result = self._model.generate(mel)[0]
        return (getattr(result, "text", "") or "").strip()

    def unload(self) -> None:
        self._model = None
        try:
            import mlx.core as mx

            mx.clear_cache()
        except Exception:
            pass
