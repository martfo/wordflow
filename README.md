# WordFlow

![Platform: macOS 14.4+](https://img.shields.io/badge/platform-macOS%2014.4%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black)
![Swift 5](https://img.shields.io/badge/Swift-5-orange)
![Python 3.11](https://img.shields.io/badge/Python-3.11-3776ab)
![Latest release](https://img.shields.io/github/v/release/martfo/wordflow)
![100% local](https://img.shields.io/badge/runtime-100%25%20local-brightgreen)
![License: GPL v3](https://img.shields.io/github/license/martfo/wordflow)

A fully local, Wispr Flow-style dictation utility for macOS. Hold Right Control,
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

## Installing (double-click app, no terminal)

```sh
make dmg
```

builds `dist/WordFlow.dmg`. Open it, drag **WordFlow.app** to Applications, then
right-click the app and choose **Open** once (it is signed locally, not
notarised). WordFlow lives in the menu bar — there is no Dock icon.

On first launch the app provisions its own Python backend into
`~/Library/Application Support/WordFlow/runtime` (from the bundled `uv`, no
system Python needed) and, if the speech models are not already in the Hugging
Face cache, downloads them once. After that it runs fully offline. Grant
**Microphone** and **Accessibility** when asked (Accessibility is what lets the
hotkey and text insertion work). Then hold **Right Control** and speak; double-tap
it to lock hands-free. Right Control is the default because, unlike a character
key such as §, a modifier keeps working even while another app has macOS secure
input on; § and other keys are selectable in Settings.

`make dmg` signs ad-hoc by default (no certificate needed). For permissions that
survive rebuilds without re-prompting, create a stable local identity once with
`scripts/make_signing_cert.sh`.

## Developing

The backend runs under uv; the app is a SwiftPM package.

```sh
make gate        # the fast gate: backend pytest + Swift Testing (the meaning of green)
make pipeline    # slow tier: the real MLX models against the voice fixtures (reference machine)
make run         # run from the checkout (needs: cd backend && uv sync --extra models)
make dmg         # build and package the installable app
```

`make run` points the app at the repo's backend via
`WORDFLOW_BACKEND_PYTHON` / `WORDFLOW_BACKEND_DIR`, so it skips provisioning. The
installed app needs none of this: on first run it provisions its own Python
backend into `~/Library/Application Support/WordFlow/runtime` from the bundled uv
binary, and downloads the models once. All user data (history, dictionary,
config, logs) lives in `~/Library/Application Support/WordFlow/data`; copy that
folder to carry your history and dictionary to another Mac.

## Recording the voice fixtures

The latency and accuracy tests run against the user's own voice. Generate the
fixtures once:

```sh
uv run --with sounddevice --with numpy python backend/scripts/record_fixtures.py
```

## Coexistence with Polenta

WordFlow uses port 8770 and its own Application Support folder, distinct from
Polenta's 8765 and its vault, so both apps run at the same time.

## License

WordFlow is free software, released under the **GNU General Public License v3.0
or later** (see [LICENSE](LICENSE)). Copyright (C) 2026 Martin
([github.com/martfo](https://github.com/martfo)).

It bundles third-party language resources under their own terms: the
American-to-British map is derived from the VarCon dataset (see
`backend/wordflow/resources/NOTICE-VarCon.txt`), and the en_GB spelling
dictionary is the SCOWL/Hunspell `en_GB` data (see
`backend/wordflow/resources/dict/`), both redistributable and compatible with
the GPL.
