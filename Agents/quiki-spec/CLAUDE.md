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

1. Root `CLAUDE.md` — project overview + current phase status
2. `notes/dev/design_spec.md` — current phase detail and what's in progress
3. `notes/dev/decisions.md` — locked decisions (most recent first)
4. `notes/dev/open_questions.md` — anything unresolved that may need scoping
5. `Agents/quiki-dev/CLAUDE.md` — current implementation task brief
6. `Agents/quiki-devops/CLAUDE.md` — current devops task brief
7. `Agents/quiki-docs/CLAUDE.md` — current docs task brief

---

## How to brief another session

**To assign an implementation task:**
1. Edit `Agents/quiki-dev/CLAUDE.md` → replace the "Current Task Brief" section with the new brief.
2. Include: branch name, PR title, files to touch, integration notes, tests required, checklist reminders.
3. If the task resolves an open question, update `notes/dev/open_questions.md`.
4. If the task introduces a new locked decision, draft an ADR stub in `notes/dev/decisions.md` for the implementation Claude to fill in.

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

## Current project state

See root `CLAUDE.md` → Development Pipeline Summary for the authoritative phase table.

**Phase 3 remaining:**
- Desktop keyboard shortcuts + window-state persistence (Windows + Linux) — next implementation task
- Stream performance / lazy loading — defer until threshold is hit
- Onboarding coachmarks — defer unless user testing reveals a need

**Phase 4+:** Sync plugin axis (v1.1+), MCP (v2.0+) — not in scope until Phase 3 is complete.

---

## Key doc discipline

- `notes/dev/manifesto.md` is normative. Do not propose spec changes that conflict with it.
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
