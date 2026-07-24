# Block Indentation — Feature Spec

This document specifies what it actually takes to make indented block content (nested lists, blockquotes) render correctly in QuKi-Notes — including wrapped continuation lines, not just the first visual row of each block. Formal decision record: `notes/dev/decisions.md` → ADR-34. This is the third time this exact constraint has blocked a piece of work (list nesting #241, then blockquote indentation twice during ADR-33 Stage 4) — this document exists so the fourth time doesn't happen.

---

## The problem, confirmed with evidence, not theory

Blockquote content indentation (ADR-33 Stage 4) was implemented as leading blank characters reserved before the content — the same trick already proven for checkbox/list marker width. Device-tested and screenshotted against real GitHub rendering: it works for the *first visual row* of a blockquote line. It does not work for wrapped continuation rows. A long blockquote line that word-wraps has its first line correctly indented; the wrapped continuation snaps back to the unindented left margin.

This is not a bug in the specific character count or a tunable constant — it is a structural property of how the editor renders text. `QuikiRenderEditor` (`quiki_render_editor.dart`) lays out the **entire document as one continuous `TextPainter`**, one fixed width, one paragraph. Leading blank characters only affect where a *logical* source line's rendered text begins. Flutter's automatic word-wrap doesn't know to re-apply "start N characters in" after it breaks a line into multiple *visual* rows — it just continues from the paragraph's own left edge. There is no per-line or per-block width/offset in a single `TextPainter` layout.

Issue #241 (nested/indented lists) already predicted this exact wall in its own "Additional Context" when it was filed: *"The single-`TextPainter` model also makes visual indentation non-trivial (same challenge as blockquotes — requires custom paint offsets)."* That was theory at filing time. It is now confirmed, reproducible fact.

## Why this can't be patched around

Indentation that survives word-wrap is not a text-styling property — it's a **layout box property**, the same category as CSS `margin-left`/`padding-left` on a block element. Every real text-layout engine (browsers included) handles this the same way: an indented block gets its own layout box, narrower than its container, offset horizontally, and *that* box's line-breaking happens within its own reduced width. There is no way to fake this with character tricks, because the wrap point itself needs to happen earlier (at the narrower width) — you can't wrap correctly at the full document width and then just shift the result over.

Concretely, in this codebase: `QuikiRenderEditor.performLayout()` calls `_textPainter.layout(maxWidth: paintWidth)` exactly once, for the whole document. Every coordinate-mapping function that exists — `positionForOffset`, `getOffsetForCaret`, `getPositionForOffset`, and the tap-hit-testing for links/checkboxes/images — is built on that single `TextPainter`'s `getOffsetForCaret`/`getPositionForOffset`. This is not a small, isolated piece of the editor; it's the coordinate system the entire input/cursor/selection layer is built on.

## What a real fix requires

Split the document's layout into **runs** — maximal sequences of consecutive lines sharing the same indent level (0 for ordinary text, N for a nested list item or blockquote at depth N). Each run gets laid out with its own `TextPainter`, at a reduced `maxWidth` (full width minus that run's indent) and painted at an X-offset (indent level × indent unit). Runs stack vertically; a `QuikiRenderEditor` with one run behaves exactly as it does today (the common case, indent level 0, is unaffected).

**Scope this surgically, not as a ground-up rewrite.** `RenderModel.build()` already does the hard, correctness-critical work of producing one flat rendered string with bidirectional source↔rendered offset maps and per-character style resolution (nested inline formatting, reveal/collapse, etc. — the whole ADR-33 effort). That does not need to be rebuilt. What's needed:

1. `RenderModel` additionally exposes **run boundaries**: for the flat rendered text it already produces, a list of `(startOffset, endOffset, indentLevel)` runs, in order. This is a thin addition — the information ("what indent level is line X at") already needs to exist per block element; it's a matter of surfacing it, not recomputing the whole render pass.
2. `QuikiRenderEditor` changes from one `TextPainter` to a list of `TextPainter`s, one per run, each built from the corresponding *slice* of the existing flat rendered `TextSpan`, laid out at `maxWidth - runIndent`, and positioned at `(runIndent, cumulativeY)`.
3. Every coordinate-mapping function gains one extra step: given a global rendered offset, find which run it falls in (the runs are sorted and non-overlapping, so this is a straightforward lookup), compute the offset relative to that run's `TextPainter`, delegate to that `TextPainter`'s existing `getOffsetForCaret`/`getPositionForOffset`, then translate the result by the run's `(runIndent, cumulativeY)` origin. Given a local tap position, find which run's vertical band it falls into first, then delegate within that run. The *logic* of each function doesn't change — it gets one level of indirection in front of it.

This keeps `RenderModel`'s existing, already-correct offset-mapping and inline-formatting machinery completely intact, and confines the actual rewrite to `QuikiRenderEditor`'s layout/paint/hit-test layer — the part that's genuinely constrained by the single-`TextPainter` assumption.

## What indent level actually comes from

- **Blockquotes, including nested (`>>`, `>>>`)** — in scope for this spec, not deferred. Depth is computed by peeling `>` prefixes off the start of the line: each `>` (optionally followed by one space before the next `>` or the content) consumes one level. `> text` = depth 1, `>> text` / `> > text` = depth 2, and so on — a permissive, greedy-consume heuristic in the same spirit as this codebase's existing HTML-tag detection (ADR-33 Stage 3), not full CommonMark grammar validation. `MdElement`'s marker length (`_srcMarkerLen`, already shared with `ol`) becomes "however many characters the depth-counting loop consumed," generalizing the single-level `1` or `2` it holds today.
- **Nested list items** (#241's original ask): indent level needs to be *detected* per line from leading whitespace (2- or 4-space, or tab), which today the parser doesn't do at all — every list-line check in `MdParser.parse()` is anchored at column 0 (`line.startsWith('- ')`), so an indented line matches nothing and falls through to plain-paragraph handling. This is genuinely new parser work, separate from and layered on top of the rendering fix.

## Nested blockquotes need more than depth — they need per-level stripe continuity

Once blockquote depth is dynamic, the render side needs to paint **one stripe per level**, not one stripe per line. And the levels don't all span the same lines — matching real GFM/GitHub nested-blockquote rendering (nested `<blockquote>` elements: an outer quote's border spans its entire range *including* any deeper-nested content inside it; an inner level's border only spans where that deeper nesting actually continues). Concretely:

```
> level 1 line
>> level 2 line
> level 1 again
```

renders with stripe-level-1 spanning all three lines continuously, and stripe-level-2 spanning only the middle line. This means run/stripe continuity (already needed for the plain multi-line-blockquote case shipped in ADR-33 Stage 4 — `groupBlockquoteRuns`) generalizes from "is this line a blockquote, yes/no" to **per-level**: a level-K stripe continues across consecutive lines whose depth is `>= K`, independent of whether depth exactly matches from one line to the next. Each level's stripe sits at its own X position in the indent gutter (level 1 outermost/leftmost, deeper levels progressively further right, content starting after the deepest active level).

## Explicitly deferred (not part of this spec)

- **Tab/Shift+Tab keyboard handling** (#77) — creating/adjusting list nesting depth interactively. Depends on list-nesting parser support existing first; its own brief once that lands.
- **Mixed ordered/unordered nesting, block-relative numbering at depth > 0** — real behavior questions once list nesting exists, not blocking the rendering foundation.

## Test strategy

This is layout/paint code — the same honest limitation that applied to the blockquote vertical-alignment fix applies here: Flutter's widget-test environment renders text as placeholder boxes, not real glyphs, so **run boundaries, indent math, and coordinate-translation logic are reliably unit-testable** (assert on computed positions/widths directly, and the golden-test technique proven useful for checking horizontal layout during ADR-33 Stage 4 applies here too), but **final on-screen visual correctness needs real device verification**, same as every rendering fix in this project. Say so honestly in any implementation report rather than asserting pixel-perfect confidence that hasn't been earned.

## Build stages

Each stage independently shippable, per project convention.

| Stage | What ships | Key milestone | Proves |
|---|---|---|---|
| 1 — **merged** (PR #292, merged 2026-07-23) | Multi-run rendering foundation in `QuikiRenderEditor` + `RenderModel` run-boundary exposure, applied to blockquotes **including nested depth** (`>`, `>>`, `>>>`) — parser depth-counting, multi-stripe painting with per-level continuity | Blockquote wrapped continuation lines indent correctly (the exact bug open across three prior rounds), *and* nested blockquotes render with the correct number of stripes spanning the correct ranges. Closed #242, #237. **Device-tested and confirmed by the project owner before merge**, including the 16px/level indent and 4px stripe gap. | The mechanism proven on its hardest in-scope case, not just the easy one — deliberately not deferring the nested case to avoid re-discovering it doesn't work later |
| 2+3 — **merged** (PR #294, merged 2026-07-24) | List-item indent-level detection in `MdParser` (leading whitespace → nesting depth) wired directly into Stage 1's rendering foundation, in one combined brief. **Combined rather than split**, unlike the original plan below: shipping Stage 2 alone would make an indented list line go from "renders as literal text" to "renders as a bullet/checkbox glyph flush at the left margin, indistinguishable from a top-level item" — a user-visible half-working state, not a clean incremental step (unlike ADR-33's stages, which never had this problem). Also includes list auto-continue (Enter key) preserving the current line's indentation when continuing a nested item, and the Tab key inserting a literal tab character (previously silently swallowed by Flutter's default focus-traversal system) — letting the keystroke through only, not interactive indent/dedent (that's still Stage 4 / #77). Two rounds of device-test fixes: ol numbering across a deeper-nested interruption now correctly continues (`1. / 1. / 2.`, not `1. / 1. / 1.`); list/ol/checkbox markers repainted as a Canvas gutter decoration instead of inline text (fixes wrapped-row misalignment, mirroring Stage 1's blockquote fix); a marker-gutter-leak bug where a non-marker line merged into the same run as a marker-bearing line purely because their `indentLevel` matched (fixed by requiring `RenderRun.listMarker` to also match for two lines to merge — confirmed via a real pasted-document repro, not a synthetic one); list-marker vertical alignment brought in line with the checkbox box's already-tuned formula. Closed #241. | `- item` / `  - sub-item` parse as two nesting levels *and* render with real, wrap-correct visual indentation | #241's core ask, fully working — confirmed via two rounds of real device testing |
| 4 | Tab/Shift+Tab indent handling (#77) | Users can create/adjust list nesting interactively | #77 |

*(Stages 2 and 3 were originally planned as separate briefs — see the git history of this file for the original two-row version — but were combined at brief-writing time; the reasoning is in the Stage 2+3 row above.)*

---

**See also**: `notes/dev/decisions.md` → ADR-34, `notes/dev/nested_inline_markdown.md` (ADR-33 — the inline-formatting engine this indentation work sits alongside, not inside), issue #241, issue #77.

**Last Updated**: 2026-07-22
