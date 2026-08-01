# Text Selection — Standard Android Behavior (Research)

**Status**: the Android/Material behaviors documented below (sections 1–8) are confirmed by the project owner as the target requirements for QuKi-Notes' own selection implementation — not just research to weigh. Section 1a is a QuKi-Notes-specific extension beyond stock Android, also confirmed. This is still not an ADR and not a build plan — scope-for-v1/staging, reading-mode selection support, and desktop-specific (Windows/Linux) equivalents remain open and need their own discussion before a brief gets written.

This documents what Android actually does for text selection, sourced from Material Design and Android platform documentation, independent of anything in this codebase. The point is to have a real target to hold an implementation against, not to guess at "reasonable" behavior.

---

## 1. Entry points — how a selection starts

- **Tap**: places a collapsed cursor at the tapped position (no selection). Tapping inside an existing selection collapses it to that point.
- **Long-press** (~500ms hold — the conventional Android/iOS threshold) selects the **word** under the finger.
- **Double-tap** does the same thing — selects the word under the finger. Long-press and double-tap are two equivalent, redundant entry points into word selection, not two different behaviors.
- Both **immediately show the two drag handles and the floating toolbar** described below — selection start is never a bare, unadorned highlight.

### Smart Text Selection (Android 8.0 Oreo+)

Word selection isn't purely a `\w`-boundary scan on stock Android — a system service (Android System Intelligence / the OS's text-classification model) recognizes **entities** and expands the initial selection to cover the whole entity, not just the word under the finger:

- A phone number selects the **whole number**, not one group of digits.
- An email address selects the **whole address**.
- A URL selects the **whole URL**.
- A postal address selects the **whole address**, spanning multiple words/lines.

This happens automatically on the same long-press/double-tap gesture that starts a plain word selection — the user doesn't do anything different, the boundary is just smarter when the system recognizes a known entity type. The floating toolbar also gains contextual actions for the recognized type (Call/Copy for a phone number, Compose for an email, Open/Copy for a URL, Maps for an address) alongside the standard Cut/Copy/Paste set.

**Relevance to a markdown editor**: this is the strongest argument for QuKi-Notes' own selection to be at least *link-aware* — a double-tap/long-press landing inside a rendered `[text](url)` or an autolinked bare URL arguably should select the meaningful unit (the link), not just whichever bare word the tap happened to land on.

### 1a. QuKi-Notes extension: email + punctuated numeric strings (confirmed requirement)

QuKi-Notes has no access to Android's OS-level text-classification service (Android System Intelligence is a system app, not something a third-party app can invoke) — so none of stock Android's Smart Text Selection is available for free, regardless of platform. Whatever entity-awareness this editor gets, it has to implement itself, the same way bare-URL autolink detection is already a heuristic living in `MdParser`, not something the OS provides.

Confirmed scope for QuKi-Notes' own entity detection, beyond a plain `\w` word-boundary scan:

- **Email addresses** — a long-press/double-tap landing inside an email address selects the whole address, not just the local-part or domain fragment on either side of the `@`.
- **Punctuated numeric strings** — a long-press/double-tap landing inside a run of digits combined with `.`, `-`, `/`, `(`, or `)` characters selects the *whole* run, not just the digit group the tap happened to land in. This is deliberately broader than stock Android's phone-number-specific detection — the intent is to also catch serial numbers, part numbers, and similar structured identifiers (e.g. `(555) 123-4567`, `SN-2024-0847-B12`-style mixed alphanumeric... — note: whether letters mixed into an otherwise-numeric identifier, like a serial number with a letter suffix, should also be captured is not yet resolved by "numeric strings with `./-/(/)`" alone; worth confirming the exact character class before implementation, since "numeric" and "serial/part number" aren't quite the same shape in practice).

Not yet decided: whether recognizing one of these entity types should also change the floating toolbar's contents (stock Android adds Call/Compose/Open/Maps-style contextual actions for a recognized entity — see §6) — QuKi-Notes has no equivalent "call this number" or "compose to this email" action to offer, so the open question is narrower: does recognition only change *selection boundary* behavior, or is some contextual action worth adding too (e.g. an explicit "Copy" shortcut is already covered by the standard toolbar either way).

---

## 2. Selection handles

- Two independent, **teardrop-shaped** drag handles appear at the selection's start and end the moment a selection exists (word-select, or any other way a selection gets created).
- Each handle is its own **later, independent gesture** — dragging one is not tied to whatever gesture created the selection. A user can long-press to select a word, lift their finger, then come back seconds later and drag either handle to adjust the boundary.
- Handles move **independently** — dragging the start handle only moves the selection's start; the end handle only moves the end.
- **Handles can cross**: dragging the start handle past the current end position (or vice versa) flips which one is logically "start" and which is "end" — the selection just continues to span between wherever the two handles currently sit, it doesn't clamp or refuse to cross.
- Handle **drag precision is character-level**, not word-snapped — even though the *initial* selection (long-press/double-tap) snaps to a whole word (or a whole entity, per Smart Selection), adjusting it afterward via the handles lets the user land on any character boundary.
- A **drag can cross line boundaries** — pulling a handle down past the end of the current visual line continues the selection into the next line and beyond, same as any ordinary multi-line select.
- Touch target size is standard Material spec: **22×22dp** handles, though the actual touch-hit area is generally larger than the visible glyph (standard Android practice for small touch targets, ~48dp minimum recommended touch target regardless of visual size).
- A **collapsed cursor also has a draggable handle** (a single one, not two) — even without a selection, the cursor position itself can be dragged to reposition it precisely, which is a separate, smaller affordance than the two-handle selection case.

---

## 3. Magnifier / loupe

Available since Android 9 (API 28):

- Appears **while actively dragging a handle** (either the selection handles or the single collapsed-cursor handle) — not during any other gesture.
- Shows a **magnified copy of the text near the handle**, positioned above the finger so the finger itself doesn't obscure the exact character being targeted.
- **Horizontal tracking**: follows the finger's x-position smoothly and continuously.
- **Vertical locking**: stays fixed to the center of the *current text line* — it does not follow the finger vertically within a line, only jumps between lines as the drag crosses a line boundary.
- **Clamped to line bounds**: the magnifier's content is bounded so it never shows past the actual left/right edges of the current line (e.g., dragging past the last character doesn't show blank space or the next line's content inside the lens).
- The selection handle itself is **not visible inside the magnifier** on stock Android — only the surrounding text is shown, the handle graphic is excluded from the magnified view (a known, deliberate detail; some third-party implementations get this wrong and show the handle flashing in/out of the lens, which reads as a bug against the platform norm).

---

## 4. Auto-scroll during drag

- Dragging a selection handle (or the collapsed-cursor handle) near the **top or bottom edge of the visible viewport** triggers the view to scroll automatically, revealing more content in that direction.
- This lets a selection extend to content that wasn't on-screen when the drag started, without the user needing to lift their finger, scroll manually, and resume dragging.

---

## 5. Haptic feedback

Two distinct, standard feedback moments (`android.view.HapticFeedbackConstants`):

- **On long-press activation** — a standard, slightly more pronounced tick when the word/entity selection first triggers (the same category of feedback as a long-press anywhere else in Android, e.g., app icon long-press).
- **`TEXT_HANDLE_MOVE`** — a distinct, deliberately **subtle** haptic constant fired repeatedly as a handle is dragged across character boundaries during an active drag. Android's own haptics design guidance is explicit that this needs to stay subtle specifically because it repeats so frequently during a single drag (same principle applied to scroll-tick and similar continuous-feedback cases) — a strong buzz per character would be fatiguing, not helpful.

---

## 6. Floating toolbar

- **Trigger**: appears the moment a selection exists (or, in a lighter form, even for a bare collapsed cursor if the clipboard has content — see below).
- **Actions and ordering**: Material guidance is explicit — order actions **by usage frequency, most-used leftmost**, with any remaining/secondary actions collapsed into an overflow ("More") rather than cramming everything into the primary row. The typical primary set for an editable field is **Cut, Copy, Paste**, with **More** as a 4th slot expanding into the rest (Select All, Share, and any Smart-Selection contextual actions like Call/Open/Maps when an entity was recognized).
- **Collapsed-cursor variant**: even with nothing selected, tapping into a field with clipboard content available shows a lighter toolbar (typically just **Paste**, sometimes **Select All**) — the toolbar isn't gated purely on "is there a selection," it's gated on "is there something useful to offer right now."
- **Positioning**: anchored to the selection — above it when there's room, below it when there isn't (e.g., a selection near the top of the viewport).
- **Dismissal**: on taking an action (the toolbar typically closes after Cut/Copy/Paste, though Copy in particular may just briefly confirm and close rather than staying open), or on tapping elsewhere to collapse/move the selection.

---

## 7. Word/line/paragraph selection beyond a single word

Stock Android's own `EditText`/`TextView` doesn't have a strong single native gesture for "select whole paragraph" or "select whole line" the way some desktop apps use triple-click — that's more of an app-specific or desktop-editor convention (e.g., Google Docs, many code editors) than a guaranteed Android platform behavior. Where it exists on Android, it's typically an *extension* apps build on top of the standard word-select + draggable-handle primitives already described above, not a separate system-level gesture. Worth being explicit about this distinction rather than assuming triple-tap-for-paragraph is "standard Android" — it isn't, in the same unambiguous way double-tap-for-word is.

---

## 8. Accessibility note (not deep-dived here)

TalkBack (Android's screen reader) has its own separate interaction model for text selection — cursor and selection movement are driven through explicit TalkBack gestures/menu actions rather than the touch/drag model above, since TalkBack users aren't relying on visually locating a handle. Flagging that this exists as a distinct concern worth its own pass later, not folding it into the touch-gesture spec above.

---

## A framing note for QuKi-Notes specifically

This project already has its own visual design system — GitHub Primer Dark/Light High Contrast palette and Lucide icons only, not stock Material widgets or Material's default toolbar typography (Roboto Medium 14sp all-caps, per the M2 spec) or default handle/toolbar colors. The behavioral conventions above (gesture entry points, handle independence, magnifier semantics, auto-scroll, toolbar action-ordering logic, haptic moments) are what should transfer — not necessarily stock Material's exact visual styling, which this app already deliberately overrides everywhere else.

---

## Staging — confirmed by the project owner

This editor has no Flutter selection machinery to build on (see the framing note above) — handles, magnifier, auto-scroll, and entity-aware selection are all from-scratch work, staged as four independently shippable, independently device-testable rounds:

1. **Correct word/entity selection + double-tap.** Includes a real, confirmed correctness bug: long-press currently selects only part of a word in some cases, not the whole word — found through actual use, not a hypothesis, and directly why this project isn't trusting "the code reads like it should work" as a substitute for verification here. Long-press and double-tap must be two equivalent entry points into the same underlying selection logic, extended for §1a (email + punctuated numeric strings). See `Agents/quiki-dev/CLAUDE.md` for the active brief.
2. Draggable selection handles + crossing.
3. Auto-scroll while dragging a handle near a viewport edge.
4. Magnifier + haptic polish — explicitly provisional: try it for a round or two; if it isn't landing, it can be dropped, *unless* stages 2/3 turn out to genuinely need it for usable cursor/handle placement rather than just polish.

Tap-to-place-cursor is deliberately **not** being touched or preemptively hardened (e.g. against double-tap's effect on single-tap recognition latency) until real device feel says it needs it — per the project owner's explicit call not to fix a hypothetical.

## Still open (not resolved by "adopt Android's behavior as requirements")

- **Reading mode**: reading mode currently hides the cursor and disables the edit gesture set entirely. Whether selection (for copying) works there at all, and with which subset of the toolbar (Copy/Select All only, no Cut/Paste — matching Android's read-only `TextView` convention), is unresolved.
- **Desktop (Windows/Linux) equivalents**: this document is Android-specific by design. Double-click-for-word and triple-click-for-paragraph are common desktop conventions but — per §7 — aren't a single unambiguous platform standard the way Android's gestures are. Needs its own decision, not a straight port of the Android spec.
- **Exact character class for §1a's punctuated-numeric-string detection**: digits plus `. - / ( )` is the confirmed starting point; whether letter-suffixed identifiers (e.g. a serial number ending in a letter) should also be swept in is unresolved — see §1a. Stage 1's brief leaves the final call to whoever implements it, with reasoning required.

---

## Sources

- [Material Design 2 — Android text selection toolbar](https://m2.material.io/design/platform-guidance/android-text-selection-toolbar.html) — toolbar actions, ordering rule, overflow behavior.
- [Android Developers — Implement a text magnifier](https://developer.android.com/develop/ui/views/text-and-emoji/magnifier) — magnifier trigger, tracking, and clamping behavior.
- [Android Developers — Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback) and [Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles) — `TEXT_HANDLE_MOVE` constant, subtlety guidance for repeated feedback.
- Smart Text Selection / entity recognition (Android 8.0+): cross-checked across multiple Android platform-behavior write-ups describing phone/email/URL/address boundary expansion via the OS text-classification service.
- General Android long-press (~500ms) and double-tap timing conventions: cross-checked against Android accessibility "touch & hold delay" settings documentation and standard `ViewConfiguration` behavior descriptions.
