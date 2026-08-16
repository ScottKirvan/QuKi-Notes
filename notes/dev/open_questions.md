# Open Questions

Genuinely unresolved items. When implementation forces an answer, **move the entry to `decisions.md`** with the resolution and link the PR that settled it.

Do not implement past one of these without proposing a resolution in the PR body.

---

## ~~OQ-1: WYSIWYG markdown rendering~~ — **Resolved (v0.9.1, PR #54)**

**Resolution**: Stayed on `super_editor`. Two-part fix:
1. `_parseBody` / `_extractBody` replaced with `deserializeMarkdownToDocument` / `serializeDocumentToMarkdown` (both built into `super_editor`; `super_editor_markdown` companion package deprecated and merged upstream). `MarkdownSyntax.normal` used for GFM compatibility.
2. Custom `EditReaction` subclasses added in `lib/features/editor/markdown_inline_reactions.dart`: bold (`**x**`), italic (`_x_`, `*x*`), inline code (`` `x` ``), task list (`- [ ] `). Block reactions (headings, lists, blockquote) were already provided by `createDefaultDocumentEditor`. ADR-24.

Fenced code block rendering deferred — not a priority for quick-capture use case.

---

## ~~OQ-2: super_editor image node integration~~ — **Removed**

**Resolution**: `super_editor` was replaced by the single-buffer `markdown_live_editor` package (ADR-30, v0.15.1). The `super_editor`-specific integration question is moot. Image paste (Phase 1.4) remains blocked by CargoKit being archived; when that work is unblocked, the integration point will be in `markdown_live_editor`'s `buildTextSpan()` via a `WidgetSpan` for `![](...)` lines, or a post-processing step. A new OQ will be opened at that time.

---

## OQ-3: GitHub OAuth App `client_id` distribution (deferred)

Defers to whichever plugin first needs GitHub OAuth (likely the GitHub sync plugin in Phase 4, or a GitHub-flavoured transport before that).

When that PR lands, decide:

- (a) Committed as a constant in the plugin
- (b) Injected via `--dart-define=QUKI_GH_CLIENT_ID=...` at build time
- (c) Read from `assets/config.json` at runtime

`client_id` is not secret per the OAuth spec; (a) is acceptable unless the repo goes public AND a different OAuth App is needed per fork.

**Surface during:** First PR that introduces an OAuth-needing plugin.

---

## OQ-4: Initial-sync progress UX threshold (deferred to sync work)

Bulk-pull progress banner: always, or only above some threshold? Decision belongs with the first sync plugin in Phase 4.

**Likely resolution:** time-based — show banner if sync hasn't completed within 1–2 seconds.

---


## OQ-NEW-4: Linux `flutter_secure_storage` keyring matrix

`flutter_secure_storage` on Linux uses `libsecret`, which requires a Secret Service implementation (GNOME Keyring, KeePassXC's secret-service, KWallet bridge). On a vanilla server install or a headless WM there may be no Secret Service running.

**Risk:** plugins that store tokens (any OAuth-using transport, any sync backend) fail to initialize on Linux when no keyring is available.

**Options:**
- (a) Hard fail with clear error directing user to install + start gnome-keyring (or equivalent).
- (b) Fall back to an encrypted-at-rest file in the app docs dir (security ≈ zero against local-user attacker but workable for a personal app).
- (c) Refuse to install plugins that need secrets when keyring is absent.

**Surface during:** First plugin that calls `flutter_secure_storage` on Linux.

---

## ~~OQ-6: Link tap behavior in rendered mode (ADR-31)~~ — **Resolved 2026-07-04**

**Resolution**: Tap navigates (opens the URL). Reveal-and-edit is triggered by cursor entering the element via keyboard: arrow-key in from either side, or backspace in from the right. Cursor landing at the start or end boundary of the source range also reveals — consistent with the boundary rule for all other element types.

**Reasoning**: QuKi-Notes is a scratchpad and pastebin as much as a capture surface; following links (e.g., a parts list with product URLs) is a primary workflow. Navigate-on-tap matches that use case and matches the expectation of every other reading surface. Keyboard-entry is the natural and frictionless path to edit mode; no special gesture is needed. Obsidian's model was considered — it also navigates on click and reveals on edge-tap or modifier-click. The difference is that in Obsidian, edge-tap requires precision (hitting the exact boundary pixel) or a modifier key. In QuKi-Notes, the boundary-reveal rule applies naturally: tapping anywhere past the end of the link (or beginning, if there's space before it) lands the cursor at the boundary and reveals source — the same rule as every other element type. No special gesture needed; the model is consistent throughout.

**Recorded in**: ADR-31 links bullet, `notes/dev/decisions.md`.

---

## OQ-7: switcher-reselect keyboard dismissal — is stock Flutter's onStop() FlutterView.GONE workaround the cause?

`notes/dev/keyboard_focus_state.md`'s three completed rounds fixed a real bug (`connectionClosed()` forcing an unfocus) but did not explain the sharpest repro found so far: tap into a note (keyboard open) → swipe to Recents/app-switcher overview → immediately re-select QuKi-Notes (never actually leaving to a different app) → the keyboard visibly and genuinely closes (`viewInsets.bottom` really drops to 0) and does not return. None of the six existing telemetry signals (`connClosed`, `focusLost`, `focusGained`, `connOpen`, `explicitClose`, `onNewIntent`) changed at all during this repro — ruling out everything on the Dart↔engine `TextInputClient` boundary.

**A round-4 investigation** (`investigate/switcher-keyboard-dismiss` branch) diffed the app's `AndroidManifest.xml`, `styles.xml`, and `MainActivity.kt`/`StoragePlugin.kt` against a freshly-generated stock Flutter 3.44.0 Android scaffold, and checked every Android-native plugin dependency (`file_picker`, `receive_sharing_intent`, `quill_native_bridge`, `window_manager`) for lifecycle/window/IME hooks. The only manifest deviation from stock is `android:launchMode="singleTask"` (stock: `singleTop`) — already weakened as a lead in Round 3 (a plain Recents-reselect never delivers a new `Intent`, so `launchMode` shouldn't matter, and `onNewIntent` telemetry confirmed it doesn't fire during this repro). Theme files are byte-identical to stock. `MainActivity.kt` overrides nothing lifecycle-related before this round. `StoragePlugin.kt` only handles file-path/permission method calls, no lifecycle hooks. All four Android-native plugin dependencies were read directly and ruled out: `window_manager` has no Android implementation at all; `receive_sharing_intent`'s native code has no lifecycle/focus/IME hooks; `quill_native_bridge`'s `ActivityAware` hooks only rebind an activity reference; `file_picker` registers `Application.ActivityLifecycleCallbacks` + a `DefaultLifecycleObserver`, but every callback body is empty except an already-inert `onActivityDestroyed` cleanup.

**A new, source-verified lead**: read directly against the local Flutter 3.44.0 engine source (`FlutterActivityAndFragmentDelegate.java`, confirmed to match this project's exact Flutter version) — `onStop()` (which every Recents-overview backgrounding triggers) unconditionally calls `flutterView.setVisibility(View.GONE)`, restoring the prior visibility in the matching `onStart()`. This is a documented, stock Flutter engine workaround for a OnePlus black-screen bug (flutter/flutter#93276) — not anything QuKi-Notes added, and it runs on every device (no device-model gating in the source). `FlutterView` is the View that holds Android's native input focus while the keyboard is up. Setting the currently-focused View to `GONE` is a known trigger for Android to clear that view's focus, which can tear down the bound IME connection entirely at the native View/InputMethodManager layer — invisible to any Dart `TextInputClient` callback, and restoring visibility afterward does not on its own re-request focus or re-show the keyboard. This would explain both the silence of all six existing signals and why non-Flutter comparison apps ("every other app tested") don't share the symptom, without requiring anything QuKi-Notes-specific.

**Not confirmed** — this is a plausible, source-backed mechanism, not a proven cause. Six new TEMP DEBUG counters were added to `packages/markdown_live_editor/lib/src/keyboard_focus_debug.dart` (`activityStop`/`activityStart`, each paired with the FlutterView's actual `View.getVisibility()` at that moment; `nativeFocusChange`, a native `ViewTreeObserver.OnGlobalFocusChangeListener` reporting Android's own View-level focus transitions) specifically to let the next real device test confirm or rule this out, mirroring how Round 3's counters tested its own hypothesis.

**Surface during**: the next `notes/dev/keyboard_focus_state.md` device-verification round. If `activityStop` reports `GONE` and `nativeFocusChange` shows `FlutterView -> null` (or similar) during the switcher-reselect repro, that confirms the mechanism — the fix would then need to either explicitly re-request focus + re-show the keyboard in `onStart()` when the editor held focus before backgrounding (a MainActivity-level or Dart-level `onResume` hook), or find a way to prevent/compensate for the visibility toggle. If the counters show no correlation, this is ruled out and the mystery remains open.

---

## Resolved / Removed

- **OQ-5: Workflow JSON schema validation** — **Removed.** Workflow JSON DSL dropped entirely per ADR-14. Transports are Dart code; no JSON schema to validate.

- **OQ-NEW-1: Which built-in transport ships first?** — **Resolved (Phase 2, v0.5.0).** Both ClipboardTransport and ShareSheetTransport shipped in the same Phase 2 PR. Clipboard proved the loader + UI first (zero deps, zero auth); Share Sheet followed immediately. Append-to-GitHub-file deferred until the OAuth helper exists (Phase 4+). No new ADR needed — consistent with the "likely resolution" stated at spec time.

- **OQ-NEW-2: Plugin discovery model** — **Resolved (Phase 2, v0.5.0).** Built-in compile-time registry only (`lib/core/transports/registry.dart`). Every transport ships in the same APK; new transports require a new app version. Re-evaluate if third parties start writing transports post-v1.

- **OQ-NEW-3: Linux distribution format** — **Resolved (Phase 3, `build-linux.yml`).** Tarball (`quki-notes-linux.tar.gz`). Promote to AppImage only if Linux usage justifies it; Flatpak/Snap only if a user explicitly requests it.

---

**Last Updated**: 2026-07-04
