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

**Task**: Phase 3 — WYSIWYG markdown rendering investigation + implementation (OQ-1 / #27)
**Branch**: `feat/wysiwyg-markdown-editor`
**PR title**: `feat(editor): live WYSIWYG markdown rendering`
**Closes**: #27

### Context

Live WYSIWYG markdown rendering is a **hard MVP requirement** per the manifesto — not a Phase 3 enhancement. The current `editor_screen.dart` implementation (`_parseInitialBody` / `_extractBody`) is plain-text only: it splits on `\n\n`, creates `ParagraphNode` entries, and rejoins on save. Bold, headings, task lists, code blocks etc. are not rendered live.

**Before writing a line of implementation code**, investigate and report to Scott:

1. Does `super_editor` support live markdown input conversion (typing `**` → bold node, `# ` → heading node, `- [ ] ` → task list item)? Check `super_editor` changelog, README, and example apps for "markdown shortcuts" or "input transformer".
2. What GFM features does it cover? Specifically: bold, italic, strikethrough, headings (H1–H3), unordered list, ordered list, task list `- [ ]`, inline code, fenced code block, blockquote.
3. If coverage is insufficient, assess `appflowy_editor` as the fallback (OQ-1 option b). This is a significant rewrite; only recommend it if `super_editor` genuinely cannot deliver.

Report findings as a comment on issue #27 before implementing.

### What to implement (after Scott approves the approach)

Wire up whichever editor delivers live GFM rendering. The round-trip test plan below must pass:

- `**text**` → bold node; serialize back → `**text**`
- `_text_` → italic node; serialize back → `_text_`
- `~~text~~` → strikethrough; serialize back → `~~text~~`
- `# heading` → H1 node; serialize back → `# heading`
- `- item` → unordered list item; serialize back → `- item`
- `1. item` → ordered list item; serialize back → `1. item`
- `- [ ] item` → task list item (unchecked); serialize back → `- [ ] item`
- `` `code` `` → inline code; serialize back → `` `code` ``
- Fenced code block → code block node; serialize back with triple-backtick fence

Auto-save (`AutoSaveController`) and the `activeQukiIdProvider` load path must continue to work — the serialized body stored in SQLite must be valid GFM that another client could render.

### Files likely to touch

- `lib/features/editor/editor_screen.dart` — editor configuration + markdown round-trip
- `lib/features/editor/formatting_toolbar.dart` — verify toolbar actions still apply correct node types
- `pubspec.yaml` — may need version bump or package swap
- `notes/dev/decisions.md` — add ADR for the chosen approach
- `notes/dev/open_questions.md` — resolve OQ-1

### Tests required

- Unit tests: fixture for each GFM feature listed above — parse markdown → serialize → compare.
- Widget test: typing `**bold**` in the editor results in a bold-rendered node (not plain text).
- Existing auto-save + stream tests must still pass.

### Checklist

- `just lint` and `just test` before committing.
- If switching to `appflowy_editor`: add an ADR entry in `decisions.md` explaining why `super_editor` was insufficient.
- No vault-like features, no analytics.

---

## Queued — Session 2 (start after Session 1 is merged)

**Task**: Phase 3 polish — auto-capitalization bug + Primer DHC color palette
**Branch**: `fix/editor-autocap-primer-theme`
**PR title**: `fix(ui): disable editor auto-capitalization and apply Primer DHC color palette`
**Closes**: #32, #37

### Fix 1 — Auto-capitalization (#32)

The editor auto-capitalizes the first letter of each new line. This violates the capture-app contract — user input must be preserved exactly.

Set `textCapitalization: TextCapitalization.none` on the `SuperEditor` (or `appflowy_editor` equivalent) IME/keyboard configuration in `lib/features/editor/editor_screen.dart`. Verify on Android (primary) that lowercase input is preserved. Confirm Windows/Linux are not affected (desktop keyboards don't typically auto-cap, but verify the setting is applied).

### Fix 2 — Primer DHC color palette (#37)

The app uses Flutter's default `Colors.deepPurple` seed color. Spec calls for **GitHub Primer Dark High Contrast** palette (design_spec.md → Settings → Theme).

Replace `ColorScheme.fromSeed(seedColor: Colors.deepPurple)` in `lib/app.dart` with a hand-crafted `ColorScheme` using these Primer DHC tokens:

| Role | Token | Hex |
|---|---|---|
| background (canvas) | `canvas.default` | `#0a0c10` |
| surface | `canvas.subtle` | `#272b33` |
| onSurface (foreground) | `fg.default` | `#f0f3f9` |
| onSurfaceVariant (muted) | `fg.muted` | `#9ea7b4` |
| primary (accent) | `accent.fg` | `#71b7ff` |
| primaryContainer | `accent.emphasis` | `#1f6feb` |
| outline (borders) | `border.default` | `#7a828e` |

Light system theme: use Primer Light High Contrast equivalents (check primer.style/primitives). `ThemeMode.system` stays — no manual override. Both `light` and `dark` `ThemeData` must be updated.

### Files to touch

- `lib/features/editor/editor_screen.dart` — `textCapitalization` setting
- `lib/app.dart` — `ColorScheme` replacement for both light and dark themes

### Tests required

- Widget test: `EditorScreen` keyboard config has `TextCapitalization.none`.
- No automated tests for theme colors — verify visually on device.

### Checklist

- `just lint` and `just test` before committing.
- No new dependencies. No drift schema changes.
