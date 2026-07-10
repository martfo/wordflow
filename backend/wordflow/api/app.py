"""The FastAPI surface the Swift app talks to, on 127.0.0.1:8770.

Everything stateful is injected through AppState so tests run the same app
against a fake engine and a temporary data folder."""

from __future__ import annotations

from dataclasses import dataclass

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from wordflow.accuracy import harness
from wordflow.api.service import cleanup_toggles, run_dictation
from wordflow.asr.audio import decode_wav_base64
from wordflow.asr.manager import ModelManager
from wordflow.cleanup.pipeline import Pipeline
from wordflow.config import Config
from wordflow.dictionary import learning, store as dict_store
from wordflow.history import store as history
from wordflow.storage import settings as settings_store
from wordflow.storage.paths import DataFolder


@dataclass
class AppState:
    conn: object
    data: DataFolder
    config: Config
    manager: ModelManager
    pipeline: Pipeline


class TranscribeRequest(BaseModel):
    audio_base64: str
    sample_rate: int = 16_000
    target_app: str | None = None
    target_bundle_id: str | None = None
    locked: bool = False


class CorrectRequest(BaseModel):
    text: str


class InsertedRequest(BaseModel):
    inserted: bool


class DictionaryRequest(BaseModel):
    canonical: str
    hints: list[str] = []
    source_dictation_id: int | None = None


class SettingRequest(BaseModel):
    key: str
    value: object


class CleanupRequest(BaseModel):
    toggles: dict[str, bool]


class FillersRequest(BaseModel):
    fillers: list[str]


class ModelRequest(BaseModel):
    name: str


class BakeoffRequest(BaseModel):
    audio_base64: str
    sample_rate: int = 16_000


class AccuracyRequest(BaseModel):
    audio_base64: str
    reference_text: str
    sample_rate: int = 16_000


def create_app(state: AppState) -> FastAPI:
    app = FastAPI(title="WordFlow backend")
    conn, data, config = state.conn, state.data, state.config

    @app.get("/health")
    def health() -> dict:
        return {
            "status": "ok",
            "active_model": state.manager.active_model,
            "model_loaded": state.manager.is_loaded,
            "loading": state.manager.loading,
        }

    @app.post("/transcribe")
    def transcribe(request: TranscribeRequest) -> dict:
        outcome = run_dictation(
            conn=conn, data=data, config=config, manager=state.manager,
            pipeline=Pipeline(state.pipeline.stages, cleanup_toggles(conn, config)),
            audio_base64=request.audio_base64, sample_rate=request.sample_rate,
            target_app=request.target_app, target_bundle_id=request.target_bundle_id,
        )
        return {
            "dictation_id": outcome.dictation_id,
            "raw": outcome.raw,
            "text": outcome.text,
            "nothing_heard": outcome.nothing_heard,
            "flags": outcome.flags,
        }

    # --- History ---

    @app.get("/history")
    def list_history(q: str | None = None) -> list[dict]:
        rows = history.list_dictations(conn, query=q)
        for row in rows:
            row["taught_entries"] = dict_store.entries_taught_by(conn, row["id"])
        return rows

    @app.get("/history/{dictation_id}")
    def get_history(dictation_id: int) -> dict:
        try:
            row = history.get_dictation(conn, dictation_id)
        except KeyError:
            raise HTTPException(404, "no such dictation")
        row["taught_entries"] = dict_store.entries_taught_by(conn, dictation_id)
        return row

    @app.delete("/history/{dictation_id}")
    def delete_history(dictation_id: int) -> dict:
        history.delete_dictation(conn, dictation_id)
        return {"deleted": True}

    @app.post("/history/clear")
    def clear_history() -> dict:
        return {"cleared": history.clear_all(conn)}

    @app.put("/history/{dictation_id}/inserted")
    def set_inserted(dictation_id: int, request: InsertedRequest) -> dict:
        conn.execute(
            "UPDATE dictations SET inserted = ? WHERE id = ?",
            (1 if request.inserted else 0, dictation_id),
        )
        conn.commit()
        return {"inserted": request.inserted}

    @app.post("/history/{dictation_id}/correct")
    def correct_history(dictation_id: int, request: CorrectRequest) -> dict:
        try:
            old = history.get_dictation(conn, dictation_id)["cleaned_text"]
        except KeyError:
            raise HTTPException(404, "no such dictation")
        history.correct_dictation(conn, dictation_id, request.text)
        change = learning.single_word_change(old, request.text)
        offer = None
        if change is not None:
            offer = {"heard": change.heard, "corrected": change.corrected}
        return {"saved": True, "offer": offer}

    # --- Dictionary ---

    @app.get("/dictionary")
    def get_dictionary() -> list[dict]:
        entries = dict_store.read_entries(data.dictionary_path)
        return [
            {
                "canonical": e.canonical,
                "hints": e.hints,
                "source_dictation_id": dict_store.entry_source_dictation(conn, e.canonical),
            }
            for e in entries
        ]

    @app.post("/dictionary")
    def add_dictionary(request: DictionaryRequest) -> dict:
        entry = dict_store.add_entry(data.dictionary_path, request.canonical, request.hints)
        dict_store.record_link(conn, entry.canonical, request.source_dictation_id, entry.hints)
        return {"canonical": entry.canonical, "hints": entry.hints}

    @app.delete("/dictionary/{canonical}")
    def delete_dictionary(canonical: str) -> dict:
        removed = dict_store.remove_entry(data.dictionary_path, canonical)
        dict_store.forget_link(conn, canonical)
        return {"deleted": removed}

    # --- Settings, cleanup, fillers, model ---

    @app.get("/settings")
    def get_settings() -> dict:
        return {
            "active_model": settings_store.get(conn, "active_model", config.active_model),
            "text_retention_days": settings_store.get(conn, "text_retention_days", config.text_retention_days),
            "keep_audio": settings_store.get(conn, "keep_audio", config.keep_audio),
            "idle_unload_minutes": settings_store.get(conn, "idle_unload_minutes", config.idle_unload_minutes),
        }

    @app.put("/settings")
    def put_setting(request: SettingRequest) -> dict:
        settings_store.put(conn, request.key, request.value)
        return {"saved": True}

    @app.get("/cleanup")
    def get_cleanup() -> dict:
        return cleanup_toggles(conn, config)

    @app.put("/cleanup")
    def put_cleanup(request: CleanupRequest) -> dict:
        merged = {**cleanup_toggles(conn, config), **request.toggles}
        settings_store.put(conn, "cleanup", merged)
        return merged

    @app.get("/fillers")
    def get_fillers() -> dict:
        text = data.fillers_path.read_text() if data.fillers_path.exists() else ""
        fillers = [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]
        return {"fillers": fillers}

    @app.put("/fillers")
    def put_fillers(request: FillersRequest) -> dict:
        header = "# WordFlow filler list. One filler per line; # starts a comment.\n"
        data.fillers_path.write_text(header + "\n".join(request.fillers) + "\n")
        return {"fillers": request.fillers}

    @app.post("/model")
    def switch_model(request: ModelRequest) -> dict:
        if request.name not in ("parakeet", "whisper"):
            raise HTTPException(422, "unknown model")
        settings_store.put(conn, "active_model", request.name)
        state.manager.switch(request.name)
        return {"switching_to": request.name}

    # --- Bake-off and accuracy harness (AC-9.3, AC-9.5) ---

    @app.post("/bakeoff")
    def bakeoff(request: BakeoffRequest) -> dict:
        samples, rate = decode_wav_base64(request.audio_base64)
        results = harness.run_bakeoff(state.manager, samples, rate)
        return {"results": [
            {"model": r.model, "text": r.text, "error": r.error} for r in results
        ]}

    @app.post("/accuracy")
    def accuracy(request: AccuracyRequest) -> dict:
        samples, rate = decode_wav_base64(request.audio_base64)
        scores = harness.run_accuracy(conn, state.manager, request.reference_text, samples, rate)
        return {"scores": [
            {"model": s.model, "wer": s.wer, "reference_words": s.reference_words,
             "transcript": s.transcript, "error": s.error} for s in scores
        ]}

    @app.get("/accuracy")
    def accuracy_runs() -> list[dict]:
        return harness.list_runs(conn)

    return app
