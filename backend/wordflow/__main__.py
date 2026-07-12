"""The backend service: python -m wordflow <path-to-config.json>.

Launched and supervised by the Swift app, never by hand. The offline flags are
pinned before any Hugging Face import, so model loading never phones home; only
the onboarding downloader (a separate entry point) lifts them (AC-10.2)."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def _pin_offline() -> None:
    """Pin the Hugging Face libraries offline, so model loading never phones
    home. Set before importing anything that pulls in huggingface_hub. The cache
    location is left at the Hugging Face default (~/.cache/huggingface), so the
    weights are shared with any other MLX use on the machine and are downloaded
    once per Mac by the onboarding downloader."""
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")


def _exit_with_parent() -> None:
    """The backend is a supervised child of the app and must never outlive it:
    an orphan keeps the port and answers the next app version with stale code.
    When the parent dies we are reparented to launchd (pid 1)."""
    import threading
    import time

    parent = os.getppid()

    def watch() -> None:
        while True:
            time.sleep(2.0)
            if parent != 1 and os.getppid() == 1:
                os._exit(0)

    threading.Thread(target=watch, name="parent-watchdog", daemon=True).start()


def main(config_path: str) -> None:
    from wordflow.config import load_config

    config = load_config(Path(config_path))
    data_root = Path(config.data_path)
    _pin_offline()
    _exit_with_parent()

    import uvicorn

    from wordflow.api.app import AppState, create_app
    from wordflow.asr.manager import ModelManager
    from wordflow.asr.registry import build_engine
    from wordflow.cleanup.pipeline import default_pipeline
    from wordflow.history.retention import purge_old_entries, retention_days
    from wordflow.logging.setup import configure_logging
    from wordflow.storage.db import open_db
    from wordflow.storage.paths import DataFolder

    data = DataFolder(data_root).ensure()
    configure_logging(data.logs_dir, config.log_level)
    conn = open_db(data.db_path)

    import logging

    log = logging.getLogger("wordflow")
    removed = purge_old_entries(conn, retention_days(conn, config.text_retention_days))
    if removed:
        log.info("retention removed %d old dictations at startup", len(removed))

    from wordflow.storage import settings as settings_store

    active = settings_store.get(conn, "active_model", config.active_model)
    manager = ModelManager(
        factory=lambda name: build_engine(name, config),
        active=active,
        idle_unload_minutes=int(settings_store.get(conn, "idle_unload_minutes", config.idle_unload_minutes)),
    )
    # Load the model at launch so the first dictation is inference only.
    try:
        manager.warm_up()
    except Exception as exc:
        log.warning("model warm-up deferred: %s", exc)
    manager.start_reaper()

    app = create_app(AppState(
        conn=conn, data=data, config=config, manager=manager, pipeline=default_pipeline(),
    ))
    uvicorn.run(app, host="127.0.0.1", port=config.backend_port, log_config=None)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python -m wordflow <path-to-config.json>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
