# QuKi-Notes — Formal Code Review

**Date**: 2026-08-17
**Author**: Spec session (project-owner-directed review)
**Status**: Complete. All 12 findings (11 correctness findings plus one bundled dead-code cleanup) filed as GitHub issues, linked inline below.
**Requested by**: project owner, as a full, in-depth, non-skimming review of the entire codebase — explicitly not limited to the two areas flagged at the outset (race conditions generally, and a second opinion on PR #376's keyboard/focus investigation). Those two are covered in depth below, but so is everything else in scope.

---

## 1. Executive Summary

QuKi-Notes is a small (~10,000 lines of Dart across ~35 files, plus a thin Android native shim) but architecturally ambitious Flutter application. It does two genuinely hard things most note apps don't attempt: it stores every note as a plain, portable Markdown file with a JSON sidecar rather than a database, and it renders and edits that Markdown live — bold appears bold, headings appear large, checkboxes are tappable — through a from-scratch text-input and rendering engine (no `TextField`, no `RenderEditable`, no `TextSelectionOverlay`) that the project built and has been iterating on for months. That second piece, `packages/markdown_live_editor`, is by a wide margin the most complex and highest-risk code in the repository, and it earns that risk: it is also, on the whole, carefully built.

This review found **two Critical-severity issues and five High-severity issues**, all in areas the project's own documentation claims are solid: the storage layer's data-loss guarantees, and the currently-unmerged keyboard-focus fix (PR #376). Neither category is a surprise once traced, but neither had been found before this review, and both are the kind of bug that is rare in casual testing and then reliably reproducible once a user's workflow happens to hit the right timing — which for the storage findings means "auto-save fires while the user does something else," an extremely common sequence, not an edge case.

The headline risk is **not** that the codebase is poorly engineered. It is that the storage layer's atomic-write claim — the app's core promise, since users are told their notes are "theirs," in "plain-text files," safe without a backup ritual — is only atomic against a *single* writer, and this app has at least four independent, uncoordinated triggers (a 2-second debounce, a 30-second timer, an explicit flush, and an app-lifecycle hook) that can all try to write the same file. None of the four coordinate with each other or with delete. Under realistic use — not adversarial, not a stress test, just "the periodic timer happens to fire while the user backgrounds the app to switch to something else" — this can silently revert a note to stale content or, in one flow (changing the storage location from Settings), silently write a note's live content into the *wrong* folder while showing the user a blank editor.

The second finding worth executive attention is that **PR #376's own resume-after-interruption fix is built on a signal (`FocusNode.hasFocus`) that the same investigation's Round 1 already proved is unreliable** — the fix can reopen the keyboard after a user has deliberately dismissed it, because none of the seven documented rounds tested that specific sequence. This doesn't invalidate the seven rounds' work, which is unusually rigorous (traced against Android/Flutter engine source repeatedly, not guessed) — but it is a concrete reason not to merge the branch as-is, independent of the "not fixed yet" status the PR already carries.

Everything else found is real but narrower in blast radius: a resource leak in the custom editor's selection-handle dragging (a `Timer` and a screen overlay that can survive indefinitely if a drag is cancelled by the OS rather than ended normally), a handful of reentrancy gaps in lifecycle/window-state handling, and one navigation bug (storage-location change from Settings creating a second live editor screen). None of these are exotic; all were found by reading the actual code paths a real user's actions travel, not by searching for style violations.

**Bottom line**: this is a codebase worth investing further review time in, not one that needs to be rearchitected. The fixes below are targeted, well-scoped, and — per the recommended sequencing in Section 7 — mostly collapse into two or three storage-layer briefs rather than a dozen separate patches.

| Metric | Count |
|---|---|
| Files reviewed in full (not sampled) | ~35 `.dart` files (~10,000 lines) + 2 Kotlin files, across `main` and the PR #376 branch |
| Critical findings | 2 |
| High findings | 5 |
| Medium findings | 3 |
| Low / hygiene findings | 2 |
| Areas checked and explicitly ruled out (false leads) | 8 |
| `flutter analyze` result (root + package) | Clean, zero issues, both scopes |

---

## 2. Purpose, Scope, and What This Review Is Not

**Purpose**: an independent, formal correctness review of the entire QuKi-Notes codebase as it stands today, at the project owner's direct request, prompted in part by a wish to sanity-check the diagnostic reasoning behind an unresolved, seven-round investigation into a keyboard/focus bug (PR #376) — but explicitly scoped by the project owner to cover the whole project, not just that investigation.

**In scope**:
- Every `.dart` file under `lib/` (the app) and `packages/markdown_live_editor/lib/` (the custom editor package the app depends on) — read in full.
- `android/app/src/main/kotlin/com/quki/quki_notes/MainActivity.kt` and `StoragePlugin.kt` — the only native code in the project (Windows/Linux have no custom native layer; iOS/macOS are scaffolded but not built).
- Both the current `main` branch and, separately, the full diff of the unmerged `fix/keyboard-focus-connection-closed` branch (PR #376), since that branch is under active discussion.
- Static analysis (`flutter analyze`, both the app and the package) as a cross-check against the manual review.

**Out of scope for this pass** (called out explicitly so it isn't assumed covered):
- `test/` and `packages/markdown_live_editor/test/` — test *quality* (coverage gaps, brittle assertions, etc.) was not audited. Where a finding below references a test file, it's because that test file's *absence of coverage* for a specific scenario was directly relevant to a production-code finding — not a general test audit.
- CI/CD workflow files, build configuration, and DevOps tooling, except where incidentally touched by a reviewed diff (see the `notify.yml` note in Section 6.4).
- Visual/UX review, accessibility, or manifesto-alignment review (colors, icons, chrome) — those are covered by the project's existing brief-review process and weren't re-litigated here.
- Performance profiling — nothing here was measured on a device; findings are about correctness, not speed.

**Method note**: this review was conducted as three parallel deep-review passes plus the Spec session's own direct reading of the PR #376 diff (see Section 3 for full methodology). Every finding reported by a sub-review was independently spot-checked against the actual source before being included here — several candidate findings from the sub-reviews were downgraded or dropped entirely when direct verification didn't support them (see Section 6.4, "Ruled out"), and the branch-staleness note under Section 6.5 exists specifically because a plausible-looking finding turned out, on verification, not to be real.

---

## 3. Methodology

Given the size of the codebase and the explicit instruction not to skim, this review was split into independently-scoped passes so that each file received a full read rather than a sample:

1. **App-layer pass** (storage, transports, screens, window/lifecycle management, main/app bootstrap) — every file under `lib/` outside the editor package, read in full, hunting specifically for race conditions, dangling resources, and state-machine integrity, per the project owner's explicit framing.
2. **Editor-package pass** (`packages/markdown_live_editor/lib/`) — every file in the custom text-editing engine, read in full, with the same hunting brief plus package-specific risk areas (offset-map correctness across text mutation, gesture-recognizer interaction, IME connection lifecycle).
3. **Dead/unreachable-code pass** — a dedicated pass across the entire codebase (both of the above scopes) specifically for code that can never execute or never needs to: unused members, unreachable branches, orphaned files, and stale conditionals. Findings land in Section 8 once complete.
4. **PR #376 direct review** — conducted personally by the Spec session, not delegated: the full diff against `main` was read commit-by-commit, cross-referenced against `notes/dev/keyboard_focus_state.md`'s own seven-round investigation log, and checked against the branch's new test files to determine what is and isn't covered.

Every finding that reached this document was checked directly against the source at the cited file and line before being written up — not transcribed from a sub-review's report at face value. Static analysis (`flutter analyze` at the app root and inside the package) was run as an independent cross-check; it returned zero issues in both scopes, which is expected (the analyzer catches a narrow class of problems — unreachable code after a `return`, unused local variables — and none of the findings below are in that class; they require tracing actual runtime sequences, which static analysis does not do).

---

## 4. Functional and Architectural Overview

This section exists so the findings in Section 6 are legible without independently re-deriving the architecture — a formal review should be readable on its own, not require cross-referencing the codebase to understand why a given bug matters.

### 4.1 What the app is

QuKi-Notes is a capture-first notes app: the point is that opening the app should be as close to instant as typing itself, with no folder-picking, no title field, no save button. A "QuKi" is one such note. The design explicitly rejects vault-style organization (no folders, tags, or backlinks) in favor of a single chronological stream, and rejects any database in favor of one plain `.md` file per note plus a small JSON sidecar for metadata (`.meta/{uuid}.json`, holding creation/modification timestamps) — both living directly in a folder the user chooses (or the app's own sandbox, if the user opts for that instead). This is a genuine product commitment ("open data... the user owns"), not an implementation detail, and it's why the storage-layer findings in Section 6 carry more weight than they would in an app where the data model is an implementation detail the user never sees.

### 4.2 The three layers that matter for this review

**Storage layer** (`lib/core/storage/`). `QuKiStorage` does the actual file I/O — create, update, soft-delete (move to a `.trash/` subfolder), restore, hard-delete — using a write-temp-file-then-rename pattern intended to make each write atomic (a crash mid-write leaves either the old file or the new file intact, never a half-written one). `QuKiIndex` and `TrashIndex` are in-memory Riverpod `Notifier`s that mirror the filesystem's current state for the UI to read without hitting disk on every rebuild; they're populated by a full directory rescan (`refresh()`) and kept in sync incrementally by direct mutation calls (`addMeta`/`updateMeta`/`removeMeta`) from wherever a write happens. This split — an authoritative filesystem plus a best-effort in-memory mirror updated from two different code paths (rescan vs. incremental mutation) — is the shape that produces Finding 1.5.

**Auto-save** (`lib/features/editor/auto_save_controller.dart`). The editor never has an explicit "Save" button; instead, `AutoSaveController` writes on a 2-second idle debounce after a keystroke, a 30-second periodic tick regardless of activity, an explicit `flush()` called before navigating away from the editor, and a hook on app-lifecycle transitions (backgrounding, etc.). This is a deliberate design choice (documented as ADR-6, "save vs. send") and a reasonable one for a capture app — but it means the storage layer's single-writer atomicity assumption is tested constantly, by design, not as an edge case.

**The custom markdown editor** (`packages/markdown_live_editor/`). Ordinary Flutter text editing uses `TextField`/`RenderEditable`, which comes with selection, cursor painting, and IME (keyboard) connection handling built in. QuKi-Notes needed live Markdown rendering — `**bold**` shown as **bold**, not as literal asterisks, with the raw source only revealed when the cursor is inside that span — which `RenderEditable` can't do, so the project built its own: a custom `RenderBox` (`QuikiRenderEditor`) that lays out and paints text itself, a custom `TextInputClient` implementation (`QuikiEditorState`) that talks to the platform's keyboard directly, and a bidirectional offset-mapping layer (`RenderModel`) that translates between "position in the raw Markdown source" and "position in the collapsed, rendered text the user sees," since those two can have different lengths (a collapsed `**` pair is two characters shorter than its rendered form is long, in the other direction — bullets and checkboxes substitute a whole marker for a single source character). On top of that base, the package layers selection (word/entity-aware long-press and double-tap), draggable selection handles with auto-scroll near the viewport edge, and a magnifier — each added in a separate, previously-documented stage of work. This is genuinely hard, stateful software, closer in kind to a browser's contenteditable implementation than to typical app code, and the majority of this review's High-severity findings live here because that's where the real complexity is.

**The app's own state machine for "is the user currently typing"** (spread across `editor_screen.dart` and the package) has been through multiple documented redesigns and is the subject of PR #376. In short: `FocusNode.hasFocus` (Flutter's own bookkeeping) turned out not to reliably track whether Android's on-screen keyboard is actually visible, in either direction — sometimes staying `true` after the keyboard visibly closes, sometimes (per earlier project history) going `true`/`false` for reasons unrelated to real focus. The project's current approach reads the OS's own live keyboard-height signal (`viewInsets.bottom`) instead, on mobile. PR #376 is the latest round of hardening this after a further, still-not-fully-resolved bug where backgrounding and resuming the app (especially while another app also holds a keyboard open) leaves the editor's native focus and the visible keyboard state out of sync. Section 6.3 covers this fix and a gap in it.

### 4.3 How a typical user action moves through these layers

To make the findings concrter: consider "user is typing a note, then taps the QuKis list icon to switch notes." Each keystroke updates the in-memory `TextEditingValue` and (after the 2s debounce) calls into `AutoSaveController.save()`, which calls `QuKiStorage.update()`, which writes to a temp file and renames it into place, then updates the sidecar's `modifiedAt`, then calls `QuKiIndex.updateMeta()` to keep the in-memory list in sync without a rescan. Tapping the QuKis icon calls `_autoSave.flush()` (forcing any pending debounced save to happen immediately) and then navigates to `StreamScreen`, whose `initState` calls `QuKiIndex.refresh()` — a full rescan. If the flush's write and the rescan's directory listing overlap in just the wrong order (Finding 1.5), the rescan can overwrite the flush's own update with a stale read of the same file mid-write. This is the level of granularity at which the findings below were traced — not "concurrent access is theoretically possible somewhere," but the specific call sequence a specific user action produces.

---

## 5. Risk Matrix

| # | Issue | Finding | Severity | Area | User-visible impact if triggered | Ease of triggering |
|---|---|---|---|---|---|---|
| 0.1 | [#380](https://github.com/ScottKirvan/QuKi-Notes/issues/380) | Second live `EditorScreen` created via "Change location" | Critical | Storage / Navigation | Note appears blank; edits can later land in the wrong folder | Requires a specific but ordinary flow (Settings → Change location while editing) |
| 0.2 | [#381](https://github.com/ScottKirvan/QuKi-Notes/issues/381) | No reentrancy guard on save + non-unique tmp file | Critical | Storage | Silent content corruption or reversion to stale text | Ordinary — four independent save triggers overlap routinely |
| 1.1 | [#382](https://github.com/ScottKirvan/QuKi-Notes/issues/382) | Selection-handle drag has no `onPanCancel` | High | Editor package | Leaked `Timer`, permanent on-screen magnifier artifact, stuck drag visuals | Requires a pointer-cancel mid-drag (system gesture, incoming call) — uncommon but not rare |
| 1.2 | [#383](https://github.com/ScottKirvan/QuKi-Notes/issues/383) | Handle-drag state not invalidated on document swap | High | Editor package | Unhandled crash (`RangeError`) on Cut/Copy | Requires share-in arriving mid-drag — rare, but a real crash when it happens |
| 1.3 | [#384](https://github.com/ScottKirvan/QuKi-Notes/issues/384) | Delete races with in-flight autosave | High | Storage | A "deleted" note silently reappears | Ordinary timing, uncommon-but-real sequence |
| 1.4 | [#385](https://github.com/ScottKirvan/QuKi-Notes/issues/385) | Primary write path lacks retry hardening applied elsewhere | High | Storage | Silent save failure with no retry or user signal | Platform-dependent (Windows AV/indexing interference), already proven to occur in this codebase for the sibling code path |
| 1.5 | [#386](https://github.com/ScottKirvan/QuKi-Notes/issues/386) | Index refresh can overwrite a concurrent correct update | High | Storage | Stale sort order / modified time in the notes list | Ordinary — opening the notes list while autosave is active |
| 1.6 | [#387](https://github.com/ScottKirvan/QuKi-Notes/issues/387) | PR #376 resume-fix gated on a proven-unreliable signal | High | Editor / native focus (unmerged) | Keyboard reappears after a deliberate dismiss + backgrounding | Ordinary phone-use sequence, untested by the PR's own seven rounds |
| 2.1 | [#388](https://github.com/ScottKirvan/QuKi-Notes/issues/388) | No reentrancy guard on resumed-lifecycle handler | Medium | Setup flow | Duplicate navigation on double lifecycle event | Uncommon (platform-dependent double-fire) |
| 2.2 | [#389](https://github.com/ScottKirvan/QuKi-Notes/issues/389) | Unawaited save on app pause/detach | Medium | Storage / lifecycle | Possible lost edit on abrupt process kill | Compounds 0.2/1.4; not independently common |
| 2.3 | [#390](https://github.com/ScottKirvan/QuKi-Notes/issues/390) | Non-atomic window-bounds write | Medium | Desktop window state | Wrong window position/size on next launch | Requires rapid move+resize overlap |
| 8 | [#391](https://github.com/ScottKirvan/QuKi-Notes/issues/391) | Dead code cleanup (bundled) | Low | Various | None — maintenance only | — |
| 3.x | — | See Section 6.5 | Low | Various | Cosmetic / maintenance only | — |

---

## 6. Findings

Findings are numbered to match the priority tiers used throughout this document and in the project's own brief-tracking convention (`notes/dev/decisions.md`-style numbering). Each finding states the mechanism, a concrete failure sequence (not a hypothetical), how it was verified, and a recommendation. Severity reflects a combination of how bad the outcome is and how ordinary the triggering sequence is — a Critical finding here means "silent data loss or corruption reachable through normal use," not merely "theoretically possible under contrived conditions."

### 6.1 Critical

#### 0.1 — "Change storage location" from Settings creates a second, live `EditorScreen` on top of the original — [issue #380](https://github.com/ScottKirvan/QuKi-Notes/issues/380)

**Files**: `lib/features/setup/storage_setup_screen.dart:193-197` (`_openEditor()`), reached via `lib/features/settings/settings_screen.dart:64-76`.

**What's wrong**: `_openEditor()` unconditionally calls `Navigator.of(context).pushReplacement(... EditorScreen())`, with no check for how the screen was reached. `StorageSetupScreen` has two legitimate entry points: first-launch setup, where it *is* the app's root and `pushReplacement` is correct — and Settings → "Change location," which pushes it *on top of* the already-live root `EditorScreen` (with `SettingsScreen` in between). In the second case, `pushReplacement` only swaps out the top route (`StorageSetupScreen` itself); the stack becomes `[EditorScreen(original, root), SettingsScreen, EditorScreen(new)]`. The original `EditorScreen`'s `State` — including its `AutoSaveController`, its 30-second periodic save timer, and its `WidgetsBindingObserver` registration — is never disposed. It stays alive, armed, and completely hidden underneath the new screens.

**Concrete failure sequence**: A user is composing a note. They open Settings, then tap "Change location," and pick a new folder. `_openEditor()` fires and they land on what looks like a fresh, blank editor — which reads as data loss, though at this instant it isn't. But the *original*, orphaned `EditorScreen` is still alive underneath, still holding their in-progress content, and its periodic autosave timer is still running. When that timer next fires, it resolves `quKiStorageProvider` — a global provider tracking the *current* storage location, not one scoped to the screen instance that created it — which by now points at the newly-chosen folder. The old screen's stale content gets silently written into the new location, fully disconnected from anything the user can see or interact with.

This directly contradicts the project's own documented architecture (root `CLAUDE.md`): *"Editor is the permanent root... no second EditorScreen is ever pushed."* This isn't a stylistic violation of that rule — it's the exact failure mode the rule exists to prevent.

**Verification**: confirmed directly by the Spec session, not merely taken from the sub-review's report — both the unconditional `pushReplacement` call and the `Navigator.push` (not `pushReplacement`) call from Settings that puts `StorageSetupScreen` on top of an existing stack were read in full.

**Recommendation**: when reached with `isChangingLocation: true`, `_openEditor()` should pop back to the existing root `EditorScreen` (e.g. `Navigator.popUntil`) and have it re-read the new storage path, rather than pushing a new instance. Separately, `EditorScreen._openSettings()` should call `await _autoSave.flush()` before navigating, matching every other navigation-away path in that file (`_openQuKisList()`, `_onTransport()`) — its current omission independently makes this race easier to hit, since it means whatever content exists at the moment Settings is opened is *not* guaranteed saved before the location change happens.

---

#### 0.2 — No reentrancy guard on auto-save, combined with a non-unique atomic-write temp path — [issue #381](https://github.com/ScottKirvan/QuKi-Notes/issues/381)

**Files**: `lib/features/editor/auto_save_controller.dart:33-58`, `lib/core/storage/quki_storage.dart:221-225`.

**What's wrong**: `AutoSaveController.save()` can be entered from four independent triggers — the 30-second periodic timer, the 2-second idle debounce, an explicit `flush()` call, and an unawaited call from the app-lifecycle hook — and none of them are mutually exclusive. The method's only guard against redundant work, `if (body == _lastSavedBody) return;`, compares against a value that isn't updated until *after* the write completes, so two overlapping calls for the same note both pass the guard and both proceed to write.

The underlying write primitive compounds this. `QuKiStorage._writeAtomic` writes to a fixed, non-unique temp path derived only from the destination:

```dart
Future<void> _writeAtomic(File dest, String content) async {
  final tmp = File('${dest.path}.tmp');
  await tmp.writeAsString(content);
  await tmp.rename(dest.path);
}
```

Two concurrent writers for the same note share the exact same temp file. This produces two distinct failure modes. First, one write's `writeAsString` can interleave with another's, producing a file with mixed content from both writes. Second — and more insidious, because it produces no error at all — completion order is not guaranteed to match invocation order: if an *older* edit's rename happens to complete after a *newer* edit's, the file on disk silently reverts to the older content, and whichever call finishes last also updates `_lastSavedBody`, so the app's own bookkeeping believes the document is fully synced when the user's latest edit has, in fact, been quietly discarded. The same read-modify-write hazard applies to the `.meta/{uuid}.json` sidecar write that records the note's modification time.

The project documents its write path as atomic (ADR-25), and it is — per writer. It was never designed to be safe against two concurrent writers targeting the same file, and this app's own save-trigger design (four independently-timed paths, all able to fire close together) means that precondition isn't a contrived edge case; it's a routine consequence of normal use, most obviously "the 30-second timer happens to fire in the same window as a debounce-triggered save that hasn't finished yet" — plausible on a slow or synced storage location, which the app explicitly supports (ADR-27/28's user-choosable storage location, including "Filesystem storage" folders that could be, e.g., a synced Documents folder).

**Recommendation**: serialize `save()` so overlapping calls queue rather than race — e.g. chain each call onto any in-flight `Future`, or use a simple `bool _saving` guard with a "re-run if a change arrived while saving" flag. Independently, give `_writeAtomic` a per-call-unique temp filename and/or a per-note write lock inside `QuKiStorage`, so even callers outside `AutoSaveController` (if any are added later) can't reintroduce this class of bug.

### 6.2 High

#### 1.1 — Selection-handle drag has no `onPanCancel`: a resource and UI-state leak on any real pointer-cancel — [issue #382](https://github.com/ScottKirvan/QuKi-Notes/issues/382)

**Files**: `packages/markdown_live_editor/lib/src/selection_handle.dart:96-100`, `packages/markdown_live_editor/lib/src/quiki_editor.dart:1599-1709`.

The draggable text-selection handles (Stage 2 of the project's own selection work) wire `onPanStart`/`onPanUpdate`/`onPanEnd` on their `GestureDetector`, but not `onPanCancel`. All of the cleanup for an active drag — stopping the Stage 3 auto-scroll timer, hiding the Stage 4 magnifier overlay, and clearing the internal drag-tracking state — lives exclusively inside the `onPanEnd` handlers. Flutter delivers `onCancel`, not `onEnd`, when a gesture is interrupted rather than completed normally: the system back-gesture starting mid-drag, an incoming-call overlay taking the touch, or a second finger triggering a different system gesture are all realistic ways this can happen on a phone. None of the cleanup code runs in that case.

Because this editor is, by the project's own architecture, the app's permanent root screen — effectively never disposed during ordinary use, since switching notes reuses the same instance — a leaked cleanup path here isn't a one-frame glitch. The auto-scroll `Timer.periodic` (ticking every 16ms) keeps running for the remainder of the app session; the magnifier's `OverlayEntry` stays visibly rendered on screen indefinitely; and the dragged handle stays stuck at zero opacity (its "currently being dragged" paint state), visually broken until the app is fully restarted.

**Recommendation**: wire `onPanCancel` on both selection handles, routing to the same cleanup logic the `onPanEnd` handlers already perform (minus the step that commits a final selection value, since a cancelled gesture has no meaningful final position).

---

#### 1.2 — In-progress handle drag isn't invalidated when the underlying document is swapped mid-drag — [issue #383](https://github.com/ScottKirvan/QuKi-Notes/issues/383)

**Files**: `packages/markdown_live_editor/lib/src/quiki_editor.dart:683-694, 1599-1709`, `packages/markdown_live_editor/lib/src/markdown_editor.dart:669-698`.

A selection-handle drag captures one end of the selection ("`fixed`") as a raw text offset at the moment the drag begins, and nothing invalidates that captured offset if the editor's entire document is replaced while the drag is still in progress. This isn't a contrived scenario for this app specifically: the documented share-in flow creates a brand-new note and loads it into this *same, persistent* editor instance (via `activeQukiIdProvider`, deliberately without pushing a second screen), which is exactly this kind of mid-drag document swap.

**Concrete failure sequence**: a user is dragging a selection handle in a long note when a share-in intent arrives from another app. The editor's text is replaced with new, likely much shorter, content. The next drag update resolves the *moving* end of the selection safely against the new (shorter) document — but combines it with the stale `fixed` offset from the old document to build a `TextSelection`, and `TextSelection` performs no bounds clamping. If the user then taps Cut or Copy on this out-of-range selection, the underlying string operation (`replaceRange`/`textInside`) throws an unhandled `RangeError` — a real, user-reachable crash, not a theoretical one.

**Recommendation**: when the controller detects a text replacement (as opposed to an incremental edit) while a handle drag is active, cancel the drag using the same cleanup path recommended for Finding 1.1, rather than letting the next drag update commit a selection built from a mix of pre- and post-swap offsets.

---

#### 1.3 — Deleting a note can race with an in-flight autosave for the same note, resurrecting it outside `.trash/` — [issue #384](https://github.com/ScottKirvan/QuKi-Notes/issues/384)

**Files**: `lib/features/editor/editor_screen.dart:287-336`, `lib/core/storage/quki_storage.dart:106-149`.

Deleting the currently-open note correctly disarms *future* autosaves before doing anything else — but a save that was already in flight when the delete was tapped (the periodic timer, for instance, having fired moments earlier) isn't accounted for. The soft-delete operation itself uses a check-then-act pattern (confirm the file exists, then rename it into `.trash/`), already hardened with a retry loop for a documented Windows file-locking issue affecting exactly this rename operation. If a concurrent, in-flight save's own write is between its temporary-file write and its rename-into-place at the moment the delete's rename runs, the delete can act on a pre-update version of the file (or find nothing yet to move) while the stale save's rename completes afterward — recreating the file at its original, non-trash location. Because the in-memory index was already told the note was removed, this resurrected file is invisible until the next full directory rescan, at which point it reappears in the notes list as a note the user believed they had deleted.

**Recommendation**: coordinate delete with the same per-note in-flight-write tracking recommended for Finding 0.2, so a delete cannot complete while a save for that note is still outstanding.

---

#### 1.4 — The app's primary write path lacks retry protection the project already built for the same documented failure, on a sibling code path — [issue #385](https://github.com/ScottKirvan/QuKi-Notes/issues/385)

**File**: `lib/core/storage/quki_storage.dart:221-225` versus `137-149`.

The rename-into-place step used by delete and restore carries a detailed, twenty-line comment documenting a real, previously observed Windows failure: antivirus or search-indexing software can transiently lock a just-written file for a few milliseconds, causing the rename to throw even immediately after confirming the file exists. That code path was given a five-attempt retry loop with backoff specifically because of this. The write path used for *every single note creation and edit* — meaning every autosave, the single most frequently executed operation in the app — performs the identical write-then-rename sequence with no retry at all. The only thing catching a failure there is `AutoSaveController.save()`'s blanket log-and-swallow error handler, which means a transient rename failure on the app's busiest code path silently drops a save, with no retry and no signal to the user that anything went wrong.

**Recommendation**: apply the same retry pattern already proven necessary for the sibling operation, ideally by sharing one retry-wrapped rename helper between both call sites rather than maintaining two implementations of the same defense.

---

#### 1.5 — Index refresh can silently overwrite a concurrently-applied, correct update with a stale scan — [issue #386](https://github.com/ScottKirvan/QuKi-Notes/issues/386)

**File**: `lib/core/storage/quki_index.dart:19-23, 62-66`.

The in-memory notes-list index is kept current two ways: incremental, targeted updates from wherever a write happens, and full directory rescans (`refresh()`), which unconditionally overwrite the entire in-memory state with whatever the scan found — with no check for whether the in-memory state was correctly updated by an incremental mutation while that scan was still running. The notes list screen triggers a full rescan every time it's opened, and the 30-second autosave timer is, by design, running constantly in the background regardless of what screen is showing. If a rescan's directory read happens to start before an in-flight save's incremental index update lands, but the rescan's own state assignment resolves after that update — the correct, fresh update is silently discarded in favor of the stale scan, and the note shows the wrong modification time or sort position in the list until the next refresh happens to catch it. This requires no unusual timing: opening the notes list is one of the most common user actions in the app, and it happens to be exactly the trigger for the code path that can undo a concurrent, correct write.

**Recommendation**: have `refresh()` merge against known-newer entries already present in state (e.g., don't let a scan result overwrite an entry whose in-memory `modifiedAt` is newer than what the scan found) rather than performing a blind overwrite.

---

#### 1.6 — PR #376's resume-after-interruption fix is gated on the exact signal its own investigation already proved unreliable, and the resulting compound scenario was never tested — [issue #387](https://github.com/ScottKirvan/QuKi-Notes/issues/387)

**Files** (unmerged branch `fix/keyboard-focus-connection-closed`): `lib/features/editor/editor_screen.dart` (the `_pendingFocusRestore` flag and its `onWindowFocusChanged` handler), `packages/markdown_live_editor/lib/src/markdown_editor.dart` (`restoreFocusAfterInterruption()`).

This is the Spec session's own finding, reached by reading the full PR diff and its test files directly rather than delegating — the two background review agents used for the rest of this document were scoped to `main`, not this branch, specifically so this section could be an independent second opinion as requested.

**Context first, because it matters for judging this fairly**: the seven rounds of investigation documented in `notes/dev/keyboard_focus_state.md` are unusually rigorous work. Each round is backed by actual device testing, several are traced against primary sources (Android's own developer documentation, the Flutter engine's Java source, `FocusManager`'s Dart source) rather than assumed, and the document is refreshingly honest about what didn't work — Round 1's own hypothesis being disproven by the diagnostics it shipped with is recorded plainly, not glossed over. This is not sloppy work. The finding below is a genuine gap that rigor didn't happen to cover, not a sign the rigor was performative.

**The gap**: `_pendingFocusRestore` — the flag that decides whether to force a keyboard re-open when the app regains window focus — is set, on losing window focus, to `_editorController.hasActiveBlock`, which is a direct alias for `FocusNode.hasFocus`. But Round 1's own device testing already established that `hasFocus` is not a reliable proxy for whether the keyboard is actually visible — specifically, it was found to stay `true` even after the user dismisses the keyboard through Android's own dismiss icon or the system back gesture. That exact finding is what motivated the whole Round 2 pivot away from focus-driven UI visibility. Round 5/6's resume-fix reintroduces a dependency on that same proven-unreliable signal, for a different decision this time — not "should the toolbar show," but "should the app force the keyboard back open on resume."

**Concrete failure sequence, not covered by any of the seven rounds' documented test scenarios**: a user is editing, with the keyboard visible. They deliberately dismiss the keyboard — via the dismiss icon or the back gesture — and, per Round 1's own finding, `hasFocus` stays `true` even though the keyboard is now genuinely gone. They then background the app to switch to something else. `onWindowFocusChanged(false)` fires, and because `hasFocus` never changed, `_pendingFocusRestore` gets set `true`. When they return to the app, `onWindowFocusChanged(true)` fires, and the fix does exactly what it's designed to do: it forces a genuine unfocus-then-refocus cycle and reopens the keyboard. The keyboard pops back up — even though the user had just, deliberately, closed it before switching away.

This was checked directly, not inferred: none of the seven rounds' documented test scenarios combine "dismiss the keyboard" with "then background and resume" (the closest is scenario 1, which backgrounds with the keyboard already *open*, and scenario 2, which tests the dismiss icon *alone*, with no subsequent backgrounding). The new automated tests added on this branch were also read in full — the package-level tests for `restoreFocusAfterInterruption()` only verify the function in isolation, given `hasFocus == true` as a starting precondition; nothing tests how that precondition itself gets set, and nothing at the `EditorScreen` level exercises the `_pendingFocusRestore`/`onWindowFocusChanged` path at all.

**Recommendation**: before this branch is treated as ready to merge, either re-gate `_pendingFocusRestore` on a signal Round 1 didn't already disprove — the live `viewInsets.bottom > 0` check Round 2 already established as ground truth would be the natural choice, since it's already the signal the rest of the app trusts for "is the keyboard actually visible" — or, at minimum, add the missing "dismiss, then background, then resume" scenario to both the device-test checklist and the automated test suite before concluding the branch is safe, independent of whatever the ADB-debugging thread investigating the original bug finds.

### 6.3 Medium

#### 2.1 — No reentrancy guard on the storage-setup screen's resumed-lifecycle handler — [issue #388](https://github.com/ScottKirvan/QuKi-Notes/issues/388)

**File**: `lib/features/setup/storage_setup_screen.dart:106-126`.

The flag tracking "waiting for the user to grant a permission in system settings" isn't cleared until the async permission-check sequence that follows a `resumed` lifecycle event fully completes. Android is known to occasionally deliver `resumed` more than once in quick succession around returning from a system settings screen. If a second `resumed` arrives while the first permission-check is still in flight, both can independently resolve as "granted" and both call into the same navigation method, risking a duplicate navigation attempt.

**Recommendation**: clear the waiting flag at the very start of the handler, before its first `await`, rather than only on the denied-permission branch.

---

#### 2.2 — Unawaited save on app pause/detach has no completion guarantee — [issue #389](https://github.com/ScottKirvan/QuKi-Notes/issues/389)

**File**: `lib/features/editor/editor_screen.dart:116-122`.

The app triggers a save, fire-and-forget, when the app-lifecycle observer reports the app going inactive, paused, or detached — exactly the states after which Android may suspend or kill the process shortly afterward, with no guarantee the fired-off write actually completes in time. This is a known, generally hard-to-fully-close gap in any Flutter app's lifecycle handling, not unique to a flaw here — but it's worth stating explicitly because it directly compounds Findings 0.2 and 1.4 (no reentrancy protection, no retry on a known transient failure) rather than mitigating either of them; a save racing another save, or hitting the documented Windows rename failure, right as the process is also about to be killed, is the worst-case combination of everything above landing at once.

**Recommendation**: document this as an accepted, platform-level risk at minimum. Separately, investigate whether the Android platform channel this app already maintains (`StoragePlugin.kt`) could support a short-lived background-execution extension around this specific save, though this may not be worth the complexity given how rare a true process-kill-during-save window is in practice.

---

#### 2.3 — Desktop window-bounds persistence writes four values non-atomically — [issue #390](https://github.com/ScottKirvan/QuKi-Notes/issues/390)

**File**: `lib/features/window/window_state_service.dart:42-46`.

Window move, resize, and close events each independently trigger a save of the window's position and size as four separate, sequential writes with no coordination between them. Two of these events firing close together — plausible during a single maximize-or-restore action, which some window managers report as a near-simultaneous move-plus-resize — can interleave their writes, persisting a rectangle that mixes coordinates from two different snapshots in time. The impact is cosmetic only (the window opens in a slightly wrong position or size on next launch), not a data-loss concern, which is why this is Medium rather than High despite being a real race.

**Recommendation**: debounce the save (a short timer reset on each event would match the apparent intent of "save once after the user's gesture settles") or persist the four values as a single serialized unit so a partial write can't be observed.

### 6.4 Ruled out — checked directly, not bugs

Recording these explicitly, as the project's own review discipline (documented in this Spec session's own working notes) already practices: a formal review is more useful when it states what was checked and found sound, not only what was found broken, both so these areas aren't re-investigated later and so the positive findings below aren't read as omissions.

- **`render_model.dart` and `md_parser.dart`** (the markdown parsing and offset-mapping core) are both pure, stateless functions with no state shared across calls — every risk of a stale offset map originates, if anywhere, in how their *callers* hold onto results across a mutation, not in these files themselves.
- **The image-loading cache** in the editor's rendering path was checked for a duplicate-load race (check-then-add to a loading set, then an async load): the check and the add are synchronous with no `await` between them, so no race exists there, and every completion callback is guarded against the widget having already been disposed.
- **HTML clipboard paste** was checked for unguarded async continuations and swallowed-error paths: both the HTML-read and plain-text-fallback branches correctly guard against the widget being disposed mid-await, and a clipboard-read failure is caught and falls back to plain text rather than crashing paste.
- **The scroll/selection-handle deferred-rebuild machinery** — the fix for a previously-documented stale-scroll-position bug — was traced end-to-end, including how the newer auto-scroll-while-dragging feature piggybacks on the same mechanism, and found internally consistent on every path, including the widget unmounting mid-flight.
- **`QuikiEditorState.dispose()`** was checked for use-after-dispose ordering bugs across all its timers, listeners, and controllers: cancellation and listener removal consistently happen before the objects they reference are torn down, on every path.
- **The transient frame where the IME connection is closed but focus hasn't yet updated**, on the current `main` branch (i.e., the pre-PR-#376 baseline): a real gap exists for one frame, but the existing tap-handling logic already explicitly accounts for exactly this combination and recovers cleanly on the next tap — no incorrect behavior was found stemming from it today.
- **The split between two different "read the keyboard inset" APIs** used in PR #376 (`View.of(context).viewInsets` inside the editor package versus `MediaQuery.viewInsetsOf(context)` in the app's own screen code) looks, at first glance, like an inconsistency worth flagging — but tracing exactly where each read happens relative to the enclosing `Scaffold`'s inset-consuming behavior confirmed both are correct as written; the `Scaffold` zeroes the inset for its own body's descendants after resizing around the keyboard, and each of the two reads is correctly positioned on the appropriate side of that boundary. This is flagged in Section 6.2's discussion of 1.6 as a fragile, currently-correct-but-untested coupling to exact widget-tree position rather than as its own bug, since nothing currently pins this relationship in a test.
- **The known, already-accepted double-tap gesture latency** from an earlier stage of the selection feature was re-confirmed as intentional, already device-tested, and not re-flagged as a new issue here.

### 6.5 Note on a plausible-looking but non-issue: PR #376's diff and `notify.yml`

Reading PR #376's diff against `main` in isolation shows the branch appearing to remove the recently-added Discord-notification deduplication logic in `.github/workflows/notify.yml`. This was checked directly and is **not** a real problem: no commit *on the PR branch itself* touches that file. The apparent removal is an artifact of the branch having been created before that unrelated fix landed on `main` — a routine rebase or ordinary three-way merge resolves it without reverting anything. Recorded here specifically so this doesn't get independently rediscovered and mistaken for a real finding by a future reviewer reading the same raw diff.

---

## 7. Recommendations and Suggested Sequencing

The findings above cluster more than the flat list suggests. A sensible brief-writing order:

1. **Storage-layer hardening as one bundled effort ([#380](https://github.com/ScottKirvan/QuKi-Notes/issues/380), [#381](https://github.com/ScottKirvan/QuKi-Notes/issues/381), [#384](https://github.com/ScottKirvan/QuKi-Notes/issues/384), [#385](https://github.com/ScottKirvan/QuKi-Notes/issues/385), [#386](https://github.com/ScottKirvan/QuKi-Notes/issues/386))**. These five findings share a root cause — the storage layer has no coordination between concurrent writers, and the in-memory index has no protection against a stale scan overwriting a fresher incremental update. A single per-note write-serialization mechanism (a lock or queue keyed by note id) plausibly closes or substantially narrows #381, #384, and #386 at once, and #385's retry hardening is a small, mechanical addition to the same code path. #380 is a separate root cause (a navigation bug, not a concurrency bug) but belongs in the same review pass since it's reached through the same screens and is arguably the fastest of the five to fix and verify. This is squarely the storage layer's core promise to the user — plain files, safely theirs — and deserves to be treated as the top priority coming out of this review.
2. **PR #376 ([#387](https://github.com/ScottKirvan/QuKi-Notes/issues/387))**: this branch should not be merged as-is regardless of the outcome of the ADB-debugging thread already investigating the underlying bug — the gap identified here is independent of whether that investigation's original bug gets fixed. Whoever picks the branch back up should see this finding before the next round.
3. **Selection-handle hardening ([#382](https://github.com/ScottKirvan/QuKi-Notes/issues/382), [#383](https://github.com/ScottKirvan/QuKi-Notes/issues/383))**: narrower blast radius than the storage findings, but both are real, traceable bugs in frequently-used interaction code (dragging a selection handle). Worth one bundled brief.
4. **Medium and Low findings ([#388](https://github.com/ScottKirvan/QuKi-Notes/issues/388), [#389](https://github.com/ScottKirvan/QuKi-Notes/issues/389), [#390](https://github.com/ScottKirvan/QuKi-Notes/issues/390), [#391](https://github.com/ScottKirvan/QuKi-Notes/issues/391), Section 6.5's items)**: low urgency on their own; reasonable to fold into whichever future brief happens to touch the same files, rather than justifying dedicated review cycles now.

---

## 8. Dead and Unreachable Code

A dedicated pass, separate from the correctness review above, covering all 41 files in scope (every file in `lib/`, every file in `packages/markdown_live_editor/lib/`, and both Kotlin files), cross-referenced against both test directories. This class of finding is lower-stakes than Sections 6.1–6.3 — nothing here is a live bug — but it's real maintenance debt, and the project has documented precedent for exactly this kind of leftover surviving a migration (`span_parser.dart`, deleted only after being noticed during unrelated work). Filed as one bundled cleanup issue rather than eight small ones: [issue #391](https://github.com/ScottKirvan/QuKi-Notes/issues/391).

**Genuinely dead — safe to delete, zero call sites anywhere in the repo:**
- `AndroidStorageChannel.isSupported` (`lib/core/storage/android_storage_channel.dart:15`) — spot-checked directly by the Spec session; the only other match for the identifier in the whole repo is a doc comment referencing it, not a call. `StorageSetupScreen` uses its own separate `_isAndroid` getter instead.
- `QuKiStorage.fromAppDir()` (`lib/core/storage/quki_storage.dart:33-36`) — doc-commented as a test helper, but no test or production code actually calls it; all tests use `fromPath(...)`.
- `TransportRegistry.findById()` (`lib/core/transports/registry.dart:8-9`) — no caller anywhere; UI iterates the `plugins`/`enabled` lists directly instead.
- `MdElement.isInline` getter (`packages/markdown_live_editor/lib/src/md_parser.dart:252`) — the sibling `isBlock` getter is heavily used; `isInline` has zero readers.
- `MarkdownEditorConfig.syntaxColor` field (`packages/markdown_live_editor/lib/src/editor_config.dart:7,18`) — set nowhere, read nowhere; appears to describe a cursor-line marker-muting behavior that was never actually wired into `render_model.dart`.

**Unused in production, referenced only from tests — a real scope call, not an obvious delete:**
- `groupBlockquoteRuns()` (non-leveled variant, `render_model.dart:74-85`) — only referenced from `packages/markdown_live_editor/test/nested_inline_test.dart`. Production paint code exclusively uses `groupBlockquoteRunsByLevel()`, which this function's own doc comment says it was superseded by (ADR-34 Stage 1). This is the same "leftover pre-migration architecture" pattern as the already-precedented `span_parser.dart` deletion — looks like it was simply missed at the time.
- `MarkdownEditorController.focusFirstBlock()` (`markdown_editor.dart:352-353`), doc-commented "kept for API stability." Its only reference is a test named for it. It originally served the cold-launch auto-focus feature the project has since formally abandoned (root `CLAUDE.md`'s Phase 3.11/3.59 history — see also Finding 1.6's discussion of that same abandoned feature). Worth a deliberate keep-or-cut decision now, rather than continuing to carry it as a "stability" alias for a feature that no longer exists.

**Currently unreachable by every live call site, but not unreachable by construction:**
- The `autofocus` parameter on `MarkdownEditor`/`QuikiEditor` (`quiki_editor.dart` around lines 642-646 and 2074) always resolves to `false` in every path actually exercised today — `editor_screen.dart` never passes it, and no test sets it `true`. Consistent with cold-launch auto-focus being abandoned; still a valid parameter a future caller could pass, so not a deletion candidate on its own, but worth noting alongside `focusFirstBlock()` above as part of the same leftover surface.

**Intentionally kept — public/reserved API, not dead code (recorded so these aren't mistakenly "cleaned up" later):**
- `TransportContext.gps` / the `Geolocation` class (`transport_plugin.dart:42,48,72-82`) — zero construction sites today, but explicitly reserved for ADR-19's future GPS-gated transports.
- `TransportImage` / `TransportContext.userOverrides` (same file) — part of the documented `TransportPlugin` contract (ADR-14); the only currently-shipped transport (`ShareSheetTransport`) simply doesn't populate either field yet.

**Minor hygiene note, not dead code**: a stale `// ignore: unused_field` comment on `StorageSetupScreen._useAndroidFlow` (`storage_setup_screen.dart:77-78`) — the field is actually read (via the `_isAndroid` getter); the suppression looks like it predates that getter's introduction and can simply be removed.

**Explicitly checked and found clean, repo-wide**: no unreachable code after an unconditional `return`/`throw` anywhere in the 41 files reviewed; no fully orphaned files (every file has at least one real inbound import); no large blocks of commented-out Dart code; no `Platform.isX` check nested inside an already-opposite-guarded branch. Both Kotlin files are clean — every method-channel case is reachable and mirrors the Dart side exactly. Riverpod-generated `.g.dart` files were not reviewed line-by-line (they're generated output, not authored code), but every `@riverpod` declaration they wrap was confirmed to be watched from at least one real call site.

---

## Appendix A — Files Reviewed

**App layer** (`lib/`): `app.dart`, `main.dart`, `core/app_info.dart`, `core/storage/*.dart` (7 files), `core/transports/*.dart` and `core/transports/plugins/*.dart`, `features/editor/*.dart` (3 files), `features/recently_deleted/recently_deleted_screen.dart`, `features/settings/*.dart` (2 files), `features/setup/storage_setup_screen.dart`, `features/share_in/share_handler.dart`, `features/stream/stream_screen.dart`, `features/window/*.dart` (2 files), `shared/relative_time.dart`.

**Editor package** (`packages/markdown_live_editor/lib/`): `markdown_live_editor.dart`, `src/editor_config.dart`, `src/editor_controller.dart`, `src/formatting_toolbar.dart`, `src/html_paste.dart`, `src/indent_dedent.dart`, `src/markdown_editor.dart`, `src/md_parser.dart`, `src/quiki_editor.dart`, `src/quiki_render_editor.dart`, `src/render_model.dart`, `src/selection_handle.dart`, `src/selection_magnifier.dart`.

**Native**: `android/app/src/main/kotlin/com/quki/quki_notes/MainActivity.kt`, `StoragePlugin.kt` (both the `main`-branch versions and, for `MainActivity.kt`, the PR #376 branch version).

**Branch diff reviewed in full**: `fix/keyboard-focus-connection-closed` (PR #376) against `main` — all 11 changed files.

## Appendix B — Static Analysis Results

- `flutter analyze` at the project root: **no issues found** (135.6s run).
- `flutter analyze` inside `packages/markdown_live_editor`: **no issues found** (3.1s run).

Both are clean runs against the project's existing `analysis_options.yaml` (based on `package:flutter_lints/flutter.yaml`, no unusual rule suppressions). This is expected and consistent with the nature of this review's findings: static analysis catches a narrow, syntactic class of problems (unreachable code after a `return`, unused local variables and imports) and none of the findings above fall into that class — they require tracing actual runtime call sequences across async boundaries, which is outside what a static analyzer checks.

---

**Document status**: Complete as of 2026-08-17. All sections and both appendices finished; all 12 findings filed as GitHub issues [#380–#391](https://github.com/ScottKirvan/QuKi-Notes/issues?q=380..391) and linked inline throughout.

**Last updated**: 2026-08-17.
