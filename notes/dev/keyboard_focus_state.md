# Keyboard/focus state — design

**Status**: design locked 2026-08-15; implementation carried through 7 device-tested rounds on `fix/keyboard-focus-connection-closed` (PR #376, unmerged — **do not merge until a real device test confirms the fix fully holds**, per the project owner's explicit standing instruction). The bug is **not yet fixed** — see "Instrumentation removed (post-Round 7)" near the bottom of this file for the current status and what's kept vs. removed. All temporary diagnostic instrumentation was removed after Round 7 so the project owner could continue the investigation directly via ADB on another machine. This file's original design-doc content (below, "Root cause"/"The design"/"Explicitly unaffected"/"Required device verification") predates implementation and is kept as-is for the reasoning it documents; see "Investigation rounds" below for what actually happened once device testing started, which is the current source of truth for what's fixed, what isn't, and why. **Process note**: rounds 1-5 were tracked only in PR #376's own body text (edited after each round via `gh pr edit`), not written back into this file — a real gap in the "sync docs after every round" discipline this project otherwise tries to hold to. This section reconstructs that history as of Round 6 so it isn't lost if the PR is ever closed.

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

## Diagnostic aid for the verification round (Rounds 1-7, removed after Round 7)

A temporary, persistent on-screen counter — not a flash, since the backgrounding scenario's event of interest happens while the app isn't visible to react to a flash — showing call counts and last-fired timestamps for `connectionClosed()`, `unfocus()`, and `requestFocus()`, in a small corner overlay. Same pattern already used successfully for the selection-handle investigation (temporary, clearly marked, fully reverted once the round is done) — chosen because the project owner's build/install workflow (GitHub Actions → sideload) has no attached console for log-based diagnostics.

The overlay (`packages/markdown_live_editor/lib/src/keyboard_focus_debug.dart`) grew across every round from 1 through 7 rather than being rebuilt each time. It was removed in full after Round 7 (see "Instrumentation removed" below) — the project owner is continuing the investigation directly via ADB on another machine, where a live logcat/debugger makes the on-screen overlay unnecessary.

---

## Investigation rounds (device-tested, PR #376)

**Round 1 — `connectionClosed()` no longer forces an unfocus.** The one substantive change this design doc calls for above. Device-tested: disproven as a fix for the actual reported bugs — the overlay showed `connClosed`/`focusLost`/`focusGained` all stayed at `0`/`0`/`1` across every tested scenario (backgrounding, keyboard's own dismiss icon, back gesture), meaning `connectionClosed()` never fired at all during any of them. Kept anyway as a real, independently-correct improvement (mirrors stock Flutter's own Android behavior, see "Root cause" above) — just not the fix for this bug.

**Round 2 — visibility driven by `viewInsets.bottom`, not `FocusNode.hasFocus`.** `hasFocus` proved to be exactly the noisy signal Flutter's own team documented avoiding for mobile UI (see "Root cause" above) — cursor/toolbar/keyboard visibility now reads `View.of(context).viewInsets.bottom > 0` instead (`QuikiEditorState._showCursor()`, paired with a `WidgetsBindingObserver.didChangeMetrics()` override since `View.of()` doesn't auto-rebuild dependents on inset changes alone). Device-tested: fixed 5 of 6 scenarios. The 6th — full background/foreground — regressed differently: keyboard briefly returns then re-closes, ending with a stale nonzero `viewInsets.bottom` (e.g. `370.0`) and a stuck black area.

**Rounds 3-4 — diagnostics narrowing the remaining scenario to real evidence.** Round 3 added `connOpen`/`explicitClose`/`onNewIntent` telemetry to test a `launchMode="singleTask"`-via-intent-routing theory; device data showed the bug reproduces identically whether or not `onNewIntent` fires, ruling that out as the primary mechanism (`singleTask` itself stays — it's the correct, standard fix for the original share-in bug, #188, not something to revert speculatively). This also sharpened the repro: swiping to the Recents overview and *immediately re-selecting QuKi-Notes* (never actually leaving to a different app) reproduces the bug on its own, with **zero flicker in every other app tested for the identical gesture** — confirmed by the project owner directly, not assumed. Round 4 traced this against Flutter's own engine source (`FlutterActivityAndFragmentDelegate.java`) and found `onStop()` unconditionally sets `FlutterView` to `View.GONE` (a documented stock workaround for a OnePlus black-screen bug, flutter/flutter#93276, not anything QuKi-Notes added) — a real, plausible mechanism for native focus loss invisible to any Dart `TextInputClient` callback. Device data partially confirmed it (full switch-away: `activityStop` fires, native focus genuinely drops to `null` at the same timestamp, and never recovers on `activityStart`) but also showed it's incomplete: the fast switcher-peek case reproduces the bug even though `activityStop` never fires at all.

**Round 5 — force a genuine native focus re-establishment on window-focus regain.** Built `MarkdownEditorController.restoreFocusAfterInterruption()`: a forced unfocus → force-apply → refocus → force-apply cycle (not a bare `requestFocus()`, which is a confirmed no-op when `FocusManager` already believes the node is focused — verified via a control-case test that reproduces the no-op before proving the real fix works). Triggered from `Activity.onWindowFocusChanged` (new `MainActivity.kt` override + method channel), chosen over `onStop`/`onStart` specifically because it's the only signal with a chance of firing during the fast-peek case. Device-tested against both the full-switch and fast-peek scenarios: `windowFocusChanged` and `focusRestoreAttempted` both fired for the first time in this investigation — genuine confirmation the mechanism runs — but the visible end state was still broken in both tests (one: stuck nonzero `viewInsets.bottom`, toolbar visible, no real keyboard; one: `viewInsets.bottom` correctly settling to `0` but keyboard/cursor/toolbar still gone). Both tests used the same *other* app, which itself kept its own keyboard/text field open across both attempts — a genuine two-app IME-contention scenario, confirmed by the project owner as the exact repro, not a guessed variant. `nativeFocus`/`windowFocus` counts jumped by 2 between the two tests while `restoreAttempted` only jumped by 1, suggesting more than one focus-change cycle happened on the second attempt — left unexplained going into Round 6.

**Round 6 — defer the `onWindowFocusChanged` dispatch (cross-app IME race).** Traced against official Android documentation ("Handle input method visibility", developer.android.com) and Flutter's own `TextInputPlugin.java`: `InputMethodManager` does not finish marking a newly-focused window ready for `showSoftInput()` (its internal `mServedView`, set by `ViewRootImpl.checkFocusNoStartInput()`) until *after* `Activity#onWindowFocusChanged()` returns, within the handling of that same window-focus message — calling anything downstream synchronously from inside that callback can silently no-op. This is a real, general Android race, not Flutter- or app-specific, and plausibly explains why Round 5's mechanism ran but still failed sharpest in the cross-app scenario: the previous app's own active IME session means more unbind/rebind work during the handoff, widening the race window. Fix: `MainActivity.kt`'s `onWindowFocusChanged()` override now defers its dispatch via `window.decorView.post {}` instead of sending it inline — the same guarantee the documented Android fix relies on, applied one level higher since this app never calls `showSoftInput()` itself (Flutter's engine does, several async hops downstream of the restore chain this event triggers). `Activity#onResume()` was considered as a second/earlier trigger and rejected — Android's own lifecycle docs confirm it fires *before* window focus is granted, not after, and both Round 5's and Round 6's device tests already show `onWindowFocusChanged` firing reliably, so the confirmed problem was timing after the signal, not the signal itself. **Not yet explained**: the Round 5 double-increment (`nativeFocus`/`windowFocus` +2, `restoreAttempted` +1) — no fix shipped for it, since no evidence distinguishes a real second race from ordinary platform churn during a two-app IME handoff. Added `KeyboardFocusDebugCounters.sequenceLog`: a rolling, millisecond-timestamped log of every tracked event in actual firing order (the existing per-type "last fired" fields can't tell a clean cycle from an overlapping one), rendered on the overlay newest-first, so the next device test can show directly whether the deferred-dispatch fix resolves the two-app scenario outright or whether a second cycle remains visible in the sequence.

**Round 6, device-tested (twice, back-to-back, identical repro)**: a clean, deterministic, twice-reproduced failure. Both tests show an essentially identical event sequence and timing: `windowFocus(false)` → ~2s later `nativeFocus(r->null)` + `activityStop` (a full stop this time, not the fast peek Round 5 tested) → ~4-5s later `activityStart` → `windowFocus(true)` → then, all within the same millisecond, the whole restore chain (`focusLost`, `explicitClose`, `focusGained`, `connOpen`, `restoreAttempted`), followed 1ms later by `nativeFocus(null->r)`. Critically, this is now a **single, clean, non-overlapping cycle both times** — `windowFocus`/`nativeFocus` counts match exactly (3 each: one initial + one false + one true) and `restoreAttempted` is `1`, not the mysterious `2` Round 5's second test showed. Round 5's double-increment anomaly did not reproduce here — treated as scenario-specific noise, not an ongoing bug, unless it resurfaces. **The visible bug is still there, identically, both times**: `viewInsets.bottom` stuck at the exact same stale value (`370.0`) both times, toolbar visible, no real keyboard on screen. Every signal this investigation has instrumented says the fix chain works — native focus genuinely returns, a `TextInputConnection` reopens, and (confirmed by reading `quiki_editor.dart` directly) `connOpen` fires immediately after `_connection!.show()` is actually called, so `.show()` is confirmed to fire both times. The remaining problem lives in a layer nothing has instrumented: what Android's `InputMethodManager` does with that `.show()` call, and/or whether Flutter's engine ever receives a fresh platform inset callback after resume at all. Also surfaced: `findFlutterView()`'s diagnostic (Round 4) started reporting `(not-found)` on both tests, where earlier rounds saw real `GONE`/`VISIBLE` values — blinding exactly the check needed to confirm or rule out Round 4's `View.GONE` hypothesis in this exact scenario.

**Round 7 — native window-insets telemetry + `findFlutterView()` fix.** Two changes, both not yet device-tested:
- **`fix:`** `findFlutterView()` rewritten from a hand-rolled recursive view-tree walk to `findViewById(FlutterActivity.FLUTTER_VIEW_ID)` — a public constant Flutter's own source documents verbatim as "used to lookup FlutterView in the Android view hierarchy," set via `setId()` when the view is created (confirmed by reading `FlutterActivity.java`/`FlutterActivityAndFragmentDelegate.java` directly). The exact cause of the `(not-found)` regression was not found and could not be reproduced without a device — no code-level reason exists for the old hand-rolled walk to fail to find a view `FlutterActivity.onCreate()` sets as the Activity's own content view. Shipped as a genuine, independently-defensible robustness improvement regardless of cause (same framing as Round 1's `connectionClosed()` fix) — the next device test will show whether it also resolves the specific regression.
- **`chore:`** new `nativeIme` overlay row + `sequenceLog` entries, driven by `ViewCompat.setOnApplyWindowInsetsListener(window.decorView)` reading `WindowInsetsCompat.Type.ime()` (visibility + raw bottom-inset px, converted to logical pixels for direct comparison against the existing `viewInsets.bottom` row directly above it). Registered on `decorView`, not `FlutterView` (whose own `onApplyWindowInsets()` is `final` and already drives this app's real cursor/toolbar visibility via the engine — a listener on `FlutterView` itself would replace that dispatch outright); returning the insets object unconsumed lets Android's normal cascade continue to `FlutterView` unmodified, satisfying the "read-only tap, not a new signal the app reacts to" invariant (verified against `ViewGroup.dispatchApplyWindowInsets()` in AOSP source). This is the one remaining unobserved layer in the whole investigation — it will directly distinguish: (a) no fresh native inset callback ever arrives after the restore chain runs (an Android/IME-level failure invisible to the app, needing a different trigger/timing than anything tried in Rounds 1-6) vs. (b) a real callback does arrive with a real inset, but Flutter's own `MediaQuery.viewInsets` never reflects it (a Flutter-engine-side propagation bug, a fundamentally different problem from anything targeted so far).

**Round 7, device-tested — against the Round 6 build, not Round 7's own telemetry.** The project owner reran the same two-app repro a third time before Round 7's build had been installed — the resulting overlay showed no `nativeIme` row and `activityStop`/`activityStart` still `(not-found)`, confirming this test predates Round 7's changes. Result: **intermittent** — the identical gesture worked correctly once and failed twice across three total attempts (one from Round 6's own device-test round, two more here), the first genuinely clean run this whole investigation has seen. This is new information in its own right: the failure is not 100% deterministic, which the two back-to-back Round 6 failures (documented above) had not yet distinguished from a fully deterministic one. Round 7's own fix and telemetry (`findFlutterView()`, `nativeIme`) remain untested on a real device as of this note.

## Instrumentation removed (post-Round 7)

All temporary diagnostic instrumentation from Rounds 1-7 has been removed, at the project owner's request, to hand the investigation off to direct ADB debugging on another machine: the on-screen overlay (`keyboard_focus_debug.dart`, deleted in full), its wiring in `editor_screen.dart` (the `Stack`/`KeyboardFocusDebugOverlay` wrapper, the `onFocusChanged` counter call, and every `MethodChannel` handler branch except `onWindowFocusChanged`), and every diagnostic-only piece of `MainActivity.kt` (the `onNewIntent()` override, the `onCreate()` override registering the native focus listener and the Round 7 insets listener, `onStop()`/`onStart()`, `findFlutterView()`/`visibilityName()`).

**Kept — the real, still-candidate fixes**, none of which are diagnostic-only:
- `connectionClosed()` no longer calls `unfocus()` (Round 1, `quiki_editor.dart`).
- Cursor/toolbar/keyboard visibility driven by `View.of(context).viewInsets.bottom` instead of `FocusNode.hasFocus` (Round 2, `_showCursor()` + `didChangeMetrics()`).
- `MarkdownEditorController.restoreFocusAfterInterruption()` (Round 5, `markdown_editor.dart`) and its trigger: `MainActivity.kt`'s `onWindowFocusChanged()` override (now stripped down to just the real dispatch, still deferred via `window.decorView.post {}` per Round 6) + `editor_screen.dart`'s `_pendingFocusRestore` false→true pairing logic.
- The `keyboard_focus_state_test.dart` regression tests for all of the above — the `KeyboardFocusDebugCounters`-dependent assertions in the `restoreFocusAfterInterruption()` control-case test were rewritten to use `tester.testTextInput.log` (Flutter's own built-in platform-channel call log) instead, verifying the same real close-then-reopen invariant without any app-specific instrumentation.

**Not kept**: Round 7's `findFlutterView()` → `FLUTTER_VIEW_ID` rewrite and the `nativeIme` native-insets telemetry — both were diagnostic/investigative, never device-confirmed, and are gone along with the rest of the overlay. If ADB debugging on the other machine independently confirms the `(not-found)` regression or a real IME-readiness gap, either can be reintroduced from this file's Round 7 entry above, which documents the exact API and reasoning.

**Status as of this note**: the underlying bug is **not fixed**. Rounds 1, 2, and 5/6 are real, kept improvements but do not fully resolve the cross-app-IME-contention scenario on their own — device evidence through Round 6 showed the fix chain running cleanly but the visible keyboard/inset state still ending up stuck or absent, intermittently (not 100% of the time, per the Round 7-labeled device test above). The investigation continues off-session via direct ADB debugging.
