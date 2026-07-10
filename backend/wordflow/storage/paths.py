"""The WordFlow data folder on disk. Paths only; no policy.

Everything the user's data lives under `data/`, the one folder that is carried
between Macs. The provisioned runtime and the model cache live beside it under
Application Support but are rebuilt per Mac and never portable.
"""

from __future__ import annotations

from pathlib import Path


class DataFolder:
    def __init__(self, root: Path | str):
        self.root = Path(root)

    @property
    def db_path(self) -> Path:
        return self.root / "index.sqlite"

    @property
    def config_path(self) -> Path:
        return self.root / "config.json"

    @property
    def dictionary_path(self) -> Path:
        return self.root / "dictionary.txt"

    @property
    def fillers_path(self) -> Path:
        return self.root / "fillers.txt"

    @property
    def logs_dir(self) -> Path:
        return self.root / "logs"

    @property
    def audio_dir(self) -> Path:
        """Debug only: kept dictation audio when keep-audio is on."""
        return self.root / "audio"

    def ensure(self) -> "DataFolder":
        """Create the folder tree and seed the editable filler list from the
        bundled default when it is missing. Existing files are never
        overwritten."""
        for d in (self.root, self.logs_dir):
            d.mkdir(parents=True, exist_ok=True)
        if not self.fillers_path.exists():
            default = Path(__file__).resolve().parents[1] / "resources" / "fillers.txt"
            if default.exists():
                self.fillers_path.write_text(default.read_text())
        if not self.dictionary_path.exists():
            self.dictionary_path.write_text(
                "# WordFlow personal dictionary. One entry per line.\n"
                "# A canonical spelling on its own, or  canonical = sounds-like, another\n"
                "# Lines starting with # are comments.\n"
            )
        return self
