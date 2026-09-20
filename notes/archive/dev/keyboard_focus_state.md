# Keyboard/focus state — design

**Status**: Round 1 (`focusNode.hasFocus`-driven visibility + the `connectionClosed()` fix) implemented (PR #376) and **device-tested; its core hypothesis was disproven by the counters it shipped with**. Pivoting to Round 2 (`MediaQuery.viewInsets.bottom`-driven visibility) — see that section at the end. Round 1's `connectionClosed()` fix is kept (still correct on its own terms), the visibility-source change is what's being replaced.

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

---

## Round 1 device-test results, 2026-08-15 — the hypothesis was disproven

PR #376 shipped with the diagnostic overlay above. Real device results (`connClosed / focusLost / focusGained` counters, project owner's own test pass):

1. Background/foreground with keyboard open: **keyboard did not come back**. Counters: `0/0/1` (the `1` is the original tap-in; nothing changed across the whole background→foreground cycle).
2. Android's own keyboard-dismiss icon: **keyboard gone, toolbar and cursor still visible**. `0/0/1` — unchanged from baseline.
3. Back gesture while editing: **keyboard gone, toolbar and cursor still visible**. `0/0/1` — unchanged from baseline.
4. Existing note reopen: **worked correctly** — no keyboard, no toolbar, no cursor, reliably. (Separately surfaced a real, unrelated bug: an H1 line's `#` marker stays visible even with zero cursor in the document — filed as #377, not part of this investigation.)
5. Rapid dismiss/reopen cycling: not run (verification instructions were unclear; superseded by findings from 2/3 below).
6. New note creation: worked as expected, `0/0/1`.

**What this proves**: `connClosed` stayed at `0` in every scenario. `connectionClosed()` never fired once — not for backgrounding, not for the keyboard's own dismiss icon, not for the back gesture. The fix shipped in PR #376 (removing that callback's `unfocus()` call) was therefore a correct change on its own terms, but a no-op for all six of these symptoms, since the code path it touches was never reached.

More importantly: in scenarios 2 and 3, `focusLost` also stayed at `0` even though the keyboard visibly disappeared. `FocusNode.hasFocus` never became `false`. The design's core rule (`toolbar/cursor visible ⟺ hasFocus`) executed exactly as specified — the toolbar and cursor stayed visible *because* `hasFocus` genuinely never changed, not because the rule was implemented wrong. The rule was built on a signal that doesn't reliably track real keyboard visibility on Android **in either direction**: Round 1's research already established it can be forced *false* for non-deliberate reasons (over-triggering, the `connectionClosed()` problem); the device round now shows it also fails to go `false` at all when the keyboard is genuinely dismissed via native means (under-triggering). Both failure modes stem from the same root issue: `FocusNode.hasFocus` is Flutter's own bookkeeping about *focus*, not the platform's report of actual keyboard visibility, and on Android those two things are not reliably the same thing in either direction.

---

## Round 2: pivot to `MediaQuery.viewInsets.bottom`

**New rule**:

```
cursor visible, keyboard visible, FormattingToolbar visible  ⟺  MediaQuery.viewInsets.bottom > 0
```

`viewInsets.bottom` is the OS's own live-reported keyboard height — driven by the platform's window-inset system, completely independent of `FocusNode`/`TextInputConnection` bookkeeping. This is also the standard, widely-used Flutter community workaround for exactly this class of problem (`FocusNode` being an unreliable proxy for real keyboard visibility on Android is a well-known limitation across the ecosystem, not unique to this app).

### What stays, what changes

- **Focus-driven connection/keyboard-request plumbing is unaffected.** Tapping into a note still calls `requestFocus()`, which still attaches the `TextInputConnection` and requests the keyboard show. That mechanical layer is correct and untouched by this pivot.
- **Only the *visibility* decision changes.** Wherever cursor-paint and `FormattingToolbar` visibility currently derive from `hasActiveBlock`/`focusNode.hasFocus` (`markdown_editor.dart:148`, `editor_screen.dart`'s toolbar-rendering condition, and wherever the cursor's own paint logic checks focus in `quiki_render_editor.dart`), the source becomes `viewInsets.bottom > 0` instead.
- **Round 1's `connectionClosed()` fix is kept as-is** — still a correct improvement in its own right (connection teardown and focus loss shouldn't be forced together for non-deliberate reasons), just not sufficient alone. Not being reverted.

### A known risk with this signal, from this app's own prior history

`#340`'s original black-bar finding on `StreamScreen` was traced to a *stale* `viewInsets.bottom` value being used by a `Scaffold`'s `resizeToAvoidBottomInset` — i.e., this app has direct prior evidence that `viewInsets.bottom` is not perfectly instantaneous/glitch-free either. That was a different screen and a different consumer of the value (layout reservation, not a simple visibility boolean), but it's reason enough to test staleness specifically in this round rather than assume `viewInsets` is a silver bullet just because it's the more standard approach.

### Required device verification (Round 2)

Same six scenarios as Round 1's list, retested against the new signal:

1. Background/foreground with keyboard open — keyboard should return, and cursor/toolbar visibility should track it correctly with no stale/stuck state.
2. Android's keyboard-dismiss icon — cursor/toolbar should now correctly hide (this was the direct failure in Round 1).
3. Back gesture while editing — same.
4. Existing note reopen — must keep working (already correct in Round 1, confirm no regression from the signal change).
5. Rapid dismiss/reopen cycling — watch specifically for `viewInsets`-transition lag or staleness, given the `#340` precedent above.
6. New note creation — confirm no regression.

### Diagnostic overlay, extended

Add a live `viewInsets.bottom` value display (not just an event count — the actual current number, updating in real time) to the existing corner overlay from Round 1, alongside the existing counters. This is the direct signal the new rule depends on; seeing its live value during each test scenario is what will confirm or disprove this round, the same way the event counters did for Round 1.
