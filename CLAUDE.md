# QuKi-Notes — Claude Context

## What This Is

A personal **capture-and-dispatch** app: ephemeral notes (**QuKis**) captured frictionlessly on whichever device is at hand, then **tossed** to a destination via a transport plugin. No vault. No organisation. No backup ritual.

**Philosophy first.** Read `notes/dev/manifesto.md` before anything else. The manifesto is normative; this file and the spec must stay consistent with it.

**Design phase: complete.** Full spec at `notes/dev/design_spec.md`.
**Next phase: Phase 1 implementation** — local capture + first transport plugin on Android.

---

## The Three Plugin Axes (load-bearing)

QuKi-Notes is a **capture + dispatch** app with three independent plugin layers:

| Layer                        | What it does                                                                       | MVP                                            |
| ---------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------- |
| **Transports** (QuKi-Tosses) | Take a QuKi (markdown + images) → deliver to a destination. Stateless per fire.    | Yes — at least one built-in.                   |
| **Sync**                     | Move QuKis across this user's own devices. Opt-in. Off by default.                 | No — v1.1+ (skeleton lands with first plugin). |
| **MCP**                      | Expose QuKi-Notes read/list/append/toss to AI agents over Model Context Protocol.  | No — v2.0+ (axis reserved, not built).         |

All plugins are **Dart-only**. Obsidian compatibility (if/when built) lives in a separate TypeScript glue plugin in its own repo, talking to a Dart-shaped endpoint exposed by QuKi-Notes.

Core app responsibility: plugin management + the editor + the stream + file plumbing for plugins to consume. Plugins do the dispatching/syncing work.

---

## Key Decisions (all locked)

See `notes/dev/decisions.md` for full ADR rationale. Summary:

| Decision                  | Choice                                                                                                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Framework                 | Flutter (Dart)                                                                                                                                                      |
| State management / DI     | `riverpod` + `riverpod_generator` (code-gen, `@riverpod`)                                                                                                           |
| Active platforms          | Android first, then Windows + Linux                                                                                                                                 |
| Deferred platforms        | iPadOS / iOS / Mac (codebase supports; builds deferred — macOS runner cost)                                                                                         |
| Markdown flavor           | GFM                                                                                                                                                                 |
| WYSIWYG editor            | `super_editor` (fallback: `appflowy_editor`)                                                                                                                        |
| Local storage             | `drift` (SQLite ORM)                                                                                                                                                |
| Sync (MVP)                | **None.** Opt-in plugin axis lands v1.1+ (ADR-17, ADR-18)                                                                                                           |
| Transports (MVP)          | At least one built-in QuKi-Toss plugin (ADR-14)                                                                                                                     |
| MCP                       | Reserved as third plugin axis; **no code** in v1 (ADR-14, ADR-18)                                                                                                   |
| Auth                      | None in MVP. When needed by a plugin: GitHub OAuth 2.0 — Device Flow on all platforms (scopes per-plugin); no URL scheme registration                                |
| Token storage             | `flutter_secure_storage` (OS keystore), namespaced per plugin                                                                                                       |
| QuKi IDs / filenames      | UUID v4 (`uuid` package); transport-derived path `YYYY-MM-DD-{uuid8}.md` only when a plugin needs it                                                                |
| Image storage             | Separate binary files in `<app docs>/images/YYYY-MM-DD-{uuid8}.{ext}`; markdown ref `![](../images/...)`; never base64-embedded                                     |
| Deletion model            | Soft-delete via `deletedAt`; MVP background sweep at 24h. Sync-aware delete arrives with first sync plugin.                                                         |
| Save vs toss              | Save (local SQLite): 2s debounce + 30s periodic + lifecycle paused/detached. Toss (transport): manual only, user-initiated. No auto-toss, ever.                     |
| Ephemerality              | Gmail-style: framed as ephemeral via newest-first stream + no folders; persisted forever locally; no auto-delete (ADR-15)                                           |
| CLI                       | Working hypothesis only — not in MVP. Architecture preserves option (ADR-16, `notes/dev/cli_design.md`)                                                             |
| Drift migrations          | Integer `schemaVersion` + `MigrationStrategy.onUpgrade`; schema snapshots in `test/db/schemas/`; migration test required per version bump                           |
| Theme / Logging / Privacy | Follow system theme; `logging` package (console in debug, in-memory ring buffer in release); **no analytics, no crash reporting**                                   |
| Workflow JSON DSL         | **Dropped.** Replaced by transport plugins (Dart code). ADR-7 superseded by ADR-14.                                                                                 |
| Versioning                | Semantic versioning via release-please (`dart` type)                                                                                                                |
| Commits                   | Conventional commits; rebase & merge; every commit must follow conventional commit format                                                                           |
| Task runner               | `just` (justfile)                                                                                                                                                   |
| Docs                      | VitePress → GitHub Pages                                                                                                                                            |

---

## Project Structure

```
QuKi-Notes/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/         ← database/, transports/, auth/, settings/  (sync/, mcp/ added when those axes ship)
│   ├── features/     ← editor/, stream/, onboarding/, settings/
│   ├── ui/           ← cross-cutting Flutter widgets (NOT importable from CLI)
│   └── shared/       ← models/  (pure Dart; CLI-safe)
├── bin/              ← quki.dart  (added when CLI work begins; pure Dart console)
├── android/
├── windows/
├── linux/
├── ios/              ← present but not actively built
├── docs/             ← VitePress source
├── .github/
│   ├── workflows/    ← ci.yml, build-android.yml, build-windows.yml, build-linux.yml, build-ios.yml (stub), docs.yml
│   └── release-please.yml
└── justfile
```

Full layout in `notes/dev/design_spec.md` → Project Structure.

---

## Development Workflow

Claude opens focused PRs (one logical unit each). Scott tests on device and merges.

1. Claude opens PR with conventional commit title + test instructions
2. CI runs (`flutter analyze`, `flutter test`)
3. Scott tests on Android, rebase merges
4. release-please accumulates commits → opens Release PR when ready
5. Scott merges Release PR → GitHub Release created → build workflows fire (APK + Windows + Linux)

**Branch naming**: `feat/phase1-drift-schema`, `fix/toss-retry-network`
**PR size**: one screen, one service, or one action type — small enough to test in a session

---

## Development Pipeline Summary

| Phase | Goal                                                              | Status      |
| ----- | ----------------------------------------------------------------- | ----------- |
| 0     | Bootstrap scaffold (project, CI, docs)                            | Not started |
| 1     | Local QuKi capture on Android (editor + stream + drift)           | Not started |
| 2     | Transport plugin loader + first built-in QuKi-Toss                | Not started |
| 3     | Polish + share-in + Windows + Linux ports                         | Not started |
| 4     | Sync plugin axis + first sync backend (likely GitHub)             | v1.1+       |
| 5     | iPadOS / iOS / Mac builds                                         | Deferred    |
| 6     | MCP plugin axis                                                   | v2.0+       |

---

## Transport (QuKi-Toss) — Key Concepts

- A **QuKi-Toss** is a transport plugin: takes `(markdown, images, context)` → returns `success` or `failure(reason, retryable)`.
- Tosses are **stateless per fire**. They don't track history; the QuKi stays in the local stream after a successful toss.
- Tosses are **user-initiated**. No auto-toss in MVP.
- Plugin interface in `lib/core/transports/`. See ADR-14 for the API shape.
- First built-in toss: TBD at Phase 2 kickoff (candidates: clipboard, share-sheet, append-to-GitHub-file). Decision lives in `open_questions.md`.

---

## Sync (Plugin Axis — Deferred)

- Sync is **one of three plugin axes**, not a built-in feature. ADR-17.
- `lib/core/sync/` skeleton lands with the **first** sync plugin, not in MVP.
- When the GitHub sync plugin ships (likely the first), it inherits the "save vs push" debounce model (formerly ADR-6) and the SHA-based conflict-resolution pattern (formerly ADR-7), but as plugin internals, not core behaviour.

---

## Ephemerality (Gmail-Style)

- Newest-first stream surfaces what's current.
- Older QuKis age off the top but remain in SQLite + searchable.
- Tossing copies a QuKi to its destination; the local QuKi stays in the stream.
- Only the user can delete (no auto-expire in MVP). See ADR-15.

---

## Notes for Implementation Claude

**Required reading at session start** (in order):

1. `notes/dev/manifesto.md` — QuKi philosophy + tonality (normative)
2. This file — high-level context + locked decisions table above
3. `notes/dev/design_spec.md` — full design spec (jump to the section relevant to today's task)
4. `notes/dev/decisions.md` — ADR-lite log of every locked decision with rationale and rejected alternatives
5. `notes/dev/open_questions.md` — unresolved items; resolve in the PR if your task touches one
6. `notes/dev/session_protocol.md` — start/end-of-session checklist + hard rules
7. `notes/dev/testing.md` — testing strategy, what must have a test, mandatory bug-fix protocol
8. `notes/dev/pr_template.md` — PR title format + body template (use for every PR)

`notes/dev/dependencies.md` is the canonical list of approved packages; do not add new runtime dependencies without proposing an ADR first.

`notes/dev/cli_design.md` is a working hypothesis for a future CLI — read only if you're touching `lib/core/` structure (to preserve CLI-importability).

**First session only:** `notes/dev/bootstrap.md` contains the step-by-step task list for the **Phase 0 scaffold PR** (project structure, pubspec, justfile, CI workflows, VitePress). Read it once at the very first session; after the bootstrap PR is merged it becomes reference-only.

**Scott's environment setup** lives at `notes/dev/dev_env_setup.md` — Sonnet does not run any of it; included here for context on the toolchain Scott uses.

**Hard rules** (full list in `session_protocol.md`):

- The manifesto is normative. If a request conflicts with the manifesto, push back before implementing.
- Do not introduce vault-like features (folders, tags, backlinks). See manifesto "Is NOT" list.
- Do not commit or push without explicit instruction from Scott
- Open one PR per logical unit; include clear test instructions using `pr_template.md`
- Use conventional commits on every commit; Scott will rebase merge
- `just gen` must be run after any drift schema change; migration test required for version bumps
- `build-ios.yml` exists as a stub but must NOT be wired to trigger — macOS runner cost
- No analytics, no crash reporting, no telemetry SDKs — ever (see ADR-12)
- OAuth tokens and full QuKi contents are never logged
- `lib/core/` and `lib/shared/models/` must stay Flutter-free (ADR-16, for future CLI). Flutter imports go in `lib/ui/` or `lib/features/`.

---

**Last Updated**: 2026-05-28
