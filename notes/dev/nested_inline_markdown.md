# Nested Inline Markdown — Feature Spec

This document specifies what QuKi-Notes' inline markdown parsing (bold, italic, strikethrough, inline code, links, images, autolinks) needs to do to match how GitHub and Obsidian actually render markdown — including nested and combined formatting, and formatting inside list items and headings, which do not work today. Formal decision record: `notes/dev/decisions.md` → ADR-33. This document is the narrative and the scope boundary — read it first.

---

## The problem

Issue #240 was filed as "inline formatting doesn't render inside list items" — `- **important item**` shows literal asterisks instead of bold text. That's real, but it turned out to be a symptom of something bigger, found during a full code review of `MdParser` (`packages/markdown_live_editor/lib/src/md_parser.dart`) on 2026-07-21.

**The actual gap: nested and combined inline formatting doesn't work anywhere in QuKi-Notes today — not in list items, not in headings, not in a plain paragraph.**

Trace `**bold *italic* text**` through the current inline scanner:

1. It sees `**` at position 0 and opens a bold element.
2. It searches forward for the next literal `**` sequence — and does not care what's between the delimiters.
3. The single asterisks around `italic` never form a `**` pair, so the scanner skips past them invisibly. The first real `**` match is the closing one at the end.
4. One `bold` element gets created spanning the *entire* string. The scanner jumps past all of it and never looks inside that range again.

The result: the whole thing renders bold, and the literal characters `*italic*` show up as visible bold text — not hidden as delimiters, not italicized, just sitting there because nothing ever re-scanned the interior. This is a "find nearest matching pair, consume, move on" scanner. It cannot recurse, and it never could — independent of whether the surrounding line is a list item, a heading, or a paragraph.

A second, related gap: block-prefixed lines (headings `# `, list items `- `/`1. `/`- [ ] `) consume the *entire* line as one opaque element during parsing — inline scanning only runs on the trailing `else` branch (plain paragraph lines). So today, `# **bold** heading` doesn't render bold either — headings have the identical bug to list items, just never reported because nobody happened to try it.

## Why "just add recursion" isn't the fix either

The instinct is a stack-based scanner — push on an opening delimiter, pop on its match. That's the right shape, but a naive version of it still won't match GitHub or Obsidian, because real markdown emphasis resolution isn't "find the nearest matching pair." Two concrete cases where naive stacking diverges from GitHub's actual output:

- `foo_bar_baz` — GitHub does **not** italicize this. Underscore emphasis is disallowed *inside* a word.
- `foo*bar*baz` — GitHub **does** italicize this. Asterisk emphasis is allowed intraword.

A stack that treats `_` and `*` identically can't produce this distinction, because the rule isn't about matching delimiters — it's about what character sits immediately before/after the delimiter run (letter vs. whitespace vs. punctuation). This is exactly the kind of thing CommonMark's spec already solved, in public, with a published test suite, precisely so every implementation (GitHub's `cmark-gfm`, Obsidian's CodeMirror 6 markdown mode, everyone else) produces the same output instead of each inventing its own close-enough approximation. We're not going to re-derive this from first principles — we're going to implement the documented algorithm.

## The path forward

**Adopt CommonMark's delimiter-run algorithm** for the inline elements QuKi-Notes supports, and use CommonMark's own published spec examples as regression tests for that subset — "does this match GitHub" becomes a pass/fail check against a public spec, not a judgment call.

Concretely, the algorithm (same shape used by every compliant implementation):

1. Scan the line once, left to right, recording each delimiter run (`*`, `**`, `_`, `__`, `~~`, `` ` ``) along with whether it's **left-flanking** (can open) and/or **right-flanking** (can close) — determined by what character is immediately adjacent on each side (whitespace, punctuation, or a word character), plus the intraword rule that disallows `_` (but not `*`) from opening/closing next to a letter.
2. Resolve delimiter runs into actual emphasis/strong/strikethrough spans by matching openers to the nearest valid closer, same character, respecting the flanking rules — this can nest arbitrarily (`~~**_text_**~~` resolves as strikethrough containing strong containing emphasis).
3. Inline code spans (`` `code` ``) are resolved *first*, before emphasis, and everything inside a code span is fully literal — no emphasis, no links, nothing. This part QuKi-Notes already does correctly today for the single-level case; it needs to keep doing so with the same precedence once nesting is added elsewhere.
4. Links (`[text](url)`) and images (`![alt](url)`) are bracket-matched, not delimiter-run based — link/image *text* can itself contain nested emphasis (`[**bold link**](url)`), but a link cannot contain another link.

## Reveal-on-cursor semantics

**Decided 2026-07-21**: when the cursor is anywhere inside a nested/combined run, the *entire outermost element* reveals as raw source — not just the innermost piece the cursor happens to be in.

Example: `preface **bold *italic ~~strike~~ italic* bold** postface` — cursor anywhere from the first `**` to the last `**` reveals the whole `**bold *italic ~~strike~~ italic* bold**` span as raw, editable markdown text. Moving the cursor out of that whole range collapses it back to rendered form.

This is a deliberate simplification, not just a product preference: it means the reveal check only ever needs to find the *outermost* ancestor containing the cursor and test against that one range — it does not need per-level partial-reveal logic, and it does not need to solve "what does it look like when the outer span is collapsed but an inner span is revealed." One check, one range, same rule ADR-31 already established for every other element type ("the element containing the cursor is revealed").

## Scope

**In scope** — the inline markup subset QuKi-Notes already targets, made to nest and combine correctly, and made to work inside list items and headings (not just paragraphs): bold (`**`/`__`), italic (`*`/`_`), strikethrough (`~~`), inline code (`` ` ``), links (`[text](url)`), images (`![alt](url)`), bare URL autolinks.

**Backslash escapes — in scope (decided 2026-07-21).** Any ASCII punctuation character preceded by `\` renders as a literal character rather than being interpreted as markdown syntax — `\*not italic\*` shows literal asterisks, `\[not a link\]` shows literal brackets. A backslash before a non-punctuation character (a letter, digit, whitespace) is literal too — both the backslash and the character show as typed; it is not an error and not silently dropped. Escaping only suppresses *inline* markup interpretation — it does not, for example, stop a line from being detected as a list item or heading (block-prefix detection happens before inline scanning; escaping is an inline-scan concern). Not adopted: CommonMark's backslash-before-newline "hard line break" convention — that exists to force a line break during HTML paragraph reflow, and QuKi-Notes' engine never reflows paragraphs (every source newline is already a real visual line break in the plain-text buffer), so there is nothing for that convention to do here.

**HTML — detect, don't parse.** A line or inline span that matches HTML tag syntax (`<div>`, `<span style="...">`, `<!-- comment -->`, etc.) must be recognized as HTML and excluded from inline markdown scanning entirely — passed through as literal text. This matters concretely: without detection, `<div style="border: 1px solid *gray*">` would have its `*gray*` misread as italic today, because nothing currently knows that line is HTML rather than a paragraph. Detection only — QuKi-Notes does not render HTML (no DOM, no `<script>` execution, nothing); it just needs to *not* mis-parse markdown-special characters that happen to appear inside an HTML tag.

**Explicitly excluded from this spec:**
- **Tables** — genuinely wanted before v1 (not a "someday" item), but scoped out of this effort. Tables are a block-level, multi-line construct with their own alignment/column-parsing rules and deserve their own spec once this inline-engine work is proven. Track as a follow-up.
- **List-block nesting/indentation** (#241) and **Tab/Shift+Tab indent handling** (#77) — both depend on this work (list content needs to flow through the same recursive inline engine once list nesting exists) but are their own architectural surface (indent-level tracking, visual indentation rendering, keyboard input handling) and get their own brief once this lands.
- Footnotes, reference-style links (`[text][ref]` + `[ref]: url` definitions), HTML entity references (`&amp;`), fenced code blocks, blockquotes beyond today's raw-passthrough behavior — not part of QuKi-Notes' targeted GFM subset; no change from current behavior.

## What this changes architecturally

Stated as correctness requirements, not implementation prescription — the implementation session decides the actual data structures:

- Inline elements must be representable as **nested**, not strictly flat/non-overlapping. Today's element list assumes exactly one active element at any source position; that assumption no longer holds once `**bold *italic* text**` needs to produce two elements (bold, and italic nested inside it) covering overlapping source ranges.
- Rendered style at any character must be the **combination** of every currently-open ancestor's style (bold + italic + strikethrough simultaneously where they're nested), not a single element's style.
- Reveal resolution must find the **outermost** ancestor whose range contains the cursor (see "Reveal-on-cursor semantics" above) — not the innermost, and not every level independently.
- The existing bidirectional source ↔ rendered offset mapping guarantee (every source offset maps to exactly one rendered offset; collapsed delimiters map to their content's rendered boundary) must continue to hold with nesting.
- One inline-scanning implementation must serve paragraphs, headings, and list-item content after prefix stripping — not three separate code paths. (Today there are, confusingly, effectively three: the live paragraph-only scanner in `md_parser.dart`, and a second, *unreachable* implementation in `span_parser.dart` — dead code left over from the pre-ADR-31 architecture that already does some of this inline scanning, unreachable because `QuikiRenderEditor` never calls `TextEditingController.buildTextSpan()`. That dead code should be deleted as part of or before this work, not built around.)

## Test strategy

Adapt relevant cases from CommonMark's official spec test suite (commonmark.org's `spec.json` — publicly published, versioned, JSON input/expected-output pairs) for the supported subset — emphasis/strong resolution, intraword rules, code-span precedence, nested nesting, backslash escapes — as permanent regression tests, in addition to QuKi-Notes-specific cases (list-item content, heading content, the whole-chain reveal rule). "Does this match GitHub" should be checkable against a cited spec example, not eyeballed.

**Reference implementation**: [github/cmark-gfm](https://github.com/github/cmark-gfm) — GitHub's own fork of the reference `cmark` C implementation, extended with the GFM features (strikethrough, autolinks, task lists). This is literally what renders markdown on github.com. BSD-2-Clause licensed. Use it as a correctness oracle when a behavior question comes up (its `inline.c` implements the delimiter-stack/flanking-rule resolution this spec targets), and pull GFM-specific test cases from its test suite for strikethrough/autolink coverage the base CommonMark suite doesn't include. Not a runtime dependency — it's C, and more importantly, using it (or any AST-producing library) at runtime would repeat the mistake ADR-30 already rejected for the `markdown` Dart package: it doesn't expose source character offsets, which ADR-31's reveal/collapse model requires. QuKi-Notes needs its own Dart implementation; cmark-gfm is the reference for what that implementation should produce, not code it runs.

## Build stages

Each stage independently shippable, per project convention (see ADR-31's staged rollout). Stage 2 and Stage 3 are independent of each other — neither depends on the other, only on Stage 1's engine — so the order between them is a priority call, not a dependency. Originally sequenced HTML detection before list-item scanning; reordered 2026-07-21 once list-item scanning turned out to be the immediately felt gap in actual use (the original #240 report), while HTML detection guards a rarer edge case.

| Stage | What ships | Key milestone | Status |
|---|---|---|---|
| 1 | Recursive/nested inline engine, paragraphs and headings only (no list integration yet) | Nested and combined formatting works and matches CommonMark subset test cases; zero regression on existing single-level bold/italic/strikethrough/code/link/autolink behavior; whole-chain reveal implemented; link text also recursively scanned | **Complete** (PR #276, merged 2026-07-21) |
| 2 | List-item and checkbox content flows through the same Stage 1 engine (closes #240 as originally filed) | Bold/italic/links/etc. render correctly inside list items; headings already fixed by Stage 1 | Next up |
| 3 | HTML block + inline detection — markdown scanning suppressed inside detected HTML, passed through raw | Closes the `*gray*`-inside-an-attribute misparse risk | Not started |
| — | List nesting/indentation (#241), Tab/Shift+Tab indent handling (#77) | Separate spec/brief, after this lands | Not started |
| — | Tables | Separate spec/brief, wanted before v1 | Not started |

---

**See also**: `notes/dev/decisions.md` → ADR-33 for the formal decision record, `notes/dev/design_spec.md` → "Editor rendering engine (ADR-31)" for the surrounding architecture this plugs into, issues #240 (nested inline formats), #241 (nested/indented lists), #77 (Tab indenting).

**Last Updated**: 2026-07-21
