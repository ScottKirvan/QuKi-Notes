# Dependencies

Versions track what's currently pinned in `pubspec.yaml`. Use compatible-version ranges (`^x.y.z`). `TBD` = package not yet added (lands at the phase noted in the section header).

**Rule**: do not add a new runtime dependency without first proposing an ADR in `decisions.md`. Dev-only dependencies (test, codegen) can be added inline.

## Runtime

### Core (Phase 0 / Phase 1 — required for MVP local capture)

| Package | Version | Purpose |
|---|---|---|
| `flutter` (sdk) | — | Framework |
| Dart SDK | `>=3.5.0 <4.0.0` | Language |
| `flutter_riverpod` | `^3.3.1` | State management runtime |
| `riverpod_annotation` | `^4.0.2` | `@riverpod` annotation |
| `drift` | `^2.33.0` | SQLite ORM runtime |
| `sqlite3_flutter_libs` | `^0.6.0+eol` | Bundled SQLite library |
| `path_provider` | `^2.1.5` | App documents directory |
| `uuid` | `^4.5.3` | UUID v4 generation |
| `super_editor` | TBD | WYSIWYG markdown editor — **deferred from Phase 0 pubspec** (Gradle 9 / CargoKit blocker, see Notes) |
| `super_clipboard` | TBD | Clipboard image paste — **deferred from Phase 0 pubspec** (same blocker as `super_editor`) |
| `shared_preferences` | `^2.5.5` | Non-sensitive settings |
| `logging` | `^1.3.0` | Structured logger |

### Transports (Phase 2 — for first built-in QuKi-Toss)

| Package | Version | Purpose |
|---|---|---|
| `share_plus` | TBD | Share-sheet transport (toss-to-share) |

Additional transport-specific packages (e.g. `dio`, `flutter_secure_storage`, `url_launcher` for any GitHub/HTTP transport) are added **with the plugin that needs them**, not preemptively. Authentication helper (`lib/core/auth/`) lands at the same time as the first OAuth-needing plugin.

### Share-in + GPS (Phase 3 polish)

| Package | Version | Purpose |
|---|---|---|
| `receive_sharing_intent` | `^1.8.1` | Android share-in (receive intents) |
| `geolocator` | TBD | GPS capture (per-toss opt-in) |
| `geocoding` | TBD | Platform-native reverse geocoding (no API key) |

### Sync (Phase 4+ — first sync plugin)

| Package | Version | Purpose |
|---|---|---|
| `dio` | TBD | HTTP client (if not already brought in by an earlier transport) |
| `github` | TBD | GitHub API typed responses (if GitHub is the first sync backend) |
| `flutter_secure_storage` | TBD | Token storage (if not already brought in by an earlier transport) |
| `url_launcher` | TBD | OAuth device-flow verification URI launch |

## Dev / Build

| Package | Version | Purpose |
|---|---|---|
| `build_runner` | `^2.15.0` | Code-generation runner |
| `riverpod_generator` | `^4.0.4-dev.1` | Generates providers from `@riverpod` (no stable 4.x yet; pre-release tracks `riverpod_annotation 4.0.2`) |
| `drift_dev` | `^2.33.0` | Generates drift code + schema verification |
| `flutter_lints` | `^6.0.0` | Lint rules |
| `mocktail` | `^1.0.5` | Test mocks (no codegen) |

## Notes

- **`super_editor` Phase 1.2 API** (confirmed working 2026-06-01 on Pixel 6 Pro / Flutter 3.44): `createDefaultDocumentEditor(document: MutableDocument.empty(), composer: MutableDocumentComposer())` + `SuperEditor(editor:, documentLayoutKey:, stylesheet:)`. Toolbar formatting via `CommonEditorOperations(document:, editor:, composer:, documentLayoutResolver:)` — `.toggleAttributionsOnSelection({boldAttribution})` for inline, `.convertToListItem(type, node.text)` for blocks. Cursor on Android via `SuperEditorAndroidControlsScope(controller: SuperEditorAndroidControlsController(controlsColor:), child: SuperEditor(...))` — **`androidHandleColor` is a dead field, do not use it**. Default stylesheet hardcodes `color: Colors.black`; override with `defaultStylesheet.copyWith(addRulesAfter: [StyleRule(BlockSelector.all, ...)])`. `super_keyboard` (transitive) requires `compileSdk 36`; fixed in `android/build.gradle.kts` (app) and `android/build.gradle.kts` (root subprojects override). CargoKit archived 2026-03-26 — `super_clipboard` permanently blocked on Android until super_native_extensions migrates away from CargoKit. `super_editor` itself has no CargoKit dependency and builds fine.
- **`super_editor` + `super_clipboard` Gradle 9 / CargoKit blocker** (discovered Phase 0, 2026-05-31): on Android, `super_clipboard ^0.9.1` / `super_editor ^0.3.0-dev.51` resolve `super_native_extensions 0.9.1`, which depends on `irondash_engine_context 0.5.5`. That package bundles a CargoKit `plugin.gradle` calling `Project.exec()` — removed in Gradle 9.0. Flutter 3.44.0 ships Gradle 9.1.0 and the bundled AGP requires Gradle ≥ 9.1.0, so downgrading is not an option. Older `super_editor 0.2.x` builds fail earlier (missing `namespace` field in `super_native_extensions 0.7.0` Android `build.gradle`). Both packages were removed from the Phase 0 `pubspec.yaml`. Full incident notes are in the git commit history (search for "CargoKit" or "super_clipboard"). **Status check 2026-06-02**: `irondash_engine_context` still at 0.5.5, `super_native_extensions` still at 0.9.1, `super_clipboard` still at 0.9.1 — all published ~11 months ago, none updated since CargoKit was archived 2026-03-26. Blocker remains in place. Before starting Phase 1.4 image paste work, re-check pub.dev for `irondash_engine_context > 0.5.5`; if still blocked, image paste stays deferred.
- **`super_editor` ↔ markdown round-trip** is a known open question (`open_questions.md` → OQ-1). If GFM features (task lists, tables) don't round-trip cleanly, fallback is `appflowy_editor`.
- **`super_clipboard` Windows + Linux support** — verify on each desktop target during Phase 3.
- **`flutter_secure_storage` on Linux** uses libsecret — see OQ-NEW-4 for the keyring availability problem.
- **GitHub API library** (when used): `github` package for typed response models only; actual HTTP through `dio` so we control retries, rate-limit handling, and header inspection.
- The `lib/core/` constraint (Flutter-free, ADR-16) means: packages that depend on `flutter:` material (e.g. `share_plus`, `super_clipboard`) live behind interfaces in `lib/features/` or `lib/ui/` — not directly imported from `lib/core/`.
- Do not add Firebase, Sentry, Crashlytics, Google Analytics, or any telemetry SDK. See ADR-12.
