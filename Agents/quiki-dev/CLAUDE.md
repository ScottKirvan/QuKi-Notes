# QuKi-Notes — Implementation Session

You are an **Implementation session**. You write app code and tests, and open PRs.
You do NOT touch `.github/workflows/`, build configs, or `notes/dev/` docs (except to add ADR entries or open questions as directed by the session protocol).

> All file paths below are relative to the **project root** (two levels up from this file: `../../`).

---

## Required reading at session start

Read in this order — do not skip:

1. `notes/dev/manifesto.md` — normative philosophy; the manifesto overrides everything else
2. `notes/dev/design_spec.md` — jump to the section for today's task
3. `notes/dev/decisions.md` — every locked decision with rationale; do not relitigate without discussing with Scott
4. `notes/dev/open_questions.md` — if today's task touches one, propose a resolution before writing code
5. `notes/dev/session_protocol.md` — full start/end checklist + complete hard rules table
6. `notes/dev/testing.md` — what must have a test + mandatory bug-fix protocol
7. `notes/dev/pr_template.md` — use this template for every PR body

`notes/dev/dependencies.md` — canonical approved packages. No new runtime dependency without proposing an ADR in `decisions.md` first.

---

## Session start checklist

1. Read the required docs above.
2. Read the **Current Task Brief** section below.
3. Check repo state:
   - `git status` — working tree must be clean
   - `git branch --show-current` — must NOT be on `main`; create branch if needed
   - `gh pr list` — confirm no duplicate work already open
   - `gh run list -L 5` — CI on `main` must be green before starting

---

## Hard rules (condensed — full table in session_protocol.md)

- Manifesto is normative. Push back on anything that conflicts with it before implementing.
- No vault-like features (folders, tags, backlinks, archive, pinning).
- `lib/core/` and `lib/shared/models/` are Flutter-free. **Exception**: `lib/core/transports/` may import Flutter for `settingsView()` (ADR-21).
- No new runtime dependency without an ADR entry first.
- No analytics, crash reporting, or telemetry. Ever.
- Tests ship with the code in every PR. Bug fixes: failing regression test committed first.
- Do not open a PR until Scott has tested on device and confirmed it works.
- Never commit to `main`. Never force-push. Never `--no-verify`.
- `build-ios.yml` is a stub — do not wire it to trigger automatically.

---

## Current Task Brief

> Written and maintained by the Spec session. If this says "no task", ask Scott what's next.

**Task**: Phase 3.4 — Desktop keyboard shortcuts + window-state persistence
**Branch**: `feat/phase3-desktop-keyboard-window`
**PR title**: `feat(desktop): keyboard shortcuts and window-state persistence for Windows + Linux`

### Context

The app now builds and runs on Windows and Linux (Phase 3.2). Desktop users have no keyboard shortcuts and the window opens at the OS default size and position every launch. This PR adds both.

This task has two parts with different dependency profiles — read both before starting:

---

### Part 1: Keyboard shortcuts (no new dependencies)

Use Flutter's `CallbackShortcuts` or `Shortcuts` + `Actions` widgets. Register shortcuts only on desktop — wrap registration in `if (Platform.isWindows || Platform.isLinux)` (import `dart:io`). Android behavior must be unchanged.

**Shortcuts to wire:**

| Screen | Keys | Action |
|---|---|---|
| Stream | `Ctrl+N` | Open a new blank QuKi in the editor |
| Editor | `Escape` | Return to stream (same as tapping `← Stream`) |
| Editor | `Ctrl+T` | Fire the toss picker |

**Text formatting** (`Ctrl+B`, `Ctrl+I`, etc.) — check first whether `super_editor` already handles these on desktop before adding anything. If they work, document it in the PR body. Only wire what's missing.

**Integration note**: `Escape` in the editor should call the existing `_onLeave()` method, which flushes auto-save before popping. Do not bypass the save flush.

---

### Part 2: Window-state persistence (new dependency — ADR required first)

`window_manager` (pub.dev) is the standard Flutter package for reading and setting window size/position on desktop. It is not yet in `notes/dev/dependencies.md` and is a new runtime dependency.

**Before implementing this part:**
1. Propose an ADR entry in `notes/dev/decisions.md` (stub is fine — `window_manager` for desktop window control; rejected alternative: raw platform channels).
2. Show the ADR stub to Scott and get verbal approval before adding the package.
3. Once approved: add to `pubspec.yaml`, save size + position to `shared_preferences` on window close, restore on launch.

If Scott is not available to approve during the session, implement Part 1 only and note the ADR stub is ready for review. Do not add `window_manager` to `pubspec.yaml` without approval.

---

### Tests required

- Widget test: `Ctrl+N` on stream screen triggers navigation to editor.
- Widget test: `Escape` on editor screen calls `_onLeave()` (or equivalent flush path).
- Unit test for window-state persistence (if Part 2 lands): save → restore round-trip with mocked `shared_preferences`.
- No test needed for `Ctrl+T` toss shortcut if the toss picker is already covered.

### Checklist reminder

- Run `just lint` and `just test` before every commit.
- No drift schema changes — `just gen` not needed.
- If `window_manager` is added: update `notes/dev/dependencies.md` with the pinned version.
