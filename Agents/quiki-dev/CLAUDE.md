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

**Task**: Fix markdown round-trip — formatting lost on save/reload (OQ-1 / #27, partial)
**Branch**: `fix/markdown-round-trip` ← **branch already exists on remote with changes committed**
**PR title**: `fix(editor): wire super_editor markdown serializer for correct round-trip`
**Closes**: #27 (partial — round-trip fixed; live inline reactions are Session 2)

### Background (read before touching anything)

The Spec session diagnosed the root cause of the formatting-loss bug (#27). Two functions in `lib/features/editor/editor_screen.dart` were broken:

- `_parseBody` — was splitting on `\n\n` and creating plain `ParagraphNode`s, stripping all formatting (headings, bold, lists, etc.) on load.
- `_extractBody` — was calling `toPlainText()` on each node, losing all inline attributions on save.

The Spec session committed a fix to branch `fix/markdown-round-trip`. **Your job is to pick up that branch, verify it, test it on device, and open the PR.**

### What was changed

Both functions now use super_editor's built-in serializers (already exported from the `super_editor` package — no new dependency):

```dart
// _parseBody
MutableDocument _parseBody(String body) {
  if (body.trim().isEmpty) return MutableDocument.empty();
  return deserializeMarkdownToDocument(body, syntax: MarkdownSyntax.normal);
}

// _extractBody
String _extractBody() {
  return serializeDocumentToMarkdown(_document, syntax: MarkdownSyntax.normal).trim();
}
```

`MarkdownSyntax.normal` is used (not `superEditor`) to keep stored markdown GFM-compatible and free of proprietary super_editor notation.

A round-trip test file was also committed: `test/features/editor/markdown_round_trip_test.dart`.

### Your checklist

1. `git fetch origin && git checkout fix/markdown-round-trip`
2. `just lint` — fix any analysis issues.
3. `just test` — all tests must pass, including the new round-trip tests.
4. Run on device (Android primary): load an existing QuKi that contains markdown syntax — confirm headings, bold, and lists render correctly instead of showing raw `**` and `#` characters.
5. Type `# ` (hash space) in a blank line — confirm it converts to a heading node live (this already works via `createDefaultDocumentEditor` reactions).
6. Verify save → navigate to QuKis list → tap back into the QuKi → formatting is preserved.
7. Open PR with the template from `notes/dev/pr_template.md`. Scott must confirm on-device before merge.

### Known limitations (do NOT fix in this PR — that is Session 2)

- Live inline reactions for typing `**bold**`, `_italic_`, `` `code` `` are not in this PR. Users must use toolbar buttons for inline formatting.
- `- [ ]` task list conversion reaction is not in this PR.
- Fenced code blocks are deferred (Scott decision).

### Files touched

- `lib/features/editor/editor_screen.dart`
- `test/features/editor/markdown_round_trip_test.dart` (new)

---

## Queued — Session 2 (start after Session 1 is merged)

**Task**: Live inline markdown reactions — bold, italic, inline code, task list
**Branch**: `feat/markdown-inline-reactions`
**PR title**: `feat(editor): live inline markdown input reactions`
**Closes**: #27 (fully)

### What to build

Add custom `EditReaction` subclasses to the editor so typing markdown syntax converts inline:

| Type this | Result |
|---|---|
| `**text**` (type closing `**`) | bold attribution |
| `_text_` (type closing `_`) | italic attribution |
| `` `text` `` (type closing `` ` ``) | inline code attribution |
| `- [ ] ` (type space after `]`) | task list node |

Each is a custom `EditReaction` that triggers on the closing delimiter, scans backward in the current text node for the opening delimiter, and applies the attribution. Follow the pattern in `super_editor`'s `default_document_editor_reactions.dart`.

The task list reaction converts the current paragraph node to a `TaskNode` — the node type already exists in super_editor.

Register the new reactions by passing them to `createDefaultDocumentEditor(inputSource: ..., reactionPipeline: [...defaultReactions, myReactions])` or equivalent super_editor API.

### Tests required

- Widget test (or unit test via `EditorTester` if available): type `**bold**`, assert a bold-attributed span exists in the document.
- Widget test: type `_italic_`, assert italic attribution.
- Widget test: type `` `code` ``, assert code attribution.
- Widget test: type `- [ ] `, assert a `TaskNode` exists in the document.
- Existing round-trip tests from Session 1 must still pass.

### Checklist

- `just lint` and `just test` before committing.
- No new dependencies — all reactions use the existing super_editor API.
- Add an ADR entry in `notes/dev/decisions.md` for the chosen reaction implementation approach (custom `EditReaction` vs any alternative considered).
