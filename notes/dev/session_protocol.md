# Session Protocol

## Session types

QuKi-Notes work runs in three distinct session types. Each session type starts from the docs below and has a different focus:

| Session type | Who runs it | What it owns |
|---|---|---|
| **Spec** | A Claude instance dedicated to documentation | Keeps `notes/dev/` accurate; scopes and briefs the other sessions; does not write app code |
| **Implementation** | A Claude instance per feature PR | Writes app code, tests, opens PR; follows this protocol; does not touch CI/release infra |
| **DevOps** | A Claude instance per CI/infra task | Owns `.github/workflows/`, build configs, `justfile`, OQ-NEW-3 resolution; does not write app code |

The rest of this file is the protocol for **Implementation** sessions specifically. DevOps sessions follow the same start/end discipline but substitute CI tooling for `just lint` / `just test`.

---

What to do at the **start** and **end** of every implementation session, and the hard rules that apply throughout.

## At session start

1. **Read in this order:**
   - `notes/dev/manifesto.md` — normative philosophy + tonality (load-bearing)
   - `CLAUDE.md` (repo root) — high-level context + locked decisions table
   - `notes/dev/design_spec.md` — full spec; jump to the section relevant to today's task
   - `notes/dev/decisions.md` — rationale behind every locked decision; do not relitigate without project-owner input
   - `notes/dev/open_questions.md` — if your task touches an open question, propose a resolution before implementing

2. **Check repo state:**
   - `git status` — working tree should be clean before you start
   - `git branch --show-current` — confirm you are **not** on `main`; create a new branch if needed
   - `gh pr list` — see what is already open; do not duplicate work
   - `gh run list -L 5` — confirm CI on `main` is green; if red, fix that first or ask

3. **Confirm scope:**
   - Which phase? Which task from the design_spec Development Pipeline checklist?
   - One PR = one logical unit. If the assigned task is bigger than one PR's worth, split it before writing code.
- If the task is a **bug fix** (PR title will start `fix:`), follow the protocol in `testing.md` → Bug-fix protocol: write the failing regression test **before** the fix. Commit the test separately so the diff proves it catches the bug.

## While working

- Branch name: `feat/<short-slug>` or `fix/<short-slug>` or `chore/<slug>`.
- Commit type: use `fix:` for closing gaps in declared behavior — missing GFM elements, color/icon standard violations, spec deficiencies. Use `feat:` only for genuinely new capabilities not previously in scope. Mislabeling corrections as features inflates the version history.
- Run `just lint` and `just test` before every commit.
- Add a comment in code only when the logic is not self-evident from the code itself. Do not add docstrings or comments to code you didn't change.
- If you need a new runtime dependency, **stop and propose an ADR entry first**.

## At session end

1. Run `just lint` and `just test` — both must pass before stopping.
2. **Stop. Do NOT open a PR.** Push the branch and report back to the Spec session. The Spec session reviews the diff, runs `dart format`, creates the PR, and monitors CI.
3. Every commit must follow conventional commit format — commits land individually on `main` via rebase merge. PR title is descriptive only.
4. If you made a non-trivial implementation decision during the session (one of two viable approaches, novel pattern), add an entry to `decisions.md` and link it from your report back to Spec (Spec will include it in the PR body).
5. If you discovered a new open question (couldn't be resolved without more information), add it to `open_questions.md`.
6. **Never** commit or push to `main` unless explicitly instructed by the project owner. **Never** force-push. **Never** use `--no-verify`.

## Hard rules (do not violate without explicit instruction)

| Rule | Source |
|---|---|
| Do not open a PR. Stop after code + tests pass, push the branch, report back to Spec. Spec reviews the diff and opens the PR. | project workflow rule |
| Never commit to `main` unless explicitly instructed by the project owner. | project workflow rule |
| Manifesto is normative. If a request conflicts with the manifesto, push back before implementing. | `manifesto.md` |
| No vault-like features (folders, tags, backlinks, archive, pinning). | `manifesto.md` "Is NOT" list |
| `lib/core/` and `lib/shared/models/` stay Flutter-free. Flutter imports go in `lib/features/`. **Exception**: `lib/core/transports/` may import Flutter for `settingsView()` — CLI ignores that method (ADR-21). | ADR-16, ADR-21 |
| Any plugin secret (OAuth token, API key) lives in `flutter_secure_storage`, namespaced per plugin. Never in `shared_preferences`, files, or source. | ADR-2 |
| No analytics, no crash reporting, no telemetry SDK. Ever. | ADR-12 |
| `build-ios.yml` is a stub and must NOT be wired to trigger automatically | CLAUDE.md |
| Platform guards must use the mobile/desktop distinction — never `Platform.isAndroid` alone for anything that will apply to iOS. Use `Platform.isAndroid \|\| Platform.isIOS` (or a `_isMobile` helper). iOS builds are deferred but the codebase must be iOS-compatible from day one — no regression testing from scratch when iOS activates. | project requirement |
| Plugin secrets and full QuKi contents are never logged. | ADR-12 |
| Image base64-embedding in markdown is forbidden. Images are separate binary files referenced as `![](../images/...)`. | ADR-4 |
| Deletion moves the QuKi to a `.trash/` subfolder inside the storage root. Hard delete is user-initiated from the Recently Deleted screen. No background sweep, no timer. | ADR-25 |
| Save (local) and Send (transport) are separate. Send is **always** user-initiated. No auto-send. | ADR-6, ADR-14 |
| Tests ship with the code in every feature PR — not retrofitted later | ADR-13 |
| Bug fixes: failing regression test **first**, verify it fails, then write the fix | ADR-13 |
| Flaky tests are tagged and fixed within one session — never left to accumulate | ADR-13 |
| No new runtime dependency without proposing an ADR first. | `decisions.md` rule |
| Transports are Dart-only. No JS/TS/Lua/embedded interpreters. (Obsidian glue is a separate repo.) | ADR-14 |
| Sync and MCP code does **not** land in MVP. `core/sync/` and `core/mcp/` directories do not exist yet. | ADR-17, ADR-18 |

## Tooling expectations

- `just` is the task runner. Common targets: `just android`, `just windows`, `just test`, `just lint`, `just gen`, `just docs`.
- `gh` (GitHub CLI) is available for PR/issue/run operations. Prefer it over the web UI when scripting.
The app is tested on a physical Android device for manual test. Claude does not need to run the app — but `flutter analyze` and `flutter test` must pass locally before opening a PR.

## When in doubt

Ask the Spec session. The cost of one clarifying question is much lower than the cost of a PR that misses the intent.
