# WordFlow

A fully local, Wispr Flow-style dictation utility for macOS. Hold the § key,
speak, release, and cleaned English text appears at the cursor of whatever app
you are in, in under two seconds. Nothing leaves the machine. WordFlow is the
sibling of Polenta Meeting Notes: same architecture, same British-English
conventions, same privacy posture.

- **Primary model:** Parakeet TDT 0.6B v2 via MLX. **Alternative:** Whisper
  large-v3-turbo, one click away.
- **Deterministic cleanup only** (no LLM in v1): filler strip, personal
  dictionary, British spelling, em-dash removal, in a pluggable pipeline built
  to take a future LLM stage.
- **Menu bar app, no Dock icon**, with a floating pill while you dictate.
- **Fully offline after a one-time setup download.** Drag-install from a .dmg;
  nothing else installed by hand.

See `PRD.md`, `ACCEPTANCE.md`, and `DESIGN.md` for the full specification and the
decisions the build is pinned to.

## Layout

```
app/        the SwiftUI menu bar app (WordFlowApp) and its pure logic (WordFlowCore)
backend/    the Python FastAPI backend (wordflow), on 127.0.0.1:8770
fixtures/   the reference script, synthetic cleanup cases, and the user's voice recordings
scripts/    build_app.sh, build_dmg.sh, make_signing_cert.sh
docs/       the manual hardware checklist
```

## Developing

The backend runs under uv; the app is a SwiftPM package.

```sh
make gate        # the fast gate: backend pytest + Swift Testing (the meaning of green)
make pipeline    # slow tier: the real MLX models against the voice fixtures (reference machine)
make dmg         # build and package the signed app
```

To run the app from a checkout against the repo's backend, point it at a Python
environment with the backend installed and set:

```sh
export WORDFLOW_BACKEND_PYTHON=backend/.venv/bin/python3
export WORDFLOW_BACKEND_DIR="$PWD/backend"
```

The shipped app needs none of this: on first run it provisions its own Python
backend into `~/Library/Application Support/WordFlow/runtime` from the bundled uv
binary, and downloads the models once. All user data (history, dictionary,
config, logs) lives in `~/Library/Application Support/WordFlow/data`; copy that
folder to carry your history and dictionary to another Mac.

## Recording the voice fixtures

The latency and accuracy tests run against the user's own voice. Generate the
fixtures once:

```sh
uv run --with sounddevice python backend/scripts/record_fixtures.py
```

## Coexistence with Polenta

WordFlow uses port 8770 and its own Application Support folder, distinct from
Polenta's 8765 and its vault, so both apps run at the same time.
