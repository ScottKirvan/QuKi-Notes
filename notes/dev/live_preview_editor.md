# Live-Preview Markdown Editor — Feature Spec (Plain English)

This document explains, in plain language, what the QuKi-Notes editor needs to do, why the last two attempts at it fell short, and how we're actually going to build it. Technical detail and the formal decision record live in `notes/dev/decisions.md` → ADR-31 and `notes/dev/design_spec.md` → "Editor rendering engine." This document is the narrative — read it first.

---

## The approach, in short

The note's text is always the raw markdown source — that never changes, that never gets converted into some other internal format, and that's what gets saved to disk. On top of that source, we read through it once and figure out which stretches of text are "a heading," "a bold word," "a checkbox," "a link," "an image," and so on. Each of those pieces remembers exactly which characters of the original text it came from.

Normally, we show you the *rendered* version of each of those pieces: a heading in big text with no `#` in sight, a checkbox that actually looks like a checkbox, a link that just shows its name instead of the full `[text](url)` syntax, an image that's an actual picture instead of a line of markdown. But the moment your cursor lands inside one of these pieces, we swap it back to showing the raw ingredients — the actual `# ` or `[link](url)` — so you can edit it directly, character by character, exactly like a plain text box. Move your cursor away, and it renders again.

A few consequences of that fall out naturally:

- Moving the cursor past a rendered piece with the arrow keys jumps over it in one step, the way you'd expect — you don't arrow through invisible characters you can't see.
- Tapping into a rendered piece puts your cursor at whichever end is closer to where you tapped, rather than trying to guess a precise spot inside content that isn't showing its real characters. (This is standard behavior, not a shortcut we're taking — no editor we researched, including Obsidian, does better than this.)
- The genuinely tricky engineering part is that Flutter's normal text box has a deep assumption baked in: what's on screen and what's in the buffer are the same length, character for character. We're not going to fight that assumption — we're going to build our own small text box from scratch that talks to the phone/OS keyboard directly and handles cursor placement itself, using the "ingredient list" above to know where things really are in the source. That's more work up front, but it's a known, well-trodden path — it's essentially what code editors like the one inside VS Code do internally — and it's the only way to get real rendering and real raw-source-editing at the same time.

The rest of this document explains why we didn't build it this way from the start, why it matters, and how we're going to build it in stages so it doesn't become another false start.

---

## The problem we're solving

QuKi-Notes' entire pitch is: open the app, type, and it just looks right. Not "type markdown syntax and squint at it" — genuine WYSIWYG. A heading should look like a heading. A checkbox should look like a checkbox. A link should show its label, not a URL. And critically, none of that should get in the way of editing — the moment you want to change something, your cursor should be able to land right on it and show you the real markdown underneath, immediately, with no mode switch or special gesture.

That combination — real rendering *and* instant raw-source editing at the cursor — is the hard part. It's easy to build one or the other. Getting both at once, in a buffer that's always plain markdown text (never a hidden proprietary format), is the actual feature.

## Why the last two attempts fell short

The first version of this editor (`ADR-30`) took a shortcut: instead of truly rendering markdown, it just hid the syntax characters. `**bold**` stayed as eight literal characters in the invisible layer Flutter uses for cursor math, but six of them (the two pairs of `**`) were painted with zero size and no color, so visually you only saw `bold`. This trick works, but only under one condition: the "rendered" text has to be *exactly the same length* as the raw text, character for character. That's fine for hiding a delimiter and leaving a gap. It falls apart the instant you want a heading to have no `#` at all and be a different font size, or a link to show a five-word label instead of a forty-character URL, or an image to show an actual picture instead of a line of text.

We didn't realize that constraint was the actual ceiling of the design — it got written down as a permanent architectural rule ("character-count invariant") rather than recognized as a workaround with a hard limit. That's the root of what went wrong next.

The second attempt (PR #194) was tasked with fixing three visible bugs: list bullets weren't showing, checkboxes were nearly invisible, and the formatting toolbar sometimes edited the wrong line. The bullet fix was fine — swapping `- ` for `• ` happens to be a same-length substitution, so it slipped through the same-length constraint without anyone noticing there was a constraint at all. But the checkbox and ordered-list fixes were not real fixes — they just made the *raw, literal* `[ ]` brackets and numbers more visible/legible. Nothing was actually rendering: checkboxes were still shown as literal bracket text, and ordered-list numbers were still whatever digits the user happened to type, not a real computed sequence. Both "fixes" were structurally incapable of doing more than that, because the underlying model can only make existing characters more or less visible — it can't substitute in genuinely different, differently-sized content. The brief for that work asked for something the architecture could never deliver, and the implementation faithfully — and therefore incorrectly — matched that brief.

Digging into *why* nobody caught this sooner turned up the real root cause: **Flutter's standard text-editing widgets can't do this at all, at an engine level.** The obvious tool for embedding something like an image inline — `WidgetSpan` — always counts as exactly one character for cursor-placement purposes, no matter how much source text it's meant to represent. This isn't a framework quirk we can file a bug against and wait for a fix; it's confirmed directly by Flutter's own engineers as baked into the text-layout engine itself. No Flutter package or public project has solved genuine variable-length live-preview markdown editing on Flutter's stock text field. This was never a "skill issue" in the implementation — it was an architecture that could not succeed no matter how carefully it was built on top of.

## Why this matters

QuKi-Notes' whole premise is capture without friction — the manifesto's velocity and information-first principles both depend on the note looking right immediately, with zero extra steps. A markdown editor that only *sort of* renders — hiding syntax but never truly formatting — isn't a smaller version of that promise, it's a different, weaker product. Checkboxes that look like raw brackets and ordered lists with wrong numbers aren't cosmetic bugs; they're the exact thing the app is supposed to get right.

This is also, plainly, a make-or-break piece of the app. If we can't deliver real live-preview markdown editing, there isn't a compelling reason for QuKi-Notes to keep going as a separate product from any other plain note-taking app. That's the stakes this deserves.

There's a secondary upside worth naming without letting it distort the near-term plan: nothing in the Flutter ecosystem currently does this correctly. If we get it right, this is a genuine candidate for extraction into a standalone, publishable Flutter package — something that doesn't exist today. That's a real long-term goal, but it's a "don't paint ourselves into a corner" consideration, not a reason to over-build before QuKi-Notes' own needs are met.

## The path forward

We looked at how other editors that already do this — most relevantly, Obsidian's "Live Preview" mode, which is built on an editor engine called CodeMirror 6 — solve the same problem, since re-deriving this from scratch would be a waste of a solved problem.

Their approach, translated into plain terms:

1. **Read the note once and make a list of "pieces."** Each piece — a heading, a list item, a checkbox, a bold word, a link, an image — remembers exactly which stretch of the original text it came from (its "source range").
2. **Decide what to show based on where the cursor is, not by re-reading the whole note.** Every time the cursor moves, we just check: is it inside this piece's source range or not? If yes, show the raw markdown for that piece. If no, show its rendered form. This check is cheap — it's why editors like Obsidian don't lag when you click around, even in long documents.
3. **Only re-make the "list of pieces" when the text actually changes**, not on every cursor move. Typing something new triggers a fresh pass; moving the cursor around doesn't.
4. **Arrow-key movement treats a rendered piece as one step, not many.** If a link is showing as just its label, pressing the right-arrow key to move past it moves past the whole thing in one keystroke — you're not secretly arrow-keying through forty invisible characters.
5. **Tapping into a rendered piece places your cursor at whichever end is closer**, rather than trying to calculate an exact spot inside content that isn't showing its real characters one-for-one. This is a deliberate simplification that matches what every editor we looked at actually does — nobody has solved "perfectly precise cursor placement inside collapsed content," so we're not going to invent that wheel either.
6. **We have to build our own small text box, not use Flutter's built-in one.** This is the part that makes the whole thing possible: Flutter's normal text field assumes the visible text and the buffer text are the same, always. We're not fighting that assumption — we're setting it aside and writing our own version that talks to the phone's keyboard directly and manages the cursor ourselves, using the "list of pieces" from step 1 to always know where things really live in the source text. This is real, proven engineering — it's fundamentally the same approach real code editors use — but it is a genuine build, not a small patch, and it needs to be treated that way.

Because this is a real rebuild and not a tweak, we're doing it in stages, each one shippable and checkable on its own before moving to the next:

1. Build the custom text box first, with no markdown rendering at all — just prove it behaves like a normal text field (typing, cursor, selection, copy/paste) before adding any complexity on top.
2. Add the "list of pieces" and the reveal/render swap for the simplest cases (headings, bold, italic).
3. Get cursor movement and tap-placement feeling right around rendered pieces specifically — this is where most of the subtlety lives.
4. Bring back lists, checkboxes, and ordered-list numbering — done as real rendering this time, closing out the bugs from PR #194 correctly instead of patching around them again.
5. Add real inline images — something that was flatly impossible under the old model.
6. Add links. Tapping a rendered link navigates (opens the URL) — QuKi-Notes is a scratchpad and pastebin as much as a capture surface, so following links out of a note is a first-class use case. Reveal-and-edit happens when the cursor enters the link via keyboard (arrow in from either side, or backspace in from the right), or when the cursor lands at the element boundary — the same rule as every other element type.

---

**See also**: `notes/dev/decisions.md` → ADR-31 for the formal decision record (what/why/rejected alternatives), `notes/dev/design_spec.md` → "Editor rendering engine (ADR-31)" for the technical build spec, and `notes/dev/open_questions.md` → OQ-6 for the link-tap-behavior question.

**Last Updated**: 2026-07-04
