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

**Common tasks**, run from `project/` unless noted:

| Command | Description |
|---|---|
| `npm run build` | Type-check and build the web app |
| `npm test` | Unit tests (Vitest) |
| `npm run test:e2e` | Full Playwright end-to-end suite (needs `npm run build` first) |
| `npm run electron:start` | Build and launch the Electron desktop app |
| `npm run capacitor:sync` | Build the web app and sync it into the Android project |
| `npm --prefix core test` / `npm --prefix electron test` / `npm --prefix cli test` / `npm --prefix mcp test` | Each package's own unit tests |

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
| [rewrite_TODO.md](notes/dev/rewrite_TODO.md) | Running list of open work |

Prior planning documents, architecture decision records, and issue history beyond what's listed above are not authoritative — treat them as historical narrative, not a source of truth, if you come across them.

---

## Questions and Discussion

- **Issues**: [github.com/ScottKirvan/QuKi-Notes/issues](https://github.com/ScottKirvan/QuKi-Notes/issues)
- **Discord**: [discord.gg/TN6XJSNK5Y](https://discord.gg/TN6XJSNK5Y) — I'm `cptvideo`
- **LinkedIn**: [linkedin.com/in/scottkirvan](https://www.linkedin.com/in/scottkirvan/)
