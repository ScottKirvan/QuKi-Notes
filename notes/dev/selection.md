# Text Selection — Research & Gap Spec

This document is research, not a locked decision or a build plan — it exists to ground a discussion, per the project owner's explicit request ("research and spec out Android's default and expected selection behaviour — then let's discuss before proceeding"). No ADR yet. No implementation brief yet.

Two independent research threads feed this: (1) a full read of how selection currently works in `packages/markdown_live_editor` — gesture handlers, state, toolbar, tests; (2) standard Android/Material platform conventions for text selection, so "what should it do" is grounded in platform expectation rather than guessed.

---

## Why this is harder here than in a normal Flutter app

`QuikiRenderEditor` (`quiki_render_editor.dart`) is a custom `RenderObject`, and `QuikiEditorState` (`quiki_editor.dart`) implements `TextInputClient` directly (ADR-31). This editor does not use Flutter's `TextField`/`EditableText`/`RenderEditable` at all. That means none of Flutter's built-in selection machinery is available for free: no `TextSelectionOverlay`, no `TextSelectionControls`, no handle rendering, no magnifier wiring, no `LayerLink`/`CompositedTransformFollower` positioning. Everything documented below as "missing" would have to be built from scratch inside this package, the same way tap-to-source mapping, checkbox hit-testing, and the clipboard toolbar already were.

This is worth stating up front because it changes the shape of the eventual work: it's not "wire up a Flutter selection widget," it's "reimplement the pieces of Android's native selection UX this editor needs, on top of a hand-built layout/paint/hit-test system."

---

## Current state (verified by reading the code, not inferred)

### What exists

| Gesture | Current behavior |
|---|---|
| Tap | Places a collapsed cursor at the tapped position. Dismisses the toolbar first. Short-circuits (no cursor move) if the tap hit a link or checkbox glyph. |
| Long-press | Selects the word under the finger (simple `\w` regex scan), remembers the word's start as a drag anchor. |
| Long-press, finger still down, then move | Extends the selection from that anchor — **but only while the same finger stays down from the original long-press.** |
| Long-press released | Selection stays as-is; toolbar shows (mobile only); keyboard does *not* reopen (deliberate). |
| Touch drag, no prior long-press | Does nothing to selection — falls through to scrolling. Touch is explicitly excluded from the pan handler. |
| Mouse/stylus drag | Extends selection from whatever the current `baseOffset` already is (normal click-drag select). Works because tap fires first in the gesture arena, setting the base. |
| Double-tap | **Not implemented at all.** No handler registered; two independent taps just re-collapse the cursor twice. |
| Keyboard (Shift+Arrow, Ctrl+A/C/X/V) | Fully implemented and working. |

### What doesn't exist

- **Draggable selection handles.** No handle rendering, no handle hit-testing, nothing. Once a long-press selection exists and the finger lifts, there is no affordance to adjust either boundary by dragging — the selection is frozen except via keyboard shortcuts.
- **Magnifier/loupe.** No magnifier of any kind during any gesture.
- **Double-tap-to-select-word.** Long-press is the only way to select a word by touch.
- **Auto-scroll while extending a selection near a viewport edge.**
- **Any selection support in reading mode**, since reading mode currently hides the cursor and disables the editing gesture set entirely (separate question — see "Open questions" below on whether that's even in scope for what "selection" means here).

### Test coverage gap

No test in the package simulates a real gesture (`tester.longPress`, `tester.drag`, `TestGesture`) and checks the resulting `TextSelection`. Every existing selection-adjacent test sets the selection programmatically (`setSelectionForTesting`) and checks downstream effects (clipboard actions, toolbar buttons, `wrapSelection`). The gesture→selection mapping — arguably the core of "how selection works" — has zero direct coverage today.

---

## What Android actually does (platform convention, not this app's choice to invent)

Grounded in Android/Material platform documentation, not assumption:

1. **Tap**: places a collapsed cursor. Tapping inside an existing selection generally collapses it to that point.
2. **Word selection — two equivalent entry points**: both **double-tap** and **long-press** select the word under the finger. This app currently only implements one of the two.
3. **On word selection**, Android shows **two independent teardrop-shaped drag handles** (22×22dp, per Material spec) at the selection start and end. These are draggable **as their own, later gesture** — not tied to holding the original long-press. Each handle moves only its own boundary.
4. **Magnifier** (Android 9+): while dragging a handle, a magnified loupe appears above the finger, showing the text the finger is covering. It tracks the finger horizontally, stays vertically locked to the current line, and is clamped so it never shows content past the line's bounds.
5. **Handle drag can cross line boundaries** — dragging a handle down past the end of a visual line continues the selection into the next line, same as any normal multi-line select.
6. **Auto-scroll**: dragging a handle near the top or bottom edge of the visible viewport scrolls the content, letting a selection extend beyond what's currently on screen.
7. **Floating toolbar**: appears once there's a selection (Cut, Copy, Paste, sometimes "Share"/"Select all" — overflowed under "More" if the toolbar doesn't fit). Positioned above the selection when there's room, below otherwise. Dismissed by: an action being taken, or tapping elsewhere to collapse the selection.
8. **Collapsed-cursor toolbar**: Android also shows a lightweight toolbar (typically just Paste, if the clipboard has content) even for a plain collapsed cursor, not only for a real selection.

This app already has #2 partially (long-press only), #7 in a reasonable approximation (`AdaptiveTextSelectionToolbar`, gated to mobile), and #8 (collapsed selection shows Paste + Select All). It's missing #2's double-tap half, and entirely missing #3, #4, #5, #6.

---

## Gap matrix

| Platform-expected behavior | Status here |
|---|---|
| Tap places collapsed cursor | Done |
| Long-press selects word | Done |
| Double-tap selects word | **Missing** |
| Drag handles to adjust an existing selection, independent of the originating gesture | **Missing** — this is the single biggest gap, and the one users actually notice (this is very likely what's behind #238's "significant work, platform-specific" note) |
| Magnifier while dragging a handle | **Missing** |
| Handle drag crosses line boundaries | N/A — no handles to test this against |
| Auto-scroll near viewport edge while extending selection | **Missing** |
| Floating toolbar on selection (Cut/Copy/Paste/Select All) | Done |
| Lightweight toolbar on collapsed cursor (Paste/Select All) | Done |
| Keyboard selection (Shift+Arrow, Ctrl+A/C/X/V) | Done |
| Mouse click-drag select (desktop) | Done |
| Double-click word select (desktop convention) | **Missing** |
| Triple-click paragraph/line select (desktop convention in many apps) | **Missing** — and not confirmed as a strict platform requirement anywhere, worth discussing rather than assuming |

---

## Open questions for discussion

These are genuinely open — this document deliberately stops short of deciding them:

1. **Scope for v1**: the full Android UX (handles + magnifier + auto-scroll + double-tap) is a lot of from-scratch work given there's no Flutter selection machinery to build on. Is the goal to close the whole gap in one pass, or land it in stages (e.g., handles + double-tap first since that's the biggest daily-use pain point, magnifier/auto-scroll later)?
2. **Handle-drag precision**: on real Android, the initial double-tap/long-press snaps to a whole word, but dragging a handle afterward is character-precise, not word-snapped. Confirm that's the intended target here too (vs. e.g. word-snapping drag as a simpler, if less faithful, first cut).
3. **Reading mode**: reading mode currently hides the cursor and disables the edit gesture set. Should selection (for copying text) work in reading mode at all, and if so, with which subset of the toolbar (Copy/Select All only, no Cut/Paste, matching Android's read-only `TextView` convention)? This wasn't asked for explicitly and touches the reading-mode design from Phase 3.40 — flagging rather than assuming.
4. **Desktop conventions**: double-click-for-word and triple-click-for-paragraph/line are common on desktop but aren't a single unambiguous "platform standard" the way Android's gestures are (behavior varies by app/toolkit). Worth deciding explicitly rather than porting Android behavior 1:1 to desktop, given this app also ships on Windows and Linux.
5. **Magnifier implementation approach**: Flutter does expose `TextMagnifierConfiguration`/`TextMagnifier` as a semi-generic building block (used by `TextField` internally), but since this editor doesn't use `RenderEditable`, it's not clear yet whether that's reusable here or whether the magnifier would also need to be hand-built. Not investigated in depth for this document — worth a spike if magnifier support is in scope for the first stage rather than deferred.
6. **How much of this needs device testing vs. can be trusted from widget tests**: gesture-driven selection has historically been one of this codebase's harder areas to get right from code review alone (see the 2026-07-05 "Bug 1–4" gesture fixes, and the currently-zero gesture-simulation test coverage noted above). Worth deciding up front whether real-device verification is a required gate before merge for this work, not just CI-green.

---

## Sources

- Codebase: `packages/markdown_live_editor/lib/src/quiki_editor.dart`, `quiki_render_editor.dart`, `markdown_editor.dart`, and `packages/markdown_live_editor/test/*.dart` (full read, this session).
- [Material Design 2 — Android text selection toolbar](https://m2.material.io/design/platform-guidance/android-text-selection-toolbar.html)
- [Android Developers — Implement a text magnifier](https://developer.android.com/develop/ui/views/text-and-emoji/magnifier)
- [Flutter API — TextMagnifierConfiguration](https://api.flutter.dev/flutter/widgets/TextMagnifierConfiguration-class.html)
- General Android platform convention (double-tap/long-press word selection, teardrop handles, floating toolbar) cross-checked across Material Design docs and Android developer/UX references.
