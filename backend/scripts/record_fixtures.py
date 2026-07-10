"""Record the user's voice fixtures for the latency and accuracy tests.

The accent under test is the user's own, so these must be recorded by them.
Run from the repo root:

    uv run --with sounddevice python backend/scripts/record_fixtures.py

It records at the microphone's native rate and resamples to 16 kHz mono, so it
works on any Mac input device, and writes the WAVs into fixtures/audio/: the
fixed 20-sentence reference script read aloud, single utterances of about 5, 10,
30, and 60 seconds, and a first-word test. These feed the pipeline-tier tests
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

# (filename, what to say, seconds). seconds=None means "read the script; press
# Enter when finished".
PLAN = [
    ("first_word.wav", "the FIRST-WORD test: start talking the instant it says 'speak now'.", 4),
    ("utt_5s.wav", "any natural speech for about 5 seconds.", 5),
    ("utt_10s.wav", "any natural speech for about 10 seconds.", 10),
    ("utt_30s.wav", "any natural speech for about 30 seconds.", 30),
    ("utt_60s.wav", "any natural speech for about 60 seconds.", 60),
    ("reference_script.wav", "the 20-sentence reference script, shown below.", None),
]


def say(message: str = "") -> None:
    print(message, flush=True)


def _default_input():
    import sounddevice as sd

    device = sd.query_devices(kind="input")
    return device["name"], int(device["default_samplerate"])


def _resample_to_16k(frames, src_rate: int):
    import numpy as np

    samples = np.asarray(frames, dtype=np.float32).flatten()
    if src_rate == RATE or samples.size == 0:
        return samples
    out_count = int(round(len(samples) * RATE / src_rate))
    positions = np.linspace(0, len(samples) - 1, out_count)
    return np.interp(positions, np.arange(len(samples)), samples)


def _warn_if_silent(samples) -> None:
    import numpy as np

    if samples.size == 0:
        rms = 0.0
    else:
        rms = float(np.sqrt(np.mean((samples / 32768.0) ** 2)))
    if rms < 0.002:
        say("  WARNING: that clip was silent. Give the terminal microphone access in")
        say("           System Settings > Privacy & Security > Microphone, then re-run.")


def _record_fixed(seconds: int, src_rate: int):
    import sounddevice as sd

    for n in (3, 2, 1):
        say(f"  starting in {n}...")
        sd.sleep(700)
    say("  >>> SPEAK NOW <<<")
    frames = sd.rec(int(seconds * src_rate), samplerate=src_rate, channels=1, dtype="int16")
    for remaining in range(seconds, 0, -1):
        print(f"\r  recording... {remaining:2d}s left ", end="", flush=True)
        sd.sleep(1000)
    sd.wait()
    print("\r  recorded.               ", flush=True)
    return frames


def _record_until_enter(src_rate: int):
    import numpy as np
    import sounddevice as sd

    chunks = []

    def callback(indata, frames, time_info, status):
        chunks.append(indata.copy())

    say("  >>> Reading now. Press Enter the moment you finish the last sentence. <<<")
    with sd.InputStream(samplerate=src_rate, channels=1, dtype="int16", callback=callback):
        input()
    if not chunks:
        return np.zeros(0, dtype="int16")
    return np.concatenate(chunks, axis=0)


def _write_16k(path: Path, samples) -> None:
    import numpy as np

    pcm = np.clip(samples, -32768, 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


def main() -> None:
    try:
        import sounddevice  # noqa: F401
    except ImportError:
        say("sounddevice is needed. Run with:")
        say("  uv run --with sounddevice python backend/scripts/record_fixtures.py")
        sys.exit(1)

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    name, src_rate = _default_input()
    say("=" * 66)
    say("  WordFlow voice fixtures")
    say(f"  Input device: {name} ({src_rate} Hz, resampled to 16 kHz)")
    say(f"  Saving to: {AUDIO_DIR}")
    say("=" * 66)
    say("You will record 6 clips. Before each, press Enter when you are ready.")
    say("If a clip is silent, grant the terminal microphone access and re-run;")
    say("already-recorded clips are simply overwritten.\n")

    for index, (filename, description, seconds) in enumerate(PLAN, start=1):
        say(f"[{index}/{len(PLAN)}] {filename}")
        say(f"  This clip is {description}")
        if seconds is None:
            say("")
            say(SCRIPT.read_text().rstrip())
            say("")
        try:
            input("  Press Enter when ready to record... ")
        except (EOFError, KeyboardInterrupt):
            say("\nStopped. Re-run any time to finish the remaining clips.")
            return
        frames = _record_fixed(seconds, src_rate) if seconds else _record_until_enter(src_rate)
        samples = _resample_to_16k(frames, src_rate)
        _write_16k(AUDIO_DIR / filename, samples)
        seconds_len = len(samples) / RATE if hasattr(samples, "__len__") else 0
        say(f"  saved {filename} ({seconds_len:.1f}s)")
        _warn_if_silent(samples)
        say("")

    say("All done. Now run:  make pipeline")


if __name__ == "__main__":
    main()
