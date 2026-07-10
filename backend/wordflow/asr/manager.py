"""Keeps one speech model resident, mediates switching, and unloads on idle.

The active model is loaded at launch so the first dictation is inference only
(AC-2.1). Switching loads the new model in the background and keeps the previous
one serving until the new one is ready, so the swap happens between dictations,
never mid-request (AC-2.3-b). With idle unload enabled a reaper unloads the
model after the idle period, and the next dictation reloads it (AC-2.4).
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Callable

import numpy as np

from wordflow.asr.base import ASREngine

log = logging.getLogger("wordflow")

EngineFactory = Callable[[str], ASREngine]


class ModelManager:
    def __init__(
        self, factory: EngineFactory, active: str,
        idle_unload_minutes: int = 0, clock: Callable[[], float] = time.monotonic,
    ):
        self._make = factory
        self._active_name = active
        self._engine: ASREngine | None = None
        self._lock = threading.RLock()
        self._clock = clock
        self._last_used = clock()
        self._idle_seconds = max(0, idle_unload_minutes) * 60
        self._switching_to: str | None = None

    @property
    def active_model(self) -> str:
        return self._active_name

    @property
    def is_loaded(self) -> bool:
        with self._lock:
            return self._engine is not None and self._engine.is_loaded

    @property
    def loading(self) -> bool:
        with self._lock:
            return self._switching_to is not None

    def warm_up(self) -> None:
        with self._lock:
            self._ensure_loaded()

    def _ensure_loaded(self) -> None:
        if self._engine is None or not self._engine.is_loaded:
            engine = self._make(self._active_name)
            engine.load()
            self._engine = engine
            log.info("loaded model %r", self._active_name)

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        with self._lock:
            self._ensure_loaded()
            self._last_used = self._clock()
            assert self._engine is not None
            return self._engine.transcribe(samples, sample_rate)

    def transcribe_on(self, name: str, samples: np.ndarray, sample_rate: int) -> str:
        """Transcribe with a specific model without disturbing the resident
        active one. The active model uses the resident engine; any other is
        loaded transiently and unloaded again, so the bake-off can score both
        models without a permanent second model in memory."""
        with self._lock:
            if name == self._active_name:
                self._ensure_loaded()
                self._last_used = self._clock()
                assert self._engine is not None
                return self._engine.transcribe(samples, sample_rate)
        engine = self._make(name)
        engine.load()
        try:
            return engine.transcribe(samples, sample_rate)
        finally:
            engine.unload()

    def switch(self, name: str, *, background: bool = True) -> None:
        """Switch the active model. The previous model keeps serving until the
        new one has loaded; only then does the active engine swap."""
        if name == self._active_name and self.is_loaded:
            return

        def work() -> None:
            try:
                new = self._make(name)
                new.load()
            except Exception as exc:
                log.warning("switching to model %r failed: %s", name, exc)
                with self._lock:
                    self._switching_to = None
                return
            with self._lock:
                old = self._engine
                self._engine = new
                self._active_name = name
                self._switching_to = None
                self._last_used = self._clock()
            if old is not None and old is not new:
                old.unload()
            log.info("switched active model to %r", name)

        with self._lock:
            self._switching_to = name
        if background:
            threading.Thread(target=work, name="model-switch", daemon=True).start()
        else:
            work()

    def reap_if_idle(self) -> bool:
        """Unload the model if idle unload is on and the idle period has
        elapsed. Returns whether it unloaded. Called by a background reaper and,
        in tests, directly with a stubbed clock."""
        if self._idle_seconds <= 0:
            return False
        with self._lock:
            if self._engine is None or not self._engine.is_loaded:
                return False
            if self._switching_to is not None:
                return False
            if self._clock() - self._last_used < self._idle_seconds:
                return False
            self._engine.unload()
            log.info("unloaded model %r after idle period", self._active_name)
            return True

    def start_reaper(self, interval_seconds: float = 30.0) -> None:
        if self._idle_seconds <= 0:
            return

        def loop() -> None:
            while True:
                time.sleep(interval_seconds)
                try:
                    self.reap_if_idle()
                except Exception:
                    pass

        threading.Thread(target=loop, name="idle-reaper", daemon=True).start()
