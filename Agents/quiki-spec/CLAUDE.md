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
2. Include: branch name, PR title, files to touch, integration notes, tests required, checklist reminders. **Always specify the conventional commit type explicitly.** Use `fix:` for closing gaps in declared behavior (GFM completeness, color/icon standard violations, spec deficiencies). Use `feat:` only for genuinely new capabilities not previously in scope. Do not leave the type for the agent to infer.
3. **Specify every interaction behavior explicitly.** If the task touches UI, describe what each user action does — do not leave interaction patterns for the implementation session to infer. Any behavior not described in the brief or the manifesto must not be implemented; the implementation session should flag it as an open question instead.
4. **Do NOT prescribe implementation details.** Field names, data structures, algorithm design, and class organization are for the implementation session to decide. The brief specifies WHAT to build and key constraints (correctness invariants, performance bounds, integration seams, test requirements). The value of two-session review comes from the agent making independent design choices — if the brief dictates HOW, the review becomes rubber-stamping rather than a genuine second opinion. Flag correctness invariants (e.g., "all source delimiter positions must map to the same rendered offset") without specifying the data structure that enforces them.
5. If the task resolves an open question, update `notes/dev/open_questions.md`.
6. If the task introduces a new locked decision, draft an ADR stub in `notes/dev/decisions.md` for the implementation Claude to fill in.
7. **The implementation session does not decide what's deferred or in scope.** It must not narrow a brief's scope on its own judgment, and must not label a known-incomplete or broken behavior "not a bug — deferred" or otherwise instruct reviewers/testers not to report something as a bug. Deferral and scope calls belong to the spec session (with the project owner), not the implementer. If the implementation session believes something in the brief should be deferred or is out of scope, it must say so explicitly and flag it back to spec — not decide unilaterally and bury it in the PR body.

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

After every implementation sub-agent completes, the Spec session **must** do all of the following before reporting back:

### 1 — Discuss the brief before launching

- Walk through the brief: what changes, what files, what tests.
- Share the exact prompt to be sent to the implementation agent.
- Only launch after approval.

### 2 — Notify when context compaction occurs

When a conversation summary appears at the top of the context (instead of the real history), call it out explicitly in the reply so it is visible, even when working remotely.

### 3 — Review the agent's work before creating any PR

This is a genuine code review, not a compliance checklist. The agent had no context from this conversation — it implemented from the brief alone. The Spec session's job is to bring full project context to that implementation and evaluate it as an independent reviewer would.

**Mechanical checks first:**

| Check | What to verify |
|---|---|
| **Branch name** | Professional and descriptive (`fix/...`, `feat/...`, `chore/...`). No random strings. |
| **Commit attribution** | Every commit message must contain zero Claude/Anthropic attribution. Check with `git log`. Remove any attribution before continuing. |
| **`dart format`** | Run `dart format --set-exit-if-changed packages/markdown_live_editor/lib packages/markdown_live_editor/test` (or the equivalent `just` target). If it fails, fix it or ask the project owner to run locally and push. |
| **Tests** | Run independently — do not rely solely on the agent's report: `just lint` (root lint + format), `just test` (root 114 tests), and `cd packages/markdown_live_editor && flutter test` (package tests). Fix any failures before creating the PR. |

**Then read the full diff and review for:**

- **Brief compliance**: did it build exactly what was asked? Flag anything added that wasn't specified — no bonus features, no speculative abstractions.
- **Manifesto alignment**: do the changes serve the four principles (velocity, open data, information-first UI, extensibility)? Watch especially for any new UI chrome, any new data format that isn't plain Markdown, or any new dependency that adds lock-in.
- **Architectural fit**: does the implementation fit the current architecture? Check for drift into superseded patterns. The clearest example: ADR-30's character-count invariant (source length = rendered length) is dead — ADR-31 explicitly exists to handle variable-length substitutions. Any reasoning or code that assumes equal lengths in the live-preview layer is a regression. Check locked decisions in `notes/dev/decisions.md` (most recent first) when you're unsure.
- **Safety**: no QuKi content or plugin secrets logged, no new analytics surface, no data-loss path (writes atomic, trash before delete). Check any new file I/O or IPC paths.
- **Readability and simplicity**: naming is clear, structure follows existing conventions, no unnecessary abstraction. Three similar lines is fine; a premature helper is not.
- **Test coverage**: do the tests cover the correctness invariants called out in the brief? For offset-map work: are the actual table values asserted, not just `toPlainText()` and length?

Narrate what you found in each area — "I checked X and it's correct because Y" is more useful than silence.

### 4 — Create the PR

Spec creates the PR (not the agent). Use `gh pr create`. The PR body must include:
- Summary of changes
- Step-by-step device test instructions specific enough to verify without guessing
- Deferred section listing intentional omissions (so they are not filed as bugs)
- Zero Claude/Anthropic attribution

After creating: immediately check the PR body for attribution (`gh pr view --json body`) and remove any found.

### 5 — Subscribe to CI and handle failures inline

After PR creation, monitor CI:
- **`flutter analyze` errors**: fix directly in the working tree, commit, push.
- **`dart format` failures**: ask the project owner to run `dart format lib/ test/ packages/markdown_live_editor/lib/ packages/markdown_live_editor/test/` locally and push a formatting commit.
- **Test failures**: diagnose root cause, update test if behaviour intentionally changed, commit and push.
- After each fix push, wait for the next CI result before declaring green.

Do not spawn a background agent to monitor CI — fix inline and use `gh run watch` or `gh pr checks` to poll.

### 6 — Report status

Once CI is green: summarize what changed, confirm no attribution anywhere, and report that the PR is ready to merge. The project owner merges, deletes the branch, and device-tests. Never assume a branch or PR still exists after it has been merged — always start fresh from main.

---

## Current project state

See root `CLAUDE.md` → Development Pipeline Summary for the authoritative phase table.

**Current version**: v0.19.0 (released 2026-07-21, PR #262) is the latest tagged release. `main` has moved well past it — release-please bundling PR status not re-checked this sync; check `gh pr list` fresh rather than trusting this line.

**PRs open**: none as of this sync (2026-08-04) — check `gh pr list` fresh, as always, rather than trusting this being kept current in real time.

**Merged since prior sync — text selection Stage 4, closing ADR-36**:
- **PR #326** (`docs/sync-adr36-stage3-brief-stage4`, merged, plus a same-branch correction commit) — docs sync for Stage 3's merge, briefed Stage 4. **The brief needed a real-time correction**: the project owner pushed back directly on language authorizing the implementation session to drop the magnifier on its own code-level difficulty judgment — "droppable if it doesn't land" requires an actual built, working attempt tried on a real device and found wanting, not a feasibility assessment alone. Corrected in the brief, in `selection.md`/`decisions.md`, and saved as a standing feedback memory (`feedback_dont_drop_without_device_test.md`) before the launched implementation agent reported back.
- **PR #327** (`feat/selection-stage4`, merged 2026-08-03, ADR-36) — magnifier + haptics. Not dropped: the magnifier's open feasibility question (whether Flutter's magnifier machinery works without `RenderEditable`) resolved favorably, and a real implementation shipped. Given the correction that had just gone out, this review round was unusually thorough — verified essentially every non-trivial technical claim directly against the Flutter SDK source on this machine (`/d/bin/flutter/packages/flutter/`), not just the implementation's report: confirmed `RawMagnifier`/`MagnifierController` have zero `RenderEditable` dependency, confirmed Flutter's own stock `TextSelectionOverlay` fires the identical `HapticFeedback.selectionClick()` call at the identical moment (a handle-drag boundary changing) this implementation also uses, confirmed `HapticFeedback.vibrate()`'s doc comment matches the claimed Android `LONG_PRESS` semantics, and hand-traced the magnifier's positioning geometry algebraically against `RawMagnifier.focalPointOffset`'s actual documented contract. Device-tested and confirmed by the project owner — closes ADR-36, all four stages shipped. Filed two real, confirmed gaps found across the whole initiative as tracked issues per the project owner's direction, rather than leaving them as loose doc notes: **#328** (selection doesn't work in reading mode) and **#329** (no draggable handle for precise single-tap collapsed-cursor placement). Full detail: root `CLAUDE.md` implementation notes, `notes/dev/decisions.md` → ADR-36.

**Process note**: this round is a strong argument for verifying technical claims against primary sources when they're checkable, not just trusting a well-written report — every claim checked here turned out to be accurate, but the value was in confirming that independently rather than assuming a confident, detailed report is automatically a correct one (see Stage 2 Round 1's contrary lesson, where a similarly confident, detailed claim did NOT hold up under the same kind of check).

**Merged since prior sync — text selection Stage 3**:
- **PR #324** (`docs/sync-adr36-stage2-brief-stage3`, merged) — docs sync for Stage 2's merge, briefed Stage 3.
- **PR #325** (`feat/selection-stage3`, merged 2026-08-03, ADR-36) — auto-scroll while dragging a handle near a viewport edge. Built on Stage 2 Round 1's post-frame-deferred scroll-notification machinery to keep the dragged boundary resolving correctly against a stationary finger while content scrolls continuously underneath it. **Device-tested and accepted on the first attempt — no fix rounds needed, a first for this feature**, likely because the brief front-loaded the exact Stage 2 landmines (stale-transform timing, touch-position correction) instead of leaving them to be rediscovered. Independently A/B-verified during review: temporarily disabled the boundary re-resolution call, confirmed 3 of 6 regression tests genuinely failed (not a placebo fix), restored it. Also verified the report's "one-frame paint lag, test adjusted to sample after a settle-frame" claim was honest and narrowly scoped — isolated to a separate cosmetic handle-position check, with zero settle-frame allowance on the actual functional selection-boundary correctness tests. Full detail: root `CLAUDE.md` implementation notes, `notes/dev/decisions.md` → ADR-36.

**Process note**: briefing Stage 3 with explicit, named context on Stage 2's two fix rounds (not just "here's the spec," but "here are the two specific bugs the thing you're building on top of already had, and why") appears to have been worth the extra brief length — this is the first stage in this feature that shipped clean on the first device-test pass. Worth continuing this pattern for Stage 4: name the prior landmines explicitly, don't assume the next implementer will rediscover them from context alone.

**Merged since last sync (2026-08-03) — text selection Stage 2**:
- **PR #322** (`docs/selection-stage2-brief`, merged) — briefed Stage 2 (draggable handles), deliberately scoped down from `selection.md` §2 to exclude the collapsed-cursor handle, keeping the stage focused on adjusting an existing selection.
- **PR #323** (`feat/selection-stage2`, merged 2026-08-03, ADR-36) — draggable selection handles + crossing. Shipped only after two real-device-driven fix rounds on the same branch, both independently A/B-verified during review rather than trusted from the implementation report: **Round 1** fixed a genuine scroll-position-staleness bug (handle overlay rebuilding directly off a `ScrollController` notification that fires before that frame's layout applies the new offset) — but my own A/B check found its shipped regression test passed identically with or without the fix, and a no-scroll reproduction showed the reported symptom (which never involved scrolling) didn't happen this way at all; kept as a real, harmless improvement, correctly not treated as the fix. **Round 2** used temporary on-device diagnostics (a visible handle hit-box overlay, gesture-layer console logging — both fully reverted after use, since the project owner's build/install workflow is GitHub Actions → download APK → sideload, with no attached console, so the log half of the diagnostics turned out to be unusable and the visual half plus the project owner's own precise verbal description did the actual work) and found the real root cause: handles are correctly painted one line-height below the caret they represent, but touch-to-text-offset resolution wasn't correcting for that same offset, so grabbing a handle exactly where it's drawn resolved onto the wrong line. Fixed and independently verified myself (reverted the fix, confirmed the new regression tests genuinely fail with real numbers — `Expected: <30>, Actual: <45>`; restored it, confirmed they pass). Device-tested and accepted by the project owner, with a note there may be minor tweaks wanted later (not itemized, not blocking). Full detail: root `CLAUDE.md` implementation notes, `notes/dev/decisions.md` → ADR-36.

**Process notes worth remembering from this round**:
- The value of actually running the A/B check myself (revert the fix, confirm the test fails; restore it, confirm it passes) rather than trusting a well-written, detailed implementation report cannot be overstated — Round 1's fix round included a specific, confident empirical claim ("confirmed via a widget test... 12.4px apart") that did not hold up at all when I reproduced it myself (I got exactly `0.0` with the test as actually committed). The underlying theory wasn't fabricated — a real, narrower version of the bug did exist — but the specific test as shipped didn't verify what its own commit message claimed, and would have shipped as "confirmed fixed" without independent reproduction.
- When code-level investigation stalls or produces an unconvincing fix, real-device diagnostic tooling (temporary, clearly-marked, reverted immediately after use) plus asking the user to describe the exact behavior in their own words was far more productive than another round of code-only speculation — the project owner's own description ("moves a line lower the instant I touch it") was the single most useful piece of information in this entire investigation, more useful than either fix round's own code tracing.
- Before proposing any diagnostic approach that depends on console/log output, confirm how the user actually builds and runs the app — this project owner uses GitHub Actions → APK download → sideload, not a locally attached `flutter run`/IDE debugger, so console-log-based diagnostics needed to be treated as likely-unusable up front, not discovered as a dead end after already asking for them.

**Merged since prior sync (2026-08-01) — HTML paste + text selection Stage 1**:
- **PR #314** (`feat/html-paste-conversion`, merged 2026-08-01, ADR-35) — HTML clipboard paste → GFM markdown conversion, closing real friction (paste from a webpage previously lost all formatting). Mid-review, `super_clipboard` (the original clipboard-reading dependency) had to be swapped for `quill_native_bridge` after CI's `Build Android` job failed three times — `super_clipboard` transitively pulls in `irondash_engine_context`, whose Gradle integration (`cargokit`) calls `Project.exec()`, removed in Gradle 9.0, no released fix available (same root cause already blocking image paste, Phase 1.4 — confirmed systemic during this investigation, not incidental). Pinned to `quill_native_bridge ^11.1.0` (not `^11.2.0`) to avoid a `win32` conflict with `file_picker`; tradeoff is Linux gets no HTML paste yet (#316, not a regression — Linux never had this), tracked via a scoped Dependabot watch (PR #318, `.github/dependabot.yml`) so a compatible `file_picker` release surfaces automatically. Full detail: root `CLAUDE.md` implementation notes, `notes/dev/decisions.md` → ADR-35.
- **PR #320** (`feat/selection-stage1`, merged 2026-08-01, ADR-36) — Text selection Stage 1: fixes a real, confirmed bug (long-press selecting only part of a word — found through actual device use, not a code-review guess; a prior code review of the same logic had concluded it looked correct). Root cause: the old word-boundary scan ran over raw source text, which still contains hidden markdown delimiters. Fixed by scanning rendered text and mapping back through `RenderModel`'s existing offset maps. Adds double-tap (previously unimplemented) as an entry point sharing the identical underlying selection logic with long-press, plus entity-aware selection (links, emails, punctuated numeric strings) — a new QuKi-Notes-specific extension beyond stock Android behavior, confirmed by the project owner. Caught during my own CI review, before merge: I'd verified the package test suite and root `flutter analyze` but skipped root `flutter test` — CI caught a real (if benign) root-level test failure from the same double-tap-recognizer-timer issue already fixed twice elsewhere on this branch; fixed inline, re-verified independently (115/115 root, 608/608 package), CI green. Device-tested by the project owner after merge: the real, confirmed (not hypothetical) ~300ms `onTapDown` latency introduced by adding a double-tap recognizer to the gesture arena does not read as laggy in practice — closes that open question without further action. Full detail: root `CLAUDE.md` implementation notes, `notes/dev/decisions.md` → ADR-36, `notes/dev/selection.md` (the full research + staging spec).
- **PR #319** (`docs/selection-research`, merged 2026-08-01) — `notes/dev/selection.md`: standard Android/Material selection behavior researched from platform documentation (not from reading this codebase — an explicit correction from the project owner mid-session, since the initial pass conflated "what our code does" with "what's the target"), confirmed by the project owner as target requirements, staged into 4 rounds. Hit a real merge conflict before merging: this branch forked before both PR #314/#315 and PR #320 merged, and `Agents/quiki-dev/CLAUDE.md`'s task-brief section had gone stale on both sides (I'd never gone back to clear either completed brief) — resolved by clearing the brief entirely rather than picking one stale draft over the other, since neither was still live work.
- **PR #315** (`docs/adr-35-clipboard-swap`, merged) — corrected ADR-35 with the real pinned dependency version and the Linux gap, after the `super_clipboard`→`quill_native_bridge` swap.
- **PR #317** (`docs/devops-dependabot-brief`, merged) + **PR #318** (`chore/dependabot-file-picker`, merged) — briefed and implemented the scoped Dependabot watch for #316.
- **PR #313** (`docs/adr-35-html-paste`, merged) — original ADR-35 spec doc, predates the clipboard-reader swap.
- **PR #310/#311** (merged) — documented and fixed the `pumpWidget()`-reuse widget-test gotcha (see prior sync entry below for detail).

**Process notes worth remembering from this round**:
- Twice in a row (PR #307's aftermath, and now this round with PR #314→#320), I let a completed task's brief sit stale in `Agents/quiki-dev/CLAUDE.md` instead of clearing it immediately after merge — the second time it caused an actual merge conflict, not just a documentation staleness. Clear the brief the moment a PR merges, not on the next unrelated doc sync.
- Before creating PR #320, I ran the package test suite and root `flutter analyze` but not root `flutter test` — CI caught what that skip missed. My own review protocol (this file, "Sub-agent PR review... protocol") already calls for both root and package test suites; the miss was not following my own checklist, not a gap in the checklist itself.
- When the project owner asked to "research... what is standard and expected, not what our code does, which is horrible and unusable," that was a real correction, not a nuance — a first pass at `selection.md` mixed a current-codebase audit into what was supposed to be pure platform research. Rewrote it to be purely the Android/Material target spec; keep future research docs cleanly separated from current-state audits unless explicitly asked to combine them.

**Merged since prior sync**:
- **PR #307** (`feat/indent-dedent`, merged 2026-07-30) — ADR-34 Stage 4: interactive Indent/Dedent, closes #77. Revised same day it was briefed after discussion with the project owner: original scope was keyboard-Tab-only affecting list items; revised to add toolbar buttons (mobile-reliable, no keyboard dependency) and generalize the operation to a line-start whitespace prepend/strip covering plain paragraphs too (literal tab insert, deliberate logged GFM divergence — filed #305). Headings/blockquotes excluded (prepending whitespace before `#`/`>` breaks recognition), keep the pre-existing at-cursor Tab fallback. Caught and fixed during a follow-up review round, before merge: horizontal rules need a genuine no-op, not the at-cursor fallback the other excluded kinds use — `_isHrLine` requires the whole line to be only the hr character or spaces, so no cursor position preserves recognition; found because the implementer's own hr test asserted recognition would survive and then failed, and it flagged the contradiction back rather than silently loosening the assertion. Reviewed across three rounds (base implementation, a missing-test-coverage follow-up that surfaced the hr bug, and the hr fix itself) — CI green, format/analyze/tests run independently each time, full diffs read each time.
- **PR #308** (`fix/formatting-toolbar-scroll`, merged 2026-07-30) — device-tested immediately after #307: the two new buttons pushed `FormattingToolbar`'s 10-button `Row` past phone-width screens with no scroll mechanism at all. Fixed via `LayoutBuilder` + `SingleChildScrollView(horizontal)` + `ConstrainedBox(minWidth: ...)` — the `ConstrainedBox` matters, since a bare `SingleChildScrollView` shrink-wraps to content width and would let an ambient centered parent reposition the toolbar on wide screens; the implementation session's own widget test caught that regression before ever pushing.
- **PR #309** (`fix/tab-render-width`, merged 2026-07-30) — device-tested immediately after #307: Flutter has no real tab-stop concept, so a literal `\t` renders too narrow to read as an indent. Fixed by substituting any *visible* tab with 4 literal space characters in `RenderModel.build()`'s shared per-character loop (not gated on any parsed `MdElement`, so it applies identically in plain-text mode — which never parses markdown at all — and live-preview mode). List-item indentation itself is unaffected, since its tab is a hidden delimiter character that never reaches the visible-character path. While reviewing this PR, independently confirmed (via an isolated repro, not just the implementation report) a real, separate test-suite bug: `tester.pumpWidget()` called twice in one test to compare different content, with no distinguishing `Key`, silently keeps rendering the first call's content — `MarkdownEditorController`'s `State` has no `didUpdateWidget`. Traced this to a specific pre-existing test in `block_indentation_test.dart` (from the PR #294 marker-gutter-leak fix) whose "without list" comparison had been vacuous since it was written; the underlying fix was still independently verified correct by code trace at the time, so this was a test-quality gap, not a shipped bug. Documented in `notes/dev/testing.md` (PR #310) and fixed (PR #311) as small, separate follow-ups.
- **PR #294** (`feat/block-indentation-stage2`, merged 2026-07-24) — ADR-34 Stages 2+3: nested list indentation, wired into Stage 1's rendering foundation, closes #241 (the ADR's core motivating issue). Shipped after two rounds of device-test fixes on the same branch (not new PRs — fixed in place per protocol): **round 1** — ol numbering restarted instead of continuing across a deeper-nested interruption (fixed: depth-scoped invalidation, only a same-or-shallower-depth interruption restarts a level's count); wrapped list items had the same first-row-marker-consumes-inline-width bug Stage 1 fixed for blockquotes (fixed: markers repainted as a Canvas gutter decoration, mirroring the checkbox-box precedent). **Round 2** — found via the project owner's own real device testing (a pasted Obsidian document, not a synthetic repro): a non-marker line sharing an `indentLevel` with a marker-bearing line *anywhere else* in the same contiguous run inherited that line's 24px gutter and shifted right, even many lines away — root cause was `RenderRun` merging on `indentLevel` alone; fixed by also requiring `listMarker` to match. Same round also fixed Tab (previously silently swallowed by Flutter's default focus-traversal, now inserts a literal tab character — deliberately scoped to just letting the keystroke through, not interactive indent/dedent, which stays #77) and list-marker vertical alignment (bullet/ol-number labels now share the checkbox box's already-tuned formula). All three rounds independently verified by spec before merging — CI green, format/analyze/tests run independently each time, full diffs read each time. User guide updated for nesting + Tab in PR #295.
- **PR #292** (`feat/block-indentation-stage1`, merged 2026-07-23) — ADR-34 Stage 1: multi-run block indentation + nested blockquotes, closes #242 and #237. Device-tested and confirmed by the project owner before merge, including the 16px/level indent and 4px stripe gap.
- PR #290 (`chore/switch-funding-to-kofi`, merged 2026-07-22) — removed per-repo `FUNDING.yml`, defers to central `.github` org file. Also a docs-only commit direct to `main` (Sabelhawk sponsor block on the docs home page).

**ADR-33 (nested inline markdown) status**: Stages 1-4 all complete and merged (#276, #279, #281, #283) — see `notes/dev/nested_inline_markdown.md` for the full staged breakdown. Stage 5 (inline image *syntax* parsing) remains on hold, pending the project owner's own GitHub/Obsidian comparison testing — do not start it without an explicit go-ahead. Filed #285 (GitHub-strict paragraph reflow as an opt-in reading-mode toggle) as a recorded idea, not a commitment, during Stage 4 device testing.

**ADR-34 (real block indentation) status**: **All four stages complete and merged** (PR #292, PR #294, PR #307) — closed #242, #237, #241, and #77. ADR-34 is now fully shipped. See `notes/dev/block_indentation.md` for the full spec and `notes/dev/decisions.md` → ADR-34 for the up-to-date status summary. **Stage 4 (interactive Indent/Dedent — toolbar buttons + Tab/Shift+Tab)** was briefed as keyboard-Tab-only, then revised same-day after discussion with the project owner (mobile needs a toolbar entry point too; the operation generalized to also cover plain paragraphs, not just list items — see decisions.md for the full revision). PR #307 merged 2026-07-30, plus two immediate device-test follow-up PRs, both merged: toolbar horizontal scroll (#308) and tab render width (#309). **Note on this session's own process gap**: after PR #307 merged, the project owner immediately reported two more device-test bugs (#308, #309) in quick succession, and this tracking-doc sync got dropped for several days while those were fixed — caught only when a follow-up implementation agent flagged the discrepancy directly ("spec's tracking doc says Stage 4 not yet briefed, but I see Stage 4 commits already on main"). Worth remembering: syncing tracking docs promptly after every merge matters even (especially) when the next device-test report arrives before the sync happens.

**Process note worth remembering**: this round surfaced a real, non-obvious lesson about brief-writing — when spec root-causes a device-reported bug through its own investigation (reading source, tracing logic by hand, writing scratch repro tests) before writing the fix brief, it's easy to drift into describing the exact fix mechanism already found rather than just the confirmed symptom + required invariant, which defeats the point of asking a separately-briefed agent for an independent second opinion. Corrected directly by the project owner 2026-07-23. Apply going forward: brief the repro + invariant, not the mechanism, even when spec already knows the fix.

**Merged since last sync (were "open, CI green" in the stale version of this file — all confirmed merged via `gh pr list`):**
- **PR #262** (`release-please--branches--main--components--quki_notes`, merged 2026-07-21): release-please cut **v0.19.0**, bundling #257–#260.
- **PR #274** (`docs/spec-sync-pr270-merged`, merged 2026-07-21): docs-only sync after PR #270.
- **PR #275** (`docs/nested-inline-markdown-spec`, merged 2026-07-21): added `notes/dev/nested_inline_markdown.md` (feature spec for #240) + ADR-33, trimmed several stale/misleading ADRs in `decisions.md` down to one-line pointers, added the "implementer doesn't decide scope/deferral" brief-writing rule, and wrote the Stage 1 dev brief.
- **PR #279** (`fix/nested-inline-markdown-stage2`, merged 2026-07-22) — ADR-33 Stage 2: list-item/checkbox content scanning, closes #240 as originally filed. Small, clean diff (4 call sites mirroring Stage 1's heading pattern); no pre-existing tests needed changing.
- **PR #280/#281** (docs scoping + `fix/nested-inline-markdown-stage3`, merged 2026-07-22) — ADR-33 Stage 3: single-line HTML detection, scoped down from full CommonMark's 7 multi-line block types to single-line-only after the parser's lack of multi-line state-tracking made that the pragmatic cut.
- **PR #282** (docs, merged 2026-07-22): corrected two scoping mistakes in the spec — blockquotes had been wrongly excluded (stale pre-ADR-31 note carried forward without checking it still applied) and inline images had been unilaterally descoped by the spec session itself rather than surfaced to the project owner. Both caught by the project owner, not by spec review.
- **PR #283** (`fix/nested-inline-markdown-stage4`, merged 2026-07-22) — ADR-33 Stage 4: blockquote content scanning, plus three rounds of rendering-bug fixes driven by direct before/after comparison against real GitHub rendering (screenshots), not just code review: bare `>` marker recognition, empty-blockquote stripe off-by-one, wrapped/multi-line stripe continuity, content indentation, and stripe vertical alignment (root-caused to `getOffsetForCaret` anchoring to line-box top rather than glyph ink when `height > 1.0`). Shipped with one known, documented limitation (wrapped-line indent) rather than blocking further on an architectural fix that belongs with #241.
- **PR #284/#286** (docs, merged 2026-07-22): wrote the two follow-up blockquote-bug-fix briefs directly onto the existing Stage 4 branch rather than as separate PRs, per the project owner's explicit call to ship them together in #283.
- **PR #276** (`fix/nested-inline-markdown-stage1`, merged 2026-07-21) — Phase 3.45: ADR-33 Stage 1 — CommonMark delimiter-run inline engine for paragraphs and headings, including a same-day follow-up commit for nested emphasis inside link text (`[**bold link**](url)`) that the first pass had left atomic. Reviewed and independently hand-verified (traced `***text***` and `~~ ~~ok~~` through the algorithm by hand) before merge — see root `CLAUDE.md` implementation notes for full detail. **#240 stays open** — its own repro (`- **important item**`) is list-item content, which is Stage 2, not yet built.
- **PR #270** (`fix/checkbox-text-presentation`, merged 2026-07-21) — Phase 3.44: checkbox rendering fix (#267), closes #267. Opened directly on GitHub during the outage gap (not through the usual dev-session → spec-review handoff). Spec review caught a regression in the branch's last pre-merge commit before merging: it sized the checkbox tap-target box off the measured reserved-marker width instead of a fixed line-height fraction, shrinking it to roughly half size at typical font sizes — combined with a hardcoded 3px corner radius, the box rendered as a circle instead of a square, and was a harder target to tap. Fixed directly in this session (single-file, well-scoped) rather than briefed to quiki-dev: box size reverted to a fixed `lineHeight * 0.8`, corner radius scaled proportionally (`boxSize * 0.2`), and the actual overlap problem addressed at the source by widening the collapsed checkbox marker from 3 to 5 blank characters. See root `CLAUDE.md` implementation notes for full detail.
- **PR #233** (`docs/spec-sync-v0.18.2`, merged 2026-07-16): this file + root CLAUDE.md synced to v0.18.2.
- **PR #257** (`fix/editor-ux-polish`, merged 2026-07-16) — Phase 3.40: reading mode + toolbar gating (#235), wrapSelection cursor fix (#236), scroll padding (#234), T-button icon states + markdown mark icon (#239).
- **PR #258** (`feat/editor-polish-2`, merged 2026-07-16) — Phase 3.41: sticky plaintext mode (#249), standalone Send/Settings AppBar buttons (#251).
- **PR #259** (`fix/share-in-single-instance`, merged 2026-07-16) — Phase 3.42: share-in single-instance fix (#188), `launchMode singleTask`.
- **PR #260** (`feat/help-about-dialog`, merged 2026-07-16) — Phase 3.43: help/about dialog (#253).
- **PR #271** (`chore/docs-scale-down`, merged 2026-07-17): docs session — VitePress site scaled down with global zoom. Docs-only.

**Issue-closure discrepancy found during this sync**: #249 (sticky plaintext mode) and #253 (help modal) are still **open** on GitHub even though PR #258 and PR #260 respectively fully implement them — the PR bodies referenced the issues but didn't use a `Closes #N` keyword, so GitHub never auto-closed them. #251 (nav bar redesign) is correctly still open — PR #258 only did the Send/Settings half; the issue's Help button request was explicitly deferred until #253 landed, and now that #260 has shipped a help button, #251 may be fully satisfied too. Flagged to the project owner rather than closed unilaterally — see chat.

**Local git state cleaned up 2026-07-23**: after a session crash while briefing ADR-34, verified the working tree was clean and no half-finished work was stranded (it wasn't — `git status` clean, no orphaned WIP branch). Local `main` fast-forwarded (was 2 commits behind on docs-only changes: Ko-fi funding switch, Sabelhawk sponsor block). Deleted 3 stale local branches, all confirmed merged: `fix/checkbox-text-presentation` (PR #270), `chore/switch-funding-to-kofi` (PR #290), `temp/checkbox-editor-work` (no unique commits, a leftover pointer at `main`).

**Local git state cleaned up 2026-07-21**: 9 stale local branches (`feat/discord-emoji`, `feat/windows-msi-installer`, `fix/add-shared-release-workflows`, `fix/add-workflow-dispatch-to-release`, `fix/build-artifacts-remaining-platforms`, `fix/changelog-cleanup`, `fix/ci-markdown-live-editor`, `fix/discord-notify-after-builds`, `fix/notify-tag-lookup`) were left over from pre-outage devops sessions on this machine. All were confirmed merged (via `gh pr list --head <branch>`) and already deleted on the remote (GitHub's merge-then-delete-branch), so `git fetch --prune` had only local stale refs to clean up. Deleted locally with `git branch -D`; no content was lost since every one was already on `main` under a different (rebase-and-merge) commit hash.

**Issues filed 2026-07-15** (testing batch): #234–#256. Bugs: #234 toolbar obscures last line, #235 toolbar visible when unfocused, #236 cursor after closing delimiter, #237 blockquote rendering, #238 text selection UX. Features: #239 reading mode + T button, #240 nested inline formats (arch blocker), #241 nested/indented lists (arch blocker), #242 nested blockquotes, #243 GitHub callouts, #244 fenced code, #245 tables, #246 external URL images, #247 clipboard paste images (blocked), #248 toolbar context highlight, #249 sticky plaintext mode, #250 cursor/arrow nav, #251 nav bar redesign, #252 default notes, #253 help modal, #254 HTML rendering, #255 definition lists, #256 syntax highlighting (follow-on to #244).

**Issues filed 2026-07-16/17** (post-#257–260 device testing, likely from the other machine during the outage gap): #261 share-in opens QuKi list instead of routing to the new note in the editor (possible regression from the #259 `singleTask` fix — worth checking), #263 reading mode residual toolbar/cursor visibility, #264 bold formatting intermittently produces `*word**`, #265 keyboard opens after deleting a QuKi from the stream list, #266 tapping a checkbox in read-only mode scrolls to top and opens the keyboard, #267 checkbox rendering inconsistency (fixed by PR #270, merged 2026-07-21), #268 QuKi list layout polish, #269 search results should show matching text snippet, #272 notes without a `.meta/{uuid}.json` sidecar are silently ignored by the index.

**Reading mode design (decided 2026-07-15)**: T button is a 2-way rendered ↔ plaintext toggle always. Keyboard visibility = edit vs reading mode. Reading mode is triggered by user dismissing keyboard (unfocus) — hides FormattingToolbar and cursor. Existing notes open in reading mode (no keyboard); new/empty notes open in edit mode (keyboard visible). T button icon: edit+rendered = markdown mark, edit+plaintext = `code-xml`, read+rendered = `book-open`, read+plaintext = `code-xml`. Tracked in #235 (toolbar hiding) and #239 (full reading mode UX).

**Issue scope policy**: File all issues regardless of perceived scope or manifesto fit — issues are a record, not a commitment. GFM alignment with manifesto (velocity/frictionless) is broader than previously assumed.

**Resolved since last spec sync:**
- Phase 3.22 post-ship rendering bugs (PR #194, v0.15.2): list bullets, checkbox visibility, toolbar selection fix.
- ADR-31: Custom RenderObject + TextInputClient live-preview markdown engine. Supersedes ADR-30.
- Phase 3.23 (PR #201, v0.16.0): ADR-31 Stage 1 — `QuikiRenderEditor extends RenderBox` + `QuikiEditorState implements TextInputClient`, plain-text editor replacing `TextField`.
- Phase 3.24 (PR #203, v0.16.1): ADR-31 Stage 1 device-test fixes — scroll hit-test double-count, gesture kind tracking (mouse vs touch), keyboard lifecycle (`connectionClosed` → `unfocus`), long-press word selection.
- Phase 3.25 (PR #205): ADR-31 Stage 2 — `MdParser` + `RenderModel`; reveal/collapse for h1–h3, bold, italic; bidirectional offset maps.
- Phase 3.26 (PR #209, merged 2026-07-05): ADR-31 Stage 2 rendering fixes — reveal condition `<= element.end`, delimiter color = `baseStyle`.
- Phase 3.27: ADR-31 Stage 3 — boundary-reveal and tap-to-source assessed complete via IME-native source-level cursor positions; arrow-key device-test deferred pending device verification.
- Phase 3.28 (PR #211, merged 2026-07-06): ADR-31 Stage 4 — `ul`/`ol`/`checkboxUnchecked`/`checkboxChecked` element kinds; variable-length N→M marker substitution; block-relative ordered-list sequence numbers.
- CI extended to cover `packages/markdown_live_editor/` (format check + tests) (PR #210).
- Spec session process refined: brief style (WHAT + constraints, not HOW), pre-PR test checklist (run independently), code review depth (manifesto + architectural fit + safety).
- Phase 3.29 (PR #213, merged 2026-07-06): ADR-31 Stage 4 device regressions — list auto-continue IME sync, ol block-relative numbering (`1. 1. 1.` → `1. 2. 3.`, `5. 1. 1.` → `5. 6. 7.`), plain text mode toggle.
- Phase 3.30 (PR #215, merged 2026-07-06): ADR-31 Stage 5 — block-level `![alt](path)` image rendering; `ImageSlot`; async image cache; path resolution via ADR-4.
- Phase 3.31 (PR #217, merged 2026-07-06): ADR-31 Stage 6 — inline `[text](url)` link rendering; `LinkSlot`; tap-to-navigate via `url_launcher` (ADR-32); `onLinkTap` callback.
- Phase 3.32 (PR #218, merged 2026-07-07, v0.17.0): Clipboard toolbar — Cut/Copy/Paste/Select All on Android. `ContextMenuController` + `AdaptiveTextSelectionToolbar`.
- Phase 3.33 (v0.18.0): Bold delimiter fallthrough fix (#219) — unmatched `**`/`__` skips both chars, prevents spurious italic.
- Phase 3.34 (v0.18.0): GFM inline markup batch — strikethrough `~~`, inline code `` ` ``, h4/h5/h6, bare URL autolinks; icon + color fixes (link color #4A9EE8 → #71B7FF, Material → Lucide icon violations).
- Phase 3.35 (v0.18.0): GFM second batch — blockquotes `> `, horizontal rules `---`/`***`/`___`, autolink word-boundary guard, inline code background fix.
- Phase 3.36 (PRs #224, v0.18.1): Sort order fix (#75) — `modifiedAt` stored as UTC ISO-8601 in `.meta/{id}.json` sidecar; decouples list sort from filesystem mtime; migration fallback to `stat.modified` for pre-v0.18.1 notes.
- Phase 3.37 (PR #226, v0.18.1): Checkbox tap-to-toggle (#130) — `CheckboxSlot` in `RenderModel`; `checkboxSourceOffsetForTap()` in `QuikiRenderEditor`; `onCheckboxToggle` callback through `MarkdownEditor` → `EditorScreen`; tapping collapsed ☐/☑ toggles `- [ ] ` ↔ `- [x] ` and triggers auto-save.
- Phase 3.38 (PR #232, v0.18.2): Cold launch keyboard fix (#72) — `_EditorScreenState.initState()` posts `requestFocus()` via `postFrameCallback` on all platforms; removed `autofocus: true` from desktop `Focus` wrapper. Root cause: outer `Focus(autofocus: true)` claimed autofocus before the editor's `FocusNode`, so `TextInput.attach()` was never called. Fix is deterministic (fires after first frame) and avoids the double-tap regression from the earlier `autofocus: true` attempt (which was against the now-superseded ADR-26 editor).
- Phase 3.39 (PR #230, v0.18.2): Windows MSI installer — WiX 4, optional Explorer context menu (right-click → "New QuKi"), built by `build-windows.yml` in CI. Installer files in `installer/`.
- Phase 3.40 (PR #257, CI green): Reading mode (#235, #239) — keyboard visible = edit mode (`FormattingToolbar` visible); keyboard dismissed = reading mode (toolbar hidden). `MarkdownEditorController.onFocusChanged` callback + `unfocus()` method added. Existing notes open in reading mode. T button `_tButtonWidget()` — edit+rendered = `_MarkdownMarkIcon` (`CustomPainter`, standard markdown logo, 24×15); edit+plaintext = `codeXml`; read+rendered = `bookOpen`; read+plaintext = `codeXml`. `wrapSelection()` cursor fix (#236) — between delimiters when no selection. Scroll padding (#234) — `contentPadding: fromLTRB(12,12,12,36)`.
- Phase 3.41 (PR #258, CI green): Sticky plaintext mode (#249) — `shared_preferences` key `'plainTextMode'`, loaded on first frame, saved on toggle. Standalone Send/Settings buttons (#251) — `PopupMenuButton` removed; `LucideIcons.send` + `LucideIcons.settings` as direct `AppBar.actions`.
- Phase 3.42 (PR #259, CI green): Share-in single-instance fix (#188) — `launchMode="singleTask"` in `AndroidManifest.xml` (was `singleTop`).

**Next up — architectural design required before any brief:**
- **Rich list content** (links, bold, italic inside list items): parser currently skips inline scan on list lines. Requires two-pass parser restructure — detect list prefix, then scan content inline. New ADR entry needed.
- **Inline images** (mid-sentence `![alt](path)`): single-`TextPainter` model cannot reflow text around inline images. Requires multi-segment layout design. New ADR entry needed.
- Both were confirmed high-priority by the project owner (2026-07-06): "lists of links are common" and "images aren't worth supporting if we can't do inline."

**Phase 3 remaining (open bugs/deferred):**
- **#77 tabs/indenting in lists**: open (related to #241 nested lists arch blocker).
- **#237 blockquote rendering**: open — needs custom paint + screenshot iteration.
- **#238 text selection UX**: open — significant work, platform-specific.
- **Long-press drag after word select** does not extend selection on touch. Deferred.
- **Unscoped features**: #79, #80, #81, #83, #84 (ADR-29/QuickJS), #87, #135, #136, #178, #181, #182, #183, #184. See `notes/dev/roadmap.md`.
- **New issues from testing (2026-07-15)**: #240–#256. See issue tracker.

**Phase 4+:** Sync plugin axis (v1.1+), MCP (v2.0+) — not in scope until Phase 3 is complete.

---

## Visual design standard (applies to all sessions)

Two non-negotiable constraints — include in every dev brief that touches UI or color:

- **Colors**: GitHub Primer Dark High Contrast palette only. Key tokens: canvas `#0a0c10`, surface `#272b33`, foreground `#f0f3f9`, muted `#9ea7b4`, accent/link `#71b7ff`, primary action `#1f6feb`, borders `#7a828e`. Light theme uses Primer Light High Contrast equivalents. Never allow arbitrary hex values or Flutter `Colors.*` seeds in new code — flag any found during diff review.
- **Icons**: Lucide only (`lucide_flutter`, `LucideIcons.*`). Never `Icons.*` (Material) for new UI surfaces. ADR-23.
- **Markdown element styling**: rendered elements (headings h1–h6, bold, italic, strikethrough, inline code, blockquotes) must visually match GitHub Dark High Contrast — type scale, font weight, and emphasis conventions, not only colors.

Both are documented in `notes/dev/design_spec.md` and `decisions.md` (ADR-23) but must be restated in every brief that touches styling — agents do not always read the full spec.

**Known deviations**: none currently tracked.

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
