"""Record the user's voice fixtures for the latency and accuracy tests.

The accent under test is the user's own, so these must be recorded by them.
Run from the repo root:

    uv run --with sounddevice python backend/scripts/record_fixtures.py

It writes 16 kHz mono WAVs into fixtures/audio/: the fixed 20-sentence
reference script read aloud, and single utterances of about 5, 10, 30, and 60
seconds, plus a first-word test. These feed the pipeline-tier tests
(make pipeline) on the reference machine.
"""

from __future__ import annotations

import sys
import wave
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AUDIO_DIR = REPO_ROOT / "fixtures" / "audio"
SCRIPT = REPO_ROOT / "fixtures" / "reference_script.txt"
RATE = 16_000

# (filename, prompt, seconds). None seconds means "read the script; press Enter
# when finished".
PLAN = [
    ("first_word.wav", "Say a short sentence the instant recording starts, to test first-word capture.", 4),
    ("utt_5s.wav", "Speak naturally for about five seconds.", 5),
    ("utt_10s.wav", "Speak naturally for about ten seconds.", 10),
    ("utt_30s.wav", "Speak naturally for about thirty seconds.", 30),
    ("utt_60s.wav", "Speak naturally for about sixty seconds.", 60),
    ("reference_script.wav", "Read the whole reference script aloud, naturally.", None),
]


def _record(seconds: float | None) -> "list":
    import sounddevice as sd

    if seconds is not None:
        print(f"  recording {int(seconds)}s… speak now.")
        frames = sd.rec(int(seconds * RATE), samplerate=RATE, channels=1, dtype="int16")
        sd.wait()
        return frames
    input("  press Enter to start, then read the script; Ctrl-C to stop… ")
    frames = sd.rec(int(600 * RATE), samplerate=RATE, channels=1, dtype="int16")
    try:
        input("  reading… press Enter when finished. ")
    except KeyboardInterrupt:
        pass
    sd.stop()
    return frames


def _write(path: Path, frames) -> None:
    import numpy as np

    data = np.asarray(frames, dtype="<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main() -> None:
    try:
        import sounddevice  # noqa: F401
    except ImportError:
        print("sounddevice is needed. Run with: uv run --with sounddevice python "
              "backend/scripts/record_fixtures.py", file=sys.stderr)
        sys.exit(1)

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    print("The reference script:\n")
    print(SCRIPT.read_text())
    print("=" * 60)
    for filename, prompt, seconds in PLAN:
        print(f"\n{filename}: {prompt}")
        input("  press Enter when ready… ")
        frames = _record(seconds)
        _write(AUDIO_DIR / filename, frames)
        print(f"  saved {AUDIO_DIR / filename}")
    print("\nAll fixtures recorded. Run: make pipeline")


if __name__ == "__main__":
    main()
