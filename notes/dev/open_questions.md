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

## OQ-7: is the keyboard/focus bug (PR #376) a Flutter framework issue, not a QuKi-Notes bug?

**Raised by the project owner, 2026-08-18**, after PR #376's Round 12 confirmed-fixed the toolbar/cursor-stuck-visible symptom device-tested across 12 rounds (full history: `notes/dev/keyboard_focus_state.md`, issues #394, #395). Looking for the most popular Flutter app they could find, the project owner found it has the *exact same* keyboard problems this investigation has been chasing in QuKi-Notes. Project owner's own words: "This is a fundamental flutter bug... it's key to our manifesto's contract, so I'm not sure what to do... we may need to back up and roll out all of our keyboard work and try to cooperate with flutter rather than fighting it. It seems flutter was the wrong choice here."

**Explicitly unresolved, not a decision** — raised while the project owner was about to run out of session budget for the week; flagged for continuity, not acted on yet. No rollback of the keyboard work (PR #376, all 12 rounds) and no reconsideration of the locked `Framework: Flutter (Dart)` decision (`notes/dev/decisions.md`) should happen without the project owner's explicit go-ahead.

**Why this is a genuinely high-stakes question, not a routine one**: the manifesto's "Velocity" principle (capture must be fast, frictionless) depends directly on reliable keyboard behavior, since that's the primary interaction surface for a capture app. If this really is an unfixable-at-the-app-level Flutter/Android IME integration bug, that's a threat to the manifesto's own contract, not just a bug to route around.

**What needs investigating before any decision is made** (none of this has been done yet):
1. Confirm whether the popular app's symptom shares QuKi-Notes's specific root mechanism (Round 10's finding: `didChangeMetrics()` firing a stale reading ~328ms after a correct one on resume) or is only superficially similar (e.g., a different keyboard-related bug that happens to look the same from the outside).
2. Consider whether QuKi-Notes's fully custom editor (ADR-31 — no `TextField`/`RenderEditable`, a from-scratch `TextInputClient`) is *more* exposed to this than an app using Flutter's own stock text-editing widgets, since ADR-31 deliberately opted out of Flutter's built-in IME machinery that most apps (including whatever popular app was checked) still rely on.
3. If it is a framework-level issue, "cooperate with Flutter rather than fighting it" needs a concrete meaning — e.g., whether adopting more of Flutter's own stock focus/`TextInputClient` conventions would sidestep the bug — before "roll back the keyboard work" is the right response rather than one of several options.

**Same-day refinement**: the project owner's own suspicion is that this affects *all* Flutter text entry generally — "keyboard disappears on switch, toolbars get stuck sticking around" — not something specific to custom editors or to QuKi-Notes's particular architecture, and proposed the direct way to settle it: **write a minimal throwaway Flutter app using nothing but a stock `TextField`** (no custom `TextInputClient`, no ADR-31 machinery) and run it through the exact same background/foreground repro. If a bare `TextField` reproduces the same stuck-keyboard/stuck-toolbar symptom, that's strong, cheap, unambiguous evidence this is Flutter/Android-core and item 2 above (custom-editor exposure) is not the differentiator. If it doesn't reproduce, that redirects the investigation back toward something specific to QuKi-Notes's own architecture. This minimal-repro app has not been built yet — it's the recommended first concrete step whenever this is picked back up, cheaper and more conclusive than continuing to reason from the popular-app anecdote alone.

**Surface during**: the next `notes/dev/keyboard_focus_state.md`-adjacent session, once the project owner has bandwidth to dig into this. Do not start a new keyboard-investigation round or a framework-reconsideration effort based on this entry alone.

- **OQ-5: Workflow JSON schema validation** — **Removed.** Workflow JSON DSL dropped entirely per ADR-14. Transports are Dart code; no JSON schema to validate.

- **OQ-NEW-1: Which built-in transport ships first?** — **Resolved (Phase 2, v0.5.0).** Both ClipboardTransport and ShareSheetTransport shipped in the same Phase 2 PR. Clipboard proved the loader + UI first (zero deps, zero auth); Share Sheet followed immediately. Append-to-GitHub-file deferred until the OAuth helper exists (Phase 4+). No new ADR needed — consistent with the "likely resolution" stated at spec time.

- **OQ-NEW-2: Plugin discovery model** — **Resolved (Phase 2, v0.5.0).** Built-in compile-time registry only (`lib/core/transports/registry.dart`). Every transport ships in the same APK; new transports require a new app version. Re-evaluate if third parties start writing transports post-v1.

- **OQ-NEW-3: Linux distribution format** — **Resolved (Phase 3, `build-linux.yml`).** Tarball (`quki-notes-linux.tar.gz`). Promote to AppImage only if Linux usage justifies it; Flatpak/Snap only if a user explicitly requests it.

---

## OQ-8: Root cause of intermittent Android Share Sheet delivery (branch `fix/android-share-activity-context`)

**Raised during implementation, 2026-08-27.** The #337 mechanism fix (plain `ACTION_SEND` chooser via `AndroidShareChannel`/`SharePlugin.kt`, no `startActivityForResult`) is confirmed real — targets now launch as their own independent task instead of nesting under QuKi-Notes'. But delivery is still intermittent with no clean repro, unlike two comparison apps (a minimal native app, Google Keep) that share consistently.

**Investigated, not confirmed** (see PR report for full reasoning):
- **Stale `Activity` context** (`SharePlugin`'s `context`, captured once in `MainActivity.configureFlutterEngine()`): code review found no structural path for this under the app's actual lifecycle — `configChanges` covers virtually every recreation trigger, and `FlutterActivity` creates a fresh engine (and thus a fresh `SharePlugin`) per Activity instance, so a genuinely stale reference at Send-time would require a scenario not identified during review. Additionally, if a stale/invalid context *did* throw, `_onTransport()`'s existing `catch` block would already surface a visible "Send failed" snackbar — which doesn't match the reported symptom (no visible error, just no delivery). Weak lead based on available evidence, not ruled out entirely.
- **Async gap before the native call** (`await _autoSave.flush()` + the Dart↔Kotlin `MethodChannel` round trip, both absent from a native app's synchronous `onClick`): confirmed as a real, structural difference from the comparison apps. Whether it's long enough, and whether Android's Background Activity Launch restrictions (a real, documented OS mechanism that can silently no-op a `startActivity()` call with no exception thrown, if it's judged not to originate from a sufficiently "foreground" user gesture) are actually the mechanism, is **not confirmable from source alone** — it depends on real device timing.

**Not implemented**: reordering `_autoSave.flush()` to no longer block the native call (would shrink the async gap, but changes `TransportContext.quki.id`'s value for a same-session first-ever send before any autosave has run — a real, if narrow, behavior change not covered by the brief's invariant, and "no unspecified UX behaviors" — left to Spec/project owner rather than implemented speculatively).

**What was landed instead**: temporary diagnostic logging (grep `TEMPORARY DIAGNOSTIC` across `SharePlugin.kt`, `MainActivity.kt`, `android_share_channel.dart`, `editor_screen.dart`) — Activity identity/lifecycle state at registration time and at the moment `startActivity()` fires, plus Dart-side timestamps through the whole call chain. Needs the project owner to capture real `adb logcat` + app output across several attempts (successful and failed) before this can move past "leads" to a confirmed mechanism.

**Separate finding, not part of this bug**: `Logger.root` (from `package:logging`) has no listener registered anywhere in the app (`grep -rn "Logger.root" lib/` finds nothing) — every existing `_log.*` call across the codebase (e.g. `EditorScreen`'s own `_log.severe('plugin.transport threw unexpectedly', ...)`) currently produces no visible output at all, in debug or release. This diagnostic instrumentation used `debugPrint` instead specifically to route around that gap. Worth its own follow-up (wire a listener, at least in debug builds) independent of this bug.

**Surface during**: whenever the project owner has captured on-device logcat output from several real Send attempts against the intermittently-failing target(s).

---

**Last Updated**: 2026-07-04
