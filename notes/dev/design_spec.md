# QuKi-Notes — Design Spec

> **Read the manifesto first.** `notes/dev/manifesto.md` is the normative source for what QuKi-Notes is and is not. This spec is implementation guidance subordinate to that document.

---

## TL;DR

QuKi-Notes is a **capture-and-dispatch** app:

- **Capture**: open the app → blank editor, cursor ready. Type, paste images, hit back. Done.
- **Dispatch (toss)**: when you want a QuKi to go somewhere, fire a transport plugin (a "QuKi-Toss") at it. The QuKi is delivered; the local copy stays in the stream.
- **History**: the stream surfaces newest-first. Older QuKis age off the top but stay searchable. Nothing auto-deletes.

Single-device, local-only in MVP. Sync is a deferred plugin axis. MCP is reserved for v2.

---

## Vocabulary

| Term            | Meaning                                                                  |
| --------------- | ------------------------------------------------------------------------ |
| **QuKi**        | A single ephemeral note. Plural: **QuKis**.                              |
| **QuKi-Notes**  | The application.                                                         |
| **QuKi-Toss**   | A transport plugin (user-facing). The "toss" action verb fires one.      |
| **Stream**      | The newest-first list view. Not a "library", "inbox", or "documents".    |
| **Toss**        | Verb: fire a transport. Object: optionally "a toss to *daily-log*".      |

Do **not** use: vault, library, document, file, note (in UI; the entity is QuKi), workflow (deprecated internal term), inbox.

---

## Target Platforms

Priority order (single Flutter codebase across all):

1. **Android** — primary daily-driver target. Pixel 6 Pro is the dev device.
2. **Windows** — desktop companion.
3. **Linux** — third active target. Flutter Linux desktop is supported; we accept risk and track quality issues as OQs.
4. **iPadOS / iOS / macOS** — deferred. Codebase compiles for them; CI does not build them (macOS GitHub Actions runner cost).

Linux note: `flutter_secure_storage` on Linux uses `libsecret` (gnome-keyring / KWallet). On headless/server Linux this would fail, but our user-facing target is desktop Linux with a keyring daemon present.

---

## Architecture: Three Plugin Axes

```
  ┌────────────────────────────────────────────────────────────┐
  │                       QuKi-Notes Core                      │
  │                                                            │
  │   Editor   ──►   Stream   ──►   SQLite (drift)             │
  │                     │                                      │
  │                     ▼                                      │
  │                Plugin Registry                             │
  │              /       │        \                            │
  │       Transports    Sync       MCP                         │
  │       (MVP: ≥1)   (v1.1+)    (v2.0+)                       │
  └────────────────────────────────────────────────────────────┘
```

Core owns: editor, stream, persistence, settings, plugin lifecycle.
Plugins own: dispatching, syncing, exposing-to-agents.

All plugins are **Dart-only**. (Obsidian glue, if/when built, is a TS plugin in its own repo talking to a Dart-shaped IPC endpoint exposed by QuKi-Notes. Out of scope here.)

### Transport plugin contract (ADR-14)

```dart
abstract class TransportPlugin {
  String get id;
  String get displayName;
  String get description;
  Widget settingsView(WidgetRef ref);              // for Settings → Tosses

  Future<TossResult> toss({
    required String markdown,
    required List<Image> images,
    required TossContext ctx,
  });
}

class TossResult {
  final bool success;
  final String? message;       // user-facing detail
  final bool retryable;        // hint for UI
}

class TossContext {
  final DateTime firedAt;              // when toss button was pressed
  final QukiMetadata quki;             // id, createdAt, modifiedAt — for templating
  final Geolocation? gps;              // null unless all GPS gates ON (ADR-19)
  final Map<String, String> userOverrides; // free-form per-fire overrides
}

class QukiMetadata {
  final String id;
  final DateTime createdAt;
  final DateTime modifiedAt;
}

class Geolocation {
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final DateTime capturedAt;
}
```

**Key intentional constraints:**

- **`List<Image>`, not `List<Attachment>`** — a QuKi is GFM markdown which renders text + images. We do not generalise to arbitrary attachments (PDFs, videos, archives); see ADR-14 rationale. If a future use case demands it, we revisit.
- **`firedAt` vs `quki.createdAt`** — distinct on purpose. Transports may template either depending on intent (a daily-log toss uses `firedAt`; a wiki-publish toss may use `quki.createdAt`).
- **`gps` is nullable**. Transports must handle absence — see Privacy & Permissions below and ADR-19 for the opt-in gates.

Tosses are stateless **per fire** — they do not persist history beyond what the plugin chooses to store in its own settings.

### Sync plugin contract (deferred, ADR-17)

```dart
abstract class SyncBackend {
  Future<List<QukiDiff>> pull({DateTime? since});
  Future<PushResult> push(List<QukiDiff> local);
}
```

`SyncBackend` lands when the first sync plugin lands. GitHub is one possible implementation, not privileged.

### MCP plugin contract (reserved, v2.0+)

Not designed in detail. Architectural intent: an embedded MCP server inside the app advertising the same QuKi-Notes operations (list, read, search, append, toss) over the Model Context Protocol so external AI agents can use QuKi-Notes as a context store / dispatcher. Re-evaluate after v1.x stabilises.

---

## Core Features (MVP = v1.0)

### 1. Capture (Editor)

- App opens to a blank QuKi. Cursor in the body. No "title", no "untitled note", no template.
- Markdown WYSIWYG via `super_editor` (fallback: `appflowy_editor` — OQ-1 covers GFM round-trip fidelity).
- Bottom formatting toolbar: bold, italic, strikethrough, lists, code blocks, links, image.
- Image paste from clipboard via `super_clipboard`. Image share-in via Android share sheet (Phase 3).
- Auto-save: 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks, never networks.
- Back/done returns to the stream.

**Editor capabilities — built-in vs we-wire-it-up:**

| Capability                                  | Source                                       |
| ------------------------------------------- | -------------------------------------------- |
| Text selection, cursor, caret               | `super_editor` (built-in)                    |
| Copy / cut / paste / select-all (text)      | `super_editor` (standard keyboard + context menu — built-in) |
| Undo / redo                                 | `super_editor` (built-in)                    |
| Image paste from clipboard                  | `super_clipboard` + custom paste handler we write in Phase 1 (covers OQ-2) |
| Drag-and-drop image onto editor (desktop)   | Verify in Phase 3 (likely free, may need wiring) |
| Formatting toolbar buttons → markdown       | We wire — Phase 1 |
| Markdown ↔ editor doc round-trip            | `super_editor` markdown serializer, gaps tracked in OQ-1 |
| Spellcheck                                  | Platform-native (OS-provided) — verified per-platform in Phase 3 |

### 2. Stream

A newest-first list of QuKis. The temporal queue, not a filing cabinet.

- Each row: truncated first non-empty line (~50–100 chars) + relative timestamp.
- Tap → opens the QuKi in the editor.
- Swipe → delete (with brief undo affordance).
- Top-right: **+ New** opens a blank QuKi.
- Search field: live filter on body text. Search is for recall, not organisation.
- **No folders, no tags, no pinning, no archive.** Period.

### 3. QuKi-Toss (Transport)

In the editor, a "Toss" button (top-right or in the formatting toolbar overflow) opens a sheet listing configured transports. User picks one. App fires `toss()`. UI shows result (success / failure with retry).

- After a successful toss, the local QuKi remains in the stream untouched. Toss copies, never moves.
- At least one built-in transport ships with v1.0. Candidate set (decision deferred — OQ-NEW-1):
  - Clipboard (copy markdown body to system clipboard)
  - Share sheet (`share_plus` — hand the markdown to native share)
  - Append-to-GitHub-file (a specific repo + path; appends with optional timestamp/GPS prefix)

### 4. Settings

- Theme: follow system (ADR-12). No manual override in v1.
- Tosses (transports): list installed plugins, configure each via its `settingsView`.
- Sync: empty in MVP ("No sync backends installed" placeholder; copy hints at v1.1+).
- **Privacy**: per-capability opt-in toggles (GPS first; camera/mic/etc. as transports require). All default OFF. See Privacy & Permissions below.
- About: version, link to docs, link to manifesto, no telemetry disclosure.

### 5. Privacy & Permissions (ADR-19)

Device-backed enrichments (GPS today; camera/mic/contacts later if transports demand) follow a **three-gate opt-in** model. All three must be ON before the OS-level permission dialog appears or the field appears in `TossContext`:

1. **Device capability** — if the platform doesn't have the hardware (e.g. GPS on a desktop tower), the capability is invisible. No toggles, no toasts, no "feature unavailable" banners. The setting just doesn't exist.
2. **App-wide Privacy setting** — `Settings → Privacy` shows one toggle per supported capability. Default **OFF** for every one. Onboarding does NOT ask. The user discovers these settings if/when they install a transport that wants the capability.
3. **Per-transport setting** — transports that want a capability declare it in their `settingsView` with a clear opt-in. Disabled by default per-install.

**Behavioural rules:**

- Capture is **never** gated by a permission dialog. Tapping the app icon takes you to a blank QuKi. Always.
- The OS permission dialog only appears at the **first fire** of a transport that needs the capability after all three gates are ON.
- If the app-wide toggle is OFF but a transport asks for the capability: transport's `settingsView` displays a hint ("GPS is disabled in app Privacy settings"); the transport still fires, just without the field.
- OS-level permission revocation = capability gate OFF. Graceful degradation, no nagging dialog on next launch.

**MVP scope:** only GPS is wired (because at least one candidate first-toss might want geotagging — OQ-NEW-1). Camera/mic/etc. land if and when a transport needs them.

### 6. What's NOT in MVP

- No accounts, no auth (until a plugin needs one).
- No sync, no GitHub OAuth, no remote storage.
- No JSON workflow DSL, no workflow editor (transports are code, not data — ADR-14).
- No MCP server.
- No CLI.
- No backup/export beyond the toss mechanism itself.

---

## UI Shapes

### Main screen (editor)

```
┌──────────────────────────────┐
│ [<- Stream]         [Toss ▼] │
├──────────────────────────────┤
│                              │
│  [Blank QuKi]                │
│  cursor here                 │
│                              │
│                              │
├──────────────────────────────┤
│ [B] [I] [~] [•] [1.] [</>]   │
│ [Link] [Image]  [⋯]          │
└──────────────────────────────┘
```

### Stream

```
┌──────────────────────────────┐
│ QuKis              [+ New]   │
│ [search...                 ] │
├──────────────────────────────┤
│ 5 min ago — I went to the    │
│ 1 hour ago — Meeting notes   │
│ Yesterday — Grocery list:    │
│ May 24 — Project ideas for   │
└──────────────────────────────┘
```

### Toss sheet

```
┌──────────────────────────────┐
│ Toss this QuKi to...         │
├──────────────────────────────┤
│ ● Clipboard                  │
│ ● Daily Log (GitHub)         │
│ ● Share sheet                │
│                              │
│ Manage tosses in Settings    │
└──────────────────────────────┘
```

---

## Technical Architecture

### Tech Stack

- **Framework**: Flutter (Dart) — single codebase, Android + Windows + Linux active.
- **State / DI**: `riverpod` + `riverpod_generator` (`@riverpod` annotation). ADR-1.
- **Editor**: `super_editor` (WYSIWYG, full-featured) — fallback: `appflowy_editor` (OQ-1).
- **Markdown flavor**: GFM (GitHub Flavored Markdown).
- **Local storage**: `drift` (type-safe SQLite ORM).
- **Image clipboard**: `super_clipboard`.
- **Share-in**: `receive_sharing_intent` (Android; Windows/Linux equivalents TBD).
- **Share-out / toss-to-share-sheet**: `share_plus`.
- **GPS** (per-toss opt-in only): `geolocator` + `geocoding` for reverse-geocoded address strings (platform-native, no API key).
- **Secrets** (plugin-owned): `flutter_secure_storage`. ADR-2.
- **Settings** (non-secret): `shared_preferences`.
- **HTTP** (for any transport that needs it): `dio`.
- **OAuth helper** (when first plugin needs it): `dio` + `url_launcher` for GitHub Device Flow. ADR-9.
- **IDs**: `uuid` (v4).
- **Paths**: `path_provider`.
- **Logging**: `package:logging`. ADR-12.

### Riverpod conventions

- All app state through providers — no global singletons, no manual `InheritedWidget`, no `setState` outside trivial widget-local state.
- Code-gen `@riverpod` everywhere; do not hand-write `Provider<T>(...)`.
- Providers live next to the feature they belong to (`features/editor/editor_controller.dart`).
- Cross-cutting providers live in `core/` next to the service they own.
- Widgets that read providers extend `ConsumerWidget` or use `Consumer`.

| Flavor             | Used for                                                                          |
| ------------------ | --------------------------------------------------------------------------------- |
| `Provider`         | Stateless services: `AppDatabase`, `TransportRegistry`                            |
| `StreamProvider`   | `drift` queries: stream view, single QuKi watch                                   |
| `FutureProvider`   | One-shot async: plugin discovery, asset loads                                     |
| `NotifierProvider` | Stateful controllers: `EditorController` (auto-save, formatting), `TossController` |
| `StateProvider`    | Trivial mutable values: current QuKi ID, search query                             |

### Application flow

**First launch:**
1. Skip onboarding entirely — drop straight into a blank QuKi. (No "Connect GitHub" prompt; that was the old framing.)
2. A subtle Settings entry surfaces tosses + future sync.

**Subsequent launches:**
1. Honour `launch_behaviour` setting: blank QuKi (default) or stream view.

**No auth state to restore in MVP.** When a plugin that needs auth is installed (v1.1+), token refresh happens lazily on its next operation.

### Save semantics (ADR-6)

- **Save** (local SQLite): 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks the UI.
- **Toss** (transport): user-initiated. Pressing the toss button is the only path; no auto-toss.
- **Push** (sync, when sync exists): same debounce shape as save, but only triggers from foreground + manual sync button, never from periodic/lifecycle saves.

### Drift schema (v1, MVP)

```dart
class Qukis extends Table {
  TextColumn get id => text()();                       // UUID v4
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override Set<Column> get primaryKey => {id};
}

class Images extends Table {
  TextColumn get id => text()();                       // UUID v4
  TextColumn get qukiId => text().references(Qukis, #id)();
  TextColumn get filename => text()();                 // YYYY-MM-DD-{uuid8}.ext
  TextColumn get localPath => text().nullable()();
  IntColumn get bytes => integer().nullable()();

  @override Set<Column> get primaryKey => {id};
}
```

Sync columns (e.g. `syncStatus`, `remoteIdentifier`, `etag`) are **not** added in v1. They land in the schema bump when the first sync plugin ships.

Migration discipline per ADR-8: every `schemaVersion` bump ships a migration test against the prior snapshot under `test/db/schemas/`.

### Image handling (ADR-4)

- On paste / share-in: copy bytes to `<app docs>/images/YYYY-MM-DD-{uuid8}.{ext}`; insert `Images` row; reference in QuKi markdown as `![](../images/{filename})`.
- The `../images/` prefix keeps the markdown portable into a tossed destination (transports may rewrite to whatever path makes sense at the destination).
- Cascade delete on QuKi delete.
- No base64-embed, ever (file bloat + editor perf + unreadable when tossed).

### Deletion (ADR-5)

- User deletes a QuKi from the stream → set `deletedAt`. Row hidden from queries immediately.
- Background sweep at 24h hard-deletes soft-deleted rows + cascades to images.
- When a sync plugin is active: replace the 24h sweep with sync-aware behaviour (queue remote DELETE; hard-delete on ack).

### Logging & privacy (ADR-12)

- `package:logging` with hierarchical per-feature loggers (`quki.editor`, `quki.transport.github_daily_log`, etc.).
- Debug: console handler.
- Release: in-memory ring buffer (last ~500 entries) accessible from Settings → About → Logs (for user-driven bug reports).
- **Never** log: OAuth tokens, plugin secrets, full QuKi bodies.
- **No** analytics, **no** crash reporting, **no** telemetry SDK. Network traffic is whatever individual plugins make; core is offline.

---

## Project Structure

```
quki_notes/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/                  ← Flutter-free except where noted
│   │   ├── database/          ← drift, pure Dart
│   │   ├── transports/        ← plugin loader + base interfaces, pure Dart
│   │   ├── auth/              ← Device Flow helper (lazy-init by plugins)
│   │   └── settings/          ← shared_prefs wrapper
│   ├── features/              ← Flutter UI per feature
│   │   ├── editor/
│   │   ├── stream/
│   │   ├── onboarding/        ← stub in MVP (drops straight into editor)
│   │   └── settings/
│   ├── ui/                    ← cross-cutting widgets, theme
│   └── shared/
│       └── models/            ← pure Dart data classes (CLI-safe)
├── bin/                       ← future: quki.dart (CLI entry point)
├── android/
├── windows/
├── linux/
├── ios/                       ← scaffold present; not actively built
├── macos/                     ← scaffold present; not actively built
├── test/
│   ├── db/
│   │   └── schemas/           ← drift schema snapshots
│   ├── core/
│   ├── features/
│   └── widget/
├── docs/                      ← VitePress source
├── notes/dev/                 ← this folder (planning, ADRs, manifesto)
├── .github/
│   ├── workflows/             ← ci, build-android, build-windows, build-linux, build-ios (stub), docs, release-please
│   └── release-please.yml
├── pubspec.yaml
├── justfile
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .editorconfig
```

**`lib/core/` and `lib/shared/models/` must remain Flutter-free** per ADR-16 to keep the CLI option open. Flutter imports go in `lib/ui/`, `lib/features/`, `lib/app.dart`, `lib/main.dart`.

---

## Development Phases

| Phase | Goal                                                                   | Status         |
| ----- | ---------------------------------------------------------------------- | -------------- |
| 0     | Bootstrap scaffold (project, CI, docs)                                 | Complete       |
| 1     | Local QuKi capture on Android — editor, stream, drift, auto-save       | Complete (v0.3.0) |
| 2     | Transport plugin loader + built-in QuKi-Tosses + Settings → Tosses     | Complete (v0.5.0) |
| 3     | Polish + share-in + Windows + Linux desktop ports                      | Not started    |
| 4     | Sync plugin axis (`core/sync/`) + first sync backend (probably GitHub) | v1.1+       |
| 5     | iPadOS / iOS / macOS builds (CI wiring + device QA)                    | Deferred    |
| 6     | MCP plugin axis                                                        | v2.0+       |

### Phase 0 — Bootstrap

See `notes/dev/bootstrap.md`. One PR, scaffold only, no features.

### Phase 1 — Local QuKi capture ✓ Complete (v0.3.0)

Sub-PRs completed in order:

1. **Drift schema v1**: `qukis` + `images` tables + repository providers + migration test scaffold. ✓ Complete (merged)
2. **Editor screen**: blank QuKi on launch, `super_editor`, formatting toolbar (no image button yet). ✓ Complete (merged)
3. **Stream screen**: list view with search; tap-to-edit; swipe-to-delete with undo. ✓ Complete (merged)
4. **Image paste**: `super_clipboard` integration; on-disk image store; markdown rewrite; image rendering in `super_editor`. ⛔ Blocked — `super_clipboard`/CargoKit archived 2026-03-26; permanently deferred until `super_native_extensions` migrates away from CargoKit.
5. **Auto-save controller**: ADR-6 save semantics (2s debounce + 30s periodic + lifecycle hooks); ADR-20 save-on-leave bridge removed. ✓ Complete (merged, v0.3.0)
6. **Settings stub**: theme indicator (system), about page with version, `package_info_plus` for version string. ✓ Complete (merged, v0.4.0)

### Phase 2 — Transports ✓ Complete (v0.5.0)

Delivered as a single PR:

1. **Transport registry + plugin interface**: `lib/core/transports/`; compile-time built-in registry (OQ-NEW-2 resolved — no dynamic loading in v1); ADR-14 contract. ADR-21 documents the Flutter-import exception for `settingsView()`.
2. **ClipboardToss**: copies markdown body to system clipboard. Proves loader + toss-button UX with zero network involvement.
3. **ShareSheetToss**: opens native Android share sheet via `share_plus`. Second built-in toss shipped in the same PR.
4. **Toss UI**: toss button in editor → `TossPickerSheet` bottom sheet → success/failure snackbar; retry offered on retryable failures.
5. **Settings → Tosses**: `SwitchListTile` per plugin; disabled plugins hidden from toss picker. `TransportSettingsNotifier` persists enabled state via `shared_preferences`.

### Phase 3 — Polish + Windows + Linux

Sub-tasks in priority order:

1. **Android share-in** — receive content shared from other Android apps via `receive_sharing_intent`. ✓ Complete (merged). Text only; multi-part shares joined with `\n\n`; cold-start and warm-start both handled. Images deferred (CargoKit still blocked).
   - Desktop issue resolved: `Platform.isAndroid` guard added to `lib/features/share_in/share_handler.dart` — no-ops cleanly on Windows/Linux. ✓ Complete (merged).
2. **Windows + Linux CI** — verify `build-windows.yml` and `build-linux.yml` produce working artifacts; OQ-NEW-3 resolved (tarball). ✓ Complete (merged).
3. **Desktop keyboard shortcuts + window-state persistence** — keyboard shortcuts for common actions; remember window size/position across restarts.
4. **Stream performance** — lazy loading / pagination for large QuKi counts. Defer until a real threshold is hit.
5. **Onboarding** — still drops straight to editor; first-launch coachmarks at most, only if user testing reveals a need.

#### Share-in: behavior spec

- **Trigger**: another app invokes Android share and the user selects QuKi-Notes.
- **Cold start** (app not running): app launches directly into a new `EditorScreen` with `initialBody` set to the joined shared text.
- **Warm start** (app already open): a new `EditorScreen` is pushed on top of the current screen with `initialBody` set to the joined shared text.
- **Multi-part shares**: all `SharedMediaType.text` items from the intent are joined with `\n\n`. Neither text-only nor URL-only items are stripped — the user sees exactly what was shared and can edit before saving.
- **Auto-save**: shares flow through the same `EditorScreen(initialBody:)` → `AutoSaveController` path as normal QuKis. No special save behavior.
- **Images**: not handled in Phase 3. If an intent includes only images (no text), ignore silently — do not open the editor with empty body.
- **Scope**: Android only. Windows/Linux share-in is Phase 3 stretch at earliest; no platform channel work in this PR.

### Phase 4+ — Sync, iOS, MCP (post-MVP)

Designed-in via the plugin axes. Not specified in detail in this v1 spec.

---

## Local Development Tasks (`just` recipes)

```just
default:
    @just --list

android:
    flutter run -d android
windows:
    flutter run -d windows
linux:
    flutter run -d linux

test:
    flutter test

lint:
    flutter analyze
    dart format --output=none --set-exit-if-changed lib/ test/

gen:
    dart run build_runner build --delete-conflicting-outputs

build-android-debug:
    flutter build apk --debug
build-android-release:
    flutter build apk --release
build-windows:
    flutter build windows --release
build-linux:
    flutter build linux --release

docs:
    cd docs && npm run dev
```

---

## CI / Release

- **`ci.yml`** — every PR: `flutter analyze`, `dart format` check, `flutter test`. Runner: `ubuntu-latest`.
- **`build-android.yml`** — tag `v*`: signed APK + AAB attached to GitHub Release.
- **`build-windows.yml`** — tag `v*`: zipped Windows release build attached.
- **`build-linux.yml`** — tag `v*`: tarball / AppImage attached. (Format TBD at Phase 3 — recorded as OQ-NEW-3.)
- **`build-ios.yml`** — stub, `workflow_dispatch` only, deferred per ADR/CLAUDE.md.
- **`docs.yml`** — push to `main` with paths filter on `docs/**`: VitePress build → GitHub Pages.
- **`release-please.yml`** — `release-type: dart`, `package-name: quki_notes`. Opens / maintains a Release PR as conventional commits accumulate. Merging the Release PR creates the tag → fires build workflows.

---

## Testing Strategy

See `notes/dev/testing.md` for the full doctrine.

Headlines:
- Tests ship **with** the code, every PR. Not deferred to a "polish phase".
- Bug fixes follow regression-test-first: failing test committed first, then the fix.
- Layers: unit (pure Dart logic + services), widget (`super_editor` smoke + toolbar), integration (drift + UI flow), drift migration (per version bump, ADR-8).
- Mock services with `mocktail`. Never mock data classes or drift itself (`NativeDatabase.memory()`).
- No coverage gates.

---

## Open Questions

Tracked in `notes/dev/open_questions.md`. Snapshot of what's outstanding at spec time:

- OQ-1: `super_editor` ↔ GFM round-trip fidelity.
- OQ-2: `super_editor` image node integration.
- OQ-3: GitHub OAuth `client_id` distribution (deferred to first plugin that needs OAuth).
- OQ-4: Initial-sync progress UX (deferred to first sync plugin).
- OQ-NEW-1: Which built-in QuKi-Toss ships first?
- OQ-NEW-2: Plugin discovery model — built-in registry only in v1, or pubspec-declared optional packages?
- OQ-NEW-3: Linux distribution format (AppImage vs tarball vs Flatpak vs Snap).
- OQ-NEW-4: Linux + `flutter_secure_storage` keyring availability matrix.

---

## References

- `notes/dev/manifesto.md` — normative philosophy + tonality
- `notes/dev/decisions.md` — ADR-lite log of every locked decision
- `notes/dev/dependencies.md` — approved packages by phase
- `notes/dev/open_questions.md` — unresolved items
- `notes/dev/bootstrap.md` — Phase 0 task list (one-shot)
- `notes/dev/session_protocol.md` — start/end-of-session checklist
- `notes/dev/testing.md` — testing strategy + bug-fix discipline
- `notes/dev/pr_template.md` — PR title format + body template
- `notes/dev/cli_design.md` — working hypothesis for a future CLI
- `notes/dev/dev_env_setup.md` — Scott's Windows 11 setup guide

---

**Last Updated**: 2026-06-03
