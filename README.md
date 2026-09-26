# QuKi Notes &nbsp; [![starline](https://raw.githubusercontent.com/ScottKirvan/QuKi-Notes/refs/heads/starlines/ScottKirvan/QuKi-Notes/starline.svg)](https://github.com/qoomon/starlines)

<div align="center">

<img src="project/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png" alt="QuKi Notes" width="160" />

**Open the app. Type. Done.**

Ephemeral notes captured on whatever device is at hand, dispatched wherever they need to go.

[![CI](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml/badge.svg)](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ScottKirvan/QuKi-Notes)](https://github.com/ScottKirvan/QuKi-Notes/releases/latest)
[![License: MIT](https://img.shields.io/github/license/ScottKirvan/QuKi-Notes)](LICENSE.md)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](project)
[![Web](https://img.shields.io/badge/Web-PWA-5A0FC8?logo=googlechrome&logoColor=white)](#platform-support)
[![Android](https://img.shields.io/badge/Android-Capacitor-3DDC84?logo=android&logoColor=white)](#platform-support)
[![Windows](https://img.shields.io/badge/Windows-Electron-0078D4?logo=windows&logoColor=white)](#platform-support)
[![Linux](https://img.shields.io/badge/Linux-Electron-FCC624?logo=linux&logoColor=black)](#platform-support)
[![Discord](https://img.shields.io/discord/1052011377415438346?label=discord&color=00ACD7)](https://discord.gg/TN6XJSNK5Y)

[User Docs](https://scottkirvan.github.io/QuKi-Notes/) &nbsp;·&nbsp;
[Behavior Spec](notes/dev/BEHAVIOR_SPEC.md) &nbsp;·&nbsp;
[Report Bug](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=bug_report.md) &nbsp;·&nbsp;
[Request Feature](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=feature_request.md)

</div>

---

## What is QuKi Notes?

QuKi Notes is a scratchpad and pasteboard — a blank canvas when you open it. Type a thought, draft a message, jot a list, dump a link. Use the content right there, send it somewhere, or just let it drift into the list as newer things arrive. All three are valid outcomes.

A QuKi doesn't need a destination. Sometimes it's just something that needed somewhere to live — off your mind, available if it ever turns out to be useful. No vault, no folder structure, no organization ritual.

The project prioritizes **radical simplicity** in the UI (one screen, no navigation depth, a one-time storage choice on first launch and then cursor-ready forever after) and **open extensibility** in the backend — a real core API with a CLI and an MCP server built on it, alongside the app itself. Read the [manifesto](notes/archive/dev/manifesto.md) for the full philosophy.

QuKi Notes started as a Flutter/Dart app. It's since been rewritten as a single TypeScript codebase — CodeMirror for the editor, wrapped by Capacitor (Android) and Electron (Windows, Linux), plus an installable web app that needs no wrapper at all. One editor, one storage core, four targets.

---

## Features

| Feature | Details |
|---|---|
| **Instant capture** | App opens to a blank editor — no title field, no setup, cursor ready |
| **Auto-save** | 2 s idle debounce + 30 s periodic + app lifecycle hooks; no save button |
| **QuKis list** | Newest-first, case-insensitive full-text search, swipe-to-delete |
| **Trash** | Soft-deleted QuKis held for 30 days before automatic purge; restore or delete permanently any time |
| **Live-preview markdown editor** | The note renders as you type — headings, bold/italic/strikethrough, links, images, checkboxes, blockquotes, lists, tables and fenced code all render inline. The element the cursor is inside reveals its raw markdown source; move the cursor away and it renders again. No mode switch, no tap-to-flip. |
| **Images** | Paste an image directly into a note; also renders images referenced by a remote `http(s)://` URL |
| **Tables & code blocks** | GFM pipe tables and fenced code blocks render fully, reverting to raw source while the cursor is inside them |
| **Link tap** | Tap a rendered link to open it in the platform's default browser |
| **Checkbox tap** | Tap a rendered checkbox to toggle it without entering edit mode |
| **Formatting toolbar** | Bold, italic, strikethrough, inline code, heading (cycles normal → H1 → H2 → H3), unordered/ordered/task lists, indent/dedent |
| **List auto-continue** | Enter at the end of a list item continues the list; Enter on an empty item exits it |
| **Plain-text toggle** | Switch the entire note to a raw monospace text field for bulk edits or raw paste |
| **Storage location** | Choose a real folder on disk (Electron, and Android with all-files access) or private app storage; the web app uses the browser's own persistent origin storage |
| **Share out / share in** | Send a QuKi via the system share sheet (Android, Windows, macOS) or clipboard (Linux); receive shared text from another app directly into a new QuKi (Android) |
| **Obsidian-compatible theming** | Every colour and font is an Obsidian CSS variable name, defaulting to the GitHubDHC theme, so an Obsidian theme can restyle the whole app |
| **Installable, offline-capable web app** | The web build is a full PWA — installs to a home screen, works with no network |
| **Desktop keyboard shortcuts** | New QuKi and Send shortcuts on Windows / Linux |
| **Window-state persistence** | Size and position remembered between sessions (Windows / Linux) |
| **No telemetry** | No analytics, no crash reporting, no tracking — ever |

Not yet built:

- Sync across a user's own devices
- iOS / macOS native apps — the web app covers these platforms in the meantime
- A user-facing export/backup action (the underlying library export already exists in the core API and CLI/MCP; it isn't wired to a UI button yet)

---

## Platform Support

| Platform | Wrapper | Notes |
|---|---|---|
| Web | None — installable PWA | Works fully offline once installed; storage is the browser's own persistent origin storage |
| Android | Capacitor | Real folder storage (with all-files access) or private app storage |
| Windows | Electron | Real folder storage; window-state persistence; keyboard shortcuts |
| Linux | Electron | Same feature set as Windows |
| iOS / macOS | — | Not a current target; the web app is the interim option |

---

## Getting the App

Download the latest release from [**GitHub Releases**](https://github.com/ScottKirvan/QuKi-Notes/releases/latest), or just open the [web app](https://scottkirvan.github.io/QuKi-Notes/) directly and install it from the browser.

| Platform | Artifact | Install |
|---|---|---|
| Android | `.apk` | Sideload directly or via `adb install` |
| Windows | `.exe` | Run the installer |
| Linux | `.AppImage` | Mark executable and run |

---

## Development

### Prerequisites

- [Node.js](https://nodejs.org/) 22, with npm
- **Android**: Android Studio / SDK, JDK 17
- **Electron packaging**: no extra native toolchain needed beyond Node for `dist:win`/`dist:linux`

### Quick Start

The core storage package must be built before anything that depends on it (the web app, Electron, the CLI, and the MCP server all import from `core/dist/`):

```sh
git clone https://github.com/ScottKirvan/QuKi-Notes.git
cd QuKi-Notes/project

# core first
npm --prefix core ci
npm --prefix core run build

# then the web app
npm ci
npm run dev          # local dev server
```

### Common Commands

Run from `project/` unless noted otherwise. See each package's own `package.json` for the full list.

| Command | Description |
|---|---|
| `npm run dev` | Vite dev server for the web app |
| `npm run build` | Type-check (`tsc -b`) and build the web app |
| `npm test` | Unit tests (Vitest) |
| `npm run test:e2e` | Full Playwright end-to-end suite against a built `dist/` |
| `npm run electron:start` | Build and launch the Electron desktop app |
| `npm run capacitor:sync` | Build the web app and sync it into the Android (Capacitor) project |
| `npm --prefix core run build` | Build the storage core package |
| `npm --prefix core test` | Core package's own unit tests |
| `npm --prefix electron test` | Electron main-process unit tests |
| `npm --prefix cli test` | CLI unit tests |
| `npm --prefix mcp test` | MCP server unit tests |

For Android, after `capacitor:sync`, open `project/android/` in Android Studio, or build directly:

```sh
cd project/android
./gradlew assembleDebug
```

### CI

`.github/workflows/ci.yml` runs on every PR and push to `main`. It builds and tests each package in dependency order — `core` first (type-check, test, build), then the web `app`, `electron`, `cli`, and `mcp`, each with its own type-check and test step.

Platform release builds (Android APK, Windows installer, Linux AppImage) run from `build-android.yml` / `build-windows.yml` / `build-linux.yml`, triggered on a published GitHub Release and uploaded to it.

---

## Architecture

### Stack

| Layer | Choice | Notes |
|---|---|---|
| Language | TypeScript, strict mode | One codebase for web, Android, Windows, and Linux |
| Editor | [CodeMirror 6](https://codemirror.net/) | Custom live-preview reveal/collapse decorations over the parsed markdown syntax tree; the plain markdown source is always the canonical buffer |
| Markdown parsing | `@lezer/markdown` (GFM extension) | Via `@codemirror/lang-markdown` |
| Storage core | `quki-core` (`project/core/`) | Folder-is-the-index storage, trash, search, export — no framework dependency, shared by the app, CLI, and MCP server |
| Android wrapper | [Capacitor](https://capacitorjs.com/) | A small native Kotlin plugin handles file I/O, the all-files storage permission, and share-in; everything else is TypeScript |
| Desktop wrapper | [Electron](https://www.electronjs.org/) | Node's own `fs` backs real folder storage directly in the main process |
| Web target | [Vite](https://vitejs.dev/) + `vite-plugin-pwa` | Installable, fully offline-capable; storage is the Origin Private File System |
| Icons | [Lucide](https://lucide.dev/) | |
| Theming | Obsidian CSS variable names | Defaults to the [GitHubDHC](https://github.com/ScottKirvan/GitHubDHC) theme's values; any Obsidian theme can restyle the app |
| Versioning | [release-please](https://github.com/googleapis/release-please) | Conventional commits drive the CHANGELOG and version bumps |

### Directory Layout

```
project/
├── src/                # The web app: editor, screens, reveal engine, storage wiring
├── core/               # quki-core — storage, trash, search, export (no framework dependency)
├── electron/           # Electron main-process wrapper (Windows, Linux)
├── android/            # Capacitor's native Android project, incl. the custom Storage plugin (Kotlin)
├── cli/                # A thin CLI adapter over quki-core
├── mcp/                # A Model Context Protocol server adapter over quki-core
├── e2e/                # Playwright end-to-end tests
└── public/             # Static web assets (manifest, icons)
```

`core/` has no dependency on the web app, Electron, Capacitor, or any UI framework — the app, the CLI, and the MCP server are three separate callers over the same storage API.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow. In short:

- Read the [manifesto](notes/archive/dev/manifesto.md) first — it's short and normative.
- Use QuKi Notes' own vocabulary: **QuKi** / **QuKis**, the **QuKi editor**, the **QuKi list** — not "note," "document," "file," "stream," or "vault."
- [Conventional Commits](https://www.conventionalcommits.org/): `feat:` is reserved for genuinely new user-facing capability; bug fixes and corrections — even ones that close a tracked issue — use `fix:`.
- Branch from `main`, one concern per branch and PR.

---

## Design Documentation

Planning and specification documents live in `notes/`:

| Document | Purpose |
|---|---|
| [manifesto.md](notes/archive/dev/manifesto.md) | Normative philosophy — read this first |
| [BEHAVIOR_SPEC.md](notes/dev/BEHAVIOR_SPEC.md) | What the app does, screen by screen |
| [STORAGE_CONTRACT.md](notes/dev/STORAGE_CONTRACT.md) | The binding rules for how QuKis live on disk |
| [quki-rewrite-path.md](notes/dev/quki-rewrite-path.md) | The Flutter → TypeScript migration's own design record |
| [rewrite_TODO.md](notes/dev/rewrite_TODO.md) | Running list of open work |
| [github_issues_review.md](notes/dev/github_issues_review.md) | Cross-reference of legacy issues against the current codebase |

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
