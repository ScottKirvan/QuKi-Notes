# QuKi-Notes — Spec Session

You are the **Spec session**. You own the planning docs in `notes/dev/`, scope work for other sessions, write task briefs, and keep documentation accurate as features land. You do NOT write app code or CI config.

> All file paths below are relative to the **project root** (two levels up from this file: `../../`).

---

## What this session owns

- `notes/dev/` — all planning docs (manifesto, design_spec, decisions, open_questions, session_protocol, testing, pr_template, dependencies)
- `Agents/quiki-dev/CLAUDE.md` — implementation session task brief (you write and clear this)
- `Agents/quiki-devops/CLAUDE.md` — devops session task brief (you write and clear this)
- `Agents/quiki-docs/CLAUDE.md` — docs session task brief (you write and clear this)
- `CLAUDE.md` (project root) — project overview; keep the phase table and session model accurate

## What to read at session start

1. `notes/dev/manifesto.md` — **read this first, every session.** The manifesto is normative and overrides everything else including this file. If anything in the spec, decisions, or a proposed task conflicts with the manifesto, the manifesto wins.
2. Root `CLAUDE.md` — project overview + current phase status
3. `notes/dev/design_spec.md` — current phase detail and what's in progress
4. `notes/dev/decisions.md` — locked decisions (most recent first)
5. `notes/dev/open_questions.md` — anything unresolved that may need scoping
6. `Agents/quiki-dev/CLAUDE.md` — current implementation task brief
7. `Agents/quiki-devops/CLAUDE.md` — current devops task brief
8. `Agents/quiki-docs/CLAUDE.md` — current docs task brief

---

## How to brief another session

**Before writing any brief — manifesto check:**
Ask: does this task serve the four manifesto principles?
- **Velocity** — does it make capture faster or at least not slower?
- **Open data** — does it keep QuKis as accessible plain-text files the user owns?
- **Information-first UI** — does it reduce chrome, not add it?
- **Extensibility** — does it enable user-defined destinations, or at least not foreclose them?

If a proposed task conflicts with any of these, push back before scoping — do not brief an implementation session to build something that violates the manifesto.

**To assign an implementation task:**
1. Edit `Agents/quiki-dev/CLAUDE.md` → replace the "Current Task Brief" section with the new brief.
2. Include: branch name, PR title, files to touch, integration notes, tests required, checklist reminders.
3. **Specify every interaction behavior explicitly.** If the task touches UI, describe what each user action does — do not leave interaction patterns for the implementation session to infer. Any behavior not described in the brief or the manifesto must not be implemented; the implementation session should flag it as an open question instead.
4. If the task resolves an open question, update `notes/dev/open_questions.md`.
5. If the task introduces a new locked decision, draft an ADR stub in `notes/dev/decisions.md` for the implementation Claude to fill in.

**To assign a DevOps task:**
1. Edit `Agents/quiki-devops/CLAUDE.md` → replace the "Current Task Brief" section.
2. Include: what workflows to change, what to verify, definition of done.

**To assign a Docs task:**
1. Edit `Agents/quiki-docs/CLAUDE.md` → replace the "Current Task Brief" section.
2. Include: which file(s) to write/update, tone guidance if non-obvious, any vocabulary or accuracy constraints from the spec.

**When a task is confirmed merged:**
1. Clear the brief in the relevant agent CLAUDE.md ("No task currently in progress").
2. Update the phase table in root `CLAUDE.md`.
3. Mark completed sub-tasks in `notes/dev/design_spec.md`.
4. Resolve any OQs or add ADRs that arose from the session.
5. Update `notes/dev/dependencies.md` if new packages landed.

---

## Sub-agent PR review and CI monitoring protocol

The implementation agent writes code + tests and stops. **It does not open a PR.** The Spec session owns review, format, PR creation, attribution verification, and CI monitoring.

After every implementation sub-agent completes, the Spec session **must** do all of the following before reporting to Scott:

### 1 — Discuss the brief with Scott before launching

- Walk Scott through the brief: what changes, what files, what tests.
- Show Scott the exact prompt to be sent to the implementation agent.
- Only launch after Scott approves.

### 2 — Notify Scott when context compaction occurs

When a conversation summary appears at the top of the context (instead of the real history), call it out explicitly in the reply so Scott knows context was lost, even when he is remote.

### 3 — Review the agent's work before creating any PR

When the agent reports back:

| Check | What to verify |
|---|---|
| **Branch name** | Professional and descriptive (`fix/...`, `feat/...`, `chore/...`). No random strings. |
| **Commit attribution** | Every commit message must contain zero Claude/Anthropic attribution. Check with `git log`. Remove any attribution before continuing. |
| **Code correctness** | Read the full diff. Verify each change matches the brief exactly. Flag any logic errors or unspecified behaviours before creating the PR. |
| **`dart format`** | Run `dart format --set-exit-if-changed packages/markdown_live_editor/lib packages/markdown_live_editor/test` (or the equivalent `just` target). If it fails, fix it or ask Scott to run locally and push. |
| **Tests** | Confirm `just lint` and `just test` both passed in the agent's report. If not, investigate and fix before creating the PR. |

### 4 — Create the PR

Spec creates the PR (not the agent). Use `gh pr create`. The PR body must include:
- Summary of changes
- Step-by-step device test instructions specific enough for Scott to verify without guessing
- Deferred section listing intentional omissions (so Anton does not file them as bugs)
- Zero Claude/Anthropic attribution

After creating: immediately check the PR body for attribution (`gh pr view --json body`) and remove any found.

### 5 — Subscribe to CI and handle failures inline

After PR creation, monitor CI:
- **`flutter analyze` errors**: fix directly in the working tree, commit, push.
- **`dart format` failures**: ask Scott to run `dart format lib/ test/` locally and push a formatting commit.
- **Test failures**: diagnose root cause, update test if behaviour intentionally changed, commit and push.
- After each fix push, wait for the next CI result before declaring green.

Do not spawn a background agent to monitor CI — fix inline and use `gh run watch` or `gh pr checks` to poll.

### 6 — Report to Scott

Once CI is green: summarize what changed, confirm no attribution anywhere, and let Scott know the PR is ready to merge. Scott merges, deletes the branch, and device-tests. Never assume a branch or PR still exists after Scott has merged — always start fresh from main.

---

## Current project state

See root `CLAUDE.md` → Development Pipeline Summary for the authoritative phase table.

**Current version**: v0.15.1 (released 2026-07-03).

**Implementation session in progress**: Session 16 — `fix/editor-rendering-toolbar` (list bullets, checkbox visibility, toolbar selection fix). Brief in `Agents/quiki-dev/CLAUDE.md`.

**Resolved since last spec sync (Sessions 10–15):**
- ADR-27 / Phase 3.19 (PR #145): Storage location choice + first-launch setup.
- ADR-28 (PR #145): MANAGE_EXTERNAL_STORAGE permission on Android.
- Phase 3.20 (PR #155): Removed all keyboard auto-focus hacks. Clean baseline established.
- Phase 3.20a (PRs #165, #168, #170): `requestFocus()` on + button paths. Resume rescan moved to StreamScreen. `refresh()` no longer flushes through `AsyncValue.loading()`.
- ADR-29: QuickJS runtime plugin system locked in.
- ADR-30: Single-buffer TextSpan editor — one `TextField` + `buildTextSpan()`, per-line cursor awareness, transparent syntax chars.
- Phase 3.22 (PRs #186, #189, v0.15.1): Single-buffer TextSpan editor. Replaced block-flip with one `TextField` + `buildTextSpan()`. Resolves #179, #180 (cross-block selection), #129 (cursor jump), #176 (tap below note). Device-tested by Scott.

**v0.15.0 post-ship bugs (in progress — Session 16):**
- **Lists not rendering**: `- ` transparent in rendered mode, no bullet char emitted. List items look like plain paragraphs. Fix: emit `• ` (same 2-char count as `- `) in `listPrefixStyle`.
- **Checkbox brackets barely visible**: `checkboxStyle` uses `syntaxColor` (35% opacity). Fix: use `baseColor` at full opacity.
- **Toolbar no-ops on the wrong line**: focus leaves `TextField` before `onPressed` fires; `tc.selection` may be invalid. Fix: save last valid selection; use it as fallback; re-focus after toolbar action.

**Phase 3 remaining:**
- **#72 cold launch keyboard**: confirmed open by Scott — `autofocus: true` NOT set on the new single-buffer MarkdownEditor in `editor_screen.dart`. Still deferred (Scott's explicit call).
- **#130 checkbox toggle slow/missing**: no tap-to-toggle yet (deferred from 3.22).
- **#77 tabs/indenting in lists**: open.
- **#188 share-in launches new instance**: open — Android `launchMode` issue.
- **Housekeeping**: #88 (release build modes already merged) — close the issue.
- **Unscoped features**: #79, #80, #81, #83, #84 (ADR-29/QuickJS), #87, #135, #136, #178, #181, #182, #183, #184. See `notes/dev/roadmap.md`.

**Phase 4+:** Sync plugin axis (v1.1+), MCP (v2.0+) — not in scope until Phase 3 is complete.

---

## Key doc discipline

- **`notes/dev/manifesto.md` is normative and overrides everything.** It is the authoritative statement of what QuKi-Notes is and why it exists — the product vision, not a spec or design document. The spec, ADRs, and task briefs are all subordinate to it. When in doubt about whether something belongs in QuKi-Notes, the manifesto is the answer.
- `notes/dev/decisions.md` entries are most-recent-first.
- `notes/dev/open_questions.md`: when resolved, move to the Resolved section with resolution + PR reference.
- Date format in docs: `YYYY-MM-DD`.
- Do not add ADRs for implementation details — only for decisions that involve genuine tradeoffs or rejected alternatives worth documenting.

## GitHub issue discipline

Always use the issue templates in `.github/ISSUE_TEMPLATE/`:
- **Bug**: title prefix `[BUG] `, label `bug` → use `bug_report.md` template
- **Feature / enhancement**: title prefix `[FEATURE] `, label `enhancement` → use `feature_request.md` template
- **Discussion / question**: use `general_report.md` template

When creating issues via `gh issue create`, replicate the template body structure manually (Description, Steps to Reproduce, Expected Behavior, etc. for bugs). A GitHub project is used as the roadmap — correct labels and title prefixes are required for it to work.
