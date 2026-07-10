"""The dictation service: audio in, cleaned text out, history written. Shared by
the /transcribe endpoint and the tests so both exercise the same path."""

from __future__ import annotations

import logging
from dataclasses import dataclass

from wordflow.asr.audio import decode_wav_base64, looks_silent
from wordflow.asr.manager import ModelManager
from wordflow.cleanup.pipeline import Pipeline
from wordflow.cleanup.stages import CleanupContext
from wordflow.config import Config
from wordflow.dictionary.store import read_entries
from wordflow.history import store as history
from wordflow.storage import settings as settings_store
from wordflow.storage.paths import DataFolder

log = logging.getLogger("wordflow")


@dataclass
class DictationOutcome:
    dictation_id: int | None
    raw: str
    text: str
    nothing_heard: bool
    flags: list[str]


def _read_fillers(data: DataFolder) -> list[str]:
    if not data.fillers_path.exists():
        return []
    out = []
    for line in data.fillers_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def build_context(data: DataFolder) -> CleanupContext:
    return CleanupContext(
        fillers=_read_fillers(data),
        dict_entries=read_entries(data.dictionary_path),
    )


def cleanup_toggles(conn, config: Config) -> dict[str, bool]:
    stored = settings_store.get(conn, "cleanup")
    if isinstance(stored, dict):
        return stored
    return config.cleanup.model_dump()


def run_dictation(
    *, conn, data: DataFolder, config: Config, manager: ModelManager, pipeline: Pipeline,
    audio_base64: str, sample_rate: int, target_app: str | None = None,
    target_bundle_id: str | None = None,
) -> DictationOutcome:
    samples, rate = decode_wav_base64(audio_base64)
    if rate != sample_rate:
        # The app promises 16 kHz; trust the WAV header, but note a mismatch.
        log.warning("declared sample rate %s but WAV says %s", sample_rate, rate)

    if looks_silent(samples, rate):
        return DictationOutcome(None, "", "", nothing_heard=True, flags=[])

    raw = manager.transcribe(samples, rate).strip()
    if not raw:
        # The model heard nothing recognisable (a cough, a stray noise).
        return DictationOutcome(None, "", "", nothing_heard=True, flags=[])

    result = pipeline.run(raw, build_context(data))
    keep_audio = bool(settings_store.get(conn, "keep_audio", config.keep_audio))
    audio_path = None
    if keep_audio:
        audio_path = _persist_audio(data, audio_base64)

    dictation_id = history.create_dictation(
        conn, model=manager.active_model, raw_text=raw, cleaned_text=result.text,
        target_app=target_app, target_bundle_id=target_bundle_id, audio_path=audio_path,
    )
    return DictationOutcome(
        dictation_id=dictation_id, raw=raw, text=result.text,
        nothing_heard=False, flags=result.flags,
    )


def _persist_audio(data: DataFolder, audio_base64: str) -> str:
    import base64

    data.audio_dir.mkdir(parents=True, exist_ok=True)
    from wordflow.storage.db import utcnow

    path = data.audio_dir / f"{utcnow().replace(':', '-')}.wav"
    path.write_bytes(base64.b64decode(audio_base64))
    return str(path)
