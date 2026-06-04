# Architecture Decision Records

Compact log of every locked decision. Format: **what**, **why**, **rejected alternatives**. Order: most recent first.

When implementation surfaces a need to change one of these, propose an ADR update in the PR rather than deviating silently. New decisions made during implementation must be appended here.

Full detail for every entry lives in `design_spec.md`; this file is the index + rationale.

Normative framing in `manifesto.md` — read that first.

---

## ADR-23: Icon library — Lucide (`lucide_icons`)

Flutter's bundled `Icons` class covers the classic Material Design set. Material Symbols (the newer Google icon set) is not bundled and requires a separate package. Lucide was chosen instead: it is MIT-licensed, has a consistent stroke-based aesthetic that matches the app's clean visual intent, and the `lucide_icons` pub.dev package covers the full Lucide catalogue.

- **What**: `lucide_flutter ^1.17.0` added to `dependencies`. Font-based (not SVG), works with the standard `Icon()` widget. All app-bar and navigation icons in `lib/features/editor/editor_screen.dart` use `LucideIcons.*`; other screens may migrate incrementally. (`lucide_icons` was tried first but is incompatible with Flutter 3.29+ — `LucideIconData extends IconData` fails since `IconData` became `final`.)
- **Why**: Scott's explicit preference. Lucide's stroke style is cleaner than Material's filled defaults for this app's aesthetic. `Icons.*` remain available for anything not yet migrated.
- **Rejected**: `material_symbols_icons` (Google's newer set, heavier package); Lucide-via-SVG assets (requires custom rendering, no `Icon` widget compatibility); staying with `Icons.*` (Scott rejected).

---

---

## ADR-22: Window-state persistence — `window_manager`

Desktop (Windows + Linux) opens at the OS default size and position every launch. Persisting the last-used size and position improves the daily-driver desktop experience.

- **What**: `window_manager ^0.5.1` added to `dependencies`. On launch (`main()`, before `runApp`), restore saved `{x, y, width, height}` from `shared_preferences`. `WindowStateScope` widget (mounted at app root) listens via `WindowListener` and persists bounds on `onWindowMoved`, `onWindowResized`, `onWindowClose`.
- **Why**: `window_manager` is the Flutter ecosystem standard for desktop window control. No platform-side C++ modifications needed at 0.5.x — `windowManager.ensureInitialized()` in Dart is sufficient.
- **Rejected**: Raw platform channels (higher maintenance burden; `window_manager` already wraps them correctly for both targets).
- **Scope**: Windows + Linux only. Android branch skipped via `Platform.isWindows || Platform.isLinux` guard. iOS/macOS deferred per manifesto platform priority.
- **Keys in `shared_preferences`**: `window.x`, `window.y`, `window.width`, `window.height` (all `double`). Keys absent on first launch → OS chooses position.
- **Save timing**: `onWindowMoved` / `onWindowResized` use the `*d` (post-gesture) variants so SharedPreferences is not written on every drag pixel.

---

## ADR-21: Flutter import allowed in `lib/core/transports/` (settingsView exception)

The `TransportPlugin` interface defines `settingsView(WidgetRef ref) → Widget` as part of its contract so that each plugin can provide its own configuration UI shown in Settings → Tosses. This requires importing `package:flutter/material.dart` and `package:flutter_riverpod/flutter_riverpod.dart` in `lib/core/transports/transport_plugin.dart`, which technically violates the ADR-16 Flutter-free constraint on `lib/core/`.

- **What**: `lib/core/transports/` is the one approved exception to the ADR-16 Flutter-free rule. All other `lib/core/` subdirectories (`database/`, `auth/`, `settings/`) remain Flutter-free.
- **Why**: Keeping `settingsView` in the plugin contract (rather than in a separate Flutter-side adapter) avoids a three-way dependency between the plugin, the core registry, and a feature-layer adapter for every plugin ever added. The CLI (ADR-16) uses only `toss()` and can simply ignore `settingsView()` — it is never called by non-Flutter hosts.
- **Rejected**: A separate `TransportPluginUI` mixin in `lib/features/` that Flutter hosts mix in alongside the core interface — adds indirection with no practical benefit for the single-developer, single-codebase scenario; revisit if a headless server deployment is ever a real target.
- **Scope**: only `lib/core/transports/`. The rest of `lib/core/` and all of `lib/shared/` remain Flutter-free per ADR-16.

---

## ADR-20: Save-on-leave bridge (Phase 1.3) → superseded by Phase 1.5 auto-save

Phase 1.3 (stream screen) requires content to appear in the list after the user types something in the editor. Full auto-save (ADR-6 debounce + lifecycle) lands in Phase 1.5. A minimal "save when the user explicitly navigates away" bridge was added to `EditorScreen` for Phase 1.3 so the stream is testable.

- **What**: `_saveIfNeeded()` fires when the user taps `← Stream`. First call on a new QuKi inserts a row; subsequent calls update it (tracked via `_savedQukiId` state).
- **Not triggered by**: hardware back button (known limitation; Phase 1.5 fixes this).
- **Superseded by**: Phase 1.5 auto-save controller (2s debounce + 30s periodic + lifecycle hooks). When Phase 1.5 lands, `_saveIfNeeded()` and `_savedQukiId` are removed and replaced by the controller.
- **Rejected**: pre-creating an empty row in `_openNew()` — produces permanent `(empty)` entries when the user abandons without typing.

---

## ADR-19: Privacy & device permissions — three-gate opt-in, capability-aware

Device-backed enrichments (GPS, future: camera, microphone, contacts, calendar) are never requested unless ALL three gates are ON:

1. **Device capability gate** — if the platform doesn't expose the capability (e.g. GPS on a desktop Windows tower without a Bluetooth GPS), the field is omitted from `TossContext` and the corresponding setting is hidden. No "this feature requires a device with GPS" toast; the affordance simply does not exist.
2. **App-wide setting gate** — `Settings → Privacy` exposes one toggle per capability: "Allow transports to request GPS" (etc.). **Default OFF** for every capability. Onboarding does NOT ask about these; the app boots into a blank QuKi and any later toss that would need permission is what surfaces the prompt.
3. **Per-transport setting gate** — each transport that wants the capability declares it in its `settingsView`; the user opts in per transport. Only when all three gates are ON does the OS permission dialog appear, and only on the **first fire** of a transport that needs the capability.

**Implications:**

- A user can install a "GitHub Daily Log with GPS" transport, leave the app-wide GPS toggle OFF, and the transport's GPS feature is silently disabled (toss still works, no GPS in the appended payload). The transport's `settingsView` shows a hint: "GPS is disabled in app Privacy settings."
- A user who turns ON app-wide GPS but doesn't enable it for a specific transport gets the same result for that transport.
- Permission revocation at the OS level is treated as "capability gate OFF" — graceful, no nag.
- The OS permission dialog appears at first toss-with-permission, not at install time and not at onboarding. **Capture is never gated by a permission dialog.**

**Rejected:**
- Asking for permissions at onboarding (violates frictionless-capture; primes the user with a security prompt before they've typed a word).
- Default-on for any device capability (privacy posture — the user must consciously opt in).
- A single app-wide "Enable all transport capabilities" toggle (too coarse; defeats per-transport intent).

**Why this matters specifically:** the manifesto says capture must be frictionless. A permission dialog at any point between "tap app icon" and "cursor in editor" is friction. This ADR makes that contract enforceable.

## ADR-18: MVP scope — local-only, transports built in, no sync, no MCP

- **MVP = v1.0 = local-only capture + at least one transport plugin.** No GitHub sync. No MCP.
- Sync is **opt-in** and ships as a **plugin axis**, not as a core feature. Skeleton (`lib/core/sync/`) lands with the first sync plugin in v1.1+, not in MVP.
- MCP is reserved as a third plugin axis, documented in the spec, but **no code lands** until v2.0+.
- Single-user default: install the app, write QuKis, toss them, done. No accounts, no auth, no cloud round-trips required to use it.
- **Rejected**: ship-with-GitHub-sync-as-the-defining-feature (couples MVP to OAuth + rate limits + conflict UX — slows v1 by months; and overstates QuKi's actual job, which is capture-and-dispatch, not durable storage).
- **Why this matters**: prevents Phase 2 (sync) from being scoped into Phase 1; prevents transport plugins from accidentally depending on sync primitives.

## ADR-17: Sync as an opt-in plugin axis (not a core feature)

- "Sync" is **one of three plugin axes** (transports, sync, MCP) — not a feature baked into core.
- The sync API is `SyncBackend` (interface): pull-changes(since: timestamp) → list of QuKi diffs; push-changes(list) → ack/conflict.
- **GitHub is one possible sync backend**, not privileged. Others on the long list: S3-compatible buckets, WebDAV, local filesystem (Syncthing-paired folder), Dropbox, raw HTTP webhook target.
- Off by default. Users in Settings → Sync can install/enable a sync plugin.
- **Conflict resolution** is sync-plugin-specific. The GitHub sync plugin uses SHA-based conflict detection (former ADR-6 behavior); other backends choose their own.
- **Rejected**: GitHub-as-the-only-sync (locks ~95% of users out who don't want GitHub for personal scratch notes); generic "sync engine" with adapters (over-engineered — let each plugin be opinionated).

## ADR-16: CLI lives in the same repo, sharing the core library

- CLI is a **future Dart console app** under `bin/quki.dart` sharing the core library at `lib/core/` and `lib/shared/models/`.
- Core library MUST remain Flutter-free. Anything `import 'package:flutter/...'` lives under `lib/ui/` or `lib/features/`.
- CLI **not** built in MVP. This ADR locks the architectural constraint so the MVP doesn't paint into a corner.
- **Rejected**: separate `packages/quki_core` + `packages/quki_cli` melange (premature monorepo split); CLI as a feature flag in the Flutter app (UX confusion + binary size).
- Working hypothesis: `cli_design.md`.

## ADR-15: Ephemerality model — Gmail-style, no auto-delete

- QuKis are **framed** as ephemeral via UI affordances (newest-first stream, no folders, no tagging) but **persisted forever** locally by default.
- Search exists for recall but is not promoted to a primary organization tool.
- A tossed QuKi is **copied**, not moved — the local QuKi remains in the stream.
- User-initiated delete is the only deletion mechanism. No auto-archive, no expire-after-N-days in MVP.
- **Rejected**: hard auto-delete after N days (data loss surprise); explicit archive folder (folders are vault behavior — ADR-15 forbids it); soft delete that hides from stream but keeps DB row (already covered by ADR-5 mechanically; the UX-level intent is "deleted means gone from the user's mental model").
- **Why**: the friction of organising is what makes vaults heavy. The framing of "ephemeral but searchable" is what keeps QuKis weightless without surprising the user with data loss.

## ADR-14: Plugin architecture — three independent axes, Dart-only

- QuKi-Notes exposes **three plugin axes** with separate lifecycles and interfaces:
  - **Transports** (a.k.a. **QuKi-Tosses**): take (text, [images]) → success/failure. Stateless per fire. Multiple may exist; user picks at toss time.
  - **Sync backends**: bidirectional QuKi diff transport across this user's devices. At most one active at a time per ADR-17.
  - **MCP servers**: expose QuKi-Notes state (list/read/append/toss) to AI agents via Model Context Protocol. v2.0+.
- All plugins are **Dart-only**. No JS/TS, no native bindings, no embedded interpreters. (Obsidian gets a glue **TypeScript** plugin that talks to a Dart-shaped QuKi-Notes HTTP/IPC endpoint — that glue lives in its own repo and is out of scope for QuKi-Notes core.)
- Plugin manifests + UI registration through `lib/core/transports/`, `lib/core/sync/`, `lib/core/mcp/` respectively.
- **Transport interface (MVP)** — drives Phase 2:
  ```dart
  abstract class TransportPlugin {
    String get id;
    String get displayName;
    String get description;
    Widget settingsView(WidgetRef ref);  // configuration UI

    Future<TossResult> toss({
      required String markdown,
      required List<Image> images,
      required TossContext ctx,
    });
  }

  class TossResult {
    final bool success;
    final String? message;     // user-facing detail
    final bool retryable;      // hint for UI
  }

  class TossContext {
    final DateTime firedAt;              // when toss was triggered
    final QukiMetadata quki;             // id, createdAt, modifiedAt — for templating
    final Geolocation? gps;              // null unless all GPS gates ON (ADR-19)
    final Map<String, String> userOverrides;
  }
  ```
- **`List<Image>`, not `List<Attachment>`** — deliberate. A QuKi is GFM markdown, which renders text + images. Generalising to "attachments" (PDFs, videos, archives) violates the manifesto's ephemeral/frictionless framing — a QuKi hauling a 50MB MP4 isn't a QuKi anymore. Revisit only if a concrete use case forces it.
- **`TossContext.firedAt` vs `TossContext.quki.createdAt`** — distinct on purpose. `firedAt` is when the toss button was pressed; `quki.createdAt` / `quki.modifiedAt` are properties of the QuKi itself. Transports may template either (e.g. an "append to daily log" toss uses `firedAt`; a "publish to wiki" toss may use `quki.createdAt` for backdated entries).
- **`TossContext.gps`** is opt-in at multiple gates per **ADR-19**; nullable in the type so transports must always handle absence.
- **Rejected**: a single "workflow JSON DSL" living in a repo (was the original ADR-7 framing — see deprecation notice on ADR-7); embedding a scripting language (Lua/JS) for user-authored transports (security + maintenance burden); shipping a "marketplace" UI (premature); a generic `List<Attachment>` (see images note above).

## ADR-13: Testing discipline — tests with code, regression tests for fixes

- **Tests ship with code, every PR.** No "tests come later in Phase 4" — that line is removed from the design_spec.
- **Bug fixes follow strict regression-test-first discipline**: write a failing test that reproduces the bug, commit it, then write the fix. The test stays in the suite permanently.
- Layers: unit (pure logic + services), widget (stateful UI), integration (DB + UI flows), drift migration (schema verification).
- Mock services with `mocktail`; never mock data classes or drift itself (use `NativeDatabase.memory()`).
- No coverage threshold — perverse incentive. PR review asks "where's the test?" instead.
- Flaky tests: zero tolerance. Tag and fix immediately; do not let them accumulate.
- **Rejected**: deferred testing (lets bugs land + locks in untestable architectures); coverage gates (incentivizes noise tests); mocking the database (couples tests to ORM internals).
- Full operational detail: `notes/dev/testing.md`.

## ADR-12: Theme / Logging / Privacy posture

- **Theme**: follow system (`ThemeMode.system`); ship light + dark in v1; no manual override in MVP.
- **Logging**: `package:logging`; console in debug, in-memory ring buffer in release; per-feature hierarchical loggers; sensitive data never logged.
- **Privacy**: no analytics, no crash reporting, no telemetry. Network limited to `github.com` / `api.github.com`.
- **Rejected**: Sentry/Crashlytics/Firebase (privacy posture; revisit only if distribution broadens).

## ADR-11: Rate limiting & lazy image download (sync-plugin scope)

- **Applies only when a sync plugin is active** (v1.1+). MVP has no rate-limit considerations because nothing leaves the device until the user tosses.
- GitHub sync plugin: GitHub auth limit 5,000 req/hr; throttle when `X-RateLimit-Remaining < 100`. QuKis pulled newest-first; **images lazy-fetched** on first view (row inserted with `localPath = null`).
- **Why lazy for images**: QuKi bodies are KB-sized, images can be MB each; bulk image pull would burn bandwidth + rate budget for files the user may never view.
- Per-transport rate-limit behavior is the **transport plugin's responsibility**, not core's.

## ADR-10: Cross-device timestamps on pull (sync-plugin scope)

- **Applies only when a sync plugin is active.** MVP keeps `createdAt` / `modifiedAt` purely local with sub-second precision.
- Sync plugin contract for a remote-only QuKi pulled to this device: generate fresh local UUID for `id`; capture remote-identifier (e.g. `githubPath`) verbatim in a plugin-owned field; `createdAt` = derived from remote metadata (filename date prefix + `00:00:00` local for the GitHub plugin); `modifiedAt` = pull time.
- Sub-day precision loss on cross-device round-trip is acceptable for the first sync plugin; revisit if it bites.
- **Rejected**: YAML frontmatter (commits us to non-empty file content schema and adds parsing); extra `GET /commits` per file (rate-limit cost).

## ADR-9: OAuth (deferred to sync / transport plugins)

- **No OAuth in MVP** — nothing in core needs to call an authenticated service. Local-only.
- When the GitHub sync plugin or any GitHub-flavoured transport ships, it uses **GitHub Device Flow** with `client_id` only (public client, no secret).
- Scopes for the GitHub sync plugin: `repo`, `read:user`. Transport plugins request their own minimum scope (e.g. an "append to issue" transport may need only `public_repo`).
- Common helper code (device-flow dance + `flutter_secure_storage` round-trip) lives in `lib/core/auth/` so multiple GitHub-aware plugins share it without reimplementing the flow.
- **Rejected**: PKCE-per-platform via `flutter_appauth` (platform-specific URL scheme registration; Windows + Linux support immature); raw client-secret flow (cannot keep secret in a client app).

## ADR-8: Drift migration discipline

- Integer `schemaVersion` + `MigrationStrategy.onUpgrade`.
- Schema snapshots committed under `test/db/schemas/`; verified via `drift_dev schema verify`.
- Every version bump = a migration test that runs the upgrade against the prior snapshot.
- v1 = `qukis` + `images` (Phase 1, single-device, no sync columns yet — sync columns added in the version bump that lands the first sync plugin).
- **Why**: drift migrations are manual; without a snapshot test, additive changes silently work and destructive changes silently break.
- **Superseded fragment**: earlier wording mentioned a `workflows` table (workflow-as-data). With workflow JSON dropped per ADR-14, no such table exists. Transport plugin configuration lives in plugin-owned tables/prefs, not in a global registry.

## ADR-7: Workflow target SHAs — always re-fetch  ⚠️ DEPRECATED

**Superseded by ADR-14** (transport plugins replace JSON workflow DSL) and **ADR-17** (sync is a plugin axis, not a built-in).

Original framing (workflows as JSON files in GitHub doing read-modify-write append) is gone. The behavior it described — "fetch latest SHA before each PUT to avoid 409" — is now a **per-transport-plugin implementation detail** for any GitHub-flavoured transport (e.g. an "append to daily log" toss). Plugins that need this pattern should follow it; the core app does not enforce it generically.

Retained as a historical note so future Claude doesn't think we forgot about the 409 retry pattern when implementing a GitHub-append transport.

## ADR-6: Save vs Push — separate concerns (MVP: save only)

- **Save** (local SQLite): 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks, never networks.
- **Push** (sync plugin): NOT IN MVP. When the first sync plugin lands (v1.1+), it uses the same debounce + manual button pattern: 2s idle + foreground + manual sync only; periodic/lifecycle saves do **not** trigger push.
- **Toss** (transport): user-initiated, never automatic. Pressing a QuKi-Toss button is the only way a QuKi leaves the device. No auto-toss in MVP.
- **Why**: protects against long-typing-run data loss without networking. Max unsaved window ≈ 30s. Sync is a separate, deferred axis (ADR-17).

## ADR-5: Deletion model — Recently Deleted with user-configurable retention

- `qukis.deletedAt` nullable column. Set on user delete; row hidden from main QuKis list queries immediately.
- **Recently Deleted screen**: shows soft-deleted QuKis newest-first for the retention period. This is **data recovery**, not organization — no sort, filter, or filing within it.
  - Tap → restore (clears `deletedAt`; QuKi returns to top of QuKis list).
  - Swipe → permanent delete (hard-delete immediately; modal confirmation dialog).
- **Retention period**: user-configurable in Settings (default TBD — 7 days is a reasonable starting point; 24h is too short for a fat-finger recovery scenario). Background sweep hard-deletes rows + cascades to images after the retention period expires.
- **Post-MVP (sync active)**: soft-delete + queue for push; on successful remote DELETE → hard-delete local row + cascade to images. 404 = success.
- **Why**: 24h was too short for the "fat-fingered an important note and didn't notice until later" scenario. Making retention configurable respects that different users have different recovery windows. The Recently Deleted screen is a safety net, not a filing feature — its design must resist feature creep toward vault-like behavior.
- **Rejected**: auto-expire only with no recovery UI (too easy to lose important notes permanently); archive folder (organization feature — violates manifesto).

## ADR-4: Image storage — separate binary files

- Binary files in `<app docs>/images/{filename}` on disk; tracked in `images` table.
- In-QuKi markdown reference: `![](../images/{filename})` — kept relative so the markdown remains portable into a tossed destination (the transport rewrites paths as needed).
- Filename: `YYYY-MM-DD-{uuid8}.{ext}`.
- Cascade delete on QuKi delete.
- When a sync plugin is active: push image before referencing QuKi (avoids broken-link window); images have their own sync state.
- **Rejected**: base64-embed in markdown (file bloat, editor performance, unreadable when tossed to GitHub); threshold hybrid (complexity not worth MVP).

## ADR-3: QuKi IDs & filenames — UUID v4 + 8-hex suffix

- QuKi `id` = UUID v4 (`uuid` package).
- **MVP**: no on-disk markdown file is produced by the app. QuKi body lives in SQLite. The filename pattern below only matters when a transport or sync plugin needs a stable path.
- Transport/sync-plugin-derived filename: `YYYY-MM-DD-{uuid8}.md`, deterministic from `createdAt` + `id` on the originating device. Once chosen, captured in a plugin-owned field and never recomputed.
- **Rejected**: `YYYY-MM-DD-NNN.md` (offline-device collisions; requires GET-before-write to assign NNN); `YYYY-MM-DDTHHMMSS.md` (clock-skew collisions).
- 2^32 collision space per day = effectively zero collision risk without coordination.

## ADR-2: Token storage — `flutter_secure_storage` for any plugin secret

- Any plugin that needs to hold a secret (OAuth token, API key, signed JWT) uses `flutter_secure_storage` namespaced by plugin id (e.g. `quki.transports.github_daily_log.token`).
- All other settings stay in `shared_preferences` (plaintext is fine for non-secrets).
- **Why**: a `repo`-scope GitHub token = read/write all user repos; plaintext on Android (`/data/data/.../shared_prefs/*.xml`) or Windows (`%APPDATA%`) is an unacceptable threat surface for ~zero implementation cost.
- Core enforces no API-level distinction; convention is plugin authors use `flutter_secure_storage` for anything that would be embarrassing in a screenshot.

## ADR-1: State management — Riverpod (code-gen)

- `riverpod` + `riverpod_generator` with `@riverpod` annotation throughout.
- No global singletons, no manual `InheritedWidget`, no `setState` outside trivial widget-local state.
- Provider lives next to the feature it serves; cross-cutting providers live in `core/`.
- **Rejected**: Bloc (more ceremony than warranted for solo project); plain `provider` (Riverpod is the maintained successor); manual DI (loses testability and reactive streams).
