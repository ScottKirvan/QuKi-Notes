# QuKi Notes &nbsp; [![starline](https://starlines.qoo.monster/assets/ScottKirvan/QuKi-Notes)](https://github.com/qoomon/starline)

<div align="center">

<img src="assets/media/logo.jpg" alt="QuKi Notes" width="160" />

**Open the app. Type. Done.**

Ephemeral notes captured on whatever device is at hand, dispatched wherever they need to go.

[![CI](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml/badge.svg)](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ScottKirvan/QuKi-Notes)](https://github.com/ScottKirvan/QuKi-Notes/releases/latest)
[![License: MIT](https://img.shields.io/github/license/ScottKirvan/QuKi-Notes)](LICENSE.md)
[![Flutter stable](https://img.shields.io/badge/Flutter-stable-0553B1?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-supported-3DDC84?logo=android&logoColor=white)](#platform-support)
[![Windows](https://img.shields.io/badge/Windows-supported-0078D4?logo=windows&logoColor=white)](#platform-support)
[![Linux](https://img.shields.io/badge/Linux-supported-FCC624?logo=linux&logoColor=black)](#platform-support)
[![Discord](https://img.shields.io/discord/1052011377415438346?label=discord&color=00ACD7)](https://discord.gg/TN6XJSNK5Y)

[User Docs](https://scottkirvan.github.io/QuKi-Notes/) &nbsp;·&nbsp;
[Design Spec](notes/dev/design_spec.md) &nbsp;·&nbsp;
[Report Bug](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=bug_report.md) &nbsp;·&nbsp;
[Request Feature](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=feature_request.md)

</div>

---

## What is QuKi Notes?

QuKi Notes is a capture app. You open it, type a thought (a **QuKi**), and close it. That's it.

A QuKi doesn't need a destination. Sometimes it's just something that needed somewhere to live — off your mind, available if it ever turns out to be useful. When it does need to go somewhere, there's a Send action: clipboard, Android share sheet, or any transport plugin you wire up. No vault, no folder structure, no organization ritual.

The project prioritizes **radical simplicity** in the UI (one screen, no navigation depth, no configuration required to start) and **open extensibility** in the backend — a plugin axis for transports, a reserved axis for sync, and a reserved axis for MCP integration. Read the [manifesto](notes/dev/manifesto.md) for the full philosophy.

> [!NOTE]
> **Status: v0.13.0 · Phase 3 complete.**
> Core capture, local storage, transport plugins, block-flip WYSIWYG markdown editing, and Recently Deleted are all shipped. All design docs and Claude session directives are committed to the repo — start with the [manifesto](notes/dev/manifesto.md).

---

## Features

Shipped and working in v0.9.6:

| Feature | Details |
|---|---|
| **Instant capture** | App opens to a blank editor — no title field, no setup, cursor ready |
| **Auto-save** | 2 s idle debounce + 30 s periodic + app lifecycle hooks; no save button |
| **QuKis list** | Newest-first, case-insensitive search, swipe-to-delete |
| **Recently Deleted** | Soft-deleted QuKis held until you remove them; restore or permanently delete |
| **Transport plugins** | Compile-time registry; two built-in transports |
| **Clipboard transport** | Copies full QuKi text to system clipboard; Android, Windows, Linux |
| **Share Sheet transport** | Opens the system share dialog; Android and Windows |
| **Android share-in** | Receive text shared from any other app into a new QuKi |
| **Block-flip WYSIWYG editor** | Document split into one block per line; idle blocks render via `flutter_markdown`; tap a block to edit, tap away to render |
| **Formatting toolbar** | Bold, italic, strikethrough, H1, unordered list, ordered list, task list |
| **List auto-continue** | Press Enter at the end of a list item to continue the list; Enter on an empty item exits the list |
| **Inline markdown shortcuts** | `**x**` → bold, `_x_` / `*x*` → italic, `` `x` `` → code, `- [ ] ` → task item |
| **Task checkbox tap** | Tap a rendered checkbox to toggle `[ ]` ↔ `[x]` without entering edit mode |
| **Cross-block keyboard navigation** | Arrow-up/down at block boundaries moves focus to the adjacent block |
| **Plain-text toggle** | T icon in the app bar — switch between block-flip WYSIWYG and a single plain-text field |
| **Primer High Contrast theme** | GitHub Primer Dark HC in dark mode; Primer Light HC in light mode |
| **Desktop keyboard shortcuts** | Ctrl+T (Send...), Ctrl+N (new QuKi) on Windows / Linux |
| **Window-state persistence** | Size and position remembered between sessions (Windows / Linux) |
| **Settings** | Per-transport enable/disable; theme follows system |
| **No telemetry** | No analytics, no crash reporting, no tracking — ever |

Not in this release:

- Image paste — upstream CargoKit blocker; deferred
- Sync — v1.1+ opt-in plugin axis
- iOS / macOS builds — codebase supports them; CI deferred

---

## Platform Support

| Platform | Status | Notes |
|---|---|---|
| Android | Supported | Reference device: Pixel 6 Pro |
| Windows | Supported | Window-state persistence; keyboard shortcuts |
| Linux | Supported | CI-verified; same feature set as Windows |
| iOS / iPadOS | Codebase ready | CI build deferred; not a listed release target |
| macOS | Codebase ready | CI build deferred; not a listed release target |

---

## Getting the App

Download the latest release from [**GitHub Releases**](https://github.com/ScottKirvan/QuKi-Notes/releases/latest).

| Platform | Artifact | Install |
|---|---|---|
| Android | `.apk` | Sideload directly or via `adb install` |
| Windows | `.zip` | Extract and run the bundled `.exe` |
| Linux | `.tar.gz` | Extract and run the bundled binary |

---

## Development

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — stable channel
- [just](https://github.com/casey/just) — task runner (`winget install Casey.Just`)
- **Android**: Android SDK + connected device or emulator
- **Windows desktop**: Visual Studio 2022 Build Tools with "Desktop development with C++"

Full setup walkthrough for Windows 11: [notes/dev/dev_env_setup.md](notes/dev/dev_env_setup.md)

### Quick Start

```sh
git clone https://github.com/ScottKirvan/QuKi-Notes.git
cd QuKi-Notes
flutter pub get
just android      # run on connected Android device or emulator
just windows      # run Windows desktop build
just linux        # run Linux desktop build
```

### Task Runner

All common tasks are in the [`justfile`](justfile):

| Command | Description |
|---|---|
| `just android` | Run on connected Android device (prefers physical over emulator) |
| `just windows` | Run Windows desktop build |
| `just linux` | Run Linux desktop build |
| `just test` | Run the test suite |
| `just lint` | `flutter analyze` + `dart format` check |
| `just gen` | Regenerate Riverpod code after touching `@riverpod`-annotated providers |
| `just build-android-release` | Build release APK |
| `just build-windows` | Build release Windows bundle |
| `just build-linux` | Build release Linux bundle |
| `just docs` | Start VitePress dev server for the user docs site |

### Code Generation

This project uses `build_runner` for Riverpod (`@riverpod` annotations). After touching any `@riverpod`-annotated provider, run:

```sh
just gen
```

### CI

The CI workflow (`.github/workflows/ci.yml`) runs on every PR and push to `main`:

1. `flutter analyze` — static analysis
2. `dart format --set-exit-if-changed` — format check
3. `flutter test` — test suite

Platform release builds (Android APK, Windows bundle, Linux tarball) are triggered by release-please on version tags and uploaded to the GitHub Release.

---

## Architecture

### Stack

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter / Dart | Single codebase; all active platforms |
| State / DI | `flutter_riverpod` + `riverpod_generator` | `@riverpod` code-gen throughout |
| Local storage | Individual `.md` files + `.meta/{uuid}.json` sidecars | `dart:io`; no ORM; `mtime` is the source of truth for `modifiedAt` |
| Editor | `markdown_live_editor` (monorepo package) | Block-flip WYSIWYG; `flutter_markdown` for rendering, `TextField` per block for editing; GFM-compatible storage |
| Icons | `lucide_flutter` | Migrated from Material icons in v0.8.0 |
| Desktop window | `window_manager` | Size/position persistence on Windows + Linux |
| Clipboard / share | `share_plus` | Cross-platform clipboard; Android share dialog |
| Share-in | `receive_sharing_intent` | Android only; Platform-guarded |
| Settings persistence | `shared_preferences` | Non-secret per-plugin enable/disable state |
| Versioning | release-please (`dart` type) | Conventional commits drive CHANGELOG + semver |

### Directory Layout

```
lib/
├── main.dart                    # entry point; desktop window init
├── app.dart                     # MaterialApp root; Android share-in routing
├── core/
│   ├── storage/                 # QuKiStorage (file I/O), QuKiIndex, TrashIndex, QuKiSearch
│   ├── transports/              # TransportPlugin interface + compile-time registry
│   │   └── plugins/             # ClipboardToss, ShareSheetToss
│   ├── auth/                    # Reserved — OAuth device flow (ADR-9, v1.1+)
│   ├── settings/                # shared_preferences wrapper
│   └── sync/                    # Reserved skeleton (ADR-17, v1.1+)
├── features/
│   ├── editor/                  # EditorScreen, AutoSaveController, formatting toolbar
│   ├── stream/                  # StreamScreen — QuKis list, search, swipe-delete
│   ├── recently_deleted/        # RecentlyDeletedScreen — restore or hard-delete
│   ├── settings/                # SettingsScreen
│   ├── share_in/                # Android text share-in receiver (Platform-guarded)
│   └── window/                  # Desktop window-state listener and service
└── shared/
    └── models/                  # Pure Dart data classes; Flutter-free for future CLI
```

`lib/core/` is kept Flutter-free (except `transports/`, which may use Flutter for `settingsView()`) to preserve a future CLI path — see ADR-16.

### The Three Plugin Axes

QuKi Notes is built around three extension points. Only the first is active in the current release:

| Axis | Purpose | Status |
|---|---|---|
| **Transports** | Deliver a QuKi to a destination (clipboard, share sheet, webhook, …) | Active — 2 built-in plugins |
| **Sync** | Move QuKis across a user's own devices, opt-in per backend | Reserved skeleton — v1.1+ |
| **MCP** | Expose QuKi Notes to AI agents over Model Context Protocol | Reserved — v2.0+ |

Transports are registered at compile time in `lib/core/transports/registry.dart`. The interface is `TransportPlugin` — implement `toss()` + `settingsView()` and add to the registry.



### Key Design Decisions

Architecture decisions are logged as ADRs in [notes/dev/decisions.md](notes/dev/decisions.md). Highlights:

| Decision | Choice | ADR |
|---|---|---|
| No dynamic plugin loading | Transport plugins compiled in; no runtime discovery | ADR-14 |
| `lib/core/` Flutter-free | Preserves a future CLI sharing core logic | ADR-16 |
| File-based storage | Individual `.md` files; no ORM; `mtime` is `modifiedAt` | ADR-25 |
| Soft-delete → `.trash/` | Swipe moves to `.trash/`; restore or hard-delete from Recently Deleted | ADR-5 |
| Save vs. send | Auto-save always on; send is always user-initiated | ADR-6 |
| No sync in MVP | Local-only; sync is opt-in plugin axis, not a core feature | ADR-18 |
| No telemetry, ever | Not deferred, not opt-in — permanently out of scope | ADR-12 |

---

## Contributing

### Before You Start

Read the [manifesto](notes/dev/manifesto.md) first — it is short and normative. If a proposed feature conflicts with it, the answer is no. Then read [design_spec.md](notes/dev/design_spec.md) for the current feature set, vocabulary, and phase plan.

Vocabulary that matters in code, docs, and commit messages:

| Write | Never write |
|---|---|
| QuKi / QuKis | note, document, file |
| QuKis list | stream, library, inbox |
| Send (user-facing) | Toss (user-facing) |
| Transport | workflow, integration |
| The app | the vault |

### Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). release-please reads every message to drive version bumps and the CHANGELOG:

```
feat(editor):     new user-visible behavior       → minor bump
fix(transport):   bug fix                          → patch bump
fix(docs):        documentation change             → patch bump + docs build
refactor(stream): no behavior change              → no bump
test(database):   add or fix tests                 → no bump
chore(ci):        CI / build config only           → no bump
```

All commits in a PR must follow this format before merge.

### PR Workflow

1. Fork the repo and create a branch from `main`
2. Make your changes; run `just lint && just test` before pushing
3. Open a PR — CI runs automatically on every push
4. One approving review required
5. Rebase-and-merge (no merge commits on `main`)

---

## Design Documentation

All planning documents live in `notes/dev/`. Read these before proposing structural changes:

| Document | Purpose |
|---|---|
| [manifesto.md](notes/dev/manifesto.md) | Normative philosophy — read this first |
| [design_spec.md](notes/dev/design_spec.md) | Full feature spec, vocabulary, development phases |
| [decisions.md](notes/dev/decisions.md) | Architecture Decision Records (ADR-1 → ADR-26) |
| [open_questions.md](notes/dev/open_questions.md) | Active blockers and unresolved questions |
| [dependencies.md](notes/dev/dependencies.md) | Approved packages and rationale by phase |
| [testing.md](notes/dev/testing.md) | Test strategy and conventions |
| [dev_env_setup.md](notes/dev/dev_env_setup.md) | Full development environment setup (Windows 11) |

---

## Roadmap

| Phase | Goal | Status |
|---|---|---|
| 0 | Bootstrap scaffold | Complete |
| 1 | Local QuKi capture on Android | Complete (v0.3.0) |
| 2 | Transport plugin system + built-in transports | Complete (v0.5.0) |
| 3 | Polish, share-in, desktop | Complete (v0.13.0) |
| &ensp;3.1 | Android share-in | Complete |
| &ensp;3.2 | Windows + Linux CI verification | Complete |
| &ensp;3.3 | Platform guard: share-in on desktop | Complete |
| &ensp;3.4 | Desktop keyboard shortcuts + window-state | Complete (v0.7–v0.8) |
| &ensp;3.5 | WYSIWYG markdown rendering | Complete (v0.9.1) |
| &ensp;3.6 | Primer High Contrast theme | Complete (v0.9.2) |
| &ensp;3.7 | Editor UX polish batch | Complete (v0.9.4–v0.9.5) |
| &ensp;3.8 | Storage migration: Drift → individual `.md` files | Complete (v0.9.6) |
| &ensp;3.9 | Recently Deleted screen | Complete (v0.9.6) |
| &ensp;3.10 | WYSIWYG editor rewrite (ADR-26) — all 4 stages | Complete (v0.10.0–v0.12.0) |
| &ensp;3.11 | Stream performance (lazy loading) | Deferred — threshold not hit |
| 4 | Sync plugin axis + first sync backend | v1.1+ |
| 5 | iOS / iPadOS / macOS builds | Deferred |
| 6 | MCP plugin axis | v2.0+ |

---

## License  

MIT — see [LICENSE.md](LICENSE.md).

---

## Contact

- **Issues & PRs**: [github.com/ScottKirvan/QuKi-Notes](https://github.com/ScottKirvan/QuKi-Notes)
- **Discord**: [discord.gg/TN6XJSNK5Y](https://discord.gg/TN6XJSNK5Y) — I'm `cptvideo`
- **LinkedIn**: [linkedin.com/in/scottkirvan](https://www.linkedin.com/in/scottkirvan/)
- **User Docs**: [scottkirvan.github.io/QuKi-Notes](https://scottkirvan.github.io/QuKi-Notes/)

[CHANGELOG](notes/CHANGELOG.md)


