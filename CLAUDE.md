# QuKi-Notes — Project Overview

A personal **capture-and-dispatch** app: ephemeral notes (**QuKis**) captured frictionlessly on whichever device is at hand, then **tossed** to a destination via a transport plugin. No vault. No organisation. No backup ritual.

**Philosophy first.** Read `notes/dev/manifesto.md` before anything else. The manifesto is normative; all other docs must stay consistent with it.

---

## Session Model

Work runs in three concurrent Claude session types. Launch each from its own folder under `Agents/`:

| Session | Launch from | What it owns |
|---|---|---|
| **Spec** | `Agents/quiki-spec/` | `notes/dev/` docs, task briefs, phase tracking |
| **Implementation** | `Agents/quiki-dev/` | App code + tests, one PR per session |
| **DevOps** | `Agents/quiki-devops/` | `.github/workflows/`, build configs, `justfile` |

Each folder has its own `CLAUDE.md` with role-specific instructions and the current task brief. Start there.

---

## The Three Plugin Axes (load-bearing)

| Layer | What it does | MVP |
|---|---|---|
| **Transports** (QuKi-Tosses) | Take a QuKi → deliver to a destination. Stateless per fire. | Yes — ClipboardToss + ShareSheetToss shipped |
| **Sync** | Move QuKis across this user's own devices. Opt-in. | No — v1.1+ |
| **MCP** | Expose QuKi-Notes to AI agents over Model Context Protocol. | No — v2.0+ |

---

## Key Decisions (locked — full rationale in notes/dev/decisions.md)

| Decision | Choice |
|---|---|
| Framework | Flutter (Dart) |
| State management / DI | `riverpod` + `riverpod_generator` (`@riverpod`) |
| Active platforms | Android first, then Windows + Linux |
| Deferred platforms | iPadOS / iOS / macOS (codebase supports; builds deferred) |
| Markdown flavor | GFM |
| WYSIWYG editor | `super_editor` |
| Local storage | `drift` (SQLite ORM) |
| Sync (MVP) | None — opt-in plugin axis v1.1+ (ADR-17, ADR-18) |
| Transports (MVP) | Built-in compile-time registry; ClipboardToss + ShareSheetToss shipped (ADR-14) |
| `lib/core/transports/` | Flutter import allowed for `settingsView()` (ADR-21) |
| MCP | Reserved, no code in v1 (ADR-14, ADR-18) |
| Auth | None in MVP; GitHub Device Flow when a plugin needs it (ADR-9) |
| Token storage | `flutter_secure_storage`, namespaced per plugin (ADR-2) |
| Image storage | Separate binary files; `![](../images/...)`; never base64 (ADR-4) |
| Deletion | Soft-delete via `deletedAt`; 24h sweep (ADR-5) |
| Save vs toss | Save: 2s debounce + 30s periodic + lifecycle. Toss: user-initiated only (ADR-6) |
| Ephemerality | Gmail-style: framed ephemeral, persisted forever locally (ADR-15) |
| CLI | Working hypothesis; not in MVP; `lib/core/` stays Flutter-free for it (ADR-16) |
| Drift migrations | Integer `schemaVersion` + snapshot tests per bump (ADR-8) |
| Theme / Logging / Privacy | System theme; `logging` package; no analytics ever (ADR-12) |
| Versioning | Semantic versioning via release-please (`dart` type) |
| Commits | Conventional commits; rebase & merge |
| Task runner | `just` (justfile) |
| Docs | VitePress → GitHub Pages |

---

## Project Structure

```
QuKi-Notes/
├── Agents/
│   ├── quiki-spec/    ← Spec session root (CLAUDE.md + briefs)
│   ├── quiki-dev/     ← Implementation session root (CLAUDE.md + task brief)
│   └── quiki-devops/  ← DevOps session root (CLAUDE.md + task brief)
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/       ← database/, transports/, auth/, settings/ (Flutter-free except transports/)
│   ├── features/   ← editor/, stream/, settings/, share_in/
│   └── shared/     ← models/ (pure Dart; CLI-safe)
├── android/
├── windows/
├── linux/
├── ios/            ← scaffold present; not actively built
├── .github/
│   ├── workflows/
│   └── release-please/
├── notes/dev/      ← all planning docs (manifesto, spec, decisions, OQs, etc.)
├── docs/           ← VitePress source
├── pubspec.yaml
├── justfile
└── CHANGELOG.md
```

---

## Development Pipeline Summary

| Phase | Goal | Status |
|---|---|---|
| 0 | Bootstrap scaffold | Complete |
| 1 | Local QuKi capture on Android | Complete (v0.3.0) |
| | 1.1 Drift schema v1 | Complete |
| | 1.2 Editor screen (super_editor + toolbar) | Complete |
| | 1.3 Stream screen | Complete |
| | 1.4 Image paste | Blocked — CargoKit archived; deferred |
| | 1.5 Auto-save controller | Complete (v0.3.0) |
| | 1.6 Settings stub | Complete (v0.4.0) |
| 2 | Transport plugin loader + built-in QuKi-Tosses | Complete (v0.5.0) |
| 3 | Polish + share-in + Windows + Linux | In progress |
| | 3.1 Android share-in | Complete (merged) |
| | 3.2 Windows + Linux CI verification | Complete (merged) |
| | 3.3 Platform guard: share-in on desktop | Complete (merged) |
| | 3.4 Desktop keyboard shortcuts + window-state | Not started |
| | 3.5 Stream performance (lazy loading) | Defer until threshold hit |
| 4 | Sync plugin axis + first sync backend | v1.1+ |
| 5 | iPadOS / iOS / macOS builds | Deferred |
| 6 | MCP plugin axis | v2.0+ |

---

## Hard Rules (apply to all sessions)

- The manifesto is normative. Push back on anything that conflicts with it.
- No vault-like features: no folders, tags, backlinks, archive, or pinning.
- No analytics, crash reporting, or telemetry. Ever. (ADR-12)
- `build-ios.yml` is a stub — must NOT be wired to trigger automatically.
- Plugin secrets and full QuKi contents are never logged.
- Never commit to `main` unless Scott explicitly instructs it.

---

## Implementation Notes (current as of v0.5.0+)

**Navigation**: `StreamScreen` is pushed from `EditorScreen` (stream is NOT the root). `app.dart` home = `EditorScreen(onLeave: push StreamScreen)`.

**Auto-save**: `AutoSaveController` implements ADR-6 — 2s idle debounce + 30s periodic + lifecycle hooks. The Phase 1.3 save-on-leave bridge was removed in Phase 1.5.

**riverpod_generator 4.0.4-dev.1 + drift types**: `@riverpod` functions returning `Stream<List<Quki>>` fail with `InvalidTypeException`. Workaround: `StreamScreen` calls the drift DAO directly via `StreamBuilder`. Revisit when riverpod_generator stable 4.x ships.

**Transport registry**: Plugins registered at compile time in `lib/core/transports/registry.dart`. `TransportSettingsNotifier` persists enabled state via `shared_preferences`. `enabledTransportsProvider` filters to enabled plugins only.

**Share-in**: `lib/features/share_in/share_handler.dart` — guarded with `Platform.isAndroid`; no-ops cleanly on Windows/Linux.

**`flutter test` on Windows**: If `flutter test` crashes with `PathAccessException: sqlite3.dll Access is denied`, run `flutter clean` in a fresh terminal (close VS Code first).

**Last Updated**: 2026-06-03
