# Build prompt — Grits, a local dictation app for macOS

You are building this project from scratch in this directory. Read `PRD.md` and
`ACCEPTANCE.md` in full before writing anything else. They are the product requirements and
the acceptance criteria, they were settled through several rounds of review, and they are
not up for renegotiation — where you hit a genuine contradiction or impossibility, stop and
raise it rather than quietly deciding differently.

## What you are building, in one paragraph

A fully local Wispr Flow-style dictation utility ("Grits" is the working name — confirm
naming and logo with the user before any final branding). Hold the § key, speak, release,
and accurate English text appears at the cursor of the frontmost app in under two seconds
for utterances up to 60 seconds. Menu bar app plus a floating pill, no Dock icon. Parakeet
TDT 0.6B via MLX as the primary model, Whisper large-v3-turbo as the alternative,
deterministic cleanup only (no LLM in v1, but the pipeline must be pluggable for a future
LLM stage). Fully offline after a one-time setup download. Self-contained: DMG drag-install,
nothing else installed by hand, movable between Macs.

## The reference codebase: Polenta

The user's Polenta Meeting Notes app lives at:

    /Users/dtrb/Work/Dtrb/Code projects/mieliepap

Study it before designing anything. It is the source of truth for look and feel, tone,
conventions, and architecture. This project must feel like Polenta's sibling. Specifically:

- **Architecture**: SwiftUI app supervising a Python 3.11 FastAPI backend as a child
  process, backend under uv in development, provisioned into Application Support on first
  run in the shipped app. Copy this pattern; reuse the supervision and provisioning code.
- **Conventions to copy**: `DESIGN.md` discipline (see below), `Makefile` with `make gate`,
  tests named by AC id, pytest fast-gate/pipeline-tier markers, Swift Testing for the app,
  `docs/MANUAL_CHECKLIST.md` for `[manual-hardware]` criteria, `build_app.sh` /
  `build_dmg.sh` / `make_signing_cert.sh` style packaging with a local signing certificate.
- **Code to reuse or port**: the British English pass (American-to-British map + en_GB
  Hunspell via spylls, both bundled), the em dash strip and language lint, the SQLite
  storage layer with its migration runner, the keychain helper if needed, and the backend
  logging setup.
- **Look and feel**: match Polenta's typography, spacing, and plain-spoken British English
  copy. Error messages tell the user exactly what is missing rather than failing silently.
- **Coexistence**: Polenta owns port 8765 and its own data folders. Grits must pick a
  different fixed localhost port and its own Application Support directory, and both apps
  must run at the same time.

## Step 0 — repo and DESIGN.md first

Initialise a git repository. Before any feature code, write `DESIGN.md` in Polenta's style:
it pins the decisions the build depends on, and once written it is the source of truth for
the codebase — where it and this prompt differ, reconcile deliberately and keep both in
step. DESIGN.md must pin at least:

- Bundle id, app name, backend port, data folder paths.
- The hotkey mechanism: CGEventTap details, how § is swallowed only when pressed alone
  (modifier combinations pass through), how pause/quit/crash all restore normal typing,
  the ANSI-keyboard fallback to Right ⌘, and secure-input detection.
- Audio capture: AVAudioEngine/CoreAudio at 16 kHz mono, per-dictation stream with the
  stream-starting → listening pill states. No always-on microphone.
- Exact model identifiers and pinned revisions for parakeet-mlx and mlx-whisper
  large-v3-turbo, and the cache layout in Application Support.
- The cleanup pipeline stage interface (ordered, pluggable, per-stage toggles — this is the
  seam the future LLM stage plugs into; see PRD "Forward compatibility").
- The reference machine for latency tests (ask the user which Mac; record it).
- The fixtures plan (below).
- Source tree, mirroring Polenta's layout.

## Build order

Follow the PRD's phases. The definition of done never changes: a feature is complete when
its acceptance-criteria tests pass and `make gate` is still green.

1. **P1 — core loop**: backend with Parakeet resident, hold-§ capture, transcription, paste
   insertion with clipboard restore, menu bar item, mic selection. The app must be usable
   for real daily dictation at the end of P1.
2. **P2 — trust**: floating pill with all states, double-tap lock, Esc cancel, the full
   cleanup pipeline including the British pass, history with retention, onboarding with
   permissions flow and the one-time setup download.
3. **P3 — accuracy flywheel and shipping**: personal dictionary with learning from
   corrections, bake-off and accuracy harness, Whisper turbo alternative, idle unload,
   DMG packaging and signing, new-Mac portability checklist.

At each phase boundary: run the pipeline tier, regenerate `docs/MANUAL_CHECKLIST.md` from
the `[manual-hardware]` criteria for that phase, and hand it to the user to run on real
hardware. Do not mark those criteria done yourself.

## Fixtures — you need the user's voice

Latency and accuracy tests run against recordings of the user (they have an accent and
dictate in English only — that accent is precisely what the tests must cover). Early in P1,
build a small recording harness, generate the fixed 20-sentence reference script, and ask
the user to record: the script, plus utterances of roughly 5, 10, 30, and 60 seconds.
Synthetic fixtures (fillers, American spellings, em dashes, dictionary words, ordering
traps) you create yourself. Fixtures live in `fixtures/`.

## Hard-won constraints — do not rediscover these

Each of these already has an acceptance criterion; they are listed here because each one
was a review finding and the obvious implementation gets it wrong:

- **First-word clipping**: mic start-up (worst on Bluetooth) eats the first word if you
  transcribe from key-down. The pill's listening state must reflect *actual* sample flow,
  and capture must be complete from that moment (AC-1.6).
- **§ semantics**: swallow § alone (including auto-repeat); pass through ⇧§/⌥§/⌘§; a tap
  under 500 ms with no speech discards silently; double-tap within 400 ms locks — get the
  state machine right before polishing anything (AC-1.1–1.3).
- **Secure input blocks event taps entirely** — the hotkey may never fire. Detect secure
  input, explain, recover; never inject into a secure field (AC-4.4).
- **Clipboard restore** must preserve non-text pasteboard contents (images, files), not
  just strings (AC-4.2).
- **Trailing newlines are always stripped** or a dictation into a terminal executes
  (AC-4.7).
- **Dictionary output is protected from later passes** — a taught "Center Parcs" must
  survive the British pass (AC-3.5-b).
- **`HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` pinned in the backend** or Hugging
  Face libraries phone home at model load and the offline guarantee fails (AC-10.2-b).
- **Model switching**: the previous model serves until the new one is fully loaded; never
  swap mid-request (AC-2.3-b).
- **Recording never waits for processing** (Polenta's rule): back-to-back dictations queue
  and insert in spoken order (AC-1.7).
- **The 2 s budget is scoped to ≤ 60 s utterances**; longer lock-mode dictations complete
  with a processing state and no guarantee (AC-2.2).
- **No external binaries anywhere** — no ffmpeg, no shelling out from the pipeline
  (AC-12.2-a). Audio goes app → backend as 16 kHz PCM.

## Working with the user

Work autonomously within the documents. Stop and ask only for: permission grants and
`[manual-hardware]` checklist runs, the fixture recordings, the reference-machine choice,
final naming/branding, and any genuine contradiction you find in the requirements. Report
test results faithfully — if something fails or is flaky, say so plainly. All user-facing
copy in British English, no em dashes, Polenta's voice throughout.
