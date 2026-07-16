"""Parakeet TDT 0.6B v2 via parakeet-mlx, the primary model. Imported lazily so
the fast gate never needs MLX; it runs only in the pipeline tier and the
installed app. The model repo and its pinned revision come from the caller."""

from __future__ import annotations

import numpy as np

# Parakeet transcribes multi-minute clips whole without trouble (tested clean to
# ~6 minutes), and chunking costs a little accuracy at the window boundaries, so
# it is only a safety valve for extreme lengths: audio longer than the threshold
# is split at quiet points (to avoid cutting a word) and the pieces stitched.
# Normal dictation always runs whole.
CHUNK_THRESHOLD_SECONDS = 300.0
CHUNK_TARGET_SECONDS = 60.0
CHUNK_SEARCH_SECONDS = 4.0
_ENERGY_WINDOW_SECONDS = 0.1


def _chunk_spans(audio: np.ndarray, rate: int) -> list[tuple[int, int]]:
    """Split indices for long audio, each boundary placed at the quietest point
    near the target length so words are not cut mid-syllable."""
    n = len(audio)
    target = int(CHUNK_TARGET_SECONDS * rate)
    search = int(CHUNK_SEARCH_SECONDS * rate)
    win = max(1, int(_ENERGY_WINDOW_SECONDS * rate))
    spans: list[tuple[int, int]] = []
    start = 0
    while start < n:
        if start + target >= n:
            spans.append((start, n))
            break
        lo = max(start + int(1.0 * rate), start + target - search)
        hi = min(start + target + search, n)
        best_pos, best_energy = lo, float("inf")
        step = max(1, win // 2)
        pos = lo
        while pos + win <= hi:
            energy = float(np.mean(np.square(audio[pos:pos + win])))
            if energy < best_energy:
                best_energy, best_pos = energy, pos
            pos += step
        split = best_pos + win // 2
        if split <= start:
            split = min(start + target, n)
        spans.append((start, split))
        start = split
    return spans


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
        from wordflow.asr.audio import normalise_peak

        target_rate = self._model.preprocessor_config.sample_rate
        audio = np.ascontiguousarray(samples, dtype=np.float32)
        if sample_rate != target_rate and audio.size:
            positions = np.linspace(0, len(audio) - 1, int(round(len(audio) * target_rate / sample_rate)))
            audio = np.interp(positions, np.arange(len(audio)), audio).astype(np.float32)
        if audio.size == 0:
            return ""
        audio = normalise_peak(audio)

        if len(audio) / target_rate <= CHUNK_THRESHOLD_SECONDS:
            return self._generate(audio)
        # Long dictation: transcribe each quiet-split window and stitch, so a
        # long clip never collapses to a wrong short phrase.
        parts = [self._generate(audio[a:b]) for a, b in _chunk_spans(audio, target_rate)]
        return " ".join(p for p in parts if p).strip()

    def _generate(self, audio: np.ndarray) -> str:
        # parakeet-mlx's own transcribe() loads audio by shelling out to ffmpeg,
        # which the PRD forbids (AC-12.2). We already hold decoded PCM, so we feed
        # the model's front end directly (get_logmel -> generate, float32 input).
        if audio.size == 0:
            return ""
        import mlx.core as mx
        from parakeet_mlx.audio import get_logmel

        mel = get_logmel(
            mx.array(np.ascontiguousarray(audio, dtype=np.float32)),
            self._model.preprocessor_config)
        result = self._model.generate(mel)[0]
        return (getattr(result, "text", "") or "").strip()

    def unload(self) -> None:
        self._model = None
        try:
            import mlx.core as mx

            mx.clear_cache()
        except Exception:
            pass
