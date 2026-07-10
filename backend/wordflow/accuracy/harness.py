"""The bake-off and accuracy harness. The bake-off transcribes one recording on
each model and returns the transcripts side by side so the user picks a winner
on their own voice (AC-9.3). The accuracy harness scores each model's word error
rate against the fixed reference script and stores the run so runs stay
comparable over time (AC-9.5)."""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass

import numpy as np

from wordflow.accuracy.wer import word_error_rate
from wordflow.asr.manager import ModelManager
from wordflow.storage.db import utcnow

DEFAULT_MODELS = ["parakeet", "whisper"]


@dataclass
class ModelTranscript:
    model: str
    text: str
    error: str | None = None


@dataclass
class AccuracyScore:
    model: str
    wer: float
    reference_words: int
    transcript: str
    error: str | None = None


def run_bakeoff(
    manager: ModelManager, samples: np.ndarray, sample_rate: int,
    models: list[str] | None = None,
) -> list[ModelTranscript]:
    results: list[ModelTranscript] = []
    for name in models or DEFAULT_MODELS:
        try:
            text = manager.transcribe_on(name, samples, sample_rate).strip()
            results.append(ModelTranscript(name, text))
        except Exception as exc:
            results.append(ModelTranscript(name, "", str(exc)))
    return results


def run_accuracy(
    conn: sqlite3.Connection, manager: ModelManager, reference: str,
    samples: np.ndarray, sample_rate: int, models: list[str] | None = None,
    now: str | None = None,
) -> list[AccuracyScore]:
    created = now or utcnow()
    scores: list[AccuracyScore] = []
    for name in models or DEFAULT_MODELS:
        try:
            text = manager.transcribe_on(name, samples, sample_rate).strip()
            result = word_error_rate(reference, text)
            conn.execute(
                "INSERT INTO accuracy_runs(created_at, model, wer, reference_words, transcript) "
                "VALUES (?, ?, ?, ?, ?)",
                (created, name, result.wer, result.reference_words, text),
            )
            scores.append(AccuracyScore(name, result.wer, result.reference_words, text))
        except Exception as exc:
            scores.append(AccuracyScore(name, 1.0, 0, "", str(exc)))
    conn.commit()
    return scores


def list_runs(conn: sqlite3.Connection, limit: int = 50) -> list[dict]:
    rows = conn.execute(
        "SELECT id, created_at, model, wer, reference_words FROM accuracy_runs "
        "ORDER BY id DESC LIMIT ?", (limit,),
    ).fetchall()
    return [dict(r) for r in rows]
