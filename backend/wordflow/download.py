"""The onboarding model downloader: the only place the Hugging Face offline
flags are lifted, and only for the duration of the download (AC-10.2-b, AC-9.2).

Run as: python -m wordflow.download <path-to-config.json>

It fetches Parakeet and Whisper into the app's models folder (HF_HOME), records
the resolved commit revisions in models.lock.json so the backend loads pinned
revisions thereafter, and prints progress lines the app can show. After it
returns, normal operation runs fully offline.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from wordflow.config import load_config

REPOS = {
    "parakeet": lambda c: c.models.parakeet,
    "whisper": lambda c: c.models.whisper,
}


def _lift_offline(models_dir: Path) -> None:
    # The one moment the guarantee is relaxed, on purpose.
    os.environ.pop("HF_HUB_OFFLINE", None)
    os.environ.pop("TRANSFORMERS_OFFLINE", None)
    os.environ["HF_HOME"] = str(models_dir)
    models_dir.mkdir(parents=True, exist_ok=True)


def _revision_from_snapshot(path: str) -> str | None:
    # huggingface_hub stores snapshots at .../snapshots/<commit>/...
    parts = Path(path).parts
    if "snapshots" in parts:
        i = parts.index("snapshots")
        if i + 1 < len(parts):
            return parts[i + 1]
    return None


def download(config_path: str) -> dict[str, str]:
    config = load_config(Path(config_path))
    models_dir = Path(config.data_path).parent / "models"
    _lift_offline(models_dir)

    from huggingface_hub import snapshot_download

    revisions: dict[str, str] = {}
    for name, repo_of in REPOS.items():
        repo = repo_of(config)
        print(f"Downloading {name} ({repo})…", flush=True)
        local = snapshot_download(repo_id=repo, resume_download=True)
        revision = _revision_from_snapshot(local)
        if revision:
            revisions[name] = revision
        print(f"Done {name}.", flush=True)

    lock = models_dir / "models.lock.json"
    lock.write_text(json.dumps(revisions, indent=2) + "\n")
    print(f"Pinned revisions written to {lock}", flush=True)
    return revisions


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python -m wordflow.download <path-to-config.json>", file=sys.stderr)
        sys.exit(2)
    download(sys.argv[1])
