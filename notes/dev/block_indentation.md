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

- **Blockquotes** (already shipped, ADR-33 Stage 4): a fixed, single indent level today (no nested `>>` support yet — see "Explicitly deferred" below). This is the natural first proof point for the new mechanism, since it needs zero new parser work — the indent level for a blockquote line is already implicit (1), it's the *rendering* of it that's broken.
- **Nested list items** (#241's original ask): indent level needs to be *detected* per line from leading whitespace (2- or 4-space, or tab), which today the parser doesn't do at all — every list-line check in `MdParser.parse()` is anchored at column 0 (`line.startsWith('- ')`), so an indented line matches nothing and falls through to plain-paragraph handling. This is genuinely new parser work, separate from and layered on top of the rendering fix.

## Explicitly deferred (not part of this spec)

- **Nested blockquotes** (`>>`, multiple levels) — the rendering foundation this spec describes would support it once blockquote indent level is computed dynamically instead of fixed at 1, but detecting and painting multiple stacked border stripes per line is its own follow-on, not required to fix the wrapped-line bug that's actually blocking things today.
- **Tab/Shift+Tab keyboard handling** (#77) — creating/adjusting list nesting depth interactively. Depends on list-nesting parser support existing first; its own brief once that lands.
- **Mixed ordered/unordered nesting, block-relative numbering at depth > 0** — real behavior questions once list nesting exists, not blocking the rendering foundation.

## Test strategy

This is layout/paint code — the same honest limitation that applied to the blockquote vertical-alignment fix applies here: Flutter's widget-test environment renders text as placeholder boxes, not real glyphs, so **run boundaries, indent math, and coordinate-translation logic are reliably unit-testable** (assert on computed positions/widths directly, and the golden-test technique proven useful for checking horizontal layout during ADR-33 Stage 4 applies here too), but **final on-screen visual correctness needs real device verification**, same as every rendering fix in this project. Say so honestly in any implementation report rather than asserting pixel-perfect confidence that hasn't been earned.

## Build stages

Each stage independently shippable, per project convention.

| Stage | What ships | Key milestone | Proves |
|---|---|---|---|
| 1 | Multi-run rendering foundation in `QuikiRenderEditor` + `RenderModel` run-boundary exposure, applied to blockquotes (already at a fixed indent level, zero new parser work needed) | Blockquote wrapped continuation lines indent correctly — the exact bug that's been open across three prior rounds | The core mechanism works, using the simplest possible case |
| 2 | List-item indent-level detection in `MdParser` (leading whitespace → nesting depth, parent-child tracking) | `- item` / `  - sub-item` parse as two nesting levels | Parser side of #241 |
| 3 | Wire Stage 2's parsed indent levels through Stage 1's rendering foundation | Nested lists render with real, wrap-correct visual indentation | #241's core ask, fully working |
| 4 | Tab/Shift+Tab indent handling (#77) | Users can create/adjust list nesting interactively | #77 |
| — | Nested blockquotes (`>>`) | Separate future spec | Deferred |

---

**See also**: `notes/dev/decisions.md` → ADR-34, `notes/dev/nested_inline_markdown.md` (ADR-33 — the inline-formatting engine this indentation work sits alongside, not inside), issue #241, issue #77.

**Last Updated**: 2026-07-22
