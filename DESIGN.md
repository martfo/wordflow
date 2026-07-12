# DESIGN.md

This file pins the decisions the build depends on, so the code and the build prompt agree.
It is written before feature code and kept in step with the codebase. Where this file and
`BUILD_PROMPT.md` / `PRD.md` differ, treat this file as the source of truth for the codebase
and reconcile the two deliberately.

WordFlow is the sibling of Polenta Meeting Notes (`~/Work/Dtrb/Code projects/mieliepap`). It
copies Polenta's architecture (a SwiftUI app supervising a Python FastAPI backend), its build
discipline (`make gate`, tests named by AC id, a fast gate and a slow pipeline tier), its
British-English conventions, and its privacy posture. It reuses Polenta's language pass, its
SQLite migration-runner pattern, its provisioning and supervision code, and its packaging
scripts. Where Polenta records meetings and summarises them, WordFlow does one thing: hold a
key, speak, release, and cleaned English text appears at the cursor.

## Scope in one paragraph

A fully local, Wispr Flow-style dictation utility for macOS. Hold the § key, speak, release,
and accurate cleaned English text is inserted at the cursor of the frontmost app in under two
seconds for utterances up to sixty seconds. A menu bar item and a floating pill; no Dock
icon. Parakeet TDT 0.6B via MLX is the primary model, Whisper large-v3-turbo the alternative.
Cleanup is deterministic (no LLM in v1) but built as an ordered, pluggable pipeline so a
future LLM stage slots in. Everything runs on the machine. The only network access is the
one-time first-run download of the backend environment and the models. English only.
Recording never waits for processing: back-to-back dictations queue and insert in spoken
order.

## Platform and versions

- macOS 14.4 or later, Apple Silicon only.
- App: Swift 5 language mode (built with the Swift 6.x toolchain), SwiftUI. Menu bar app via
  `MenuBarExtra`; the pill is a non-activating `NSPanel`. Tests in Swift Testing.
- Backend: Python 3.11. FastAPI, uvicorn, pydantic v2. Tests in pytest, with markers that
  separate the fast gate from the slow `pipeline` tier and the always-skipped `manual` tier.
- Speech-to-text: Parakeet TDT 0.6B v2 via `parakeet-mlx` (primary); Whisper large-v3-turbo
  via `mlx-whisper` (alternative). Both run on MLX on Apple Silicon.
- British English pass: the bundled American-to-British map plus the en_GB Hunspell
  dictionary read through `spylls`. Both bundled for offline use. Ported unchanged from
  Polenta.
- Environment: uv. The backend runs as a supervised child process of the app, provisioned
  into Application Support on first run.

## Naming, identifiers, and ports

- Display name: **WordFlow**.
- Bundle identifier: `co.uk.designturbine.wordflow` (Polenta uses
  `co.uk.designturbine.meetingnotes`).
- Swift executable target: `WordFlowApp`; pure-logic library target: `WordFlowCore`.
- Python package: `wordflow` (run as `python -m wordflow <config.json>`).
- Backend port: **127.0.0.1:8770**, fixed. Deliberately not Polenta's 8765, so both apps run
  at once (AC-11.2). No other localhost service is assumed in v1; the future LLM stage will
  reuse Polenta's LM Studio on 127.0.0.1:1234.
- Local signing identity: `WordFlow Local Signing`.
- Keychain: not used in v1. Parakeet and Whisper are downloaded from public Hugging Face
  repositories with no token, so there is no Hugging Face token to store. The seam is left
  open if a future gated model needs one.

## Data folder layout

Everything WordFlow stores lives under one Application Support tree, distinct from Polenta's
vault (AC-10.3). FileVault provides encryption at rest.

```
~/Library/Application Support/WordFlow/
  runtime/                 provisioned Python (per-Mac, not portable)
    python/                standalone CPython 3.11 fetched by uv
    venv/                  the backend virtualenv
    .provisioned          marker holding runtimeVersion; written only on a complete run
  models/                  Hugging Face cache (per-Mac; HF_HOME points here)
    models.lock.json       resolved model repo + commit revisions, written by the downloader
  data/                    THE PORTABLE FOLDER — copy this between Macs (AC-12.5)
    index.sqlite           history and dictionary-link store (WAL)
    config.json            backend config (below)
    dictionary.txt         the personal dictionary, plain and human-editable
    fillers.txt            the editable filler-word list
    logs/                  backend.log and backend.jsonl, rotating
    audio/                 debug only: kept dictation audio when "keep audio" is on
```

`runtime/` and `models/` are rebuilt on a new Mac by provisioning and the model download.
`data/` is the only folder the user ever needs to carry across, and it holds no audio unless
the debug toggle is on.

## Provisioning and the backend runtime

Copied from Polenta's proven mechanism (its AC-3.1-e), adapted to the WordFlow layout:

- On first run the app provisions the backend into `runtime/`: a bundled `uv` binary fetches
  a standalone CPython 3.11 into `runtime/python`, creates `runtime/venv`, and installs the
  backend package that ships inside the app bundle at `Contents/Resources/backend` with its
  MLX extras. A `.provisioned` marker holding `runtimeVersion` is written only after a
  complete run, so a partial install is always detected and run over.
- `RuntimeInstalling` is a protocol with `fetchPython`, `createEnvironment`,
  `installDependencies`, `verifyBackendStarts`; the real implementation shells out to the
  bundled uv, and tests inject a fake to drive every outcome without a network. `Provisioner`
  runs the four steps in order and is idempotent. `runtimeVersion` starts at `"1"` and is
  bumped on any breaking runtime change (a changelog lives in `Provisioner.swift`).
- `BackendSupervisor` launches `python -m wordflow <config.json>`, health-checks `/health`
  every three seconds, replaces an orphan holding the port at startup (lsof + SIGTERM), and
  restarts the backend if it dies (AC-11.1). The backend runs a parent-watchdog thread and
  exits if reparented to launchd, so quitting the app never orphans Python (AC-11.4).
- In development the app finds the interpreter via `WORDFLOW_BACKEND_PYTHON` and the package
  via `WORDFLOW_BACKEND_DIR`, exactly as Polenta uses its own env vars.

## The hotkey: CGEventTap, the § key, and its state machine

The hotkey is the highest-risk subsystem. It is a `CGEventTap`, not Carbon's
`RegisterEventHotKey` (which Polenta uses for a modifier chord). A tap is required because the
default key, §, is a plain key with no modifier, and it must be *swallowed* while dictation is
active so it never types a character.

- **Tap**: an active (not listen-only) `CGEventTap` at `kCGSessionEventTapLocation`, on
  `keyDown`, `keyUp`, and `flagsChanged`. Active taps that consume events need the
  Accessibility permission. Returning `nil` from the callback swallows the event; returning it
  unchanged passes it through. The tap is re-enabled automatically if the system disables it
  for timeout.
- **The § key** is virtual keycode `0x0A` (`kVK_ISO_Section`) on ISO/UK keyboards.
- **Swallow-alone semantics** (AC-1.1-c, AC-1.1-d): a § `keyDown`/`keyUp` with none of
  Command, Option, Control, Shift held is consumed (including auto-repeat `keyDown`s) and
  drives dictation. § pressed with any of those modifiers is passed through unchanged and does
  **not** start dictation, so ⇧§, ⌥§, ⌘§ type as normal. To type a literal lone §, the user
  pauses dictation from the menu bar, which removes the tap.
- **Restoring normal typing** is automatic: the key is only ever swallowed by our own live
  tap. Pause removes the tap; Quit removes it; a crash tears down the process and with it the
  tap. There is nothing to "restore" — § types normally the instant the tap is gone
  (AC-1.1-c).
- **ANSI fallback** (AC-1.5-c): on a keyboard with no § key the default hotkey is Right ⌘,
  detected via `flagsChanged` events carrying keycode `0x36` (`kVK_RightCommand`) with the
  right-command device mask, so Left ⌘ is unaffected. Keyboard layout is probed at launch via
  the current `TISInputSource`; the presence of a § key decides the default.
- **Configurable** (AC-1.5): the hotkey is stored in `UserDefaults`
  (`hotkeyKeyCode`, `hotkeyKind`) and can be set to §, Right ⌘, fn (Globe), or F5. A change
  takes effect immediately by rebuilding the tap; the choice persists across restarts.
- **Secure input** (AC-4.4): when `IsSecureEventInputEnabled()` is true, macOS suppresses the
  tap's key events entirely, so the hotkey cannot fire. A one-second poll detects secure input,
  the pill/menu bar says plainly that dictation is unavailable and why, and normal service
  resumes automatically when secure input ends. Nothing is ever injected into a secure field.

### The press state machine (`HotkeyStateMachine`, in WordFlowCore, clock-injected, unit-tested)

Inputs are `keyDown`, `keyUp` (auto-repeat `keyDown`s are ignored for state), and a timer
tick; the clock is injected so the whole machine is tested without hardware. States: `idle`,
`arming` (capture requested, samples not yet flowing), `listening` (held), `locked`,
`processing`. Emitted commands: `startCapture`, `stopAndTranscribe`, `discardSilently`,
`enterLocked`, `cancel`.

- **Hold-to-talk**: `keyDown` from `idle` → `startCapture`, enter `arming`; the pill shows
  stream-starting, then `listening` once the audio callback delivers its first samples
  (AC-1.6). `keyUp` after a hold of **≥ 500 ms** → `stopAndTranscribe`.
- **Accidental tap** (AC-1.2-a): `keyUp` after **< 500 ms**. Capture is stopped but the audio
  and a 400 ms decision window are held. If no second `keyDown` arrives and no speech was
  detected in the buffer, `discardSilently` (no transcription, no insertion, no history). If
  speech *was* detected, the short utterance is transcribed normally.
- **Double-tap to lock** (AC-1.3-a): a second `keyDown` within **400 ms** of the tap's `keyUp`
  → `enterLocked`; the pill shows the locked state and capture continues hands-free.
- **Single tap while locked** (AC-1.3-b): any `keyDown`/`keyUp` in `locked` →
  `stopAndTranscribe`.
- **Esc** (AC-1.4): while `arming`/`listening`/`locked`, Esc → `cancel`: capture stops,
  nothing is transcribed or inserted, no history entry, the pill disappears. The tap watches
  for Esc (keycode `0x35`) only while recording and does not swallow it otherwise.
- **Locked screen** (AC-1.8): while the session is locked the tap is inert; no capture starts.

## Audio capture

- `AVAudioEngine` input tap → linear-interpolation resample to **16 kHz mono** float → append
  to a running buffer. Ported from Polenta's `CaptureController`/`AudioMixer`/`LevelMeter`,
  reduced to a single microphone channel (no system-audio tap). No always-on microphone: the
  engine is started per dictation and torn down on stop.
- The pill's `listening` state is driven by the *first real audio buffer*, not by key-down, so
  the first word is never clipped (AC-1.6), worst case a Bluetooth mic's start-up delay. The
  buffer is complete from that first callback onwards.
- On stop the buffer is serialised to a minimal 16-bit PCM WAV (`AudioMixer.wavData`) and sent
  to the backend as base64 in the `/transcribe` request. No file is written for the normal
  path; audio only touches disk when "keep audio" debug mode is on. No external binary is ever
  spawned (AC-12.2): capture is native Core Audio, and the WAV is built in Swift.
- Microphone selection mirrors Polenta: `InputDevice.allWithDefault()` lists devices plus
  "Follow system default" (the default); `MicrophonePreference` persists the choice;
  `MicrophoneSelection.choose` re-selects the remembered device after a device-list change and
  falls back to the system default when a pinned device disappears (AC-7.3), posting a menu bar
  notice. A live level meter (`LevelMeter.level`) confirms the mic before recording (AC-7.2).

## Text insertion

`TextInserter` (in WordFlowApp) inserts the cleaned transcript at the cursor of the frontmost
app:

- **Primary path**: the Accessibility API. Get the focused UI element
  (`kAXFocusedUIElementAttribute`) and set/replace the selected text
  (`kAXSelectedTextAttribute`), so text lands at the caret, not appended (AC-4.1).
- **Fallback path**: synthesise ⌘V after placing the text on the pasteboard. The prior
  pasteboard contents are saved and restored across *all* representation types (images, files,
  RTF), not just strings (AC-4.2), by archiving every `NSPasteboardItem`.
- **No focused field** (AC-4.3): the transcript is left on the clipboard and the pill says so
  plainly.
- **Secure field**: never inject (AC-4.4); insertion is refused while secure input is active.
- **Trailing newline** is always stripped from inserted text, so dictating into Terminal never
  executes it (AC-4.7). History keeps the untrimmed cleaned text.
- Every dictation lands in History regardless of insertion outcome, so a swallowed paste is
  recoverable (AC-4.6).

## Back-to-back dictations and ordering

Recording never waits for processing (the Polenta rule). Each release hands its audio to the
backend at once and a new dictation can start immediately (AC-1.7). The backend transcribes on
a single FIFO worker, so completions come back in submission order, which is spoken order. The
app's `InsertionQueue` (WordFlowCore, unit-tested) holds in-flight dictations and inserts each
result strictly in submission order, each at the frontmost app's cursor at its own insertion
time.

## Backend: models, loading, and the ASR engine

- **Engine interface** `ASREngine`: `load()`, `transcribe(pcm16k) -> str`, `unload()`,
  `is_loaded`. Two implementations: `ParakeetEngine` (`parakeet-mlx`) and `WhisperEngine`
  (`mlx-whisper`). A `ModelManager` holds the active engine, keeps it resident, and mediates
  switching and idle unload.
- **Model identifiers** (pinned):
  - Parakeet: repo `mlx-community/parakeet-tdt-0.6b-v2`.
  - Whisper: repo `mlx-community/whisper-large-v3-turbo`.
  - Exact commit revisions are resolved and written to `models/models.lock.json` by the
    onboarding downloader at first download; the engines load that pinned revision thereafter.
    Until a machine has downloaded, the lock is absent and only the downloader (which lifts the
    offline flags) may reach the network.
- **Level normalisation**: captured audio is peak-normalised to ~0.95 in the engine, after the
  silence gate, before the model runs. Quiet capture (a distant or low-gain mic, or AirPods
  input) otherwise loses the attack of consonants and the model mishears them ("brown" heard
  as "round"); normalising recovers them, with the gain capped so a near-silent buffer is not
  amplified into noise. Applied in both engines so live, bake-off, accuracy, and pipeline paths
  preprocess identically.
- **No ffmpeg** (AC-12.2): `parakeet-mlx`'s own `transcribe(path)` shells out to ffmpeg to
  load audio, and `mlx-whisper` does the same when given a path. WordFlow never gives either a
  path: the backend already holds decoded 16 kHz mono PCM, so `ParakeetEngine` feeds the
  model's front end directly (`get_logmel` then `generate`, the same path `transcribe` takes
  minus the file load) and `WhisperEngine` passes the sample array to `mlx_whisper.transcribe`.
  So the pipeline spawns no external binary and the shipped app needs no ffmpeg.
- **Resident at launch** (AC-2.1): the active model is loaded during startup warm-up, so the
  first dictation carries no lazy-load penalty. `/health` reports `model_loaded` and
  `active_model`.
- **Switching** (AC-2.3): selecting a new model loads it in the background; the previous model
  keeps serving until the new one is fully loaded, and the swap happens between dictations,
  never mid-request. No dictation is lost.
- **Idle unload** (AC-2.4): with `idle_unload_minutes > 0`, the model is unloaded after that
  idle period (backend RSS drops); the next dictation reloads it, the pill showing a loading
  state rather than failing.
- **Offline pinned** (AC-10.2): the backend process runs with `HF_HUB_OFFLINE=1` and
  `TRANSFORMERS_OFFLINE=1` set in `__main__` before any HF import, and `HF_HOME` pointed at
  `models/`. Only the onboarding downloader clears the two flags, for the duration of the
  download alone.

## Cleanup pipeline (deterministic, pluggable)

An ordered list of stages behind one interface, each with its own toggle (AC-3.4, AC-3.6). The
seam the future LLM stage plugs into.

```
CleanupStage (Protocol):
    key: str                         # stable id, used for the settings toggle
    def apply(self, doc: CleanupDoc) -> CleanupDoc
```

`CleanupDoc` carries the working text plus a set of **protected spans**. A stage that produces
a canonical form (the dictionary) marks its output spans protected; later stages skip
protected spans (AC-3.5-b). The registry is an ordered list; a dummy stage can be inserted at
any index and is applied in order with no change to the others (AC-3.6-a). A stage that raises
is skipped with a logged warning and the rest of the pipeline still runs (AC-3.6-b).

Pinned order (AC-3.5-a) — the PRD order:

1. `punctuation` — light normalisation of the model's already-punctuated, already-capitalised
   output: trim, collapse runs of whitespace, ensure the first letter is capitalised and the
   text ends with terminal punctuation. Never rewrites words.
2. `filler` — strips a conservative, editable list (`um`, `uh`, `er`, `erm`, and `you know` as
   an interjection) from `fillers.txt`, preserving sentence structure (AC-3.1).
3. `dictionary` — the personal-dictionary correction pass; its replacements are marked
   protected (AC-3.5-b).
4. `british` — the em-dash-free American-to-British conversion (`convert_to_british`), skipping
   protected spans and code spans, plus the read-only Hunspell flag (AC-3.2).
5. `emdash` — `strip_em_dashes` last (AC-3.3).

Both the raw model transcript and the final cleaned text are returned and stored (AC-6.1-c),
so the future LLM stage can be evaluated against real past dictations.

## Personal dictionary

- Stored as `data/dictionary.txt`, plain and human-editable (AC-5.3). One entry per line:
  `canonical` on its own, or `canonical = hint1, hint2` where hints are "sounds-like"
  phrases. Lines beginning `#` are comments. External edits are picked up on the next dictation
  (the file mtime is checked; at most an app restart is ever needed).
- **With a sounds-like hint** (AC-5.1-a): the hint phrase is matched (case-insensitively,
  across word boundaries) in the transcript and replaced with the canonical form
  (`melly pap` → `mieliepap`).
- **Without hints** (AC-5.1-b): only near-misses are corrected, defined exactly as case
  differences or hyphen/space/punctuation variants of the canonical form
  (`mielie pap`, `Mieliepap` → `mieliepap`). Anything fuzzier needs a hint.
- **Learning from corrections** (AC-5.2): when the user edits a history entry and the change is
  a single word-level fix, the app offers "Always transcribe X as Y?"; accepting appends a
  dictionary entry (with X as a sounds-like hint) and records the source dictation; declining
  applies the one-off edit only.
- **Cross-links** (AC-5.5, AC-8.3-c): a learned entry stores `source_dictation_id`; the entry
  opens its source dictation, and a corrected dictation shows which entry it produced.

## History and SQLite schema

SQLite at `data/index.sqlite`, opened WAL, with the same append-only migration runner as
Polenta (`PRAGMA user_version`). Audio is deleted immediately after transcription; only text
is kept, default retention 90 days (AC-6.3, AC-6.4).

Migration 1 (the P1 schema, extended through P2/P3 by append-only migrations):

- `dictations(id INTEGER PK, created_at TEXT, target_app TEXT, target_bundle_id TEXT,
  model TEXT, raw_text TEXT, cleaned_text TEXT, char_count INTEGER, inserted INTEGER,
  audio_path TEXT)` — `raw_text` is the model output before cleanup, `cleaned_text` the final
  inserted text (AC-6.1). `audio_path` is set only when keep-audio is on (AC-6.4-b).
- `dictionary_entries(id INTEGER PK, canonical TEXT, hints TEXT, enabled INTEGER,
  created_at TEXT, source_dictation_id INTEGER REFERENCES dictations(id))` — mirrors
  `dictionary.txt`; the file is the source of truth and this table carries the link
  provenance. `hints` is a JSON array.
- `settings(key TEXT PRIMARY KEY, value TEXT)` — overrides for `text_retention_days`,
  `keep_audio`, `active_model`, `idle_unload_minutes`, and the cleanup toggles, so the app
  tunes them without rewriting config.json (Polenta's pattern).

Only completed dictations are recorded; cancelled (Esc) and silently-discarded taps write
nothing (AC-6.1-b). Search is a `LIKE` over `cleaned_text` and `raw_text` (AC-6.2).

## config.json

```json
{
  "data_path": "/Users/martin/Library/Application Support/WordFlow/data",
  "backend_port": 8770,
  "active_model": "parakeet",
  "models": {
    "parakeet": "mlx-community/parakeet-tdt-0.6b-v2",
    "whisper": "mlx-community/whisper-large-v3-turbo"
  },
  "idle_unload_minutes": 0,
  "text_retention_days": 90,
  "keep_audio": false,
  "cleanup": { "punctuation": true, "filler": true, "dictionary": true,
               "british": true, "emdash": true },
  "log_level": "info"
}
```

`idle_unload_minutes` of 0 means never unload. The editable filler list lives in
`data/fillers.txt`, seeded from a bundled default, not in config.json, so it is as
human-editable as the dictionary.

## API surface (127.0.0.1:8770)

Injected `AppState` (Polenta's pattern) so tests run the real app against a temp data folder
and a fake engine.

- `GET /health` → `{status, active_model, model_loaded, loading, queued, secure_input?}`.
- `POST /transcribe` `{audio_base64, sample_rate, target_app, target_bundle_id, locked}` →
  `{dictation_id, raw, text, nothing_heard}`. Runs the model then the cleanup pipeline, writes
  history (unless `nothing_heard`), returns the text for the app to insert. FIFO worker.
- `GET /history`, `GET /history?q=`, `GET /history/{id}`, `DELETE /history/{id}`,
  `POST /history/clear`.
- `POST /history/{id}/correct` `{text}` → applies the edit, returns a dictionary-entry offer
  when the change is a single word-level fix (AC-5.2).
- `GET/PUT /dictionary`, `POST /dictionary` (add), `DELETE /dictionary/{id}`.
- `GET/PUT /settings`, `GET/PUT /cleanup`, `GET/PUT /fillers`.
- `POST /model` `{name}` → background switch (AC-2.3).
- `POST /bakeoff`, `POST /accuracy` (P3): transcribe the same audio on each installed model and
  score WER against the reference script, storing runs.

## Reference machine and latency

The latency acceptance criteria (AC-2.2) are measured on the pinned reference machine:

> **Mac Studio, M3 Ultra.**

Budgets (release-equivalent to text-ready), scoped to utterances ≤ 60 s: ≤ 1 s for a 10 s
utterance, ≤ 2 s for 30 s and 60 s. Longer dictations complete with a processing state and no
guarantee (AC-2.2-d). Latency tests live in the `pipeline` tier and run at phase boundaries on
that machine; the fast gate never runs the real model.

## Fixtures plan

Fixtures live in `fixtures/`, created before the features that use them (ACCEPTANCE.md).

- **User-voice audio** (`fixtures/audio/`, git-ignored, recorded locally by the user): the
  fixed 20-sentence reference script read aloud (`reference_script.wav`) and single utterances
  of roughly 5, 10, 30, and 60 seconds (`utt_5s.wav` … `utt_60s.wav`), plus a first-word test
  (`first_word.wav`). A small in-app recording harness / `backend/scripts/record_fixtures.py`
  captures them at 16 kHz mono. The accent is deliberately the user's own, because that is what
  the accuracy tests must cover. These are what the `pipeline`-tier latency and WER tests run
  against.
- **The reference script** (`fixtures/reference_script.txt`): the fixed 20 sentences, checked
  in, generated once and never changed so WER runs are comparable over time.
- **Synthetic text fixtures** (`fixtures/cleanup/`, checked in, authored by the build): JSON
  cases of `{raw, expected}` for fillers, American spellings, em dashes, dictionary targets,
  and an ordering trap whose correct output depends on the pinned pass order. These drive the
  fast-gate cleanup tests and need no audio.

## Source tree

```
wordflow/                    (this repository)
  DESIGN.md
  README.md
  Makefile                   make gate runs the fast gate
  docs/MANUAL_CHECKLIST.md   the [manual-hardware] checklist
  app/
    Package.swift
    Sources/
      WordFlowApp/           menu bar, pill, settings, onboarding, supervisor, client,
                             CGEventTap, capture, insertion
      WordFlowCore/          pure logic: hotkey state machine, insertion queue, audio WAV,
                             level meter, mic preference, provisioner, permission state
    Tests/WordFlowCoreTests/ named by AC id
    Support/                 Info.plist, WordFlow.entitlements, AppIcon
  backend/
    pyproject.toml
    scripts/                 build_british_map.py (from Polenta), make_fixtures.py,
                             record_fixtures.py, download_models.py
    wordflow/
      __main__.py            python -m wordflow <config.json>; pins offline flags
      config.py
      api/app.py             FastAPI surface
      asr/                   base engine, parakeet, whisper, manager, fake (for tests)
      cleanup/               pipeline, doc, stages (punctuation, filler, dictionary,
                             british, emdash)
      language/              british.py, emdash.py, flag.py, lint.py  (ported from Polenta)
      dictionary/            store (file <-> table), apply pass, learning
      history/              store, retention
      storage/               db.py (migration runner), paths.py
      logging/setup.py       (ported from Polenta)
      resources/             american_to_british.json, technical_allowlist.txt, dict/en_GB,
                             NOTICE-VarCon.txt, fillers.txt default
    tests/
      unit/                  fast gate, named by AC id
      pipeline/              slow: real MLX models on the reference machine
      manual/                always-skipped placeholders for the checklist
      conftest.py
  fixtures/
    reference_script.txt
    cleanup/                 synthetic text fixtures
    audio/                   user-voice recordings (git-ignored)
  scripts/                   build_app.sh, build_dmg.sh, make_signing_cert.sh
```

## Packaging and portability

Follows Polenta's scripts, renamed for WordFlow:

- `scripts/build_app.sh` assembles `dist/WordFlow.app` from the SwiftPM release build,
  `Support/Info.plist` (carrying `NSMicrophoneUsageDescription` and `LSUIElement` for the
  no-Dock menu bar app), the bundled language resources, the backend copy, and the uv binary,
  then signs inside out with the local identity `WordFlow Local Signing` and
  `Support/WordFlow.entitlements`. `SKIP_SIGNING=1` leaves it unsigned for test builds.
- `scripts/build_dmg.sh` stages the app, an Applications symlink, and a short read-me with the
  right-click-Open step, then builds `dist/WordFlow.dmg` with hdiutil. Model weights never
  ship in the dmg.
- `scripts/make_signing_cert.sh` is the one-off that creates the local identity. A stable
  identity keeps Microphone and Accessibility permissions across rebuilds (AC-12.3-b).
- Entitlements: `com.apple.security.device.audio-input` and
  `com.apple.security.cs.disable-library-validation` (MLX loads dynamic libraries). Not
  sandboxed. Accessibility is a TCC grant, not an entitlement.
- No ffmpeg, no Homebrew, no system Python, no uv on the target machine (AC-12.1): audio is
  captured and encoded natively, and the backend is provisioned from the bundled uv plus the
  one-time download.

## Definition of done

`make gate` runs every fast-gate test (backend `pytest -m "not pipeline and not manual"` plus
the Swift Testing suite) and is the single meaning of green. The `pipeline` tier runs at phase
boundaries on the reference machine. `docs/MANUAL_CHECKLIST.md` is regenerated from the
`[manual-hardware]` criteria at each phase boundary and run by a person on real hardware; those
criteria are never marked done from here. A feature is complete when its acceptance-criteria
tests pass and the fast gate is still green.

## Build order

Per the PRD's phases:

1. **P1 — core loop**: backend with Parakeet resident, hold-§ capture, transcription, paste
   insertion with clipboard restore, menu bar item, mic selection. Usable for daily dictation
   at the end of P1.
2. **P2 — trust**: floating pill with all states, double-tap lock, Esc cancel, the full
   cleanup pipeline including the British pass, history with retention, onboarding with the
   permissions flow and the one-time setup download.
3. **P3 — accuracy flywheel and shipping**: personal dictionary with learning from
   corrections, bake-off and accuracy harness, Whisper turbo alternative, idle unload, DMG
   packaging and signing, new-Mac portability checklist.
