# Keyboard/focus state — design

**Status**: design locked 2026-08-15; implementation carried through 12 rounds on `fix/keyboard-focus-connection-closed` (PR #376, unmerged — **do not merge until a real device test confirms the fix fully holds**, per the project owner's explicit standing instruction). **The long-standing visible symptom this whole investigation was chasing — the toolbar/cursor stuck visible over a closed keyboard — is confirmed fixed as of Round 12**, device-tested by the project owner ("goes away and stays away"). A separate, new usability problem was found during that same test — the keyboard sometimes takes several seconds to reappear on a deliberate tap — filed as [issue #395](https://github.com/ScottKirvan/QuKi-Notes/issues/395), not yet root-caused. Round 11's workaround for issue #394 (the still-unexplained stale `didChangeMetrics()` reading) remains in place and confirmed working; #394's own root cause is still unknown. **All temporary on-screen diagnostic instrumentation (Rounds 10-11's overlay) was removed after Round 12**, at the project owner's request, so they can use the app normally for a while — see "Instrumentation removed (Round 12)" near the bottom for what's kept (every real fix) vs. removed (the overlay only). This file's original design-doc content (below, "Root cause"/"The design"/"Explicitly unaffected"/"Required device verification") predates implementation and is kept as-is for the reasoning it documents; see "Investigation rounds" below for what actually happened once device testing started, which is the current source of truth for what's fixed, what isn't, and why. **Process note**: rounds 1-5 were tracked only in PR #376's own body text (edited after each round via `gh pr edit`), not written back into this file — a real gap in the "sync docs after every round" discipline this project otherwise tries to hold to. This section reconstructs that history as of Round 6 so it isn't lost if the PR is ever closed.

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

**Round 7, device-tested — against the Round 6 build, not Round 7's own telemetry.** The project owner reran the same two-app repro a third time before Round 7's build had been installed — the resulting overlay showed no `nativeIme` row and `activityStop`/`activityStart` still `(not-found)`, confirming this test predates Round 7's changes. Result: **intermittent** — the identical gesture worked correctly once and failed twice across three total attempts (one from Round 6's own device-test round, two more here). Intermittent failures are not new to this investigation generally — testing has deliberately focused on the sharpest, most reliably reproducible scenarios precisely because much of the broader bug has been intermittent throughout. What's new here specifically is that *this particular repro* — the two-app cross-IME-contention scenario Round 5/6's evidence was built on, which had been 100% consistent (failed every time it was tested) — revealed itself capable of an intermittent result for the first time. Round 7's own fix and telemetry (`findFlutterView()`, `nativeIme`) remain untested on a real device as of this note.

## Instrumentation removed (post-Round 7)

All temporary diagnostic instrumentation from Rounds 1-7 has been removed, at the project owner's request, to hand the investigation off to direct ADB debugging on another machine: the on-screen overlay (`keyboard_focus_debug.dart`, deleted in full), its wiring in `editor_screen.dart` (the `Stack`/`KeyboardFocusDebugOverlay` wrapper, the `onFocusChanged` counter call, and every `MethodChannel` handler branch except `onWindowFocusChanged`), and every diagnostic-only piece of `MainActivity.kt` (the `onNewIntent()` override, the `onCreate()` override registering the native focus listener and the Round 7 insets listener, `onStop()`/`onStart()`, `findFlutterView()`/`visibilityName()`).

**Kept — the real, still-candidate fixes**, none of which are diagnostic-only:
- `connectionClosed()` no longer calls `unfocus()` (Round 1, `quiki_editor.dart`).
- Cursor/toolbar/keyboard visibility driven by `View.of(context).viewInsets.bottom` instead of `FocusNode.hasFocus` (Round 2, `_showCursor()` + `didChangeMetrics()`).
- `MarkdownEditorController.restoreFocusAfterInterruption()` (Round 5, `markdown_editor.dart`) and its trigger: `MainActivity.kt`'s `onWindowFocusChanged()` override (now stripped down to just the real dispatch, still deferred via `window.decorView.post {}` per Round 6) + `editor_screen.dart`'s `_pendingFocusRestore` false→true pairing logic.
- The `keyboard_focus_state_test.dart` regression tests for all of the above — the `KeyboardFocusDebugCounters`-dependent assertions in the `restoreFocusAfterInterruption()` control-case test were rewritten to use `tester.testTextInput.log` (Flutter's own built-in platform-channel call log) instead, verifying the same real close-then-reopen invariant without any app-specific instrumentation.

**Not kept**: Round 7's `findFlutterView()` → `FLUTTER_VIEW_ID` rewrite and the `nativeIme` native-insets telemetry — both were diagnostic/investigative, never device-confirmed, and are gone along with the rest of the overlay. If ADB debugging on the other machine independently confirms the `(not-found)` regression or a real IME-readiness gap, either can be reintroduced from this file's Round 7 entry above, which documents the exact API and reasoning.

**Status as of this note**: the underlying bug is **not fixed**. Rounds 1, 2, and 5/6 are real, kept improvements but do not fully resolve the cross-app-IME-contention scenario on their own — device evidence through Round 6 showed the fix chain running cleanly but the visible keyboard/inset state still ending up stuck or absent, intermittently (not 100% of the time, per the Round 7-labeled device test above). The investigation continues off-session via direct ADB debugging.

---

## Round 8 — native `ImeTracker` logs via `adb logcat`, first direct observation of the actual IME transition (2026-08-17)

Conducted live, with the project owner at a machine with the device on USB for a limited window, picking up exactly where Round 7 left off — the layer nothing had instrumented yet ("what Android's InputMethodManager does with that `.show()` call, and/or whether Flutter's engine ever receives a fresh platform inset callback after resume at all"). Rather than reintroducing app-side instrumentation, this round used Android's own native `ImeTracker` logging (`adb logcat -s InputMethodManager:* ImeTracker:* ViewRootImpl:* InsetsController:*`), which requires no app rebuild and was not available to any prior round because the project's normal build/test workflow (GitHub Actions → download APK → sideload) has no attached console.

**A real confound found and corrected before the useful capture**: the device was first tested against a **debug** build (`flutter run` via `just android`, live VM-service/debugger attached). Three same-session attempts against the debug build did not reproduce the bug at all. Checked directly: the installed package showed the `DEBUGGABLE` flag set, and `.github/workflows/build-android.yml` confirms every one of Rounds 1-7's actual device tests used a `flutter build apk --release` artifact, sideloaded — not a debug/`flutter run` build. A debug build with an attached debugger gets different OS treatment around process lifecycle/backgrounding priority and runs unoptimized/JIT'd code with different timing, which is exactly the kind of thing that could mask a race-condition bug like this one. A release APK was built (`just build-android-release`) and sideloaded (`adb install -r`) instead, confirmed via `dumpsys package` showing no `DEBUGGABLE` flag, before continuing. **Worth carrying forward**: any future device-test round for this bug should confirm it's testing a release build, not assume `flutter run`'s convenience is equivalent.

**The repro, captured via `adb logcat` against the release build**: open a note (keyboard up) → switch to another app holding its own keyboard open (the Claude Android app was used, incidentally, since that's what the project owner was using to run this session) → switch back to QuKi-Notes. Reported result: **keyboard gone, toolbar and cursor still present, blank space where the keyboard should be** — the same stuck-visible-chrome symptom Round 6 already described, now reproduced once more and, for the first time, with native logs covering the exact millisecond window.

**The captured sequence, timestamped, pid 24976 = QuKi-Notes**:

```
14:25:02.942  ViewRootImpl(24976): Skipping stats log for color mode         — QuKi-Notes becomes visible again (resume)
14:25:03.000  system_server → com.quki.quki_notes:18e106df
                 onRequestHide  ORIGIN_SERVER  reason HIDE_UNSPECIFIED_WINDOW  — Android's own automatic hide-on-resume, not app code
14:25:03.001  com.quki.quki_notes:f7537df2
                 onRequestShow  ORIGIN_CLIENT  reason SHOW_SOFT_INPUT          — the app's own restoreFocusAfterInterruption() firing, 1ms later
14:25:03.002  com.quki.quki_notes:f7537df2
                 onCancelled at PHASE_CLIENT_APPLY_ANIMATION                   — the app's show request LOSES the race
14:25:03.003  InsetsController(24976): hide(ime())
                 Setting requestedVisibleTypes to 503 (was 511)                — the app's own InsetsController immediately hides itself
14:25:03.052  system_server:f5122beb onHidden                                 — the hide ACTUALLY COMPLETES (confirmed, not cancelled)
14:25:03.344  system_server:cc70ca31 onCancelled at PHASE_SERVER_SHOULD_HIDE  — a 3rd show attempt (from the server) also loses, since the server has already decided to hide
14:25:13.002  com.quki.quki_notes:18e106df
                 onTimeout at PHASE_CLIENT_REPORT_REQUESTED_VISIBLE_TYPES      — 10s later, the ORIGINAL hide request from resume times out, unresolved
```

**What this answers, directly, for the first time**: the app's own forced show request (`restoreFocusAfterInterruption()`'s `unfocus()` → `requestFocus()` cycle, reaching `.show()`) collides with — and loses to — Android's own automatic hide-on-resume request, one millisecond apart. This is not an ambiguous or stuck state at the native level: `onHidden` is unambiguous, the IME genuinely, fully closes. The bug is that QuKi-Notes' own UI (toolbar, cursor) does not follow that real, confirmed hide — it's left showing edit-mode chrome for a keyboard that Android's own IME stack has already and definitively closed. This directly resolves the question Round 6/7 left open ("does a fresh IME callback ever arrive after resume, or does Flutter fail to reflect one that arrived") — a real transition **does** arrive (the hide, `onHidden`), but it's not the transition the app's fix is racing for (the show), and the app's post-resume UI state isn't correctly tracking the transition that actually won.

**What this does NOT yet establish**: why the toolbar/cursor visibility state specifically fails to follow the confirmed hide. `_showCursor()`'s `View.of(context).viewInsets.bottom > 0` check (Round 2) should, in principle, reflect a real hide via a fresh `didChangeMetrics()` callback — whether that callback fires correctly after this specific collision sequence, or fires with a stale/incorrect inset value, was not captured in this round (would need `ViewRootImpl`'s actual inset-dispatch logging, a different and more verbose log tag than what was captured here, or reintroducing a narrowly-scoped Dart-side check on `didChangeMetrics()` invocation count/timing specifically after this sequence).

**Recommended next step**: the collision is now the concrete, evidenced target — not "the fix doesn't work" in the abstract, but specifically "the app's own forced show request races Android's automatic hide-on-resume and loses, then the app's inset-tracking doesn't correctly follow the resulting real hide." Two candidate directions, not yet attempted: (a) don't fight Android's automatic hide-on-resume at all — detect it and let it win, rather than racing a forced show against it, since forcing the show is what's colliding; or (b) keep the forced-show approach but defer it until *after* the automatic hide-on-resume request has resolved (it resolves within ~50ms per this capture — well within a single frame), rather than firing both simultaneously from the same `onWindowFocusChanged(true)` event.

Full capture (220 lines, includes surrounding system noise): retained in the session scratchpad, not committed to the repo (raw logcat, not meant as a durable artifact) — re-capturable in ~2 minutes with the command above against a release build if needed again.

**Cross-reference**: filed against [issue #387](https://github.com/ScottKirvan/QuKi-Notes/issues/387) (part of the 2026-08-17 full codebase review, `notes/dev/code_review_2026-08-17.md` § 6.2 Finding 1.6), which flagged a different, independent gap in the same PR — this round's finding and that one are both real and don't overlap: #387 is about the *gating signal* for whether to attempt a restore at all (stale `hasFocus`), this round is about what happens once a restore attempt *does* fire and collides with Android's own behavior.

---

## Round 9 — stop racing the automatic hide-on-resume; stop forcing the show (2026-08-17)

**Direction chosen by the project owner**, from Round 8's two candidate directions: (a) don't fight Android's automatic hide-on-resume at all — stop forcing a show that's confirmed to always lose — rather than (b) retiming the forced show to fire after the automatic hide resolves. Explicit framing, quoted directly because it matters for judging this round: "we can try to correct the [auto-restore] behavior later, but for now, let's at least stop it from looking so broken." This is a scoped, deliberately non-final fix — it trades away Round 5's original goal (auto-restoring the keyboard after a genuine cross-app interruption) for no longer visibly losing a race the app was always going to lose. That tradeoff is accepted, not incidental; this round does not attempt to preserve auto-restore behavior by any other means.

### What changed

`_EditorScreenState`'s `onWindowFocusChanged` handler (`editor_screen.dart`) no longer calls `_editorController.restoreFocusAfterInterruption()` on the `true` branch. The `_pendingFocusRestore` false->true pairing logic is otherwise untouched — it's still set on `false`, still consumed (reset to `false`) on the matching `true` — so the plumbing survives for a future round attempting direction (b) or something else, per this round's own brief. `MarkdownEditorController.restoreFocusAfterInterruption()` itself is untouched in the package; it's simply no longer called from this trigger. Its own tests (`packages/markdown_live_editor/test/keyboard_focus_state_test.dart`) exercise the method directly against a `MarkdownEditorController` and don't go through `EditorScreen`'s method-channel handler at all, so they continue to pass unmodified — the method isn't wrong, it's just not this round's tool anymore.

The native side (`MainActivity.kt`'s `onWindowFocusChanged()` override, the method channel, the deferred `window.decorView.post {}` dispatch from Round 6) is untouched — the dispatch mechanism itself still fires reliably; this round just stops one specific consumer of it from acting on the `true` case.

### Does this make issue #387 moot?

**Yes — confirmed by tracing the actual code path, not just assumed.** #387's finding was that `_pendingFocusRestore` is set from `_editorController.hasActiveBlock` (a direct `FocusNode.hasFocus` alias), which Round 1 already proved stays `true` even after a deliberate keyboard dismiss — so a user who dismisses the keyboard, backgrounds, and resumes would get the keyboard forced back open, because the stale-`true` gate wrongly decided a restore was warranted. That entire finding is about what happens *once the gate says yes* — and after this round's change, nothing meaningful happens when it does: the `true` branch still flips `_pendingFocusRestore` back to `false` (consuming it, so the flag doesn't leak into a later cycle) but the one action that gate used to unlock — forcing a genuine unfocus->refocus cycle that reopens the keyboard — no longer exists on this path. A gate that's wrong but guards nothing has nothing left to do damage with. If a future round reintroduces a call here (direction (b), or anything else keyed off `_pendingFocusRestore`), #387's underlying finding becomes live again at that point and should be re-checked against whatever new consumer is added — this round does not fix the gating signal itself, it just removes its only current effect.

### The toolbar/cursor-sync question — reasoned, but not device-verified

The brief asked whether `_showCursor()`'s `View.of(context).viewInsets.bottom > 0` check, refreshed via `QuikiEditorState`'s `WidgetsBindingObserver.didChangeMetrics()` override, correctly follows the real, confirmed hide Round 8 captured (`onHidden` at `14:25:03.052`) now that it's no longer contested by the app's own competing show request.

**No device or emulator access was available to verify this directly in this session** — consistent with how every prior round in this investigation has been honest about that boundary (Round 7's own "not yet device-tested" framing, Round 8's own "not yet establish[ed]" section), this is stated plainly rather than guessed past.

**Reasoning for why the removal should be sufficient, based on evidence already in this file, not fresh speculation**: `didChangeMetrics()` is a `WidgetsBindingObserver` callback the Flutter engine invokes whenever `PlatformDispatcher.onMetricsChanged` fires — it does not care what caused the underlying metrics change, only that one happened. Round 2's own device-test pass already confirmed this exact mechanism (`_showCursor` + `didChangeMetrics`) correctly tracks a real keyboard hide in 5 of 6 tested scenarios, including ordinary user-driven dismissal (the keyboard's own dismiss icon, the back gesture) — mechanically, those are the same kind of event as Round 8's `InsetsController.hide(ime())` -> `onHidden`: a real, platform-driven IME hide that ends with Android reporting a fresh, smaller (here, zero) inset back through the same `ViewCompat`/`WindowInsetsCompat` pipeline `FlutterView` already listens to. The one thing that was different about the cross-app-resume scenario before this round is that it was never a clean single transition — the app's own forced show was actively fighting the automatic hide in the same ~110ms window Round 8 captured, and Round 6's device evidence showed a stale nonzero `viewInsets.bottom` in exactly that contested scenario. Removing the losing side of that fight leaves the automatic hide to resolve as an uncontested, ordinary IME-hide transition — the same shape of event Round 2 already found this mechanism handles correctly elsewhere. That is a reasoned inference from existing evidence, not a fresh claim verified this round.

**What specifically remains unverified**: whether `didChangeMetrics()` actually fires (or fires with a fresh, non-stale value) in this exact resume-timing window — i.e., in the narrow interval right as the window/activity itself regains focus, as opposed to an ordinary mid-session user gesture while the app is already fully foregrounded and settled. Round 7 flagged native inset-dispatch during resume specifically as "the one remaining unobserved layer" and never got to instrument it; this round did not either. If the next device test (the project owner has real-time ADB access as of this writing) still shows a stuck toolbar/cursor after this change, the next diagnostic step should be exactly what Round 7 proposed: `ViewRootImpl`'s own inset-dispatch logging, or a narrowly-scoped, temporary Dart-side check on `didChangeMetrics()` invocation count/timing specifically bracketing this sequence.

### Correctness invariants held

Rounds 1, 2, and 6 are untouched: `connectionClosed()` still doesn't force an unfocus; visibility is still driven by `viewInsets.bottom`, not `FocusNode.hasFocus`; `MainActivity.kt`'s deferred `window.decorView.post {}` dispatch is unchanged. The `onWindowFocusChanged` native dispatch mechanism (method channel, false->true pairing) stays intact as plumbing, per this round's brief — nothing was ripped out, only the one forced-show call site was removed.

### Required device verification (adds to the list above)

7. **Cross-app resume after a genuine interruption (Round 5/6/8's repro)**: open a note (keyboard up), switch to another app holding its own keyboard open, switch back. Per this round's deliberate tradeoff, the keyboard is **not** expected to auto-restore anymore — confirm instead that the toolbar/cursor do NOT stay visibly stuck showing edit-mode chrome for a keyboard that's genuinely gone (the actual "stop it from looking broken" goal). If chrome is still stuck, the toolbar/cursor-sync question above is the next thing to instrument, not another attempt at the forced show.
8. **Deliberate dismiss, then background, then resume** (the #387 scenario): dismiss the keyboard on purpose, background, resume. Confirm the keyboard does NOT reappear on its own — this is now automatically true given #387's own gate has nothing left to trigger, but worth a real device pass to confirm the reasoning above holds in practice, not just on paper.

---

## Round 10 — narrowly-scoped `didChangeMetrics()` telemetry, reintroducing the overlay pattern (2026-08-17)

**Motivating evidence — Round 9's negative device-test result.** The project owner device-tested Round 9 (stop racing Android's automatic hide-on-resume) and reported it did **not** fix the visible symptom: toolbar still present, cursor still present, blank space where the keyboard should be — the exact same stuck-chrome symptom every round before it has shown. This is a real, informative negative result, not a wasted round: it rules out "the show/hide collision was the whole story." Round 8's `adb logcat` capture proved the automatic hide-on-resume genuinely and unambiguously completes (`onHidden`) once nothing is racing it — Round 9 stopped the app's own forced show from contesting it — and yet the app's own visible state still doesn't follow that real, confirmed hide. That narrows the open question to exactly the one Round 9's own report already flagged as unverified: does `QuikiEditorState.didChangeMetrics()` (the `WidgetsBindingObserver` override `_showCursor()` depends on, Round 2's mechanism) fire at all after this exact resume sequence, and if so, with what `View.of(context).viewInsets.bottom` value?

**Why an on-screen overlay again, not console logging.** The project owner's one-time ADB/device-console window (used for Round 8) is no longer available. Every future round goes back to this project's normal workflow — GitHub Actions builds the APK, the project owner downloads and sideloads it, with no attached console — so a persistent on-screen diagnostic badge is the only channel available, the same reasoning that motivated Rounds 1-7's now-removed overlay.

**What was added — two signals, plus a combined chronological log:**

- **`didChangeMetrics()` invocation tracking** (the core new signal this round exists to capture): `QuikiEditorState.didChangeMetrics()` (`packages/markdown_live_editor/lib/src/quiki_editor.dart`) now records a call count, last-fired timestamp, and the exact `View.of(context).viewInsets.bottom` value (converted to logical pixels) read at that same moment, via a new `KeyboardFocusDebugCounters.recordDidChangeMetrics()`. Recorded strictly after the existing `if (!_isMobile) return;` guard and before the existing `setState(())` call — read-only, does not change what the method does.
- **`onWindowFocusChanged` timestamps**: `_EditorScreenState`'s existing `lifecycle_debug` `MethodChannel` handler (`lib/features/editor/editor_screen.dart`) — which already receives every native dispatch from `MainActivity.kt`'s Round 6/9 deferred-post mechanism, kept fully intact this round — now also records the `true`/`false` value and timestamp via `KeyboardFocusDebugCounters.recordWindowFocusChanged()`, immediately before the existing (unchanged) `_pendingFocusRestore` logic runs. No native (`MainActivity.kt`) changes were needed — the dispatch already reaches Dart; this only adds a recording call to what was already received there.
- **A combined chronological sequence log** (`KeyboardFocusDebugCounters.sequenceLog`, millisecond-timestamped, capped at 40 entries, newest-first on the overlay): both signals above log into the same rolling list in actual firing order, recreating Round 6's `sequenceLog` mechanism for this narrower two-signal case. This is what directly answers the open question — a single count/timestamp per signal can't show whether `didChangeMetrics` fired at all relative to the `windowFocus(true)` that starts the resume sequence, only the log can.

**New file**: `packages/markdown_live_editor/lib/src/keyboard_focus_debug.dart` (recreated fresh, not restored from git history — deliberately scoped to only these two signals rather than reintroducing every counter Rounds 1-7 accumulated, since most of those questions are now answered or superseded). Exported from the package barrel (`markdown_live_editor.dart`) the same way as before. `KeyboardFocusDebugOverlay` (a persistent, not transient, corner badge — the resume scenario happens while the screen isn't being watched, so a flash would be missed) is wired into `editor_screen.dart`'s body via the same `Stack` pattern Rounds 1-7 used: `SafeArea`'s child becomes `Stack(children: [<existing Column>, const KeyboardFocusDebugOverlay()])`.

**Correctness invariants held.** This is a read-only diagnostic tap, no behavior change: Round 1 (`connectionClosed()` doesn't force an unfocus), Round 2 (`viewInsets.bottom`-driven visibility, including the `_isMobile` guard and the `setState(())` call, both untouched), Round 6 (`MainActivity.kt`'s deferred `window.decorView.post {}` dispatch), and Round 9 (no forced-show call on the `onWindowFocusChanged(true)` branch, `_pendingFocusRestore` false→true pairing logic unchanged) are all unmodified — verified by re-reading each touched method after editing, not just by intent. No QuKi content is logged or transmitted; only counts, timestamps, and the bare numeric inset value, matching every prior round's discipline.

**Device-tested — result captured and acted on in Round 11 below.** The overlay resolved the question in favor of possibility (b): `didChangeMetrics()` does fire — twice — the first time with a correct value, the second time with a stale one. See Round 11 for the exact captured sequence, the issue filed for the still-unexplained root cause (#394), and the pragmatic workaround shipped on top of this telemetry.

---

## Round 11 — suppress the stale post-resume `didChangeMetrics()` reading (issue #394) (2026-08-17)

**This is a workaround, not a root-cause fix.** Round 10's telemetry answered its own open question but raised a new one this round does not attempt to answer: *why* does `didChangeMetrics()` fire a second time, 328ms after a correct reading, with a value that exactly matches the pre-interruption open keyboard height? That mechanism is filed as [issue #394](https://github.com/ScottKirvan/QuKi-Notes/issues/394) and remains genuinely unknown — not guessed at, not assumed benign. This round exists only to stop the *visible symptom* (toolbar/cursor stuck over a keyboard that's confirmedly closed) without losing sight of the fact that the underlying cause is still open. The project owner's explicit direction going into this round: "do not lose the knowledge that this errant call is firing — we need this to be clean eventually."

**The captured evidence this round works from** (Round 10's overlay, real device):

```
17:54:14.073  windowFocus(false)                              — app backgrounded
17:54:21.396  windowFocus(true)                                — app resumed
17:54:21.402  didChangeMetrics(viewInsets.bottom=0.0)           — CORRECT, 6ms after resume
17:54:21.730  didChangeMetrics(viewInsets.bottom=370.0)         — WRONG, 328ms later
```

### The mechanism

In `QuikiEditorState` (`packages/markdown_live_editor/lib/src/quiki_editor.dart`):

- A new `didChangeAppLifecycleState()` override (added to the same `WidgetsBindingObserver` this class already mixes in for `didChangeMetrics()`) records only *when* an `AppLifecycleState.resumed` transition happened — a 2-second `_kResumeConfirmationWindow` during which a following `viewInsets.bottom == 0` reading counts as the "genuine, correct" post-resume confirmation. This does **not** touch focus in any way, holding the existing hard rule below intact.
- When `didChangeMetrics()` observes exactly that — a zero reading inside the resume-confirmation window — it arms an 800ms `_kStaleMetricsGraceWindow` (`_suppressingStaleResumeMetrics = true`, backed by a `Timer`, not a `DateTime.now()` delta comparison, so the window is deterministically drivable from a widget test via `tester.pump(duration)` — the same reasoning already used for the Stage 3 selection auto-scroll `Timer.periodic`). 328ms is the only measured data point for the stale call; 800ms is roughly 2.4x that, chosen as a safety margin for device-to-device jitter while staying short enough that it cannot be mistaken for a general dampening of `_showCursor()`.
- While that window is open, `_showCursor()` distrusts a live nonzero `viewInsets.bottom` reading and reports `false` (hidden) instead — this has to be an active override of the *live* value, not just skipping a `setState()` at the moment the stale reading arrives, since `_showCursor()` is re-evaluated on every rebuild and the stale value becomes the `FlutterView`'s actual live `viewInsets` once delivered.
- The grace window is cancelled immediately — not just left to expire — by any genuine, deliberate focus-gain: `_onFocusChanged`'s focus-gained branch (covers new-note autofocus and any other real `requestFocus()` call) and `_onTapDown`'s focus/connection-handling block (covers a tap while focus was never actually lost across the resume — the confirmed-common case per Round 1's evidence, where `FocusNode.hasFocus` never changes during a real backgrounding interruption at all, so `_onTapDown` takes its "already focused, re-show the connection" branch rather than the "request focus" branch, and would never pass through `_onFocusChanged`'s own cancellation otherwise). Both call sites share one `_cancelStaleMetricsSuppression()` helper.
- A reading arriving *after* the grace window has naturally elapsed is trusted normally, with no special handling — this app has no way to distinguish a late-arriving stale call from a genuine one, and the design deliberately does not try to (a wider, unbounded suppression would stop being "a short grace window" and start being a general dampening of `_showCursor()`, which the brief for this round explicitly ruled out).

### Telemetry — the evidence must stay visible, not vanish behind the fix

Round 10's overlay (`keyboard_focus_debug.dart`) is **kept**, not removed — its job changed: it is no longer just a one-question diagnostic to retire once Round 10's question was answered, it is now the only on-device way (GitHub Actions → sideload, no attached console) to confirm the suppression is actually triggering, and to notice if #394's root cause ever silently disappears on its own. A third counter was added, following the same pattern as the existing two: `suppressedStaleMetricsCount` / `lastSuppressedStaleMetrics` (timestamp) / `lastSuppressedStaleMetricsValue` (the actual suspicious `viewInsets.bottom` value), recorded via `KeyboardFocusDebugCounters.recordSuppressedStaleMetrics()` every time the suppression actually engages, fed into the same `sequenceLog` the other two signals use, and shown on the overlay as a third line. `keyboard_focus_debug.dart`'s own header comment now says explicitly: do not delete this file (or the Round 11 suppression logic in `quiki_editor.dart`) until #394 itself is closed — root cause identified, and either fixed at the source or confirmed permanently gone.

### Correctness invariants held

Rounds 1, 2, 6, and 9 are untouched: `connectionClosed()` still doesn't force an unfocus; visibility is still fundamentally driven by `viewInsets.bottom`, not `FocusNode.hasFocus` (this round only adds a time-scoped override on top of that mechanism, it doesn't replace it); `MainActivity.kt`'s deferred dispatch and the removed forced-show call are unmodified. `didChangeAppLifecycleState()` is a new override but follows the same hard rule Round 9 restated: app-lifecycle transitions must never call `requestFocus()`/`unfocus()` themselves — it records a timestamp only.

### Tests

`packages/markdown_live_editor/test/keyboard_stale_resume_metrics_test.dart` (new) — `AppLifecycleState.resumed` simulated via `WidgetsBinding.instance.handleAppLifecycleStateChanged(...)` (the same pattern already used in `test/features/setup/storage_setup_screen_test.dart`), `viewInsets` changes simulated via `tester.view.viewInsets = FakeViewPadding(...)` (matching `keyboard_viewinsets_test.dart`'s established convention). Five cases: the exact #394 repro (stale reading ~328ms after a confirmed zero reading is suppressed, and recorded), a genuine tap immediately after resume is never blocked (exercises `_onTapDown`'s "already focused" branch specifically, not `_onFocusChanged`), ordinary same-session keyboard open/close with no resume ever occurring is completely unaffected, suppression naturally expires once the grace window elapses, and a nonzero reading with no preceding confirmed-zero reading is never suppressed (arming requires the genuine reading, not resume alone).

### What remains open

Issue #394 itself — the actual root cause of the second, stale `didChangeMetrics()` call. Candidate directions logged on the issue: Android's `ViewRootImpl`/`InsetsController` redelivering a cached `WindowInsets` object during resume-related relayout, or a Flutter-engine-side metrics-caching gap. Needs either device console access (not currently available) or a further targeted on-screen diagnostic pass — not attempted this round.

---

## Round 12 — unify the toolbar's visibility signal with the cursor's (2026-08-17)

**Round 11, device-tested — the suppression mechanism fired exactly as designed, and the visible bug was still there.** The overlay confirmed: `suppressedStaleMetrics` incremented 1ms after a stale `370.0` reading that arrived 317ms after a confirmed `0.0` reading (matching Round 10's original 328ms capture almost exactly) — proof the workaround genuinely triggered. And yet the toolbar (and, per the project owner's report, the general "stuck" feel) was still there.

**The reason, found directly, not via more diagnostics**: Round 11's suppression lives entirely inside `QuikiEditorState._showCursor()` (`packages/markdown_live_editor/lib/src/quiki_editor.dart`), which governs the *cursor's* paint visibility. `lib/features/editor/editor_screen.dart` has always computed the *FormattingToolbar's* visibility (and the T-button's icon) independently:

```dart
final keyboardVisible = isMobile
    ? MediaQuery.viewInsetsOf(context).bottom > 0
    : _editorController.hasActiveBlock;
```

This reads the same underlying platform inset directly via `MediaQuery`, with zero knowledge of Round 11's suppression window. So the cursor correctly stayed hidden — the fix works — while the toolbar, driven by a second, parallel, unpatched consumer of the same raw signal, popped back up anyway.

### The fix

A single source of truth now exists for "is the keyboard considered visible right now" on mobile, and both the caret and the host app read it:

- New `QuikiEditorState.isKeyboardVisible` getter — recomputes `_showCursor(context)` directly (the exact same computation, including the suppression window), distinct from the pre-existing test-only `showsCursorForTesting` (which reads back off the render object instead — not suitable for a production call site that needs a correct answer before the next frame paints).
- New `QuikiEditor.onKeyboardVisibilityChanged` callback, fired via a new `_notifyKeyboardVisibilityIfChanged()` helper called from every site that can change the computed value without necessarily firing a `FocusNode` transition: `didChangeMetrics()` (a fresh inset reading), `_onFocusChanged()` (focus-gain cancels the suppression), and `_onTapDown()`'s already-focused branches (same cancellation, but with no focus transition to notify through otherwise).
- Threaded up through `MarkdownEditorController` as `isKeyboardVisible` / `onKeyboardVisibilityChanged`, mirroring the existing `hasActiveBlock` / `onFocusChanged` pattern exactly.
- `editor_screen.dart`'s mobile branch now reads `_editorController.isKeyboardVisible` instead of its own `MediaQuery.viewInsetsOf(context).bottom > 0`. **Desktop's branch (`hasActiveBlock`) is untouched** — this investigation has always been scoped to Android/mobile; desktop has no software keyboard.

A real, separate correctness gap was caught and fixed in the existing `formatting_toolbar_test.dart` mobile-visibility tests along the way: they drove `tester.view.viewInsets` directly but never set `QuikiEditorState.debugForceMobile`, which the new `isKeyboardVisible` path depends on — the package's own `_isMobile` gate is a separate switch from the app's `isMobileProvider` override those tests already used. Without forcing both, `_showCursor()` would silently take its desktop fallback (`FocusNode.hasFocus`) on the desktop/CI test host, defeating the exact scenario those tests exist to catch. Fixed with matching `setUp`/`tearDown`.

### Tests

New group in `test/features/editor/editor_screen_test.dart` — one test reproduces the exact #394 sequence end-to-end (focus → keyboard up → resume → confirmed-zero reading → stale reading 328ms later) and asserts `find.byType(FormattingToolbar)` — not just the cursor — stays hidden through the suppression window, then reopens on a genuine tap; a second confirms ordinary (non-resume) show/hide via typing/dismiss-icon/back-gesture is completely unaffected by the signal-unification change.

### Correctness invariants held

Rounds 1, 2, 6, 9, and 11's existing logic inside `quiki_editor.dart` is unmodified — this round exposes what already existed more broadly (a new getter/callback plus three call sites to the new notify helper), it doesn't change the suppression mechanism itself.

### What remains open

Issue #394's actual root cause is still unknown — this round closes a real gap in Round 11's *coverage*, it is not a step toward explaining *why* the stale `didChangeMetrics()` call happens in the first place.

**Round 12, device-tested — the long-standing symptom is fixed.** The project owner confirmed via real use: the toolbar/cursor now correctly "goes away and stays away" after a cross-app resume — the exact symptom this entire investigation, across all twelve rounds, was chasing. This closes the *visible* bug.

**A separate, new usability problem surfaced during that same test.** Sometimes, after the toolbar/cursor correctly hide, tapping back into the note to resume typing takes *several seconds* for the keyboard to reappear — in the project owner's own words, "not usable like this." Filed as [issue #395](https://github.com/ScottKirvan/QuKi-Notes/issues/395) with full repro/context. Not yet root-caused — 800ms (Round 11's grace window) is far shorter than "several seconds," so the grace window itself is an unlikely direct cause on its own, but this hasn't been traced yet. Candidate angles logged on the issue: Android's own `InputMethodManager` state after the automatic hide-on-resume plus this app's focus/connection churn during that window; or something unrelated to Rounds 9-12 that's simply more noticeable now that the toolbar/cursor correctly reflect "not focused" instead of masking it.

---

## Instrumentation removed (Round 12)

At the project owner's explicit request — "remove the telemetry for now, I want to try using this a bit" — all remaining on-screen diagnostic instrumentation (Rounds 10-11's overlay) has been removed:

- `packages/markdown_live_editor/lib/src/keyboard_focus_debug.dart` deleted in full (the `KeyboardFocusDebugCounters` singleton, the `KeyboardFocusDebugOverlay` widget, and every counter: `didChangeMetrics`, `windowFocusChanged`, `suppressedStaleMetrics`, and the combined `sequenceLog`).
- Its export from the package barrel (`markdown_live_editor.dart`) removed.
- `quiki_editor.dart`: the `recordDidChangeMetrics()` and `recordSuppressedStaleMetrics()` calls inside `didChangeMetrics()` removed; the import removed.
- `editor_screen.dart`: the `recordWindowFocusChanged()` call removed; the `Stack` + `KeyboardFocusDebugOverlay()` wrapper around the editor body removed, restoring `SafeArea`'s direct `Column` child.
- `packages/markdown_live_editor/test/keyboard_stale_resume_metrics_test.dart`'s five tests (Round 11's real regression coverage for the #394 suppression mechanism) are **kept**, not deleted — they used `KeyboardFocusDebugCounters.suppressedStaleMetricsCount`/`lastSuppressedStaleMetricsValue` as an additional assertion layer on top of the real behavioral check (`showsCursorForTesting`); those counter-based assertions were removed, and the tests now verify the same real suppression behavior directly against `showsCursorForTesting` alone, which was always the primary, sufficient signal.

**Kept — every real fix, none of which was diagnostic**: Round 1 (`connectionClosed()`), Round 2 (`viewInsets.bottom`-driven visibility), Round 6 (`MainActivity.kt`'s deferred dispatch), Round 9 (no forced-show call on resume), Round 11 (the full stale-metrics suppression mechanism — `didChangeAppLifecycleState()`, `_kResumeConfirmationWindow`, `_kStaleMetricsGraceWindow`, `_suppressingStaleResumeMetrics`, `_cancelStaleMetricsSuppression()`), and Round 12 (`isKeyboardVisible`/`onKeyboardVisibilityChanged`, the unified toolbar/cursor signal). None of these are diagnostic-only; all remain exactly as they were, confirmed unmodified by re-reading each touched file after the removal.

**Not lost**: the full evidentiary record — Round 10's exact captured sequence, Round 11's suppression mechanism and its device-test confirmation, and now Round 12's device-tested fix — all remain in this file's "Investigation rounds" section above, plus issues #394 and #395 on GitHub. Removing the overlay removes the *live, on-device* visibility into these signals going forward, not the history of what was already found. If #394's root cause or #395's latency issue need further on-device diagnosis, a future round can reintroduce a narrowly-scoped overlay again, the same way Round 10 did after Round 7's removal.
