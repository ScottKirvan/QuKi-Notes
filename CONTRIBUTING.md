# Contributing to QuKi-Notes

Thank you for your interest in contributing. This document covers everything you need to get oriented before opening a PR or filing an issue.

---

## Before You Start

Read the [manifesto](notes/dev/manifesto.md) first. It is short. It defines what QuKi-Notes is and — critically — what it is not. The manifesto is normative: if a proposed change conflicts with it, it will not be accepted regardless of implementation quality.

The hard constraints, summarized:

- **No vault-like features** — no folders, no tags, no backlinks, no archive, no pinning
- **The editor is always home** — it does not have a back button; navigation depth is intentionally shallow
- **Send is user-initiated** — nothing is automatically dispatched; auto-save is separate from sending
- **Nothing auto-deletes** — ephemerality is a framing choice, not a timer
- **No telemetry, ever** — no analytics, crash reporting, or tracking of any kind; this is not deferred, it is out of scope permanently

If you want to understand *why* these constraints exist, the manifesto explains the reasoning. If you are unsure whether your idea fits, open an issue and ask before writing code.

---

## Vocabulary

Use these terms consistently in code, commit messages, issues, and PRs:

| Write | Never write |
|---|---|
| QuKi (singular), QuKis (plural) | note, document, file |
| QuKis list | stream, library, inbox |
| Send (user-facing action) | Toss (user-facing) |
| Transport | workflow, integration |
| Recently Deleted | trash, archive |
| The app | the vault |

Transport plugin code names (`ClipboardToss`, `ShareSheetToss`, `TossPickerSheet`) use "Toss" because they predate the vocabulary lock. New code should use "send" for user-facing strings and "transport" for the concept.

---

## Development Setup

**Prerequisites:**

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — stable channel
- [just](https://github.com/casey/just) task runner
- Android: Android SDK + connected device or emulator
- Windows desktop: Visual Studio 2022 Build Tools with "Desktop development with C++"

Full Windows 11 setup walkthrough: [notes/dev/dev_env_setup.md](notes/dev/dev_env_setup.md)

**Quick start:**

```sh
git clone https://github.com/ScottKirvan/QuKi-Notes.git
cd QuKi-Notes
flutter pub get
just android    # or: just windows / just linux
```

**Common tasks:**

| Command | Description |
|---|---|
| `just test` | Run the test suite |
| `just lint` | `flutter analyze` + `dart format` check |
| `just gen` | Regenerate Riverpod + Drift code after schema or provider changes |
| `just android` | Run on connected Android device |
| `just windows` | Run Windows desktop build |

Run `just gen` any time you touch a `@riverpod`-annotated provider or a Drift table / DAO.

---

## Testing

Tests ship with the code in every PR (ADR-13). For bug fixes, write a failing regression test first, then fix it. See [notes/dev/testing.md](notes/dev/testing.md) for the full test strategy.

Before pushing:

```sh
just lint && just test
```

---

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/). release-please reads every message to drive version bumps and the CHANGELOG — the scope and type both matter.

**Format:** `type(scope): description`

| Type | When to use | Version bump |
|---|---|---|
| `feat` | New user-visible behavior | Minor |
| `fix` | Bug fix | Patch |
| `fix(docs)` | Documentation change | Patch + triggers docs build |
| `refactor` | No behavior change | None |
| `test` | Adding or updating tests | None |
| `chore` | CI, build config, maintenance | None |

**Scope** is the affected area: `editor`, `stream`, `transport`, `database`, `settings`, `ci`, `docs`, etc.

**Examples:**

```
feat(editor): add WYSIWYG markdown rendering
fix(stream): guarantee undo snackbar dismissal via explicit Timer
fix(docs): add philosophy page to user guide
refactor(transport): extract toss context into separate class
test(database): add regression test for soft-delete restore
chore(ci): pin flutter-action to v2
feat!: change TransportPlugin interface — breaking
```

Breaking changes use `!` after the type and include a `BREAKING CHANGE:` footer.

---

## PR Workflow

1. Fork the repo and create a branch from `main`
2. Keep the branch focused — one logical change per PR
3. Run `just lint && just test` before pushing
4. Open a PR; CI runs automatically on every push
5. One approving review required before merge
6. Rebase-and-merge (no merge commits on `main`)

Branch naming conventions: `feat/...`, `fix/...`, `docs/...`, `chore/...`

---

## Design Documentation

Before proposing structural changes, read the relevant planning docs in `notes/dev/`:

| Document | Purpose |
|---|---|
| [manifesto.md](notes/dev/manifesto.md) | Normative philosophy — read this first |
| [design_spec.md](notes/dev/design_spec.md) | Feature spec, vocabulary, development phases |
| [decisions.md](notes/dev/decisions.md) | Architecture Decision Records (ADR-1 → ADR-23) |
| [open_questions.md](notes/dev/open_questions.md) | Active blockers and unresolved questions |
| [testing.md](notes/dev/testing.md) | Test strategy and conventions |

---

## Questions and Discussion

- **Issues**: [github.com/ScottKirvan/QuKi-Notes/issues](https://github.com/ScottKirvan/QuKi-Notes/issues)
- **Discord**: [discord.gg/TN6XJSNK5Y](https://discord.gg/TN6XJSNK5Y) — I'm `cptvideo`
- **LinkedIn**: [linkedin.com/in/scottkirvan](https://www.linkedin.com/in/scottkirvan/)
