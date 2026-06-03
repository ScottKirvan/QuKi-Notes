# QuKi-Notes — Claude Context

## What This Is

A personal **capture-and-dispatch** app: ephemeral notes (**QuKis**) captured frictionlessly on whichever device is at hand, then **tossed** to a destination via a transport plugin. No vault. No organisation. No backup ritual.

**Philosophy first.** Read `notes/dev/manifesto.md` before anything else. The manifesto is normative; this file and the spec must stay consistent with it.

**Design phase: complete.** Full spec at `notes/dev/design_spec.md`.
**Phases 1 and 2 complete (v0.5.0).** Next: Phase 3 — Polish + share-in + Windows + Linux.

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

Claude works on a feature branch, tests iteratively with Scott on device, then opens a PR.

1. Claude creates branch, makes changes, tells Scott to test
2. Scott tests on Android device (`just android`)
3. Iterate (more changes, more testing) until feature works
4. **Only then**: Claude commits final state, opens PR
5. CI runs (`flutter analyze`, `flutter test`)
6. Scott reviews diff, rebase merges
7. release-please accumulates commits → opens Release PR when ready
8. Scott merges Release PR → GitHub Release created → build workflows fire (APK + Windows + Linux)

**Branch naming**: `feat/phase1-drift-schema`, `fix/toss-retry-network`
**PR size**: one screen, one service, or one action type — small enough to test in a session

---

## Development Pipeline Summary

| Phase | Goal                                                              | Status                        |
| ----- | ----------------------------------------------------------------- | ----------------------------- |
| 0     | Bootstrap scaffold (project, CI, docs)                            | Complete (merged)             |
| 1     | Local QuKi capture on Android (editor + stream + drift)           | Complete (v0.3.0)             |
|       | 1.1 Drift schema v1 (qukis + images tables, DAOs, providers)      | Complete (merged)             |
|       | 1.2 Editor screen (super_editor + formatting toolbar)             | Complete (merged)             |
|       | 1.3 Stream screen                                                 | Complete (merged)             |
|       | 1.4 Image paste                                                   | Blocked — super_clipboard/CargoKit archived; deferred |
|       | 1.5 Auto-save controller                                          | Complete (merged, v0.3.0)     |
|       | 1.6 Settings stub                                                 | Complete (merged, v0.4.0)     |
| 2     | Transport plugin loader + built-in QuKi-Tosses                    | Complete (merged, v0.5.0)     |
| 3     | Polish + share-in + Windows + Linux ports                         | Not started                   |
| 4     | Sync plugin axis + first sync backend (likely GitHub)             | v1.1+                         |
| 5     | iPadOS / iOS / Mac builds                                         | Deferred                      |
| 6     | MCP plugin axis                                                   | v2.0+                         |

---

## Transport (QuKi-Toss) — Key Concepts

- A **QuKi-Toss** is a transport plugin: takes `(markdown, images, context)` → returns `success` or `failure(reason, retryable)`.
- Tosses are **stateless per fire**. They don't track history; the QuKi stays in the local stream after a successful toss.
- Tosses are **user-initiated**. No auto-toss in MVP.
- Plugin interface in `lib/core/transports/`. See ADR-14 for the API shape, ADR-21 for the Flutter-import exception.
- Built-in tosses (Phase 2, shipped): **ClipboardToss** (copies markdown to clipboard) and **ShareSheetToss** (opens Android native share via `share_plus`). Both are enabled by default and can be toggled in Settings → Tosses.

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

## Session Model

Work on QuKi-Notes runs in three distinct Claude session types:

| Session | What it owns | What it does NOT touch |
|---|---|---|
| **Spec** | `notes/dev/` — keeps docs accurate, scopes work, briefs other sessions | App code, CI config |
| **Implementation** | App code + tests, one PR per session | CI/release infra, spec docs |
| **DevOps** | `.github/workflows/`, build configs, `justfile`, OQ-NEW-3 | App code, spec docs |

Each implementation and DevOps session reads the docs below at start and follows `notes/dev/session_protocol.md`.

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
- Do not open or update a PR until Scott has tested on device and confirmed it works
- Never commit to `main` unless Scott explicitly instructs it
- Open one PR per logical unit; include clear test instructions using `pr_template.md`
- Use conventional commits on every commit; Scott will rebase merge
- `just gen` must be run after any drift schema change; migration test required for version bumps
- `build-ios.yml` exists as a stub but must NOT be wired to trigger — macOS runner cost
- No analytics, no crash reporting, no telemetry SDKs — ever (see ADR-12)
- OAuth tokens and full QuKi contents are never logged
- `lib/core/` and `lib/shared/models/` must stay Flutter-free (ADR-16, for future CLI). Flutter imports go in `lib/ui/` or `lib/features/`. **Exception (ADR-21):** `lib/core/transports/` imports Flutter for `settingsView()` — the CLI uses only `toss()` and ignores that method.

---

## Current Task Brief

> This section is maintained by the Spec session. Implementation Claude: read this first, then read the full doc list below.

**Task**: Phase 3 — Windows + Linux build verification (DevOps session)
**Branch**: `chore/phase3-desktop-ci`
**PR title**: `chore(ci): verify and fix Windows + Linux release builds`

> This is a **DevOps session** task. Do not touch app code (`lib/`, `test/`). Changes are confined to `.github/workflows/` and build configuration only.

### Context

Both `build-windows.yml` and `build-linux.yml` have existed since Phase 0 but have never been validated against the current codebase. Since then, several packages have been added — most critically `receive_sharing_intent` (Android + iOS only), which may fail to compile on Windows or Linux.

Current release: **v0.5.0**. A `feat(share_in):` commit has since landed on `main`, so release-please should have opened a v0.6.0 Release PR — check `gh pr list` and confirm.

### Primary risk: `receive_sharing_intent` on non-Android

`receive_sharing_intent` supports Android and iOS only. When building for Windows or Linux, Flutter may either:
- Compile fine but throw `MissingPluginException` at runtime (federated plugin with empty stubs), or
- Fail to compile entirely.

**First thing to do**: attempt `flutter build windows --debug` and `flutter build linux --debug` locally (or push a test branch to trigger the workflows). If either fails due to `receive_sharing_intent`, the fix is platform-conditional code in `lib/features/share_in/share_handler.dart` — use `dart:io Platform.isAndroid` or Flutter's `defaultTargetPlatform` to no-op on non-Android. Co-ordinate with Scott if a code change is needed (that becomes an implementation session task, not a DevOps task).

### Workflow audit checklist

Review each workflow for correctness before triggering a real release build:

**`build-windows.yml`**
- [ ] Confirm `flutter build windows --release` succeeds with current `pubspec.yaml`
- [ ] Verify zip path `build\windows\x64\runner\Release\*` matches actual Flutter output location
- [ ] Confirm `softprops/action-gh-release@v2` has permission to upload (needs `contents: write` permission block, or relies on the default `GITHUB_TOKEN` — check it matches `build-android.yml` pattern)

**`build-linux.yml`**
- [ ] Confirm `flutter build linux --release` succeeds with current `pubspec.yaml`
- [ ] `libsecret-1-dev` is already in the apt install list ✓ — verify it's sufficient for `flutter_secure_storage`
- [ ] Tarball path `build/linux/x64/release/bundle` — confirm this is the correct Flutter Linux output path
- [ ] `softprops/action-gh-release@v2` permission check (same as Windows)

**`build-android.yml`**
- [ ] The APK step has `--dart-define=KEY_ALIAS` on a YAML continuation line — verify this is being parsed correctly by running a test build. If it isn't needed (keystore config flows through env vars anyway), remove it.

**`ci.yml`**
- No changes expected — runs on `ubuntu-latest`, tests only, no Flutter desktop compilation.

**`build-ios.yml`**
- Do NOT modify. Stub only; `workflow_dispatch` trigger; must never be wired to fire automatically.

**`release-please.yml`**
- Confirm it's still working: `gh run list --workflow=release-please.yml -L 5`. If the v0.6.0 Release PR exists and CI is green, merge it.

### Definition of done

- `flutter build windows --release` and `flutter build linux --release` both succeed (locally or in CI)
- Both workflows upload valid artifacts to a GitHub Release (test against v0.6.0 or a manual tag)
- No regressions in `ci.yml` (PR check still green)
- If any code change was required to fix `receive_sharing_intent` on desktop, that is tracked as a separate implementation PR — this DevOps PR contains only workflow/config changes

---

## Implementation Notes (current as of v0.5.0)

**Navigation**: `StreamScreen` is pushed from `EditorScreen` (stream is NOT the root). `app.dart` home = `EditorScreen(onLeave: push StreamScreen)`. The `onLeave` callback pattern avoids a circular import between editor and stream.

**Auto-save (Phase 1.5 — in place)**: `AutoSaveController` implements ADR-6: 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. The Phase 1.3 save-on-leave bridge (`_saveIfNeeded`, `_savedQukiId`) was removed when Phase 1.5 landed. Stream sorts by `modifiedAt DESC` so editing a QuKi brings it back to the top.

**riverpod_generator 4.0.4-dev.1 + drift types**: `@riverpod` functions returning `Stream<List<Quki>>` fail with `InvalidTypeException` because `Quki` lives in a generated `part` file and the generator can't determine its import path. Workaround: `StreamScreen` calls the drift DAO directly via `StreamBuilder` (DB comes through `ref.watch(appDatabaseProvider)`). Revisit when riverpod_generator stable 4.x ships.

**Transport registry (Phase 2 — in place)**: Plugins are registered at compile time in `lib/core/transports/registry.dart`. `TransportSettingsNotifier` persists per-plugin enabled state via `shared_preferences`. `enabledTransportsProvider` filters to only enabled plugins. `TossPickerSheet` in the editor lists enabled transports; result shown as a snackbar (retry offered on retryable failures).

**`flutter test` on Windows**: If `flutter test` crashes with `PathAccessException: sqlite3.dll Access is denied`, run `flutter clean` in a fresh terminal (close VS Code first). The DLL gets locked by the previous test process.

**Last Updated**: 2026-06-02
