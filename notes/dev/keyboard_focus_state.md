# Keyboard/focus state — design

**Status**: design locked with the project owner, 2026-08-15. Not yet implemented.

**Origin**: a real device-testing pass through `notes/dev/keyboard_state_testing.md` against issues #340, #263, #235, #265, #328, #177, #239, #234 found the reading/edit-mode mechanism itself broken — existing notes rarely land in reading mode, dismissing the keyboard doesn't clear the toolbar/cursor, and backgrounding the app with the keyboard open causes a visible black-area glitch and the keyboard failing to return (unlike every other app tested — confirmed by the project owner directly, not assumed). This is not a fix for any one of those issues individually; it replaces the mechanism all of them were breaking against.

---

## Root cause, confirmed against Flutter's own source

Traced directly against the local Flutter SDK checkout (`D:/bin/flutter/packages/flutter/`) — `editable_text.dart` and `focus_manager.dart` — not assumed from general Flutter knowledge. Full citations below; this is the load-bearing evidence for the design that follows.

- **`EditableTextState.connectionClosed()` (`editable_text.dart` ~4137) does call `focusNode.unfocus()` unconditionally**, same as this app's own `connectionClosed()`. That specific line is not itself a deviation from stock Flutter.
- **`FocusManager` has a real, purpose-built app-lifecycle-driven focus-suspend/restore mechanism** (`_appLifecycleChange`, `focus_manager.dart` ~1852–1876) — exactly the kind of thing you'd want for "keyboard survives backgrounding." **It is explicitly disabled on Android and iOS** (`_respondToLifecycleChange`, ~1668–1674), with this comment on the record:
  > "It appears that some Android keyboard implementations can cause app lifecycle state changes: adding the app lifecycle listener would cause the text field to unfocus as the user is trying to type. ... Until these are resolved, we won't be adding the listener to mobile platforms."

  Flutter's own team built this, hit the same class of bug this app has been chasing, and turned it off for mobile rather than fight it.
- **On Android, backgrounding the app does not trigger `TextInputClient.onConnectionClosed` at all** — grepped the entire Android Java embedding (`TextInputPlugin.java`, `io.flutter.plugin.editing`, `io.flutter.embedding.android`) for every plausible wiring; none exists. Stock Flutter leaves `FocusNode`/`TextInputConnection` state completely untouched across a background/foreground cycle on Android — the connection is never torn down, and the OS transparently reattaches the keyboard to it on resume, with zero Dart-side code doing anything.
- **Stock's focus-lost handling (`_closeInputConnectionIfNeeded`) is UI-inert** — it tears down the connection and nothing else. No visible UI mode rides on raw focus loss anywhere in stock Flutter.
- **The "re-show keyboard even on an already-open connection" pattern on tap is intentional, documented stock behavior** (`requestKeyboard()`/`_openInputConnection()`), not a workaround. This app's equivalent pattern is not a bug and should not be touched.

**The actual gap**: this app built a whole visible UI concept — "reading mode" (toolbar + cursor visibility) — directly on top of raw `FocusNode.hasFocus`, which is precisely the signal Flutter's own team decided was too noisy to build *any* visible behavior on for mobile. Eleven-plus independent call sites (`requestFocus()`/`unfocus()`/connection show/close), each added reactively to patch one bug report (`Bug 3`, `#336`, `#354`...), compounded the problem with no single place owning the overall state.

---

## The design: drop "reading mode" as a separate concept

No new `EditorMode` enum. No state to keep in sync with focus. Just:

```
cursor visible, keyboard visible, FormattingToolbar visible  ⟺  focusNode.hasFocus
```

That's it. Rendered-vs-plain-text (the T-button) is a fully separate, orthogonal axis — completely untouched by this design. `hasActiveBlock` (already `= focusNode.hasFocus` today, `markdown_editor.dart:148`) stays the single source of truth for all three; no new field, no new getter.

### Entering "visible" (calls `requestFocus()`) — unchanged from today

- Tapping directly into the note body while unfocused (`_onTapDown`, already correct — A4 confirmed working on device)
- Opening a brand-new/blank note (`_onActiveQukiChanged`, `editor_screen.dart:220`)

### Leaving "visible" — the platform's own keyboard dismissal, nothing bespoke

- System back gesture/button while focused (standard Android behavior — dismisses the keyboard first)
- The Android keyboard's own explicit dismiss control (the down-arrow/hide icon), if that's a genuinely distinct path from the back gesture — **needs device confirmation, see verification list below**

Deliberately **not** adding: a "Done" button, tap-outside-the-text-to-dismiss handling, or any other bespoke app-level gesture. The project owner's explicit call — rely on the platform's native dismissal only, since inventing our own is exactly the kind of extra surface that got this into trouble in the first place.

### What must never touch focus, going forward — the actual fix

This is the one substantive code change this design requires:

**`connectionClosed()` (`packages/markdown_live_editor/lib/src/quiki_editor.dart:766`) must stop calling `unfocus()`.**

```dart
// Before:
void connectionClosed() {
  _connection = null;
  widget.focusNode.unfocus();
  if (mounted) setState(() {});
}

// After:
void connectionClosed() {
  _connection = null;
  if (mounted) setState(() {});
}
```

Rationale: mirrors stock's own actual behavior on Android — connection teardown and focus loss are the same event on mobile (nothing ever calls `connectionClosed()` independently of a real focus loss, since backgrounding doesn't trigger it and nothing else in this app should either, once the rest of this design holds). If focus is somehow still `true` but `_connection` is `null`, the existing `_onTapDown` fallback (`else if (_connection == null || !_connection!.attached) { _openConnection(); }`) already reconnects cleanly on the next tap — no user-visible gap, no separate unfocus round-trip needed.

**Open question this specific change needs device confirmation for**: was the original "Bug 3" scenario this code was written for — the Android keyboard's own explicit dismiss icon — actually delivered via `connectionClosed()`? If so, removing the `unfocus()` call here means tapping that dismiss icon would leave focus `true` with the keyboard gone (cursor/toolbar would stay visible with no keyboard showing) until the user taps away. This needs to be tested for real, not assumed either way — see verification item 2 below.

**App-lifecycle transitions must continue to never touch focus.** `didChangeAppLifecycleState` (`editor_screen.dart:99`) currently only calls `_autoSave.save()` — confirmed already true, locking this in explicitly as a hard rule so it can't regress in a future change without someone noticing it violates this design.

**Everything else in the existing focus-touching inventory is out of scope for this pass** — the toolbar's re-focus-after-formatting-action calls, `_onTapDown`'s eager-focus-on-tap, and `_restoreReadingModeIfSelectionCreated()` (#336) are all either foundational (mirror stock's own `requestKeyboard()` pattern) or built for a still-valid, unrelated reason (reading-mode-safe text selection). None of these are implicated by the research. Fix `connectionClosed()`, verify nothing else regresses, don't rewrite everything in this one pass.

---

## Explicitly unaffected

- Rendered vs. plain-text toggle (T-button) — independent axis, no change.
- New-note vs. existing-note initial state (`_onActiveQukiChanged`'s `requestFocus()`/`unfocus()`) — these remain the correct entry-point triggers; this design just stops them from being undermined by `connectionClosed()` firing unfocus at the wrong moment.
- Checkbox-tap and long-press/double-tap-selection reading-mode-safety (PR #350, #336) — different concern (guarding against *other* gestures eagerly grabbing focus), untouched.
- Desktop (Windows/Linux) `CallbackShortcuts`/`Focus(skipTraversal: true)` keyboard-shortcut handling — different platform, different code path, untouched.

---

## Required device verification

1. **D3 retest**: background the app with the keyboard open, wait, foreground it. Cursor/toolbar/keyboard state must be exactly what it was before backgrounding — no black area, no glitch, keyboard actually comes back.
2. **Android's own keyboard-dismiss icon** (not the back gesture) while editing — confirm what happens now that `connectionClosed()` no longer force-unfocuses. This is the one genuinely open risk in this design; test it specifically and don't assume either outcome.
3. **Back gesture while editing** — keyboard dismisses and cursor/toolbar hide together, one clean transition.
4. **Existing note reopen** — reliably lands in the no-cursor/no-toolbar state every time, not intermittently (this is the core thing PR after PR has failed to hold).
5. **Rapid dismiss/reopen cycling** (D1) — no stuck or desynced states across repeated cycles.
6. **New note creation** — cursor/toolbar/keyboard still auto-show as before (untouched path, confirm no regression anyway).

## Diagnostic aid for the verification round

A temporary, persistent on-screen counter — not a flash, since the backgrounding scenario's event of interest happens while the app isn't visible to react to a flash — showing call counts and last-fired timestamps for `connectionClosed()`, `unfocus()`, and `requestFocus()`, in a small corner overlay. Same pattern already used successfully for the selection-handle investigation (temporary, clearly marked, fully reverted once the round is done) — chosen because the project owner's build/install workflow (GitHub Actions → sideload) has no attached console for log-based diagnostics.
