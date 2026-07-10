# PRD — Local Dictation App (working name: "Grits", sibling of Polenta)

A fully local, Wispr Flow-style dictation utility for macOS. Hold a key, speak, release, and
accurate English text appears at the cursor in whatever app you are using — in under two
seconds. Nothing leaves the machine. Built in the image of Polenta Meeting Notes: same visual
language, same architecture pattern, same privacy posture.

## Problem

Typing is the bottleneck. Cloud dictation tools (Wispr Flow, Apple's server-side modes) are
fast and accurate but send audio off-device. Apple's built-in local dictation is weak on
accented English and clumsy to invoke. The user dictates in English with an accent and needs
accuracy comparable to the best cloud tools, entirely offline.

## Goals

1. Dictate into any macOS app at the cursor position, triggered by a global hotkey.
2. Text available within **2 seconds** of releasing the key (hard budget; target well under 1 s).
3. Best-in-class local English accuracy, robust to accented speech.
4. 100% local at runtime. Network is used only for the one-time setup download (backend
   environment and models).
5. Look and feel consistent with Polenta Meeting Notes.

## Non-goals

- Languages other than English; translation.
- Streaming live text while speaking (accuracy-first, transcribe on release).
- LLM rewriting/tone adjustment (Wispr Flow's "AI edits") in v1. Light deterministic cleanup
  only — but the design must leave room for a later LLM stage (see Future builds).
- Meeting/system-audio capture — that is Polenta's job. This app captures the microphone only.
- Windows/Linux, Intel Macs.

## Target platform

macOS 14.4+, Apple Silicon (same as Polenta).

## Core experience

1. User holds the **§ key** (default; configurable) and speaks. A small floating pill
   appears near the bottom of the screen: first a brief stream-starting state, then a
   **listening** state with a live mic level once audio is actually flowing — so the user
   knows exactly when the mic is hot and when to start speaking. The mic is opened per
   dictation, never kept always-on.
2. User releases the key. The pill switches to a brief processing state.
3. Within the latency budget, cleaned text is inserted at the cursor of the frontmost app.
4. **Double-tap the hotkey** to lock hands-free dictation for long passages; tap once to stop.
5. Pressing **Esc** while recording cancels — nothing is transcribed or inserted.

### Hotkey

- Default: hold **§** (top-left on ISO/UK keyboards). While dictation is active the app's
  event tap swallows the key, so it never types a character; § with a modifier (⇧§, ⌥§, ⌘§)
  passes through unchanged. To type a literal §, pause dictation from the menu bar.
- On a keyboard without § (ANSI layouts), the default falls back to Right ⌘.
- Configurable in settings to another key (e.g. Right ⌘, fn, F5).
- Hold-to-talk and double-tap-to-lock both supported; behaviour mirrors Wispr Flow.

### Edge behaviour

- **Back-to-back dictations**: recording never waits for processing (the Polenta rule). A
  new dictation can start while the previous one transcribes; transcriptions complete and
  insert in spoken order, each at the cursor position at its own insertion time.
- **Nothing heard**: silence, a breath, or a cough inserts nothing — a brief pill notice,
  no history entry.
- **Locked screen**: the hotkey is inert while the screen is locked; no audio is captured.
- **Secure input** (password fields): macOS may block the event tap entirely, so the hotkey
  may not fire at all. The app detects secure input, says plainly that dictation is
  unavailable and why, and resumes automatically when secure input ends. Nothing is ever
  injected into a secure field.

### Text insertion

- Inserted at the cursor of the frontmost app via the Accessibility API, with
  clipboard-paste injection as the fallback path (clipboard contents saved and restored).
- If no text field has focus, the transcript is placed on the clipboard and the pill says so.
- Inserted text never carries a trailing newline, so dictating into a terminal never
  executes the text.
- Every dictation also lands in History, so a swallowed paste is never lost.

## Speech-to-text

- **Primary model: Parakeet TDT 0.6B v2** via MLX — currently the top-ranked open English
  ASR model, strong on accented speech, ~30–60× real-time on Apple Silicon.
- **Alternative: Whisper large-v3-turbo** via MLX, selectable in settings for A/B comparison.
- The model is loaded at app launch and kept resident, so per-dictation latency is inference
  only.
- **First-run bake-off**: onboarding has the user dictate a few test sentences and shows both
  models' transcripts side by side, so the model choice is made on the user's own voice, not
  leaderboards.
- **Accuracy harness**: the same machinery scores each model's word error rate against a
  fixed 20-sentence reference script read in the user's voice, re-runnable any time from
  Settings → Model, with results stored so runs are comparable over time.
- Audio captured at 16 kHz mono from the selected input device.

### Latency budget (release → text inserted, 10 s utterance)

| Stage                       | Budget      |
|-----------------------------|-------------|
| Audio finalise + handoff    | ≤ 100 ms    |
| Transcription (Parakeet)    | ≤ 600 ms    |
| Cleanup passes              | ≤ 100 ms    |
| Insertion                   | ≤ 200 ms    |
| **Total**                   | **≤ 1 s typical, 2 s hard ceiling** |

The budget applies to utterances of **up to 60 seconds** of speech. Longer dictations
(locked hands-free mode) still complete — the pill shows a processing state until the text
is inserted — but carry no latency guarantee.

## Cleanup (deterministic — no LLM)

Applied in order, each pass individually toggleable in settings:

1. Model punctuation and capitalisation (native to both models).
2. Filler-word strip: um, uh, er, "you know" as an interjection — conservative list, editable.
3. **Personal dictionary pass** (below). Words the dictionary corrects are protected from
   all later passes, so a taught spelling ("Center Parcs") is never re-corrected by the
   British pass.
4. **British English pass**: reuse Polenta's bundled American-to-British map and en_GB
   Hunspell dictionary (spylls).
5. Em-dash strip, matching Polenta's language conventions.

No LM Studio dependency in v1. Self-corrections ("no, I mean Tuesday") are inserted as heard
for now — handling them is the flagship feature of the planned LLM stage (see Future builds).

### Forward compatibility with a future LLM stage

The cleanup pipeline is built as an **ordered list of pluggable stages behind one interface**
(transcript in, transcript out, each with its own settings toggle), so a future LLM stage
slots in without reworking the existing passes. Two v1 requirements exist purely to serve
that future:

- History stores **both the raw model transcript and the final cleaned text** for every
  dictation, so a future LLM stage can be evaluated against real past dictations before it
  is trusted live.
- The Settings → Cleanup section is a list that accommodates new stages, not a fixed set of
  switches.

## Personal dictionary

- An editable list of words/phrases (names, jargon: Dtrb, mieliepap, client names) with
  optional "sounds-like" hints, applied as a post-transcription correction pass.
- **Learning from corrections**, Polenta-style: in History, the user can correct any
  transcript; corrections that look like word-level fixes are offered as dictionary entries
  ("Always transcribe *melly pap* as *mieliepap*?"). Teach once, fixed forever.
- Dictionary stored as a plain human-editable file in the app's data folder.

## History

- Searchable list of past dictations: text, timestamp, target app, model used.
- Retention configurable (default 90 days for text). **Audio is deleted immediately after
  transcription** — only text is kept. Optional "keep audio" debug toggle, off by default.
- Per-entry actions: copy, correct (feeds the dictionary), delete. "Clear all" in settings.
- Stored locally in SQLite in the app's data folder, following Polenta's storage conventions.

## Microphone selection

- Settings dropdown listing all input devices, plus a "Follow system default" option
  (the default), with a live level meter to confirm the right mic before relying on it.
- If the selected device disappears (e.g. headset unplugged), fall back to the system default
  and surface a menu bar notice rather than failing silently.

## App presence & UI

- **Menu bar item** (no Dock icon): idle/recording/processing states, quick model and mic
  switchers, pause dictation, open Settings/History, quit.
- **Floating pill**: appears only while recording/processing; mic level animation; positioned
  bottom-centre; click to cancel.
- **Settings window**: styled to match Polenta — same typography, spacing, British English
  copy, plain-spoken error messages ("the app tells you what is missing rather than failing
  silently"). Sections:
  - **General** — hotkey, hold/lock behaviour, launch at login.
  - **Microphone** — device picker, follow-system-default, level meter.
  - **Model** — Parakeet/Whisper choice, re-run bake-off, idle unload.
  - **Cleanup** — toggles for each cleanup pass.
  - **Dictation data** — History and the Personal Dictionary together in one section,
    because they feed each other: correcting a history entry offers a dictionary entry, and
    each entry learned that way links back to the dictation that taught it, so you can jump
    between the two in either direction. Retention and clear-all live here too.
- Menu bar shortcuts open Settings directly at the relevant section (e.g. "History…" opens
  Dictation data).
- Launch at login (on by default, asked during onboarding).

## Onboarding (first run)

1. Welcome; explain the two permissions before asking: **Microphone** and **Accessibility**
   (for global hotkey + insertion). Each is requested at the moment it is needed, with a
   plain explanation, mirroring Polenta's permissions approach.
2. One-time setup download (the only network access the app ever performs): the backend
   environment is provisioned into Application Support and the models are fetched, with
   size and progress shown.
3. Mic check with level meter.
4. Model bake-off on the user's own voice; pick the winner.
5. Try-it playground: a text field to practise hold-to-talk before it goes system-wide.

## Privacy

- No network access at runtime; only the first-run setup download (backend environment and
  models). Verifiable by running with networking off after setup.
- Audio never persisted beyond transcription (unless debug toggle on). Text history is local,
  encrypted at rest via FileVault, per the Polenta model.
- No analytics, no accounts, no telemetry.

## Architecture (Polenta pattern)

- **App**: Swift 5.9+, SwiftUI. Menu bar app via `MenuBarExtra`; floating pill as a
  non-activating panel. Global hotkey via a CGEventTap (Accessibility). Tests in Swift Testing.
- **Backend**: Python 3.11, FastAPI + uvicorn on 127.0.0.1 (port TBD, not 8765 — must
  coexist with Polenta), run under uv in development and provisioned into Application
  Support on first run in the shipped app (Polenta's mechanism — no system Python needed),
  supervised child process of the app exactly as in Polenta. Hosts MLX models (parakeet-mlx, mlx-whisper), cleanup passes, dictionary, history
  store. Tests in pytest with fast-gate/slow-tier markers. The backend runs with
  `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` pinned, so Hugging Face libraries never
  phone home at model load; only the onboarding downloader lifts the flag, for the duration
  of the download alone.
- **Repo layout, Makefile `make gate`, DESIGN.md discipline**: copy Polenta's conventions.
- Memory: ~1.5–2 GB resident with Parakeet loaded. Settings option to unload the model after
  N minutes idle (cold start then ~2–3 s, clearly a trade-off the user opts into).

## Distribution and portability

Install is: mount the .dmg, drag the app to Applications, right-click Open once. Nothing
else is ever installed by hand — no Homebrew, no ffmpeg, no Python, no uv on the machine:

- Audio is captured natively at 16 kHz via AVAudioEngine/CoreAudio, so unlike Polenta there
  is no ffmpeg dependency at all.
- On first run the app provisions the Python backend into Application Support using the
  provisioner bundled inside the app — Polenta's proven mechanism (its AC-3.1-e), which
  works on a Mac with no Python installed.
- Models are downloaded once by the onboarding downloader into Application Support.

These first-run downloads — backend environment and models — are the only network access
the app ever performs, and the only exception to "drag and go".

**Moving between Macs**: copy the .dmg (or the app) to the second Mac; first launch re-runs
permissions, provisioning, and the model download. History and the personal dictionary are
plain files in the app's data folder — copy that folder across and they come with you.

**Signing and packaging** follow Polenta's conventions: build_app.sh/build_dmg.sh-style
scripts, a local signing certificate, `codesign --verify --deep --strict` green, and the
right-click-Open-once flow on a Mac that has never seen the app.

The only external application this project will ever assume is **LM Studio**, and only for
the future LLM cleanup stage — acceptable because it is already a Polenta prerequisite on
the same machine. v1 assumes nothing is installed.

## Success criteria

Detailed, testable acceptance criteria live in [ACCEPTANCE.md](ACCEPTANCE.md), following
Polenta's convention: tests are named by AC id, and criteria needing a real Mac are marked
`[manual-hardware]`. The headline measures:

1. Release-to-inserted-text ≤ 2 s for a 30 s utterance; ≤ 1 s for a 10 s utterance (M-series).
2. Word error rate on the user's own voice noticeably better than Apple local dictation on a
   fixed 20-sentence test script (measured in the bake-off harness, re-runnable any time).
3. Dictionary words transcribe correctly 100% of the time once taught.
4. Insertion works in: Mail, Safari/Chrome text areas, Slack, VS Code, Terminal, Notes.
5. Runs for a week without restart; mic switch and device-unplug handled without a hang.
6. With networking disabled, every feature works.

## Risks

- **§ as the hotkey** exists only on ISO (UK/European) keyboards; on ANSI layouts the
  default falls back to Right ⌘. Because the key is swallowed by the app's own event tap
  rather than a system setting, a crash automatically returns § to normal typing — there is
  nothing to restore.
- **Mic start-up delay** (worst on Bluetooth mics) could clip the first word. Mitigation:
  the pill's explicit listening state tells the user when audio is flowing; the mic is
  opened per dictation rather than kept always-on, by design.
- **Parakeet on the user's accent**: leaderboard ≠ this voice. Mitigation: bake-off is a
  first-class feature; Whisper large-v3-turbo one click away.
- **Insertion edge cases** (secure input fields, some Electron apps): fall back to clipboard
  with a clear pill message; History guarantees nothing is lost.
- **Port/resource clashes with Polenta** running simultaneously: distinct port, distinct data
  folder, both apps tested side by side.

## Phasing

1. **P1 — Core loop**: backend with Parakeet resident, hold-§ capture, transcription,
   paste insertion, menu bar item, mic selection. (Usable daily from here.)
2. **P2 — Trust**: floating pill, double-tap lock, Esc cancel, cleanup passes incl. British
   pass, history + retention, onboarding with permissions flow and model download.
3. **P3 — Accuracy flywheel and shipping**: personal dictionary + learning from
   corrections, bake-off and accuracy harness, Whisper turbo alternative, idle unload
   option, DMG packaging, signing, and the new-Mac portability checklist.

## Future builds (not in v1, but designed for now)

An **optional LLM cleanup stage**, following Polenta's LM Studio pattern (local model on
127.0.0.1:1234), added as one more stage in the pluggable pipeline:

- **Self-correction rewriting** — "book it for Monday… no, I mean Tuesday" inserts
  "book it for Tuesday" rather than the words as spoken. This is the headline feature.
- Smarter filler and repair handling than the deterministic list (restarts, stammers,
  abandoned clauses).
- Possibly per-app tone/formatting later still (e.g. bullet lists in email, terse in chat).

Ground rules already fixed: the stage is **off by default and opt-in**, degrades gracefully
to the deterministic pipeline when LM Studio is not running, and the 2-second budget applies
to whichever pipeline the user has enabled — if the LLM stage cannot meet it on their
hardware, the app must say so plainly rather than silently getting slower. The raw
transcripts kept in History (see Forward compatibility) are the evaluation set for tuning
the stage's prompt before it goes live.
