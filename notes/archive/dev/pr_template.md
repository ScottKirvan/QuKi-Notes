# Pull Request Template

Use this as the **body** of every PR. The project uses **rebase & merge** — each commit lands individually on `main`. Every commit in the PR must follow conventional commit format; the PR title is descriptive only.

## Title format

`<type>(<scope>): <imperative summary>`

| Type | Effect on release |
|---|---|
| `feat` | Minor version bump |
| `fix` | Patch version bump |
| `feat!` / `BREAKING CHANGE:` in body | Major version bump |
| `chore`, `docs`, `refactor`, `test`, `build`, `ci` | No version bump; appears in CHANGELOG |

Scope is the feature folder name when applicable: `feat(editor):`, `feat(stream):`, `feat(transports):`. Omit scope for cross-cutting changes.

**Examples:**
- `feat(editor): add formatting toolbar with bold/italic/strikethrough`
- `feat(transports): add clipboard transport as first built-in transport`
- `fix(stream): preserve scroll position after swipe-to-delete`
- `chore(deps): pin flutter_secure_storage to 9.x`

## Body template

```markdown
## Summary

<one paragraph: what changed and why>

## Phase / Task

Phase <N>: <task name as it appears in design_spec.md → Development Pipeline>

## Test Instructions

Step-by-step manual test on Android device:

1. <step>
2. <step>
3. <step>

**Expected behavior:**
- <bullet>
- <bullet>

**Edge cases to try:**
- <bullet>
- <bullet>

## Decisions Made

If this PR resolved an open question or introduced a non-trivial implementation
choice, list it here and confirm it was added to `decisions.md` /
`open_questions.md`.

- <ADR reference or "none">

## Checklist

- [ ] `just lint` passes locally
- [ ] `just test` passes locally
- [ ] **Tests added** for new feature code (see `testing.md` → What must have a test)
- [ ] **If this is a bug fix (`fix:`)**: failing regression test was written FIRST and committed separately; verified to fail before the fix; file:line referenced in PR body
- [ ] If drift schema changed: `just gen` was run, schema snapshot updated under `test/db/schemas/`, migration test added
- [ ] No new runtime dependency added (or: ADR proposed for it)
- [ ] No flaky tests added (no `Future.delayed`, no wall-clock dependencies; inject the clock)
- [ ] Branch name follows convention (`feat/phase<N>-<slug>` or `fix/<slug>`)
- [ ] No commits to `main`; no force-push; no `--no-verify`
- [ ] Plugin secrets / OAuth tokens / full QuKi contents not logged anywhere added in this PR
- [ ] No vault-like features introduced (folders, tags, backlinks, archive, pinning) — see `manifesto.md` "Is NOT" list
- [ ] No Flutter imports leaked into `lib/core/` or `lib/shared/models/` (ADR-16)
```

## PR sizing

Per `CLAUDE.md`: one PR = one logical unit — a single screen, a single service, a single transport plugin. If scope creeps past what can be tested in a single sitting, stop and split.

## CI expectations

Every PR triggers `ci.yml`:
- `flutter analyze` — zero warnings
- `flutter test` — all green

A red CI does not get merged. Fix or revert.
