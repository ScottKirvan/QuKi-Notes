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

## Current Task Brief — Session 1

> Written and maintained by the Spec session. Get Scott's sign-off before starting Session 2.

**Task**: Phase 3 polish — Primer DHC color palette + auto-capitalization fix
**Branch**: `fix/primer-theme-autocap`
**PR title**: `fix(ui): apply Primer Dark High Contrast theme and disable editor auto-capitalization`
**Closes**: #37, #32

### Fix 1 — Primer Dark High Contrast color palette (#37)

The app uses Flutter's default `Colors.deepPurple` seed color. Replace `ColorScheme.fromSeed` in `lib/app.dart` with a hand-crafted `ColorScheme` using GitHub Primer Dark High Contrast tokens:

| Flutter role | Primer token | Hex |
|---|---|---|
| background / canvas | `canvas.default` | `#0a0c10` |
| surface | `canvas.subtle` | `#272b33` |
| onSurface (foreground) | `fg.default` | `#f0f3f9` |
| onSurfaceVariant (muted) | `fg.muted` | `#9ea7b4` |
| primary (accent) | `accent.fg` | `#71b7ff` |
| primaryContainer | `accent.emphasis` | `#1f6feb` |
| outline (borders) | `border.default` | `#7a828e` |

Light system theme: use Primer Light High Contrast equivalents from primer.style/primitives. `ThemeMode.system` stays — no manual override. Both `light` and `dark` `ThemeData` must be updated. No new dependencies.

### Fix 2 — Auto-capitalization (#32)

The editor auto-capitalizes the first letter of each new line. Set `textCapitalization: TextCapitalization.none` on the `SuperEditor` IME/keyboard configuration in `lib/features/editor/editor_screen.dart`. Verify on Android that lowercase input is preserved.

### Files to touch

- `lib/app.dart` — `ColorScheme` replacement
- `lib/features/editor/editor_screen.dart` — `textCapitalization` setting

### Tests required

- Widget test: `EditorScreen` keyboard config has `TextCapitalization.none`.
- No automated tests for theme colors — verify visually on device.

### Checklist

- `just lint` and `just test` before committing.
- No new dependencies. No drift schema changes.

---

## Queued — Session 2 (start after Session 1 is merged)

**Task**: Phase 3 — Recently Deleted screen
**Branch**: `feat/recently-deleted`
**PR title**: `feat(stream): Recently Deleted screen with user-configurable retention`
**Closes**: #29

### What to build

Data recovery screen — not an organizer feature. See `notes/dev/design_spec.md` → "Recently Deleted" and ADR-5 for full behavioral spec.

- **Access**: entry point from Settings (not from the main QuKis list — avoids making it feel like a second list)
- **Screen**: newest-first list of soft-deleted QuKis; no sort, filter, tags, or pinning
- **Tap a row** → restore (clears `deletedAt`; QuKi returns to top of QuKis list)
- **Swipe a row** → permanent hard-delete (immediate; modal confirmation dialog required)
- **Retention period**: user-configurable in Settings → a new setting (default 7 days; 24h is too short for fat-finger recovery). Background sweep hard-deletes + cascades to images after the period expires.
- **Drift schema bump required**: add `schemaVersion` bump + migration test per ADR-8. The `qukis` table already has `deletedAt` — no column changes needed, but the sweep logic needs wiring.

### Tests required

- Unit test: `hardDeleteBefore(threshold)` DAO method deletes rows with `deletedAt` older than threshold and leaves newer rows.
- Widget test: Recently Deleted screen shows soft-deleted QuKis; restore tap clears `deletedAt`.
- Widget test: swipe to hard-delete shows confirmation dialog; confirm → row gone.
- Migration test: schema version bump verified against prior snapshot per ADR-8.

### Checklist

- `just lint` and `just test` before committing.
- No new runtime dependencies.
- Drift schema version bump + snapshot test required (ADR-8).
- ADR entry not required (behavior already specified in ADR-5).
