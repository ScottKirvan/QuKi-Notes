# QuKi Notes — rewrite documentation

Four documents. Read this one first; it says what the others are for and which one wins when they disagree.

---

## The documents

| File | What it is | Authority |
|---|---|---|
| **`BEHAVIOR_SPEC.md`** | What QuKi Notes does today, traced from the Flutter source. Screen by screen, including exact copy, timings and colors. | **Descriptive.** The record of current behavior. |
| **`STORAGE_CONTRACT.md`** | The rules governing QuKis on disk. Written as constraints, with an explicit reject list and a two-part acceptance test. | **Normative.** Binding. |
| **`EDITOR_REVEAL.md`** *(see note)* | Currently §12 of the behavior spec. The live-preview reveal rules. | **Normative** where it states rules. |
| **`quki-rewrite-path.md`** | The migration plan — stack choice, what happens to each component, phased sequence. | **A plan.** Advisory; supersedable. |

*Note: the reveal semantics live inside the behavior spec rather than as a separate file. If editor tasks start needing them pasted in the way storage tasks use the contract, split them out.*

---

## Precedence

When two sources disagree, in this order:

1. **A direct instruction from the project owner**, in the conversation at hand. Always wins.
2. **`STORAGE_CONTRACT.md`**, for anything touching files, the QuKi list, images, or trash.
3. **`BEHAVIOR_SPEC.md`**, for what a screen or interaction does.
4. **`quki-rewrite-path.md`**, for how the work is sequenced and what each component becomes.
5. **The Flutter source**, as the tiebreaker on current behavior.

**The Flutter source is evidence, not authority.** It is the record of what the app does, and several of its behaviors are defects these documents exist to correct. Reproduce it only where a document says to.

---

## What these documents are not built from

The rewrite works from first principles. Prior planning documents, architecture decision records, issue history, README content and user documentation are **deliberately excluded** — much of it was written by agents, describes intentions that were never implemented, or documents decisions that were later reversed without the document being updated.

**Code comments are excluded too.** They are unreliable in this codebase, and demonstrably so: one comment claims an image path "resolves to `<root>/../images/` which matches the images directory at `<root>/images/`" — two different paths asserted as equal in a single sentence, and the reason images have never rendered. Another attributes a retry loop to antivirus interference that was never tested.

**The test suite is the exception, and it is the best source in the repository.** A test states what someone decided should happen; source states what got written; comments state what someone believed at the time. Much of what `BEHAVIOR_SPEC.md` records exists only in tests — the list auto-continue rules, the intraword emphasis distinction, which markdown constructs are deliberately *not* recognised, the reveal boundary. When a question isn't answered by these documents, look at the tests before anything else.

**Read what executes.** If behavior isn't in these documents and isn't visible in the code's actual execution or asserted by a test, it isn't established — ask rather than infer.

---

## Vocabulary

**QuKi Notes** is the application. A **QuKi** is what it captures. The app has two pages: the **QuKi editor** and the **QuKi list**.

The word **database** does not appear in QuKi Notes specifications, in either its broad sense (any organized store, a filesystem included) or its narrow one (a registry with a schema). It is banned because both readings appearing in one early spec produced a storage design nobody chose — an implementation that was defensible against what was written, and wrong.

The same caution applies to any term broader in the project owner's usage than in an implementer's: *index*, *node*, *graph*, *store*, *model*, *scene*. Pin the meaning at first use, or choose a narrower word.

**If an implementation is defended as matching the specification and is nonetheless wrong, the word is the bug.** Raise the wording rather than arguing the code — an argument about code against a specification that supports the code cannot be won.

---

## This is the same app

Not a successor, not a rewrite-as-new-product. **The same QuKi Notes, with its defects fixed**, on a different stack.

That settles several things that would otherwise be guessed at:

- It ships under the **existing Play listing and package id**. The approved all-files-access permission, the install base and the beta testers all carry forward; a new listing would start that from zero.
- It **opens the user's existing folder as-is**. No conversion, no migration step, no renaming.
- Existing users **update in place**. They should find their QuKis where they left them, with the same names.
- Where behavior changes, it changes because it was **wrong**, not because this is a new product. The changes are enumerated and each has a reason.

---

## Acceptance

**Acceptance is manual and belongs to the project owner.** Work proceeds in small discrete steps, each reviewed and tested by hand. Nothing in these documents constitutes an automated gate, and a passing test suite is not a claim of completion.

Tests and regression coverage are expected as a matter of course. `quki-rewrite-path.md` lists the specific behaviors worth protecting in CI — chosen because they break silently, or because they are deliberate decisions that look like defects to someone meeting them cold. That list is about regression, not sign-off.

---

## Status

Every behavior in these documents was traced to an implementation in the Flutter source at **v0.24.1**. Where source and comments disagreed, the source is what was recorded. Where the source and a design decision disagreed, the decision is recorded as the target and the current behavior is recorded alongside it, marked as such.

Nothing here has been validated against a running CodeMirror implementation. **The stack recommendation rests on an untested assumption** — that CodeMirror can do span-level immediate reveal with inline widget substitution. Phase one of the plan exists to test exactly that, and it is a genuine go/no-go gate, not a formality.
