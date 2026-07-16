"""Decoding the 16 kHz mono PCM the app sends, and deciding when a dictation
carried no recognisable speech. The app captures and encodes the WAV natively,
so the backend never spawns an external binary to read audio (AC-12.2)."""

from __future__ import annotations

import base64
import io
import wave

import numpy as np

# Below this root-mean-square level a buffer is treated as silence, a breath, or
# room noise and discarded before the model even runs (AC-2.6).
SILENCE_RMS = 0.006
MIN_SPEECH_SECONDS = 0.15


def _decode_wav(reader) -> tuple[np.ndarray, int]:
    with wave.open(reader, "rb") as w:
        rate = w.getframerate()
        channels = w.getnchannels()
        width = w.getsampwidth()
        frames = w.readframes(w.getnframes())
    if width != 2:
        raise ValueError(f"expected 16-bit PCM, got {width * 8}-bit")
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples, rate


def decode_wav_base64(data_base64: str) -> tuple[np.ndarray, int]:
    """Return float32 mono samples in [-1, 1] and the sample rate."""
    return _decode_wav(io.BytesIO(base64.b64decode(data_base64)))


def decode_wav_file(path) -> tuple[np.ndarray, int]:
    """Decode a kept dictation WAV from disk, for re-transcription."""
    return _decode_wav(str(path))


def rms(samples: np.ndarray) -> float:
    if samples.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(samples))))


def normalise_peak(samples: np.ndarray, target: float = 0.95, max_gain: float = 40.0) -> np.ndarray:
    """Scale the audio so its loudest sample sits near full scale. Quiet capture
    (a distant or low-gain mic) otherwise loses the attack of consonants and the
    model mishears them; normalising recovers them. The gain is capped so
    near-silent buffers are not blown up into noise. Applied after the silence
    gate, so there is always real speech to normalise against."""
    if samples.size == 0:
        return samples
    peak = float(np.max(np.abs(samples)))
    if peak <= 1e-4:
        return samples
    gain = min(target / peak, max_gain)
    return (samples * gain).astype(np.float32)


def looks_silent(samples: np.ndarray, rate: int, floor: float = SILENCE_RMS) -> bool:
    """A pre-model check: too short, or too quiet to be speech."""
    if samples.size == 0 or rate <= 0:
        return True
    if samples.size / rate < MIN_SPEECH_SECONDS:
        return True
    return rms(samples) < floor
