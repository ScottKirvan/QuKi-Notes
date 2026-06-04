# CLI Design — Working Hypothesis

> Status: **Sketch.** Not implemented in MVP. Captured here so the v1 architecture doesn't paint the CLI into a corner. Revisit when the first concrete CLI use case shows up.

---

## Why Capture This Now

Scott may want a `quki` command-line interface in the future for:

- Scripted toss-from-a-pipe (`echo "ship it" | quki toss daily-log`)
- Batch import / export
- CI integration (emit a QuKi from a GitHub Action)
- Debugging the core library outside the Flutter UI

If the core library is structured well from day one, adding the CLI later is a matter of writing a thin `bin/quki.dart` and wiring `args` parsing. If the core library is tangled with Flutter widgets, the CLI becomes a port instead of a wrapper.

This doc records the **architectural intent** so v1 stays factorable.

---

## Locked: CLI lives in the same repo

Per the course-correction whiteboard, the CLI is **not** spun out into its own package on first cut. It lives as a sibling target inside `quki_notes`:

```
quki_notes/
├── lib/                    ← shared core library (UI-agnostic)
├── lib/ui/                 ← Flutter UI (entry: lib/main.dart)
└── bin/quki.dart           ← CLI entry point (Dart console; added when first useful)
```

Future move to `packages/quki_core/` + `packages/quki_cli/` is a refactor we'll do when it pays for itself, not before.

---

## Core Library Shape (the constraint)

The library under `lib/core/` and `lib/shared/` must be **importable from a pure Dart console app** with no Flutter dependency.

Concretely:

- `core/database/` (drift) — pure Dart, already Flutter-free.
- `core/transports/` (plugin loader + transport API) — pure Dart.
- `core/sync/` (when it exists) — pure Dart.
- `shared/models/` — pure Dart data classes.
- `shared/widgets/` — Flutter. **Not** importable from CLI. Fine.
- `features/*/` — Flutter UI. **Not** importable from CLI. Fine.

The dividing line: anything the CLI might call must live under `lib/core/` or `lib/shared/models/` and must `import 'dart:io'` or `package:drift/native.dart` rather than any `package:flutter/*`.

**Test this constraint:** add a `dart analyze bin/quki.dart` (or a CI step) once the CLI lands. Flutter imports leaking into core will fail the analyzer in console-app mode.

---

## Hypothetical CLI Surface (v0)

Sketch of what feels right. Subject to change at implementation time.

```
quki                              # opens REPL: read stdin, save as QuKi
quki new "ship it"                # creates a QuKi from arg
quki ls [--limit 20] [--search X] # list recent QuKis (newest first)
quki cat <id>                     # print QuKi body to stdout
quki rm <id>                      # delete a QuKi
quki toss <quki-id> <toss-id>     # fire a transport on a stored QuKi
echo "..." | quki toss daily-log  # one-shot: capture from stdin + immediately toss
quki tosses                       # list configured transports
quki doctor                       # check config / plugin availability
```

Auth, settings, and the SQLite DB are read from the **same** OS-keystore + app-documents directory the Flutter app uses, so the CLI and the app share state. (On Windows: `%APPDATA%\quki_notes\`; on Linux: `~/.local/share/quki_notes/`; on Android: N/A — CLI is desktop-only.)

---

## Open Questions for the CLI Phase

These do **not** block MVP. Recorded here to remember when the CLI work starts.

- **OQ-CLI-1**: How does the CLI authenticate for transports that need OAuth (e.g. GitHub)? Re-use the same `flutter_secure_storage`-backed token? On Linux, `flutter_secure_storage` uses libsecret — does a pure Dart console app have access? Likely yes via the same backend, but to confirm.
- **OQ-CLI-2**: Does the CLI write to the same SQLite file as the running Flutter app? Drift uses WAL by default which permits concurrent readers but only one writer. If the user runs the CLI while the app is open, what's the behavior? Probably: CLI takes the writer lock briefly; if contended, retry once then error.
- **OQ-CLI-3**: Plugin loading at the CLI — does the CLI scan the same plugin registry? If plugins ever need Flutter (they shouldn't, by ADR-14), the CLI can't load them. Enforce "transports are pure Dart" as a contract.
- **OQ-CLI-4**: Distribution. Single `dart compile exe` per platform? Or `pub global activate` from the same repo? Decide at CLI-launch time, not before.

---

## Non-Goals for the CLI

- Not a full TUI editor. Use `quki cat <id> > /tmp/x.md && $EDITOR /tmp/x.md && quki update <id> < /tmp/x.md` — the CLI is glue, not an editor. (note from scott:  launching a full editor may be an idea - like vim - similar idea to git commits that needs longer commit messages)
- Not a sync trigger. Sync runs in the app. The CLI may read sync-state but does not initiate pulls/pushes (revisit if needed).
- Not a server. No `quki serve` daemon. The MCP layer (v2.0+) is the right home for any "expose QuKi state to other processes" need.

---

## When To Promote This Doc

When Scott opens the first PR that scaffolds `bin/quki.dart`:

1. Move locked decisions here into ADRs in `decisions.md`.
2. Convert OQs above into resolved entries or move them to `open_questions.md`.
3. Mark this doc as "Historical context" and stop editing it.

Until then, this is a sketch — feel free to challenge any of it at promotion time.

---

**Last Updated**: 2026-05-28
