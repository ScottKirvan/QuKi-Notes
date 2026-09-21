# CLAUDE.md — QuKi Notes 

## Current status (2026-09-20)

The TypeScript rewrite (`project/`) has reached the end of
`notes/dev/quki-rewrite-path.md`'s phase 06 (Capacitor/Android) per that phase's own
stated scope: storage backend swap + Flutter-migration detection, the all-files
permission Kotlin, the keyboard-aware formatting toolbar, Send (share-out), and
share-in are all built and independently reviewed. All four day-one targets (web,
Android, Windows, Linux) have working implementations.

**Read `notes/dev/rewrite_TODO.md` first in any new session** — a running,
checkbox-format list of everything still open, including the remaining
rendering/editor gaps (list/task/blockquote live-reveal now exists; indentation
layout grouping does not), platform-specific loose ends, and manual-acceptance
items only Scott can check off.
`notes/dev/github_issues_review.md` cross-references all 123 issues from the old
Flutter GitHub tracker against the rewrite — what's already fixed, what's structurally
obsolete, and what's still genuinely relevant.

## Keeping This File Current

This file is the primary context for any agent working in this repo — keep it accurate
as the project evolves. When you learn what the project is, add a brief description at
the top. As key files, build commands, and architectural decisions emerge, record them
here so future sessions start with full context rather than re-deriving it.

Update this file in the same commit as the work it documents.

## Working Conventions

- Never commit or push directly to `main`. Always branch first, then PR.
- Before pushing to, or building new commits on, a previously-used branch, run `git
  fetch --prune` and confirm its remote ref still exists — a merged PR's branch may
  already be gone. At the start of any session resuming an existing branch, `git fetch
  origin && git rebase origin/main` before touching files — branches drift silently
  between sessions.
- Branch names must describe the work (e.g. `fix/login-timeout`, `feat/export-csv`).
  No random characters, UUIDs, or generated suffixes to ensure uniqueness — if a name
  is already taken, pick a more specific descriptive name instead.
- If a branch name is pre-assigned by tooling (a hosted agent session, a CI runner)
  rather than chosen by you, verify it against this convention before the first push.
  Rename locally (`git branch -m <name>`) if it doesn't match — being handed a name
  isn't an exemption from the rule.
- One concern per branch and PR. If work naturally splits into independent problems,
  split the branches too — resist bundling unrelated changes into one PR.
- Conventional commits: `feat:` / `fix:` / `docs:` / `chore:` / `refactor:` / `test:`.
  Breaking: `feat!:`.
- `feat:` is for genuinely new user-facing capabilities only. Bug fixes and corrections
  use `fix:`, even when they close a tracked issue.
- Unit tests must be written alongside all new code. All bug fixes require red/green
  tests — a failing test that reproduces the bug, then the fix that makes it pass.
- CI, lint, and formatting must all pass before committing or opening a PR. Discover
  the project's commands from the CI config, `package.json`, `Makefile`, or equivalent
  — do not assume they match another project's toolchain.
- Prefer narrow, localised changes. Favour modularity that contains the blast radius
  of future edits — a fix or feature should not require touching unrelated parts of
  the codebase. If it does, that's a design signal worth surfacing.
- Refactoring is a first-class activity, not something to defer. Improve structure as
  you go rather than accumulating technical debt for a later pass.
- When working in unfamiliar domain territory, prefer primary sources — official docs,
  specs, RFCs — over general knowledge. Flag domain uncertainty explicitly rather than
  proceeding on an assumption.
- Default to writing no comments. Add one only when the *why* is non-obvious — a
  hidden constraint, a subtle invariant, a workaround for a specific bug. If code is
  hard to understand, the fix is clearer naming and structure, not a comment explaining
  what it does.

## Change as Experiment

Work proceeds in small, verifiable, safe, directed steps — not a plan executed end to
end. Each step is small enough to evaluate on its own: land it, check whether it moved
things in the right direction, then decide the next step from what was just learned
rather than from what was originally guessed. Treat every change as an experiment with
a check at the end, not a commitment to a predetermined path.

This project runs in a constrained environment on purpose — the impulse to run ahead,
anticipate the next three steps, or solve adjacent problems while already in the code
is explicitly suppressed. Staying inside the current step is a discipline, not a
limitation to work around.

## Testing Strategy

Tests are the fastest mechanical check that generated code matches intent — treat them
as load-bearing, not optional scaffolding. Two tiers matter most here:

- **Unit tests**, written alongside the code (see Working Conventions above) — TDD
  where practical: the test exists before the implementation it verifies.
- **Acceptance tests**, written in behavior terms (given/when/then or equivalent) —
  describing what the system does from the outside, not how. These are the actual spec
  for a feature or fix; if a change can't be stated as an acceptance criterion, the
  requirement isn't clear enough yet to build against.

When a process mistake gets logged in `notes/dev/mistakes.md`, ask whether it's also a
missing test — a regression or acceptance test that would have caught it mechanically
next time, not just a process note relying on memory.

## No Shortcuts

Nothing is deferred without explicit permission from the user. A known issue is still
a bug — do not mark it "won't fix", "by design", or "out of scope" unilaterally.

If a library or package cannot meet the stated requirements, the answer is to find an
alternative or do the work from first principles — not to defer the requirement or
revise it to fit the limitation. The requirements define what the project needs; the
implementation serves the requirements, not the other way around.

## Verification Discipline

Never state that something works, is fixed, or is verified unless it was checked at
that exact moment with a command whose output is the actual basis for the claim — not
memory of an earlier check, not knowledge of what the code is supposed to do, and not
a sub-agent's self-report taken at face value. The standard is identical in both
directions: the skepticism applied to a sub-agent's "done" (see Sub-Agent Workflow)
applies just as much to Claude's own claims to the user.

Before reporting a task or verification as complete:
- State the concrete, checkable success criteria before running anything — specific
  facts ("a PR exists against branch X containing files A and B"), not a general
  expectation ("it should work").
- Check every criterion with a fresh command at the time of the claim, and cite its
  actual output as the basis for what's reported.
- If a task has multiple required scenarios (e.g. two code paths, or a dev environment
  and the real deployment target), track them explicitly and don't report the whole
  task done until every one has been checked — a passing sub-step is not a finished
  task.
- Report against the criteria list: state plainly what's verified and what isn't,
  rather than describing the completed part in success language and leaving gaps
  implicit.

## Communication

Ask questions in natural language. Never use a multiple choice / structured question
tool — including Claude Code's `AskUserQuestion` tool — if clarification is needed,
just ask directly in plain text. This is a project-wide preference, not a
per-session one: some interfaces render binned/multiple-choice questions poorly,
and forcing a question into fixed options loses the nuance an open question
would surface. Standard engineering practice is to ask a real question and read
a real answer, not to pick from a menu.

**Scott's direct statements are authoritative, not claims to verify or hedge.** If he
reports something directly — a bug, a fact about what he observed, a correction — record
and act on it as established, not as "(Scott, unverified)" or similar. The heavy
verification discipline in this file (re-run tests, re-read code, distrust a sub-agent's
self-report) is aimed at agent and code output, not at Scott's own reports of what he's
seen. Corrected explicitly after a first draft of `notes/dev/rewrite_TODO.md` hedged
three of his direct bug reports this way.

## Autonomy

Make implementation decisions independently — don't ask permission for technical
choices within the stated requirements. Escalate only when something would change
scope, defer a requirement, or contradict what the user has described as the goal.

A structural choice made while implementing a functional request — naming, module
boundaries, a relationship between two pieces — is mine to propose, but must be
flagged as a proposal, not written into this file, a spec, or code comments with the
same authority as something the user actually decided.

A description of a desired change is not, by itself, authorization to execute it. If a
message separates *what* to do from *when* ("I'll tell you when"), wait for the
explicit go-ahead before acting — even on a fully-specified, low-risk change.

**IF YOU CANNOT DO EXACTLY WHAT WAS ASKED — DUE TO A TECHNICAL CONSTRAINT OR ANY OTHER
REASON — STATE THE CONSTRAINT AND STOP.** Do not silently substitute an alternative and
proceed to implement it in the same turn. Naming the blocker is not itself permission
to pick a workaround; the user decides which alternative (if any) to pursue. This
applies even when the substitute seems obviously reasonable.

**Two-strike auto-comply.** If corrected twice on the same point, treat the second
correction as an automatic stop: comply immediately, with no further justification or
re-explanation. Don't make the user repeat themselves a third time or invoke a
stop-word to get compliance — repetition itself is the signal.

**Mark proposals as proposals.** Any architectural or structural choice made while
implementing — one not a direct restatement of something the user actually decided —
gets written into a spec, `CLAUDE.md`, or other persistent doc as `[Proposed —
unconfirmed]`, not plain declarative text carrying the same authority as a real
decision. Don't unmark your own proposal; only the user confirming it (or leaving it
alone) makes it settled.

## Attribution

No attribution of any kind in commit messages, PR bodies, or issue text — no
"Generated with", "Co-Authored-By", "Created by Claude", or any AI/tool credit lines.

**Verify by reading the repo, not from memory.** Some git hosting integrations inject
a footer server-side even into a request that omitted one — treat that as expected
behavior, not a surprise. After every commit and after every PR create/update, re-read
the actual result and strip any attribution found, regardless of source:
- Run `git log` and read the actual commit messages
- Re-fetch and read the actual PR body text
- Remove any attribution found, regardless of source

A commit or PR is not finished until this read-back check has run — don't rely on what
you wrote, check what actually landed.

## GitHub Issues and PRs

Issue and PR templates live in `ScottKirvan/.github` (or your org's equivalent) and
apply to this repo automatically via GitHub's community health file fallback.

- Bug reports → `[BUG]` title prefix, `bug_report.md` sections
- Feature requests → `[FEATURE]` title prefix, `feature_request.md` sections
- General → `[GENERAL]` title prefix, `general_report.md` sections
- PRs → fill all checklist sections; no attribution anywhere in the body

Before creating any issue: check for duplicates first — `gh issue list --state open
--limit 100` where the `gh` CLI is available, or the equivalent GitHub search/list
tool (e.g. an MCP GitHub server's `search_issues`/`list_issues`) in hosted sessions
that don't have `gh`. Don't skip the check just because the literal command doesn't
apply in a given environment.
Create issues only when explicitly asked — don't preemptively file future work.

## Sub-Agent Workflow

When using sub-agents for implementation:

- Brief sub-agents on **what** to build, not **how** — implementation decisions belong
  to the sub-agent, which serves as an independent second opinion on the approach.
- Not every implementation choice is "how." A choice is **load-bearing** — and belongs
  in the brief as a stated constraint, not left implicit — if getting it wrong would
  foreclose a decision already made elsewhere, or if fixing it later would cascade into
  sibling components rather than staying local to the one being built. The test: would
  changing this later touch only this component, or would it touch others or
  contradict something already decided? Local and reversible → genuinely "how,"
  delegate freely. Cascading or hard to reverse → state it explicitly in the brief.
  (Architecture — how two components relate, e.g. whether one delegates to the other —
  is the case that's easiest to misclassify as "how" when it's actually load-bearing.)
- Sub-agents follow all conventions in this file except they do not create PRs.
- After a sub-agent completes, review its diff and tests before creating the PR.
  This review is a genuine code review, not a compliance check — evaluate correctness,
  requirement alignment, and test quality independently.
- Simple issues found in review may be fixed directly. Significant deviations from the
  stated requirements or complex problems go back to the sub-agent rather than being
  patched over.
- Create the PR only after review passes.


# Working rules

---

## Sources of truth

Four documents govern this work. In order of precedence:

1. **A direct instruction from Scott**, in the conversation at hand. Always wins.
2. **`STORAGE_CONTRACT.md`** — normative for anything touching files, the QuKi list, images or trash.
3. **`BEHAVIOR_SPEC.md`** — what a screen or interaction does.
4. **`quki-rewrite-path.md`** — how work is sequenced and what each component becomes. Advisory.

Below those, in descending reliability:

5. **The test suite.** The best secondary source in the repository. A test records what someone *decided* should happen.
6. **The source.** Records what got written — which is not always what was intended.

**Everything else in this repository is stale by default.** Prior planning documents, architecture decision records, issue history, changelogs, READMEs and user documentation are not inputs to this work. Much of it was written by agents, describes intentions that were never implemented, or records decisions later reversed without the document being updated. If one of these lands in your context, treat it as noise and say so — do not act on it.

**Code comments are unreliable and must not be trusted.** Two demonstrated examples: one comment asserts an image path "resolves to `<root>/../images/` which matches the images directory at `<root>/images/`" — two different paths claimed to be the same in a single sentence, and the reason images never rendered. Another attributes a retry loop to antivirus interference that was never tested and that the code doesn't actually address.

**A GitHub issue is the same class of unreliable narrative as a code comment — not a way to verify one.** A Kotlin comment ported from the old Flutter app cited specific GitHub issue numbers and a named failing app as the reason for a design choice. A matching issue turned out to actually exist — but that only shows the same narrative was written down in two places, quite possibly by the same agent, in the same rationalizing mood. It does not make the narrative true. Corrected explicitly by Scott after a first pass treated "the issue exists" as if it confirmed the story: *"something being a github issue is no more concrete than the comment in the code — the code is the only source or[ld] truth... github issues are of the same class as code comments. tests are real ground truth. the code is real ground truth. any narrative is suspect."* This is consistent with, not an exception to, "everything else in this repository is stale by default" above — issue history was already named there as noise, and prose staying prose regardless of which file or platform it's filed in is the reason why.

**Read what executes.** If a behavior isn't in the four documents, isn't visible in the code's actual execution, and isn't asserted by a test, it is not established. Ask.

---

## When a document is wrong

It happens. The documents were written from the code and from conversation, and both can be misread.

**Say so. Do not quietly implement around it, and do not quietly comply with it.**

If the spec and the code disagree, report the disagreement with the specific file and line, and wait. If the spec is internally inconsistent, say which two parts conflict. If a rule appears to make a required behavior impossible, that is a finding, not an obstacle to work around.

**The word is usually the bug.** When an implementation is defended as matching the specification and is nonetheless wrong, the specification is what needs fixing — and arguing about the code will not resolve it, because the code is compliant. This project has already lost significant work to exactly that: the word *database* entered an early spec in its broad sense (any organised store, a filesystem included) and was implemented in its narrow sense (a registry that decides what exists). The implementation was defensible against what was written. Raise the wording.

---

## Scope

**Do what was asked. Then stop and report.**

If the work reveals something else worth doing, say what you found and ask. Do not pull the thread. A task that opens three interesting questions is a task plus three things to report, not a licence to investigate all four.

**Do not change direction without asking.** If partway through it becomes clear a different approach is better, stop and make the case. Changing course mid-task and presenting the result is not a shortcut — it spends context and review effort on work that wasn't requested.

Reading one file you were asked to read is the task. Reading the eleven files around it is not.

---

## Do not "fix" deliberate behavior

Several behaviors look like defects on first encounter and are not. Each is recorded in `BEHAVIOR_SPEC.md` and most are pinned by tests.

One item that *doesn't* have a settled resolution yet and must not be waved off as "not a bug": **empty-QuKi handling and the list's `(empty)` preview.** `STORAGE_CONTRACT.md` rule 16 documents "an empty body is never written" as intentional (clearing a QuKi's text leaves its last non-empty content on disk, both in the old Flutter app and in this rewrite — traced directly in both `lib/features/editor/auto_save_controller.dart` and `project/core/src/quKiStore.ts`). But Scott recalls the old app's QuKi list showing `(empty)` for a QuKi whose contents had been deleted — which shouldn't be producible through that guarded path as currently written, in either codebase. Two real, unresolved possibilities, both still live in the *current* TypeScript code: a genuine race in auto-save/index-refresh that lets an empty write through (see the GitHub issues review's #381/#386 entries), or the list's per-row preview (`project/src/screens/listView.ts:105-112`) using the exact same `(empty)` label for "the body is genuinely empty" and "the read failed for an unrelated reason" — indistinguishable in the UI today. Tracked in `notes/dev/rewrite_TODO.md`. Needs investigation and a real fix, not a shrug.

**This rewrite must not quietly drop or substitute an interaction the published app already has**, even when the literal behavior is hard to port and an alternative would be easy. Touch gestures are the concrete case that's already burned this project once: swipe-to-delete (§5/§6) has no native desktop-mouse equivalent, but "no equivalent" is not license to substitute a mouse-only convenience (hover-reveal, in the incident this note records) — mobile is an explicit target platform here, not a hypothetical one, so a substitute that only works with a mouse is a real feature regression, not a reasonable adaptation. Per the Autonomy section above: when the literal spec behavior is genuinely hard to build, state that plainly and stop — don't implement a substitute and present it as a flagged proposal after the fact. Proposing is for genuinely open "how" questions, not for working around difficulty.

---

## Completion and honesty

**Acceptance is Scott's, manual, and per step.** A passing test suite is not a claim of completion. Work proceeds in small discrete pieces, each reviewed and tested by hand.

**Never report something as working that you have not seen work.** This project has a history of work marked complete that had never functioned on a device — across several phases, for the same feature, each time in good faith. It is the single most expensive failure mode here.

State plainly:

- What you implemented and what you actually verified.
- What you could not verify, and why.
- What you changed that wasn't asked for, if anything.
- Anything you're unsure about. Uncertainty reported is cheap; uncertainty concealed is not.

If something doesn't work and you can't make it work, say that. An honest "this approach failed, here's what I learned" is worth more than a plausible implementation that doesn't run.

**Some things cannot be verified by automation at all** — keyboard-aware layout, the feel of live reveal while typing, paste-to-image, selection handles, share targets. These need a real device. Don't claim them from a green suite.

**"Not a bug" is a red flag, not a finding.** Saying it tends to mean "not something I was asked to fix" got blurred into "not actually wrong" — two different questions. Don't say it without doing the full check first: what's the correct/intended behavior here, does the code actually match it, and what's the realistic failure scenario if it doesn't. If a comparable piece of code elsewhere already does it correctly (a sibling implementation, an existing pattern in the same file), that comparison is often the fastest way to tell a real defect from an intentional tradeoff — don't skip it. A real bug doesn't stop being one because it's out of scope for the current task; out of scope means "report it and ask," not "wave it off as fine."

---

## Vocabulary

**QuKi Notes** is the application. A **QuKi** is what it captures. The app has two pages: the **QuKi editor** and the **QuKi list**. Use these exactly; don't substitute "note", "document", "file" or "item".

**The word *database* does not appear in QuKi Notes specifications**, in either sense. Say "the folder", "the files", or "the sidecar" — each names one specific thing whose behavior can be checked.

The same caution applies to any word broader in Scott's usage than in an implementer's: *index*, *node*, *graph*, *store*, *model*, *scene*. If a term could carry either reading, pin it at first use or choose a narrower word.

---

## Repository conventions

- **No AI attribution anywhere.** No generated-by lines, no session URLs, no tool credit in commit messages, PR bodies, code comments or any committed file. Check after every commit and PR and remove anything that was appended automatically.
- **Never commit to `main`** unless explicitly instructed.
- **Conventional commits**, rebase and merge.
