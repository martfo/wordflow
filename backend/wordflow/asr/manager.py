"""Keeps one speech model resident, mediates switching, and unloads on idle.

All model work runs on one dedicated thread. MLX streams are per-thread, so a
model loaded on one thread and used on another raises "no Stream in current
thread"; funnelling load, inference, unload, and switching through a single
worker keeps every MLX operation on the same thread. It also serialises
inference, which is the FIFO behaviour dictations want anyway.

The active model is loaded at launch so the first dictation is inference only
(AC-2.1). Switching loads the new model and swaps it in between dictations, never
mid-request (AC-2.3-b). With idle unload enabled a reaper unloads the model after
the idle period, and the next dictation reloads it (AC-2.4).
"""

from __future__ import annotations

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
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
        # The one thread every MLX operation runs on.
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mlx")
        self._state_lock = threading.Lock()
        self._clock = clock
        self._last_used = clock()
        self._idle_seconds = max(0, idle_unload_minutes) * 60
        self._switching_to: str | None = None

    # --- properties, read from any thread (GIL-atomic reads) ---

    @property
    def active_model(self) -> str:
        return self._active_name

    @property
    def is_loaded(self) -> bool:
        engine = self._engine
        return engine is not None and engine.is_loaded

    @property
    def loading(self) -> bool:
        with self._state_lock:
            return self._switching_to is not None

    # --- operations, all funnelled onto the single worker thread ---

    def _ensure_loaded(self) -> None:
        if self._engine is None or not self._engine.is_loaded:
            engine = self._make(self._active_name)
            engine.load()
            self._engine = engine
            log.info("loaded model %r", self._active_name)

    def warm_up(self) -> None:
        self._pool.submit(self._ensure_loaded).result()

    def _do_transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        self._ensure_loaded()
        with self._state_lock:
            self._last_used = self._clock()
        assert self._engine is not None
        return self._engine.transcribe(samples, sample_rate)

    def transcribe(self, samples: np.ndarray, sample_rate: int) -> str:
        return self._pool.submit(self._do_transcribe, samples, sample_rate).result()

    def _do_transcribe_on(self, name: str, samples: np.ndarray, sample_rate: int) -> str:
        if name == self._active_name:
            self._ensure_loaded()
            with self._state_lock:
                self._last_used = self._clock()
            assert self._engine is not None
            return self._engine.transcribe(samples, sample_rate)
        engine = self._make(name)
        engine.load()
        try:
            return engine.transcribe(samples, sample_rate)
        finally:
            engine.unload()

    def transcribe_on(self, name: str, samples: np.ndarray, sample_rate: int) -> str:
        """Transcribe with a specific model without leaving a second model
        resident (used by the bake-off). Runs on the worker thread like every
        other model operation."""
        return self._pool.submit(self._do_transcribe_on, name, samples, sample_rate).result()

    def switch(self, name: str, *, background: bool = True) -> None:
        """Switch the active model. The load runs on the worker thread; a
        dictation submitted meanwhile queues behind it rather than being lost."""
        if name == self._active_name and self.is_loaded:
            return

        def work() -> None:
            try:
                new = self._make(name)
                new.load()
            except Exception as exc:
                log.warning("switching to model %r failed: %s", name, exc)
                with self._state_lock:
                    self._switching_to = None
                return
            old = self._engine
            self._engine = new
            self._active_name = name
            with self._state_lock:
                self._switching_to = None
                self._last_used = self._clock()
            if old is not None and old is not new:
                old.unload()
            log.info("switched active model to %r", name)

        with self._state_lock:
            self._switching_to = name
        future = self._pool.submit(work)
        if not background:
            future.result()

    def _do_reap(self) -> bool:
        if self._idle_seconds <= 0:
            return False
        if self._engine is None or not self._engine.is_loaded:
            return False
        with self._state_lock:
            switching = self._switching_to is not None
            idle_for = self._clock() - self._last_used
        if switching or idle_for < self._idle_seconds:
            return False
        self._engine.unload()
        log.info("unloaded model %r after idle period", self._active_name)
        return True

    def reap_if_idle(self) -> bool:
        """Unload the model if idle unload is on and the idle period has elapsed.
        Called by the reaper and, in tests, directly with a stubbed clock."""
        return self._pool.submit(self._do_reap).result()

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
