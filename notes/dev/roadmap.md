# QuKi-Notes Roadmap

Manifesto-driven priority view of open work. Not a sprint plan — a landscape. Order within tiers is not strict. Re-evaluate against the manifesto when priorities shift.

**Last reviewed**: 2026-07-02

---

## Tier 1 — Design debt (app viability)

The block-flip architecture breaks on long content. QuKis are not capped in length. Share-in can be arbitrarily large. If you can't select across blocks or navigate a note taller than one screen, the app is broken for a real and intended use case.

| Issue | Title |
|---|---|
| #180 | Select across blocks |
| #179 | Text selection within large blocks |

These two are linked. Any solution to #180 likely resolves #179 as a side effect. Possible direction: reflection mode — rendered markdown, cross-block selection, per-element flip still available on tap. The plain-text toggle exists but exposes raw markdown syntax; a rendered-but-selectable view is the cleaner path.

---

## Tier 2 — Edit friction (every interaction)

Bugs that create friction on every use. Fix before adding features.

| Issue | Title |
|---|---|
| #129 | Cursor jumps to end of line on tap |
| #130 | Checkbox toggle unacceptably slow |
| #176 | Tapping empty space below note has no effect |
| #177 | Keyboard matrix — cold launch (#1) still open |

---

## Tier 3 — Ambient status

Not features you reach for — always-present information that informs decisions.

| Issue | Title |
|---|---|
| #136 | Character count + save status indicator |

One status strip: character count (for character-limited destinations) + saved/unsaved state. Both are velocity information.

---

## Tier 4 — New user signal

| Issue | Title |
|---|---|
| #182 | Empty note placeholder / watermark |

Blank screen with no keyboard looks like a crash. A quiet placeholder signals "ready to type."

---

## Tier 5 — Velocity features

Directly serve "open, type, done."

| Issue | Title |
|---|---|
| #184 | Termux-style bottom bar with arrow keys |
| #79  | Auto-start new note after idle |
| #80  | Replace hamburger with icon toolbar |
| #181 | Tap-hold flyout for formatting buttons |
| #83  | Spell check, autocorrect, swipe-to-type (re-evaluate if still open) |

---

## Tier 6 — Extensibility (Principle 4)

| Issue | Title |
|---|---|
| #84  | Runtime plugin loading (ADR-29: QuickJS) |

Compile-time registry is philosophical debt against the manifesto. Every hardcoded transport makes it harder to unwind.

---

## Tier 7 — Content features

| Issue | Title |
|---|---|
| #135 | Find in page |
| #81  | Hyperlink insert / edit |
| #178 | Adjustable font size |

---

## Tier 8 — Discoverability

| Issue | Title |
|---|---|
| #183 | Help modal / "?" icon |
| #87  | Partial-width QuKi list and Settings panels |

---

## Open bugs (not yet prioritized)

| Issue | Title |
|---|---|
| #174 | Checkboxes not rendering with leading spaces |
| #175 | Dash mid-sentence switches checkbox line to bullet mode |
| #77  | Tabs / indenting not working on lists |
| #75  | Opening note moves it to top of list (re-evaluate if still open) |
