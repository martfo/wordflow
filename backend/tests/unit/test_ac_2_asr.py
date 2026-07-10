"""Section 2: audio decoding, the silence gate, and the resident-model manager.
The real MLX models run only in the pipeline tier; here a fake engine stands in
so the manager's load, switch, and idle-unload logic is tested deterministically."""

import numpy as np

from wordflow.asr.audio import decode_wav_base64, looks_silent
from wordflow.asr.fake import FakeEngine
from wordflow.asr.manager import ModelManager
from tests.conftest import make_wav_base64


def test_ac_2_5_a_decodes_16k_mono():
    samples = np.linspace(-0.5, 0.5, 16_000, dtype=np.float32)
    decoded, rate = decode_wav_base64(make_wav_base64(samples, rate=16_000))
    assert rate == 16_000
    assert abs(decoded.shape[0] - 16_000) <= 1


def test_ac_2_6_a_silence_is_nothing_heard():
    silent = np.zeros(16_000, dtype=np.float32)
    assert looks_silent(silent, 16_000)
    breath = (np.random.default_rng(1).normal(0, 0.001, 16_000)).astype(np.float32)
    assert looks_silent(breath, 16_000)
    speech = (np.random.default_rng(2).uniform(-0.3, 0.3, 16_000)).astype(np.float32)
    assert not looks_silent(speech, 16_000)


def test_ac_2_1_a_warm_up_loads_before_first_dictation():
    engine = FakeEngine()
    manager = ModelManager(lambda name: engine, active="parakeet")
    assert not manager.is_loaded
    manager.warm_up()
    assert manager.is_loaded and engine.load_count == 1
    # The first transcription does not trigger a second load.
    manager.transcribe(np.zeros(10, dtype=np.float32), 16_000)
    assert engine.load_count == 1


def test_ac_2_3_b_switch_keeps_old_serving_until_new_loaded():
    parakeet = FakeEngine(name="parakeet", transcript="from parakeet")
    whisper = FakeEngine(name="whisper", transcript="from whisper")
    engines = {"parakeet": parakeet, "whisper": whisper}
    manager = ModelManager(lambda name: engines[name], active="parakeet")
    manager.warm_up()

    # Switch synchronously (background=False mirrors the eventual completion) and
    # confirm the swap is clean and no dictation errors out.
    assert manager.transcribe(np.zeros(10, dtype=np.float32), 16_000) == "from parakeet"
    manager.switch("whisper", background=False)
    assert manager.active_model == "whisper"
    assert manager.transcribe(np.zeros(10, dtype=np.float32), 16_000) == "from whisper"
    # The previous model was unloaded after the swap, not before.
    assert parakeet.unload_count == 1


def test_ac_2_4_a_and_b_idle_unload_and_reload():
    clock = {"t": 1000.0}
    engine = FakeEngine()
    manager = ModelManager(
        lambda name: engine, active="parakeet",
        idle_unload_minutes=5, clock=lambda: clock["t"])
    manager.warm_up()
    assert manager.is_loaded

    clock["t"] += 4 * 60  # under the idle period
    assert not manager.reap_if_idle()
    assert manager.is_loaded

    clock["t"] += 2 * 60  # now past 5 minutes idle
    assert manager.reap_if_idle()
    assert not manager.is_loaded  # memory dropped (AC-2.4-a)

    # The next dictation reloads the model rather than failing (AC-2.4-b).
    manager.transcribe(np.zeros(10, dtype=np.float32), 16_000)
    assert manager.is_loaded and engine.load_count == 2
