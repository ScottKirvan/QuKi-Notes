# Architecture Decision Records

Compact log of every locked decision. Format: **what**, **why**, **rejected alternatives**. Order: most recent first.

When implementation surfaces a need to change one of these, propose an ADR update in the PR rather than deviating silently. New decisions made during implementation must be appended here.

Full detail for every entry lives in `design_spec.md`; this file is the index + rationale.

Normative framing in `manifesto.md` — read that first.

**Superseded entries stay numbered but are trimmed to a one-line pointer** — this log indexes *current* decisions, not a full history of everything that was ever tried. If an entry doesn't shape what to build today, it doesn't belong here in detail. Full commit/PR history is in git if the "why we didn't do X" reasoning is ever needed.

---

## ADR-33: Nested inline markdown — CommonMark delimiter-run algorithm

**Date**: 2026-07-21

**Status**: Stage 1 complete (PR #276, merged 2026-07-21) — paragraphs and headings. Stage 2 (list-item/checkbox content, the original #240 ask) is next; Stage 3 (HTML detection) and further stages not started. Full spec + staged plan: `notes/dev/nested_inline_markdown.md` — read that first; this entry is the index pointer.

**What**: Replace `MdParser`'s flat, non-recursive inline scanner (Step 5 in the current parse loop) with a nested/recursive engine implementing CommonMark's delimiter-run + flanking-rule algorithm, scoped to QuKi-Notes' existing inline subset (bold, italic, strikethrough, inline code, links, images, autolinks) plus backslash escapes. Applies uniformly to paragraphs, headings, and list-item content — today only paragraphs get inline scanning at all. HTML is detected and excluded from markdown scanning (passed through raw), never parsed. Reveal-on-cursor for a nested/combined run shows the entire outermost element as raw source, not just the innermost piece. Reference implementation for correctness (not a runtime dependency): `github/cmark-gfm`, the actual C library github.com renders markdown with.

**Why**: Found via full code review (2026-07-21) while scoping #240 (nested inline formats in list items) — the actual gap is architectural and universal, not list-specific: the current scanner finds the nearest matching delimiter pair and never re-scans its interior, so `**bold *italic* text**` renders as one flat bold run with literal asterisks inside it, in a paragraph, a heading, or a list item alike. A naive stack (push-open/pop-close) fixes nesting but still won't match GitHub/Obsidian output on real text — e.g. `foo_bar_baz` (not italic on GitHub) vs. `foo*bar*baz` (italic on GitHub) requires the flanking-rule distinction between `_` and `*`, which a simple stack has no way to express. CommonMark's algorithm is the documented, spec-tested solution every compliant renderer (including GitHub's own `cmark-gfm`) already uses — adopting it means "matches GitHub" is a checkable fact against a public test suite, not a judgment call.

**Rejected alternatives**: two-pass approach (strip block prefix, run the *existing* flat scanner on the remainder) — fixes list-item inline scanning but does nothing for nesting, since the flat scanner never supported nesting anywhere, in or out of lists; naive stack-based push/pop matching — right shape, wrong result on real-world text (see intraword-emphasis example above); adopting an off-the-shelf markdown library (e.g. the `markdown` package) wholesale — already rejected in ADR-30 for not exposing source character offsets, which ADR-31's reveal/collapse model requires; that constraint is unchanged.

**Deferred, tracked separately**: tables (wanted before v1, but its own spec); list nesting/indentation (#241) and Tab/Shift+Tab indent handling (#77) — both build on this but are their own architectural surface.

---

## ADR-32: `url_launcher` for link navigation

**Date**: 2026-07-06

**What**: Add `url_launcher` to `dependencies` for tap-to-navigate on collapsed inline links (ADR-31 Stage 6). Call `launchUrl(Uri.parse(url))` from `editor_screen.dart` via the `onLinkTap` callback threaded through `MarkdownEditor`.

**Why**: Platform URL opening requires a plugin; `url_launcher` is the Flutter-team-maintained standard, MIT-licensed, already a transitive dependency of several packages in the ecosystem. No bespoke native code needed.

**Rejected**: `flutter_launch_url` and similar third-party wrappers — no advantage over the canonical package. Rolling platform channels manually — unnecessary complexity.

---

## ADR-31: Custom RenderObject + TextInputClient live-preview markdown engine — supersedes ADR-30

**Date**: 2026-07-04

**Current architecture.** Full technical detail: `notes/dev/design_spec.md` → "Editor rendering engine (ADR-31)". Plain-English walkthrough: `notes/dev/live_preview_editor.md`. Inline-markup parsing within this engine (nesting, list-content scanning) is further specified by ADR-33 — see below.

**What**: Replace the `TextField` + `TextEditingController.buildTextSpan()` approach entirely with a custom `RenderObject` that implements `TextInputClient` directly, bypassing `EditableText` and `RenderEditable`. The markdown source buffer remains the single source of truth. A parse pass produces elements — headings, list items, checkboxes, bold/italic/code spans, links, images, etc. — each anchored to a source range (`start`, `end` offsets into the buffer). The editor owns its own model-offset ↔ view-offset mapping and paints its own caret, selection highlight, and rendered content; none of this goes through Flutter's `TextPainter`/`RenderEditable` cursor-offset math.

**Model**:

- **Reveal/collapse by cursor intersection**: an element whose source range contains the current selection shows its raw markdown source, in place, directly editable. Every other element shows its collapsed/rendered form, which may be an entirely different length and content than its source — a heading loses its `# ` completely and grows in size; a link `[text](url)` shows only `text`; an image `![alt](url)` shows an actual embedded image; a checkbox shows a real glyph.
- **Reparse on edit, not on cursor move**: a text change re-runs the parse. QuKis are short-form notes; full reparse per keystroke is acceptable. Do not add incremental parsing until profiling proves it's needed.
- **Boundary-reveal cursor movement**: an arrow key that would land the cursor at the boundary of a collapsed element triggers reveal; the cursor lands at the near boundary of the full source text and navigates character-by-character from there. There is no skip-over behavior — every element in QuKi-Notes has editable source. Exiting the far boundary collapses the element and returns to normal navigation.
- **Tap-to-source-character hit-testing**: tapping inside a collapsed element's rendered bounds reveals the element and places the cursor at the source character corresponding to the tap position. Fallback for non-text rendered content (e.g., an embedded image widget): tap resolves to whichever source boundary is nearer the tap's x-coordinate.
- **Direct IME integration**: the widget implements `TextInputClient`, opens its own `TextInputConnection` via `TextInput.attach()`, and receives `TextEditingValue` updates from the platform IME directly.
- **Links**: tap navigates (opens URL). Reveal-and-edit is triggered by cursor entering via keyboard (arrow-key from either side, or backspace from the right), or cursor landing at the element boundary. Resolved 2026-07-04 (OQ-6).
- **Images**: always reveal source on tap (no navigate action).

**Why**: Research (2026-07-04) confirmed Flutter's `EditableText`/`RenderEditable` stack cannot support variable-length live-preview rendering at all, at the engine level:

- `TextPosition` offsets index directly into the *rendered* `TextSpan`'s flattened plain text, with no reconciliation against `TextEditingController.text` (flutter/flutter#49860).
- `WidgetSpan` always consumes exactly one UTF-16 code unit of cursor-offset space regardless of its rendered content — confirmed by a Flutter engine maintainer (flutter/flutter#107432), and cursor placement in/around `WidgetSpan`s is separately confirmed broken (flutter/flutter#150864). This is an engine-level constraint, not something patchable from userland.
- No Flutter package or published project has solved true variable-length live-preview markdown editing on stock `TextField` primitives.
- CodeMirror 6 (Obsidian's Live Preview engine) solves this via an anchored-range decoration model that never requires rendered and source text to be the same length — proven architecture, but only achievable through a custom render/input layer, not Flutter's high-level text widgets.

**Rejected alternatives**:
- *`WidgetSpan`-per-element* — blocked by the one-character-per-`WidgetSpan` engine limitation.
- *Document-model editor (`super_editor`, `flutter_quill`, `appflowy_editor`-style)* — an AST/tree becomes authoritative and markdown is serialized at the edges; the manifesto's open-data requirement (`.md` files are the real data, always) rules this out regardless of rendering sophistication.
- *Accept same-length rendering permanently, ship a lesser feature* — insufficient for the app's core value proposition (real heading sizes, real link text, real inline images).

**Scope note**: build in independently-shippable stages, not as one PR. Long-term intent is to extract and publish this as a standalone pub.dev package once proven.

---

## ADR-30: Single-buffer TextSpan editor — superseded by ADR-31

Replaced 2026-07-04 by the custom RenderObject engine (ADR-31) — the `buildTextSpan()` same-length model cannot support variable-length rendering (real heading sizes, real link text, real inline images), a hard Flutter engine-level limitation. Not implemented in the current codebase.

---

## ADR-29: Transport plugin system — QuickJS runtime scripting

**Status: locked future decision, not yet implemented.** The MVP transport mechanism today is still the compile-time registry (ADR-14) — `lib/core/transports/registry.dart`. This ADR specifies where the plugin system is headed (roadmap Tier 6, issue #84), not current behavior.

**Date**: 2026-07-01

**What**: Replace the compile-time transport registry with a runtime plugin system. Plugins are JavaScript files (authored in TypeScript, distributed as compiled `.js`) discovered from a `plugins/` directory in the user's QuKi storage root at app launch. Embedded engine: QuickJS via `flutter_js`. A plugin registers transports by calling a sandboxed Dart-exposed API (`QuKi.registerTransport`, `QuKi.getLocation`, `QuKi.readExif`, `QuKi.showModal`, `QuKi.fetch` with explicit per-plugin network permission) — no filesystem or platform access beyond that surface.

**Why**: The compile-time registry satisfies the code structure of a plugin system but not the user promise — adding a transport requires a code change, a build, and a release. The manifesto principle is *user-defined destinations*. QuickJS runs in AOT release builds on Android/iOS, is ~600KB, and the target power-user audience (Obsidian community) already knows TypeScript.

**Rejected alternatives**: Lua (unfamiliar to target audience, weak type safety); WebAssembly (overkill FFI boundary for text transforms); Python via Chaquopy/Pyodide (not iOS-viable); MCP-only (requires a running external server, not suited to device-local operations like GPS/EXIF).

---

## ADR-28: Android filesystem storage via MANAGE_EXTERNAL_STORAGE

**Date**: 2026-06-29

**What**: When the user chooses "Filesystem storage" on Android, request `MANAGE_EXTERNAL_STORAGE` and store QuKis at a fixed path: `<external storage>/Documents/QuKi_Notes/`. Binary choice (app storage vs. filesystem storage), no folder picker, matching the Obsidian model. All file I/O uses `dart:io` — `QuKiStorage` unchanged.

**Why**: `MANAGE_EXTERNAL_STORAGE` is the only mechanism giving `dart:io`-compatible access to shared external storage on Android 11+. Scoped-storage alternatives (SAF/MediaStore) require a full `QuKiStorage` reimplementation with no material UX benefit. The open-data manifesto requires notes to be user-accessible outside the app.

**Rejected alternatives**: SAF + DocumentFile API (reimplements all file I/O, no simpler UX); SAF + `dart:io` path conversion (what ADR-27 originally tried — unreliable, notes silently disappeared on restart); `getExternalFilesDir()` (cleared on uninstall); custom folder picker (no benefit over a fixed well-known path).

---

## ADR-27: Storage location — first-launch modal, SAF or app storage

**Date**: 2026-06-28

**What**: On first launch, before the editor appears, show a one-time setup modal with two choices — **Filesystem storage** (user-chosen folder via the platform's native picker; survives uninstall, accessible via file manager) or **App storage** (sandboxed `getApplicationDocumentsDirectory()`; deleted on uninstall). Choice saved to `shared_preferences`; modal never reappears. Settings → Storage always shows the current path with a "Change location" option (new QuKis go to the new path; no automated migration).

**Why**: The manifesto promises QuKis are readable/movable without opening the app — app storage violates this on Android. The one-time modal ensures an informed choice instead of a silent unsafe default, which especially matters during beta when testers reinstall frequently.

**Rejected alternatives**: silent default to app storage (data loss on reinstall); picker triggered on first save instead of at launch (interrupts capture flow); migration on location change (deferred to v1.1+ — files are plain markdown and user-moveable manually).

---

## ADR-26: Replace `super_editor` — rejection of document-model editors

**Status: rendering mechanism fully superseded (ADR-30, then ADR-31). Only the "why not a document-model editor" reasoning below still applies — the package structure and API described in the original entry no longer exist in the codebase.**

**Date**: 2026-06-15

**What still holds**: `super_editor` was removed because it interposes a document model between the user's text and the `.md` file on disk, and its markdown serializer was unreliable (mixed list types corrupted on round-trip, blank lines stripped). The manifesto requires `.md` files to be clean, human-readable plain text at all times — any editor architecture where an AST/tree is authoritative and markdown is a serialization side-effect violates this, which is why `flutter_quill`, `appflowy_editor`, and every other document-model editor remain rejected today, independent of which rendering mechanism QuKi-Notes currently uses (ADR-31).

The replacement editor lives in `packages/markdown_live_editor/` (monorepo path dependency) — extracted as a package so the Dart package boundary prevents it from accidentally importing QuKi business logic, and so it can be published to pub.dev independently if it proves solid. That extraction decision still holds; everything else in the original entry (block-flip model, `flutter_markdown`, `block_splitter.dart`) describes an intermediate architecture that no longer exists — see ADR-31 for the current one.

---

## ADR-25: Storage backend — individual `.md` files

**Date**: 2026-06-14

**Current architecture.** Replaced Drift/SQLite with individual `.md` files. One file per QuKi: `<app-documents>/qukis/{uuid}.md`, `.meta/{uuid}.json` sidecar (`{"createdAt": "..."}`), `.trash/` for soft-deleted QuKis (mirrors the same `{uuid}.md` + `.meta/` structure). `createdAt` lives in the sidecar; `modifiedAt` is the filesystem `mtime` — only changes on an actual write. In-memory `List<QuKiMeta>` index rebuilt on app start, updated synchronously on every write/delete. Search is a content scan at query time.

**Why**: The manifesto's open-data principle requires QuKi data to be directly accessible as plain files — SQLite satisfies the letter but not the spirit. SQLite also produced a `modifiedAt`-on-open bug class (#75, two failed fix attempts) that doesn't exist when filesystem `mtime` is the single source of truth.

**Rejected alternatives**: SQLite + mirrored mtime (two sources of truth); timestamp-embedded filenames (opaque, fragile parsing); single `index.json` (single point of failure, write contention); parallel SQLite index alongside `.md` files (defeats the purpose).

**Consequences**: Drift, `sqlite3_flutter_libs`, `build_runner` dropped from the dependency tree. `lib/core/database/` replaced by `lib/core/storage/`. No schema migrations exist in this model.

---

## ADR-24: Inline markdown input reactions

**Removed** — this described `super_editor`-specific `EditReaction` subclasses. `super_editor` was removed (ADR-26); no such mechanism exists in the current codebase. See ADR-31 for how inline markup is handled today.

---

## ADR-23: Icon library — Lucide (`lucide_flutter`)

**Current.** Flutter's bundled `Icons` covers classic Material Design only; Lucide was chosen for its consistent stroke-based aesthetic — MIT-licensed, full catalogue via `lucide_flutter ^1.17.0` (font-based, works with the standard `Icon()` widget). All new UI uses `LucideIcons.*`.

**Why**: cleaner stroke style than Material's filled defaults for this app's visual intent.

**Rejected**: `material_symbols_icons` (heavier package); Lucide-via-SVG assets (no `Icon` widget compatibility); staying with `Icons.*`.

---

## ADR-22: Window-state persistence — `window_manager`

**Current.** `window_manager ^0.5.1` restores/persists window `{x, y, width, height}` via `shared_preferences` on Windows + Linux (Android skipped via platform guard; iOS/macOS deferred). Save timing uses the post-gesture `onWindowMoved`/`onWindowResized` variants, not per-pixel.

**Why**: ecosystem standard for desktop window control; no platform-side native code needed.

**Rejected**: raw platform channels (`window_manager` already wraps them correctly).

---

## ADR-21: Flutter import allowed in `lib/core/transports/` (settingsView exception)

**Current.** `lib/core/transports/` is the one approved exception to the ADR-16 Flutter-free `lib/core/` rule, because `TransportPlugin.settingsView(WidgetRef) → Widget` needs `flutter/material.dart` + `flutter_riverpod`. All other `lib/core/` subdirectories remain Flutter-free.

**Why**: keeps `settingsView` in the plugin contract itself rather than a separate three-way adapter; the CLI (ADR-16) simply never calls `settingsView()`.

**Rejected**: a separate `TransportPluginUI` mixin in `lib/features/` — unneeded indirection for a single-developer, single-codebase project.

---

## ADR-20: Save-on-leave bridge (Phase 1.3)

**Removed** — a temporary "save on navigate away" shim for the stream screen before the Phase 1.5 auto-save controller existed. Long superseded; no trace of it remains in the current codebase. See auto-save behavior in the root `CLAUDE.md` implementation notes.

---

## ADR-19: Privacy & device permissions — three-gate opt-in, capability-aware

**Current — locked, not yet exercised** (no device-backed enrichment like GPS is implemented yet; this governs the design when one lands). Device capabilities (GPS today; camera/mic/contacts/calendar potentially later) are never requested unless **all three gates** are ON: (1) the platform actually exposes the capability, (2) an app-wide `Settings → Privacy` toggle per capability (default OFF, not asked at onboarding), (3) a per-transport opt-in in that transport's `settingsView`. The OS permission dialog appears only on the first fire of a transport that needs the capability with all three gates on — never at install or onboarding.

**Why**: the manifesto requires frictionless capture — a permission dialog between "tap app icon" and "cursor in editor" is friction. This ADR makes that contract enforceable rather than aspirational.

**Rejected**: asking at onboarding; default-on for any capability; a single coarse "enable all" toggle.

---

## ADR-18: MVP scope — local-only, transports built in, no sync, no MCP

**Current.** MVP = local-only capture + at least one transport plugin. No GitHub sync, no MCP in v1. Sync is opt-in and ships as a plugin axis in v1.1+ (skeleton `lib/core/sync/` lands with the first sync plugin, not before). MCP is a reserved third axis — no code until v2.0+.

**Why**: prevents sync from being scoped into Phase 1, and prevents transport plugins from accidentally depending on sync primitives. Shipping GitHub sync as MVP's defining feature would couple v1 to OAuth + rate limits + conflict UX and overstate QuKi's actual job (capture-and-dispatch, not durable storage).

---

## ADR-17: Sync as an opt-in plugin axis (not a core feature)

**Current — locked, not yet implemented.** Sync is one of three plugin axes (transports, sync, MCP), off by default. Interface: `SyncBackend.pullChanges(since) → diffs`, `pushChanges(list) → ack/conflict`. GitHub is one possible backend among several (S3-compatible buckets, WebDAV, Syncthing-paired local folder, Dropbox, raw webhook) — not privileged. Conflict resolution is sync-plugin-specific.

**Rejected**: GitHub-as-the-only-sync (locks out users who don't want GitHub for personal notes); a generic "sync engine" with adapters (over-engineered for the plugin count this needs).

---

## ADR-16: CLI lives in the same repo, sharing the core library

**Current — working hypothesis, not built.** A future Dart console app (`bin/quki.dart`) would share `lib/core/` + `lib/shared/models/`, which is why core stays Flutter-free (anything importing `package:flutter/...` lives under `lib/ui/`/`lib/features/`). Not built in MVP; this ADR only locks the constraint so MVP doesn't paint into a corner. Working hypothesis detail: `cli_design.md`.

**Rejected**: a separate `packages/quki_core` + `packages/quki_cli` split (premature); CLI as a Flutter-app feature flag (UX confusion, binary size).

---

## ADR-15: Ephemerality model — Gmail-style, no auto-delete

**Current.** QuKis are *framed* as ephemeral (newest-first stream, no folders, no tags) but persisted forever locally by default. A tossed QuKi is copied, not moved. User-initiated delete is the only deletion mechanism — no auto-archive, no expire-after-N-days.

**Why**: organizing friction is what makes vaults heavy; "ephemeral but searchable" framing keeps QuKis weightless without surprising the user with data loss.

**Rejected**: hard auto-delete after N days; an explicit archive folder (vault behavior, forbidden).

---

## ADR-14: Plugin architecture — three independent axes, Dart-only

**Current — this is the live transport mechanism today.** Three plugin axes with separate lifecycles: **Transports**/QuKi-Tosses (stateless `(text, images) → success/failure`, multiple may exist, user picks at toss time — this is what's built and shipping), **Sync backends** (ADR-17, not yet built), **MCP servers** (v2.0+, not yet built). All plugins are Dart-only — no JS/TS, no native bindings (Obsidian gets a separate glue TypeScript plugin talking to a Dart-shaped endpoint, out of scope for core).

**Transport interface (MVP, live)**:
```dart
abstract class TransportPlugin {
  String get id;
  String get displayName;
  String get description;
  Widget settingsView(WidgetRef ref);

  Future<TossResult> toss({
    required String markdown,
    required List<Image> images,
    required TossContext ctx,
  });
}

class TossResult {
  final bool success;
  final String? message;
  final bool retryable;
}

class TossContext {
  final DateTime firedAt;
  final QukiMetadata quki;
  final Geolocation? gps;   // null unless all ADR-19 gates ON
  final Map<String, String> userOverrides;
}
```

**Why `List<Image>` not `List<Attachment>`**: deliberate — a QuKi is GFM markdown rendering text + images; generalizing to arbitrary attachments (PDFs, video) violates the manifesto's ephemeral/frictionless framing.

**Rejected**: a workflow JSON DSL (see deprecated ADR-7); embedding a scripting language for user-authored transports in MVP (that's ADR-29, deferred); a marketplace UI (premature); generic `List<Attachment>`.

---

## ADR-13: Testing discipline — tests with code, regression tests for fixes

**Current.** Tests ship with code, every PR — no "tests come later." Bug fixes follow regression-test-first: failing test committed first, then the fix, test stays permanently. Layers: unit (pure logic + services), widget (stateful UI), integration (storage + UI flows). Mock services with `mocktail`; never mock data classes. No coverage threshold — PR review asks "where's the test?" instead. Flaky tests: zero tolerance.

**Rejected**: deferred testing; coverage gates (incentivizes noise tests); mocking storage internals. Full operational detail: `notes/dev/testing.md`.

---

## ADR-12: Theme / Logging / Privacy posture

**Current.** Theme follows system (`ThemeMode.system`), light + dark, no manual override in MVP. Logging via `package:logging` — console in debug, in-memory ring buffer in release, sensitive data never logged. No analytics, no crash reporting, no telemetry, ever.

**Rejected**: Sentry/Crashlytics/Firebase (privacy posture).

---

## ADR-11: Rate limiting & lazy image download (sync-plugin scope)

**Locked, applies only once a sync plugin exists (v1.1+)** — MVP has no rate-limit considerations since nothing leaves the device until toss. GitHub sync plugin: throttle when `X-RateLimit-Remaining < 100`; QuKis pulled newest-first; images lazy-fetched on first view (row inserted with `localPath = null`) since bodies are KB-sized but images can be MB each. Per-transport rate-limit behavior is that plugin's responsibility, not core's.

---

## ADR-10: Cross-device timestamps on pull (sync-plugin scope)

**Locked, applies only once a sync plugin exists.** MVP keeps `createdAt`/`modifiedAt` purely local. Sync plugin contract for a remote-only QuKi pulled to this device: fresh local UUID for `id`; remote identifier captured verbatim in a plugin-owned field; `createdAt` derived from remote metadata; `modifiedAt` = pull time. Sub-day precision loss on cross-device round-trip accepted for the first sync plugin.

**Rejected**: YAML frontmatter (forces non-empty file content schema); extra `GET /commits` per file (rate-limit cost).

---

## ADR-9: OAuth (deferred to sync / transport plugins)

**Locked, not yet needed.** No OAuth in MVP — nothing in core calls an authenticated service. When a GitHub sync plugin or GitHub-flavored transport ships, it uses GitHub Device Flow with `client_id` only (public client, no secret); scopes `repo` + `read:user` for sync, minimum-necessary for transports. Shared device-flow + `flutter_secure_storage` helper code lives in `lib/core/auth/`.

**Rejected**: PKCE via `flutter_appauth` (immature Windows/Linux URL-scheme support); raw client-secret flow (can't keep a secret in a client app).

---

## ADR-8: Drift migration discipline

**Removed** — Drift/SQLite was eliminated entirely by ADR-25. No migrations exist in the current file-based storage model.

---

## ADR-7: Workflow target SHAs — always re-fetch  ⚠️ DEPRECATED

Superseded by ADR-14 (transport plugins replace the JSON workflow DSL) and ADR-17 (sync is a plugin axis). The "fetch latest SHA before each PUT to avoid 409" pattern it originally specified is now a per-transport-plugin implementation detail for any GitHub-flavored transport, not something core enforces. Retained as a short note so a future GitHub-append transport doesn't need to rediscover the 409 pattern from scratch.

---

## ADR-6: Save vs Push — separate concerns (MVP: save only)

**Current** (storage mechanism corrected for ADR-25 — "SQLite" in the original entry is now "local files", nothing else changed). **Save** (local files): 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks, never networks. **Push** (sync plugin): not in MVP; when it lands (v1.1+), 2s idle + foreground + manual sync only — periodic/lifecycle saves never trigger push. **Toss** (transport): user-initiated only, never automatic.

**Why**: protects against long-typing-run data loss without networking; max unsaved window ≈ 30s.

---

## ADR-5: Deletion model — Recently Deleted, user-managed restore/delete

**Mechanism corrected for ADR-25.** The original entry described a SQLite `deletedAt` column and a configurable-retention background sweep — storage moved to files (ADR-25), so the actual mechanism is a `.trash/` subfolder (`{uuid}.md` + `.meta/{uuid}.json`, same shape as the live folder). **The retention-period auto-sweep was never built and is not planned** — deletion is user-managed only, no timer (see root `CLAUDE.md` Key Decisions table). What still holds: Recently Deleted is a data-recovery screen, not an organization feature — tap restores, swipe hard-deletes with confirmation, no sort/filter/filing within it.

**Why**: the friction of organizing is what makes vaults heavy; Recently Deleted must resist feature creep toward vault-like behavior. A configurable timer sounded useful at design time but added complexity nothing has asked for since — user-managed deletion is simpler and matches how QuKi-Notes treats deletion everywhere else (explicit, not automatic).

**Rejected**: auto-expire with no recovery UI; an archive folder (organization feature, forbidden).

---

## ADR-4: Image storage — separate binary files

**Locked design; feature itself blocked** (image paste blocked on CargoKit being archived — see `dependencies.md`). Binary files at `<app docs>/images/{filename}` (`YYYY-MM-DD-{uuid8}.{ext}`), referenced from QuKi markdown as `![](../images/{filename})` (relative, so the reference stays portable when tossed). Cascade delete on QuKi delete. When a sync plugin is active: push image before referencing QuKi, to avoid a broken-link window.

**Rejected**: base64-embed in markdown (file bloat, editor performance, unreadable when tossed).

---

## ADR-3: QuKi IDs & filenames

**Local filename scheme corrected for ADR-25.** QuKi `id` is always UUID v4. **Locally, the file is `{uuid}.md`** (ADR-25's actual on-disk scheme) — the original entry's `YYYY-MM-DD-{uuid8}.md` date-prefixed pattern was never built for local storage. That pattern remains the plan for a **transport- or sync-plugin-derived remote filename** (deterministic from `createdAt` + `id`, chosen once and never recomputed) — e.g. a GitHub sync plugin choosing a path in a repo — which is a separate concern from the local on-disk name.

**Rejected**: `YYYY-MM-DD-NNN.md` for remote filenames (offline-device collisions, needs GET-before-write); `YYYY-MM-DDTHHMMSS.md` (clock-skew collisions).

---

## ADR-2: Token storage — `flutter_secure_storage` for any plugin secret

**Current.** Any plugin holding a secret (OAuth token, API key) uses `flutter_secure_storage` namespaced by plugin id. Everything else stays in `shared_preferences`.

**Why**: a `repo`-scope GitHub token is read/write access to all user repos; plaintext storage is an unacceptable threat surface for ~zero implementation cost.

---

## ADR-1: State management — Riverpod (code-gen)

**Current.** `riverpod` + `riverpod_generator` with `@riverpod` throughout. No global singletons, no manual `InheritedWidget`, no `setState` outside trivial widget-local state. Providers live next to the feature they serve; cross-cutting providers live in `core/`.

**Rejected**: Bloc (more ceremony than warranted); plain `provider` (Riverpod is the maintained successor); manual DI (loses testability and reactive streams).
