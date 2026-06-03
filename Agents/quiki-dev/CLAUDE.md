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

## Current Task Brief — Session 1 of 2

> Written and maintained by the Spec session. Complete Session 1 and get Scott's sign-off before starting Session 2.

**Task**: Phase 3 polish — snackbar auto-dismiss + paragraph double-spacing
**Branch**: `fix/ui-polish-snackbar-spacing`
**PR title**: `fix(ui): auto-dismiss snackbars and fix paragraph double-spacing`
**Closes**: #24, #25

### What to fix

**#24 — Snackbars do not auto-dismiss**

All `SnackBar` widgets in the app display indefinitely until manually dismissed. Add a `duration` parameter to each:
- Toss result snackbar (success): `Duration(seconds: 2)`
- Toss result snackbar (failure / retry): `Duration(seconds: 4)` — long enough to tap Retry
- Swipe-to-delete undo snackbar: `Duration(seconds: 4)` — long enough to tap Undo

**Known Flutter 3.44 + Material 3 quirk (previous session diagnosed this):** `SnackBar` widgets without a `SnackBarAction` auto-dismiss correctly when `duration` is set. `SnackBar` widgets that include a `SnackBarAction` (the undo snackbar) do NOT auto-dismiss reliably — the action's presence suppresses the internal timer. Fix for the undo snackbar specifically:

1. Call `ScaffoldMessenger.of(context).clearSnackBars()` before `showSnackBar()`.
2. Capture the `ScaffoldFeatureController` returned by `showSnackBar()`.
3. Start a `Timer(Duration(seconds: 4), () => controller.close())` immediately after — this guarantees dismissal regardless of Flutter's internal behaviour.
4. Cancel the timer in the Undo action's `onPressed` so tapping Undo doesn't close the bar prematurely via the timer.

Also ensure `ScaffoldMessenger.of(context)` is captured *before* entering any async gap or `onDismissed` callback where the context may be stale.

**#25 — Paragraph double-spacing**

Every paragraph in the editor appears double-spaced. Two likely causes compounding each other:
1. `_extractBody` joins paragraphs with `\n\n`; `_parseInitialBody` splits on `\n\n` — each paragraph node carries a separator.
2. `super_editor`'s default stylesheet adds its own paragraph padding on top.

Audit the `StyleRule` in `EditorScreen.build` and reduce/remove the extra vertical padding between paragraph nodes. Also check whether the `\n\n` join/split logic needs adjusting or if the stylesheet fix alone is sufficient. Do not change text size or horizontal padding.

### Files to touch

- `lib/features/editor/editor_screen.dart` — stylesheet padding + `_parseInitialBody`/`_extractBody` if needed
- `lib/features/stream/stream_screen.dart` — delete undo snackbar duration
- `lib/features/editor/toss_picker_sheet.dart` — toss result snackbar duration (if snackbar lives here)

### Tests required

- Widget test: after a successful toss, the result snackbar is present and has a non-null duration ≤ 3s.
- Widget test: after swipe-to-delete, the undo snackbar has a non-null duration ≥ 3s.
- No new tests needed for spacing — visual-only change; verify manually on device.

### Checklist

- `just lint` and `just test` before committing.
- No new dependencies. No drift schema changes.

---

## Queued — Session 2 (start after Session 1 is merged)

**Task**: Phase 3 polish — editor navigation redesign + UI copy rename
**Branch**: `feat/ui-navigation-redesign`
**PR title**: `feat(ui): editor navigation redesign — QuKis icon, hamburger menu, Send terminology`
**Closes**: #26, #28

### Navigation model (read before touching anything)

- **Root editor = home**. No back arrow. No element that implies the QuKis list is the parent screen.
- **QuKis list** is pushed on top of the editor. It shows a `←` back button that pops back to the editor.
- **Editors opened from the QuKis list** (tap a row) show a `←` back button that pops back to the list.

### What to build

**Editor top bar (root editor):**
- Remove `← Stream` button entirely.
- Remove `Toss ▼` button entirely.
- Top-left: icon button (Lucide-style list/history icon — discuss with Scott if unsure; `Icons.list` or similar as a placeholder is fine) → navigates to QuKis list.
- Top-right: `IconButton` with `Icons.menu` (hamburger ≡) → opens a `PopupMenuButton` or `Drawer` with items: **Send...**, **QuKis**, **Settings**.
  - **Send...** → fires the existing toss picker sheet (rename sheet title to "Send this QuKi via...")
  - **QuKis** → navigates to QuKis list (same as top-left icon)
  - **Settings** → navigates to settings screen

**UI copy changes (strings only — do not rename internal identifiers):**

| Old string | New string | Location |
|---|---|---|
| `← Stream` | *(removed)* | EditorScreen app bar |
| `Toss ▼` | *(removed)* | EditorScreen app bar |
| `Toss this QuKi to...` | `Send this QuKi via...` | TossPickerSheet title |
| `Tossed!` | `Sent!` | Toss result snackbar |
| `Toss failed` | `Send failed` | Toss result snackbar |
| `Tosses` (Settings section) | `Transports` | SettingsScreen |
| `No transports enabled.` | *(keep as-is)* | — |

**QuKis list screen:** add a `←` back button in the app bar that pops the navigator. Title stays "QuKis". `+ New` button stays top-right.

### Files to touch

- `lib/features/editor/editor_screen.dart` — top bar redesign
- `lib/features/editor/toss_picker_sheet.dart` — title string
- `lib/features/stream/stream_screen.dart` — add back button
- `lib/features/settings/settings_screen.dart` — "Tosses" → "Transports"
- `lib/app.dart` — verify nav wiring still correct after top bar changes

### Tests required

- Widget test: root `EditorScreen` (no `qukiId`, no `onLeave` implies root) has no back button and has a hamburger icon.
- Widget test: `EditorScreen` opened with a `qukiId` shows a back button.
- Widget test: hamburger menu on root editor contains "Send...", "QuKis", "Settings" items.
- Widget test: `StreamScreen` app bar has a back button.
