# Acceptance criteria

Derived from PRD.md. Conventions follow Polenta: every automated test is named by its AC id;
criteria that need a real Mac and real hardware are marked `[manual-hardware]` and collected
into docs/MANUAL_CHECKLIST.md when the build starts. Latency criteria run in the slow
pipeline tier on the Apple Silicon reference machine recorded in DESIGN.md (pinned when the
build starts); everything else belongs to the fast gate
unless marked otherwise. A feature is complete when its ACs pass and the fast gate still
passes.

Reference fixtures: a set of recorded utterances (5 s, 10 s, 30 s, 60 s) in the user's own
voice and the fixed 20-sentence reference script for the accuracy harness,
plus synthetic fixtures containing fillers, American spellings, em dashes, and dictionary
target words. Fixtures live in `fixtures/` and are created before the features that use them.

## 1. Hotkey and capture

- AC-1.1-a: With the app running, holding the default § key starts audio capture and shows
  the floating pill. Instrumented timing (key event → pill visible) asserts ≤ 150 ms in the
  pipeline tier; the manual checklist only confirms it feels instant. `[manual-hardware]`
- AC-1.1-b: Releasing the key stops capture and hands the audio to transcription; text is
  inserted without further interaction. `[manual-hardware]`
- AC-1.1-c: While dictation is active, § never types a character — held, tapped, or
  auto-repeating. Pausing dictation from the menu bar or quitting the app returns § to
  normal typing immediately; because the key is swallowed by the app's own event tap, a
  crash returns it automatically too. `[manual-hardware]`
- AC-1.1-d: § pressed together with a modifier (⇧§, ⌥§, ⌘§) passes through to the frontmost
  app unchanged and does not start dictation.
- AC-1.2-a: An accidental tap — under 500 ms with no detected speech — discards silently:
  no transcription, no insertion, no history entry, no error.
- AC-1.3-a: A double-tap of the hotkey within 400 ms locks hands-free recording; the pill
  shows the locked state.
- AC-1.3-b: A single tap while locked stops recording and proceeds to transcription and
  insertion.
- AC-1.4-a: Pressing Esc while recording (held or locked) cancels: capture stops, nothing is
  transcribed or inserted, no history entry is written, and the pill disappears.
- AC-1.5-a: The hotkey can be changed in Settings to Right ⌘ (and other supported keys); the
  change takes effect immediately without an app restart.
- AC-1.5-b: The chosen hotkey persists across app restarts.
- AC-1.5-c: On a keyboard layout without a § key (ANSI), the default hotkey is Right ⌘.
- AC-1.6-a: The pill distinguishes a stream-starting state from a listening state, and
  switches to listening only once audio samples are actually flowing from the device.
- AC-1.6-b: Speech begun the moment the pill shows listening is captured in full — the
  first word appears in the transcript, including on a Bluetooth mic. `[manual-hardware]`
- AC-1.7-a: A new dictation can start while the previous one is still transcribing —
  recording never waits for processing. Transcriptions complete and insert in spoken order.
- AC-1.7-b: Each queued transcription inserts at the cursor position of the frontmost app at
  its own insertion time, per the normal insertion rules.
- AC-1.8-a: While the screen is locked, the hotkey is inert: no audio is captured, nothing
  is buffered. `[manual-hardware]`

## 2. Transcription, models, and latency

- AC-2.1-a: The selected model is loaded when the app finishes launching; the first dictation
  after launch meets the same latency budget as later ones (no lazy-load penalty).
- AC-2.2-a: The 10 s fixture utterance produces final cleaned text in ≤ 1 s from
  release-equivalent to text-ready, measured on the reference machine. (pipeline tier)
- AC-2.2-b: The 30 s fixture utterance produces final cleaned text in ≤ 2 s. (pipeline tier)
- AC-2.2-c: The 60 s fixture utterance — the budget boundary — produces final cleaned text
  in ≤ 2 s. (pipeline tier)
- AC-2.2-d: Utterances longer than 60 s are outside the latency budget but still complete:
  the pill shows a processing state until the text is inserted normally.
- AC-2.3-a: Switching the model in Settings takes effect for the next dictation without an
  app restart.
- AC-2.3-b: While the newly selected model is loading, the previous model keeps serving
  dictations; the switch happens between dictations, never mid-request. No dictation is
  lost or errors out.
- AC-2.4-a: With idle unload enabled and the idle period elapsed, the model is no longer
  resident (backend memory drops below the loaded threshold).
- AC-2.4-b: The first dictation after an idle unload reloads the model and completes; the
  pill shows the loading state rather than failing.
- AC-2.5-a: Audio is captured at 16 kHz mono from the selected input device.
- AC-2.6-a: A dictation containing no recognisable speech (silence, a breath, a cough)
  inserts nothing, shows a brief "nothing heard" pill notice, and writes no history entry.

## 3. Cleanup passes

- AC-3.1-a: The filler fixture ("um", "uh", "er", interjection "you know") comes out with
  fillers removed and sentence structure intact.
- AC-3.1-b: With the filler pass toggled off, fillers are retained verbatim.
- AC-3.1-c: The filler list is editable; a word removed from the list is no longer stripped.
- AC-3.2-a: The American-spelling fixture is converted by the British pass using the bundled
  map ("color" → "colour", "organize" → "organise").
- AC-3.2-b: Words flagged only by the en_GB Hunspell dictionary are handled exactly as
  Polenta's language pass handles them (same code, same behaviour).
- AC-3.3-a: Em dashes in model output are replaced per Polenta's convention.
- AC-3.4-a: Each cleanup pass has its own toggle in Settings → Cleanup; each toggle state
  persists across restart and is respected on the next dictation.
- AC-3.5-a: Passes run in the PRD order — punctuation, filler strip, dictionary, British
  pass, em dash — verified by a fixture whose correct output depends on that order.
- AC-3.5-b: Words corrected by the dictionary pass are protected from all later passes: a
  taught spelling the British pass would otherwise rewrite ("Center Parcs") survives intact.
- AC-3.6-a: The cleanup pipeline is an ordered list of stages behind one interface
  (transcript in, transcript out, per-stage toggle). Verified by a test that registers a
  dummy stage at an arbitrary position and observes it applied in order, with no changes to
  the existing stages — this is the seam the future LLM stage plugs into.
- AC-3.6-b: A stage that fails or is unavailable is skipped with a logged warning; the rest
  of the pipeline still runs and the dictation completes (the graceful-degradation behaviour
  the future LLM stage will rely on when LM Studio is not running).

## 4. Insertion

- AC-4.1-a: With the cursor in a focused text field, the transcript is inserted at the cursor
  position, not appended or prepended. `[manual-hardware]`
- AC-4.2-a: When the clipboard-paste fallback is used, the user's prior clipboard contents
  are restored after insertion.
- AC-4.3-a: With no focused text field, the transcript is placed on the clipboard and the
  pill says so plainly.
- AC-4.4-a: While macOS secure input is active (a password box), the system may block the
  event tap entirely, so the hotkey may not fire at all. The app detects secure input,
  shows a notice that dictation is unavailable and why, stays healthy, and resumes
  automatically once secure input ends. Nothing is ever injected into a secure field.
  `[manual-hardware]`
- AC-4.5-a: Insertion works in the target matrix: Mail, Safari text areas, Chrome text
  areas, Slack, VS Code, Terminal, Notes. One checklist line per app. `[manual-hardware]`
- AC-4.6-a: Every inserted or clipboard-delivered dictation also appears in History, so a
  swallowed paste is recoverable.
- AC-4.7-a: Inserted text never carries a trailing newline (automated strip test), so
  dictating into a terminal never executes the text — verified against Terminal in the
  insertion matrix. `[manual-hardware]`

## 5. Personal dictionary

- AC-5.1-a: A dictionary entry with a sounds-like hint corrects the matching fixture
  transcript ("melly pap" → "mieliepap").
- AC-5.1-b: An entry without hints enforces canonical casing/spelling of near-miss
  transcriptions, where near-miss means exactly: case differences, or hyphen/space/
  punctuation variants of the entry ("mielie pap", "Mieliepap" → "mieliepap"). Anything
  fuzzier than that requires a sounds-like hint.
- AC-5.2-a: Correcting a history entry that changes a single word offers "Always transcribe
  X as Y?"; accepting creates a dictionary entry.
- AC-5.2-b: After accepting, a fixture containing the same mishearing is corrected on the
  next dictation.
- AC-5.2-c: Declining the offer applies the one-off correction to that history entry and
  creates no dictionary entry.
- AC-5.3-a: The dictionary is stored as a plain human-editable file; an external edit is
  picked up (at most an app restart required) and applied.
- AC-5.4-a: Entries can be added, edited, and deleted in Settings → Dictation data; a
  deleted entry stops being applied immediately.
- AC-5.5-a: An entry learned from a correction links back to the dictation that taught it;
  opening that link shows the history entry (see AC-8.3-c for the reverse direction).

## 6. History

- AC-6.1-a: Every completed dictation is recorded with text, timestamp, target app, and the
  model used.
- AC-6.1-b: Cancelled (Esc) and silently-discarded (AC-1.2-a) dictations do not appear.
- AC-6.1-c: Each entry stores both the raw model transcript and the final cleaned text —
  the evaluation set for tuning the future LLM cleanup stage before it goes live. History
  displays the cleaned text; the raw transcript is visible from the entry's detail view.
- AC-6.2-a: Search finds entries by any word in their text.
- AC-6.3-a: Entries older than the retention setting are removed by the retention job;
  default retention is 90 days.
- AC-6.4-a: After a dictation completes, no audio for it exists on disk (assert the data
  folder contains no audio files).
- AC-6.4-b: With the debug "keep audio" toggle on, audio is kept alongside the entry and is
  removed when the entry is deleted.
- AC-6.5-a: Per-entry copy places the text on the clipboard; delete removes the entry;
  correct opens the edit flow that feeds AC-5.2.
- AC-6.5-b: "Clear all" empties the history store after a confirmation.
- AC-6.6-a: History lives in SQLite in the app's own data folder, following Polenta's
  storage conventions and migration runner pattern.

## 7. Microphone selection

- AC-7.1-a: The device picker lists every available input device plus "Follow system
  default"; "Follow system default" is the initial value.
- AC-7.1-b: The selection persists across restart; a pinned device is used even when it is
  not the system default. `[manual-hardware]`
- AC-7.2-a: The level meter shows live input level for whichever device is selected, before
  any recording is made. `[manual-hardware]`
- AC-7.3-a: Unplugging the pinned device falls back to the system default and posts a menu
  bar notice — no silent failure, no hang. `[manual-hardware]`
- AC-7.3-b: If the device disappears mid-recording, the recording ends gracefully and
  whatever was captured is transcribed. `[manual-hardware]`

## 8. Menu bar, pill, and Settings

- AC-8.1-a: The menu bar item shows distinct idle, recording, and processing states.
- AC-8.1-b: The menu bar menu offers quick mic and model switchers, pause dictation,
  Settings, History, and Quit; "History…" opens Settings at the Dictation data section.
- AC-8.2-a: The floating pill is visible only while recording or processing, shows a live
  mic level while recording, and clicking it cancels (same result as AC-1.4-a).
- AC-8.2-b: The pill never steals keyboard focus from the frontmost app. `[manual-hardware]`
- AC-8.3-a: Settings contains the sections General, Microphone, Model, Cleanup, and
  Dictation data.
- AC-8.3-b: Dictation data presents History and the Personal Dictionary together, with
  retention and clear-all controls in the same section.
- AC-8.3-c: Cross-links work in both directions: a learned dictionary entry opens its source
  dictation, and a corrected history entry shows which dictionary entry it produced.
- AC-8.4-a: The app shows no Dock icon; the launch-at-login toggle registers and
  deregisters the login item. `[manual-hardware]`
- AC-8.5-a: All user-facing copy is British English and passes the language lint used by
  Polenta.

## 9. Onboarding

- AC-9.1-a: Microphone and Accessibility permissions are each requested at the moment they
  are first needed, preceded by a plain explanation of why.
- AC-9.1-b: Declining a permission produces a message saying exactly what is missing and
  what will not work — the app keeps running. `[manual-hardware]`
- AC-9.2-a: Model download shows total size and progress, and survives a retry after an
  interrupted connection.
- AC-9.2-b: After onboarding completes, no further network access occurs (see AC-10).
- AC-9.3-a: The bake-off records the user reading test sentences once and shows both
  models' transcripts of the same audio side by side; choosing one sets the default model.
- AC-9.3-b: The bake-off can be re-run any time from Settings → Model, reusing or
  re-recording the test audio.
- AC-9.4-a: The playground text field receives dictated text via the real end-to-end path
  (hotkey → transcribe → insert) before the user leaves onboarding.
- AC-9.5-a: The accuracy harness scores each installed model's word error rate against the
  fixed 20-sentence reference script read in the user's voice; it is re-runnable from
  Settings → Model and stores results so runs are comparable over time.
- AC-9.5-b: Comparing the winning model against Apple's built-in dictation on the same
  script is a one-time checklist item. `[manual-hardware]`

## 10. Privacy and offline

- AC-10.1-a: With networking disabled after setup, every feature works: dictation,
  insertion, history, dictionary, settings, model switch to an already-downloaded model.
  `[manual-hardware]`
- AC-10.2-a: During normal operation the app and backend make no outbound connections other
  than loopback between app and backend (asserted by monitoring sockets during a soak run).
- AC-10.2-b: The backend runs with `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` pinned;
  loading a model with networking blocked succeeds and attempts no connection. Only the
  onboarding downloader lifts the flag, for the duration of the download alone.
- AC-10.3-a: All data lives in the app's own data folder, distinct from Polenta's vault and
  data folders.
- AC-10.4-a: No analytics or telemetry endpoints exist in the codebase (asserted by a static
  check in the fast gate).

## 11. Robustness and coexistence

- AC-11.1-a: If the backend process dies, the app restarts it and the menu bar shows the
  recovery; a dictation attempted during the gap yields a plain "still starting" message
  rather than a hang, and existing history is intact.
- AC-11.2-a: The backend binds a fixed localhost port that is not Polenta's 8765; with
  Polenta running at the same time, both apps' backends serve requests. `[manual-hardware]`
- AC-11.3-a: A 500-dictation soak run completes with backend RSS growth under 200 MB
  measured from the tenth dictation to the last, and no hang. (pipeline tier)
- AC-11.4-a: Quitting the app terminates the backend child — no orphaned Python process
  remains.
- AC-11.5-a: `make gate` runs the fast gate green on a clean checkout, matching Polenta's
  gate discipline.

## 12. Packaging and portability

- AC-12.1-a: The .dmg contains a single app bundle. On a Mac with no Homebrew, no ffmpeg,
  no Python, and no uv installed: mount, drag to Applications, right-click Open once — the
  app launches and reaches onboarding. `[manual-hardware]`
- AC-12.1-b: First run provisions the backend into Application Support using only what is
  bundled inside the app plus the one-time download, and the backend starts — proven on a
  Mac with no Python installed (Polenta's AC-3.1-e flow). `[manual-hardware]`
- AC-12.2-a: The pipeline spawns no external binaries: audio reaches the backend from the
  app as 16 kHz PCM, so there is no ffmpeg (or any other tool) anywhere in the path.
  Asserted by a static dependency check plus a process audit during the soak run.
- AC-12.3-a: `codesign --verify --deep --strict` passes on the built app bundle and its
  embedded binaries. `[manual-hardware]`
- AC-12.3-b: Rebuilding with the same local certificate and reinstalling keeps the
  Microphone and Accessibility permissions in place with no re-prompt. `[manual-hardware]`
- AC-12.4-a: Full new-Mac flow in order: install from the .dmg, right-click Open, grant
  permissions, let provisioning and the model download run, dictate into the onboarding
  playground and then into Notes — with no other software installed at any point.
  `[manual-hardware]`
- AC-12.5-a: History and the dictionary live as plain files/SQLite in the data folder;
  copying that folder to a second Mac carries them across intact.
