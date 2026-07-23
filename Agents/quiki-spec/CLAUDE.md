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

**Current version**: v0.19.0 (released 2026-07-21, PR #262) is the latest tagged release. `main` has moved well past it (PRs #270, #276, #279, #281, #283, #290) — release-please has opened the bundling PR (#277, below).

**PRs open:**
- #277 (`release-please--branches--main--components--quki_notes`) — auto-generated, will cut v0.19.1. Auto-managed by release-please; the project owner merges when ready, no spec action needed.

**Merged since last sync**:
- **PR #292** (`feat/block-indentation-stage1`, merged 2026-07-23) — ADR-34 Stage 1: multi-run block indentation + nested blockquotes, closes #242 and #237. CI green (`flutter analyze`, `dart format`, package tests 470/470, root tests 115/115 — all run independently, not just agent-reported). Reviewed in full before opening: `quiki_editor.dart` needed zero changes (verified by reading the diff, not just the report), per-level nested-blockquote stripe continuity matches the spec's worked example, wrapped-blockquote-line regression has a real geometry test against the live render object rather than a golden image. One deliberate design call worth remembering: the old ADR-33 Stage 4 blank-character blockquote indent reservation was removed entirely (not kept alongside the new layout-based indent) — keeping both would have double-indented a blockquote's first row relative to its own wrapped rows. **Device-tested by the project owner before merge — confirmed looking good**, including the previously-unverified 16px/level indent and 4px stripe gap.
- PR #290 (`chore/switch-funding-to-kofi`, merged 2026-07-22) — removed per-repo `FUNDING.yml`, defers to central `.github` org file. Also a docs-only commit direct to `main` (Sabelhawk sponsor block on the docs home page).

**ADR-33 (nested inline markdown) status**: Stages 1-4 all complete and merged (#276, #279, #281, #283) — see `notes/dev/nested_inline_markdown.md` for the full staged breakdown and the one known limitation shipped with Stage 4 (blockquote wrapped-line indent, documented on #241 rather than fixed standalone, since it's the same root constraint as list nesting). Stage 5 (inline image *syntax* parsing) remains on hold, pending the project owner's own GitHub/Obsidian comparison testing — do not start it without an explicit go-ahead. Filed #285 (GitHub-strict paragraph reflow as an opt-in reading-mode toggle) as a recorded idea, not a commitment, during Stage 4 device testing.

**ADR-34 (real block indentation) status**: root-cause fix for #241 (nested lists) and the ADR-33 Stage 4 wrapped-line blockquote-indent limitation — see `notes/dev/block_indentation.md` for the full spec. **Stage 1 (multi-run rendering foundation + nested blockquotes) merged 2026-07-23 (PR #292), device-tested and confirmed working by the project owner before merge** — closed #242 and #237. **Stage 2+3 briefed 2026-07-23**, branch `feat/block-indentation-stage2`: list-item indent-level detection wired directly into Stage 1's rendering foundation, delivered as one combined brief rather than split — see the note below on why.

**Scoping call: Stage 2 and Stage 3 combined into one brief (spec decision, 2026-07-23)**: `notes/dev/block_indentation.md`'s original stage table split "parser detects list indent" (Stage 2) from "wire it into rendering" (Stage 3) as separately shippable units, the same pattern ADR-33 used successfully. But unlike ADR-33's stages, shipping Stage 2 alone has a user-visible downside: today, an indented list line (`  - sub-item`) falls through to plain-paragraph handling and renders as literal text. Once the parser recognizes it as a list item (Stage 2) but *before* the renderer knows to indent it (Stage 3), it would start rendering as a bullet/checkbox glyph flush against the left margin — visually indistinguishable from a top-level item, which reads as broken, not as an intentional intermediate step. Combined into one brief so the feature never ships in that half-working state. Flagging this here so a future device-test doesn't mistake a genuinely half-shipped stage for a bug if this reasoning is ever revisited.

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
