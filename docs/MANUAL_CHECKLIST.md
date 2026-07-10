# Manual hardware checklist

The acceptance criteria marked `[manual-hardware]` in ACCEPTANCE.md. These need a
real Mac, real microphones, and real target apps, so a person runs them and
ticks them; they are never marked done from the build. Regenerated at each phase
boundary.

Reference machine for the latency-adjacent checks: **Mac Studio, M3 Ultra**
(the same machine the pipeline-tier latency tests run on).

How to run: build and install the app (`make dmg`, then drag-install and
right-click Open), grant Microphone and Accessibility when asked, and work
through each line.

## P1 — core loop

- [ ] **AC-1.1-a** Holding § starts capture and shows the pill; it feels instant.
- [ ] **AC-1.1-b** Releasing § stops capture and inserts text with no further interaction.
- [ ] **AC-1.1-c** While dictation is active § never types a character (held, tapped, or auto-repeating). Pausing from the menu bar or quitting returns § to normal typing at once; a force-quit does too.
- [ ] **AC-4.1-a** With the cursor in a focused text field, text is inserted at the cursor, not appended.
- [ ] **AC-4.5-a** Insertion works in each target app: Mail · Safari text area · Chrome text area · Slack · VS Code · Terminal · Notes. (One tick per app.)
- [ ] **AC-4.7-a** Dictating into Terminal never executes the text (no trailing newline).
- [ ] **AC-7.1-b** The pinned microphone persists across restart and is used even when it is not the system default.
- [ ] **AC-7.2-a** The Settings level meter shows live input for the selected device before any recording.
- [ ] **AC-7.3-a** Unplugging the pinned device falls back to the system default with a menu bar notice, no hang.
- [ ] **AC-7.3-b** A device disappearing mid-recording ends the recording gracefully and transcribes what was captured.
- [ ] **AC-8.4-a** No Dock icon; the launch-at-login toggle registers and deregisters the login item.
- [ ] **AC-11.2-a** With Polenta running, both backends serve at once (WordFlow on 8770, Polenta on 8765).

## P2 — trust

- [ ] **AC-1.6-b** Speech begun the instant the pill shows "listening" is captured in full, first word included, on a Bluetooth mic.
- [ ] **AC-1.8-a** While the screen is locked the hotkey is inert; nothing is captured or buffered.
- [ ] **AC-4.4-a** In a password field, dictation is unavailable with a plain notice, the app stays healthy, and it resumes when secure input ends; nothing is ever injected.
- [ ] **AC-8.2-b** The pill never steals keyboard focus from the frontmost app.
- [ ] **AC-9.1-b** Declining a permission gives a plain message about what will not work; the app keeps running.

## P3 — accuracy flywheel and shipping

- [ ] **AC-9.5-b** Compare the winning model against Apple's built-in dictation on the reference script (one-time).
- [ ] **AC-10.1-a** With networking disabled after setup, every feature works: dictation, insertion, history, dictionary, settings, and switching to an already-downloaded model.
- [ ] **AC-12.1-a** The .dmg holds a single app bundle; on a clean Mac (no Homebrew, ffmpeg, Python, uv) mount, drag, right-click Open, and it reaches onboarding.
- [ ] **AC-12.1-b** First run provisions the backend from what is bundled plus the one-time download, on a Mac with no Python.
- [ ] **AC-12.3-a** `codesign --verify --deep --strict` passes on the bundle and its embedded binaries.
- [ ] **AC-12.3-b** Rebuilding with the same certificate and reinstalling keeps Microphone and Accessibility granted, with no re-prompt.
- [ ] **AC-12.4-a** Full new-Mac flow in order: install from the .dmg, right-click Open, grant permissions, let provisioning and the model download run, dictate into the onboarding playground and then into Notes, with nothing else installed.
