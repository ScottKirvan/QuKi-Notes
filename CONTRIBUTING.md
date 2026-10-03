# Contributing to QuKi Notes

Thank you for your interest in contributing. This document covers everything you need to get oriented before opening a PR or filing an issue.

---

## Before You Start

Read the [manifesto](notes/archive/dev/manifesto.md) first. It is short. It defines what QuKi Notes is and — critically — what it is not. The manifesto is normative: if a proposed change conflicts with it, it will not be accepted regardless of implementation quality.

The hard constraints, summarized:

- **No vault-like features** — no folders, no tags, no backlinks, no pinning
- **The editor is always home** — it has no back button; navigation depth is intentionally shallow
- **Send is user-initiated** — nothing is automatically dispatched; auto-save is separate from sending
- **No telemetry, ever** — no analytics, crash reporting, or tracking of any kind; this is not deferred, it is out of scope permanently

If you want to understand *why* these constraints exist, the manifesto explains the reasoning. If you're unsure whether your idea fits, open an issue and ask before writing code.

For anything touching files, the QuKi list, images, or the trash folder, [`STORAGE_CONTRACT.md`](notes/dev/STORAGE_CONTRACT.md) is binding — read it before proposing a change in that area. For what a screen or interaction should actually do, [`BEHAVIOR_SPEC.md`](notes/dev/BEHAVIOR_SPEC.md) is the reference.

---

## Vocabulary

Use these terms consistently in code, commit messages, issues, and PRs:

| Write | Never write |
|---|---|
| QuKi (singular), QuKis (plural) | note, document, file, item |
| The QuKi list | stream, library, inbox |
| The QuKi editor | the note screen |
| Send (user-facing action) | Toss |
| The app | the vault |

---

## Platform Support

| Platform    | Wrapper                | Notes                                                                                      |
| ----------- | ---------------------- | ------------------------------------------------------------------------------------------ |
| Web         | None — installable PWA | Works fully offline once installed; storage is the browser's own persistent origin storage |
| Android     | Capacitor              | Real folder storage (with all-files access) or private app storage                         |
| Windows     | Electron               | Real folder storage; window-state persistence; keyboard shortcuts                          |
| Linux       | Electron               | Same feature set as Windows                                                                |
| iOS / macOS | —                      | Not a current target; the web app is the interim option                                    |

---

## Development Setup

**Prerequisites:**

- [Node.js](https://nodejs.org/) 22, with npm
- Android: Android Studio / SDK, JDK 17
- No extra native toolchain is needed for Electron itself; packaging (`dist:win` / `dist:linux`) runs through `electron-builder`

**Quick start:**

```sh
git clone https://github.com/ScottKirvan/QuKi-Notes.git
cd QuKi-Notes/project

# the storage core must be built first — the app, Electron, the CLI and
# the MCP server all import from core/dist/
npm --prefix core ci
npm --prefix core run build

npm ci
npm run dev
```

**Common tasks**, run from `project/` unless noted.  See each package's own `package.json` for the full list.:

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

## Testing

Unit tests are written alongside all new code. Bug fixes require a red/green pair — a failing test that reproduces the bug, then the fix that makes it pass.

Before pushing, from `project/`:

```sh
npm test && npm run build && npm run test:e2e
```

CI (`.github/workflows/ci.yml`) runs the same checks — type-check, test, and build — across `core`, the app, `electron`, `cli`, and `mcp`, in that dependency order.

Some things genuinely can't be verified by an automated suite: keyboard-aware layout, the feel of live reveal while typing, paste-to-image, selection handles, and share targets all need a real device. Say so plainly in a PR if something falls into that category rather than claiming it from a green suite alone.

---

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). release-please reads every message to drive version bumps and the CHANGELOG.

| Type | When to use | Version bump |
|---|---|---|
| `feat` | A genuinely new user-facing capability | Minor |
| `fix` | A bug fix or behavior correction — **including one that closes a tracked issue** | Patch |
| `docs` | Documentation only | Patch |
| `refactor` | No behavior change | None |
| `test` | Adding or updating tests only | None |
| `chore` | CI, build config, maintenance | None |

`feat` is reserved for capability that didn't exist before. A correction to existing, already-shipped behavior is `fix`, even if it happens to close a feature request.

Breaking changes use `!` after the type (`feat!:`) and include a `BREAKING CHANGE:` footer.

No AI attribution of any kind — no "Generated with," `Co-Authored-By`, or similar — in commit messages, PR bodies, or issue text.

---

## PR Workflow

1. Fork the repo and create a branch from `main`
2. Keep the branch focused — one concern per branch and PR
3. Run the full check from [Testing](#testing) before pushing
4. Open a PR — fill in the template's checklist, including on-device testing steps for anything user-facing that a device is needed to confirm
5. One approving review required before merge
6. Rebase-and-merge (no merge commits on `main`)

---

## Design Documentation

Read the relevant document in `notes/` before proposing a structural change:

| Document | Purpose |
|---|---|
| [manifesto.md](notes/archive/dev/manifesto.md) | Normative philosophy — read this first |
| [BEHAVIOR_SPEC.md](notes/dev/BEHAVIOR_SPEC.md) | What a screen or interaction does |
| [STORAGE_CONTRACT.md](notes/dev/STORAGE_CONTRACT.md) | Binding rules for QuKis, images, and trash on disk |
| [quki-rewrite-path.md](notes/dev/quki-rewrite-path.md) | The Flutter → TypeScript migration's design record |
| [GitHub issues](https://github.com/ScottKirvan/QuKi-Notes/issues) | Open work |

Prior planning documents, architecture decision records, and issue history beyond what's listed above are not authoritative — treat them as historical narrative, not a source of truth, if you come across them.

---

## Questions and Discussion

- **Issues**: [github.com/ScottKirvan/QuKi-Notes/issues](https://github.com/ScottKirvan/QuKi-Notes/issues)
- **Discord**: [discord.gg/TN6XJSNK5Y](https://discord.gg/TN6XJSNK5Y) — I'm `cptvideo`
- **LinkedIn**: [linkedin.com/in/scottkirvan](https://www.linkedin.com/in/scottkirvan/)
