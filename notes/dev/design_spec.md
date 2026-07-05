# QuKi-Notes — Design Spec

> **Read the manifesto first.** `notes/dev/manifesto.md` is the normative source for what QuKi-Notes is and is not. This spec is implementation guidance subordinate to that document.

---

## TL;DR

QuKi-Notes is a **scratchpad, pasteboard, and capture surface** — a blank canvas when you open it:

- **Open and go**: blank editor, cursor ready. Type, paste, draft, link-dump, whiteboard. No title, no folder, no template.
- **Use it, send it, or let it fade**: use the content right there, fire a transport plugin to send the QuKi somewhere (a "QuKi-Toss"), or just let it drift down the stream as newer entries arrive. All three are valid outcomes.
- **History**: the stream surfaces newest-first. Older QuKis age off the top but stay searchable. Nothing auto-deletes.

Single-device, local-only in MVP. Sync is a deferred plugin axis. MCP is reserved for v2.

---

## Vocabulary

| Term            | Meaning                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------- |
| **QuKi**        | A single ephemeral note. Plural: **QuKis**.                                                  |
| **QuKi-Notes**  | The application.                                                                             |
| **Transport**   | A plugin that delivers a QuKi somewhere. Internal/code term. Architecturally bidirectional; output only in MVP. |
| **Send...**     | User-facing action label for firing a transport. Appears in the editor hamburger menu.       |
| **QuKis**       | The list view screen title. "Stream" is acceptable in internal code and docs only.           |
| **Recently Deleted** | Data recovery screen for soft-deleted QuKis. Not an organizer feature.               |

Do **not** use in UI copy: vault, library, document, file, note (the entity is QuKi - ok to use "note" to avoid unnecessary obfuscation), workflow, inbox, toss, stream.

---

## Target Platforms

All platforms are equally valid targets. Build and CI priority reflects development order, not product importance:

1. **Android** — first active build and device-test platform. Pixel 6 Pro is the dev device.
2. **Windows** — desktop, second active target.
3. **Linux** — third active target. Flutter Linux desktop is supported; we accept risk and track quality issues as OQs.
4. **iPadOS / iOS / macOS** — deferred CI and device testing only. Codebase compiles for them; scaffolding, pubspec deps, and platform config must be kept current so enabling them requires zero rework.

Linux note: `flutter_secure_storage` on Linux uses `libsecret` (gnome-keyring / KWallet). On headless/server Linux this would fail, but our user-facing target is desktop Linux with a keyring daemon present.

---

## Architecture: Three Plugin Axes

```
  ┌────────────────────────────────────────────────────────────┐
  │                       QuKi-Notes Core                      │
  │                                                            │
  │   Editor   ──►   Stream   ──►   .md files (ADR-25)         │
  │                     │                                      │
  │                     ▼                                      │
  │                Plugin Registry                             │
  │              /       │        \                            │
  │       Transports    Sync       MCP                         │
  │       (MVP: ≥1)   (v1.1+)    (v2.0+)                       │
  └────────────────────────────────────────────────────────────┘
```

Core owns: editor, stream, persistence, settings, plugin lifecycle.
Plugins own: dispatching, syncing, exposing-to-agents.

All plugins are **Dart-only**. (Obsidian glue, if/when built, is a TS plugin in its own repo talking to a Dart-shaped IPC endpoint exposed by QuKi-Notes. Out of scope here.)

### Transport plugin contract (ADR-14)

```dart
abstract class TransportPlugin {
  String get id;
  String get displayName;
  String get description;
  Widget settingsView(WidgetRef ref);              // for Settings → Tosses

  Future<TossResult> toss({
    required String markdown,
    required List<Image> images,
    required TossContext ctx,
  });
}

class TossResult {
  final bool success;
  final String? message;       // user-facing detail
  final bool retryable;        // hint for UI
}

class TossContext {
  final DateTime firedAt;              // when toss button was pressed
  final QukiMetadata quki;             // id, createdAt, modifiedAt — for templating
  final Geolocation? gps;              // null unless all GPS gates ON (ADR-19)
  final Map<String, String> userOverrides; // free-form per-fire overrides
}

class QukiMetadata {
  final String id;
  final DateTime createdAt;
  final DateTime modifiedAt;
}

class Geolocation {
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final DateTime capturedAt;
}
```

**Key intentional constraints:**

- **`List<Image>`, not `List<Attachment>`** — a QuKi is GFM markdown which renders text + images. We do not generalize to arbitrary attachments (PDFs, videos, archives); see ADR-14 rationale. If a future use case demands it, we revisit.
- **`firedAt` vs `quki.createdAt`** — distinct on purpose. Transports may template either depending on intent (a daily-log toss uses `firedAt`; a wiki-publish toss may use `quki.createdAt`).
- **`gps` is nullable**. Transports must handle absence — see Privacy & Permissions below and ADR-19 for the opt-in gates.

Tosses are stateless **per fire** — they do not persist history beyond what the plugin chooses to store in its own settings.

### Sync plugin contract (deferred, ADR-17)

```dart
abstract class SyncBackend {
  Future<List<QukiDiff>> pull({DateTime? since});
  Future<PushResult> push(List<QukiDiff> local);
}
```

`SyncBackend` lands when the first sync plugin lands. GitHub is one possible implementation, not privileged.

### MCP plugin contract (reserved, v2.0+)

Not designed in detail. Architectural intent: an embedded MCP server inside the app advertising the same QuKi-Notes operations (list, read, search, append, toss) over the Model Context Protocol so external AI agents can use QuKi-Notes as a context store / dispatcher. Re-evaluate after v1.x stabilises.

---

## Core Features (MVP = v1.0)

### 1. Capture (Editor)

- App opens to a blank QuKi. Cursor in the body. No "title", no "untitled note", no template.
- **Markdown WYSIWYG is a hard requirement** — genuine live-preview rendering as the user types, not a syntax-highlighting trick. Typing `**text**` renders bold with the delimiters gone; `- [ ]` renders as a real checkbox glyph; `# ` renders as an actual heading with no `#` visible; links show only their label; images render as actual embedded images. Whichever element the cursor is currently inside reveals its raw markdown source, in place, so it can be edited directly; every other element shows its rendered form. This is not deferred. See `notes/dev/decisions.md` → ADR-31 and `notes/dev/live_preview_editor.md` for the implementation path.
- Editor toolbar: bold, italic, strikethrough, lists, code blocks, links, image.
- Image paste from clipboard via `super_clipboard`. Image share-in via Android share sheet. (Image paste currently blocked — CargoKit; see `dependencies.md`.)
- Auto-save: 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks, never networks.
- **Editor navigation** — the editor is the permanent root of all navigation. No back button. Ever. Regardless of which QuKi is loaded or how the user got there.
  - Top-left: QuKis icon → pushes QuKis list; list **slides in from the left** (icon is on the left).
  - Top-right: hamburger menu (≡) → Send..., QuKis, Settings; Settings **slides in from the right** (hamburger is on the right).
  - The editor is **one widget** whose content changes; its chrome does not.
- **QuKis list**: slides in from left; back/dismiss slides back out to the left. Tapping a row loads that QuKi into the root editor + pops the list. `+ New` clears the editor to blank + pops the list. No second EditorScreen is ever pushed.
- **Send sheet**: slides up from bottom (`showModalBottomSheet`). Slides down on dismiss.
- **Navigation direction principle**: the transition direction matches the physical position of the affordance that triggered it.

**Editor capabilities — built-in vs we-wire-it-up:**

| Capability                                  | Source                                       |
| ------------------------------------------- | -------------------------------------------- |
| Text selection, cursor, caret               | Custom `RenderObject` + `TextInputClient` (ADR-31) — no longer `TextField`; we own caret/selection/hit-testing directly |
| Copy / cut / paste / select-all (text)      | Implemented against the raw markdown buffer by the custom engine (ADR-31) |
| Undo / redo                                 | Implemented by the custom engine (ADR-31); no longer inherited free from `TextField` |
| Image paste from clipboard                  | Deferred — CargoKit archived, OQ-2 open      |
| Drag-and-drop image onto editor (desktop)   | Deferred — revisit after ADR-31 Stage 5      |
| Formatting toolbar buttons → markdown       | `FormattingToolbar` in `markdown_live_editor` package (unchanged mechanism — inserts/toggles markdown syntax in the buffer) |
| Markdown rendering                          | Custom live-preview engine — per-element reveal/collapse, not per-line syntax hiding (ADR-31; see "Editor rendering engine" below) |
| Spellcheck                                  | Platform-native (OS-provided) — needs re-verification once `TextField` is no longer the input widget (ADR-31 Stage 1) |

### 2. QuKis list

A newest-first list of QuKis. The temporal queue, not a filing cabinet. Screen title: **QuKis**.

- Each row: truncated first non-empty line (~50–100 chars) + relative timestamp.
- Tap → opens the QuKi in the editor (back button returns to list).
- Swipe → soft-delete; QuKi moves to **Recently Deleted**.
- Top-right: **+ New** opens a blank QuKi (back button returns to list).
- Search field: live filter on body text. Search is for recall, not organization.
- **No folders, no tags, no pinning, no archive.** Period.

### 3. Recently Deleted

Data recovery screen — not an organizer feature.

- Lists soft-deleted QuKis, newest-first, for the user-configurable retention period (default TBD; 24h is too short for real use — needs a setting).
- Tap a row → restore to the QuKis list.
- Swipe → permanent deletion (immediate; modal confirmation dialog).
- No search, no sorting, no tagging, no pinning. It is not a second inbox.
- After the retention period expires, QuKis are hard-deleted automatically.

### 4. Send (Transport)

In the editor, **Send...** in the hamburger menu (≡) opens a sheet listing configured transports. User picks one. App fires `toss()`. UI shows result (success / failure with retry, auto-dismiss after a few seconds).

- After a successful send, the local QuKi remains in the QuKis list untouched. Send copies, never moves.
- Built-in transports (shipped in Phase 2): Clipboard, Share Sheet.

### 5. Settings

- Theme: follow system (ADR-12). No manual override in v1. **Color palette: GitHub Primer Dark High Contrast** (`primer.style/primitives/colors`). Key tokens mapped to Flutter `ColorScheme`: canvas `#0a0c10`, surface `#272b33`, foreground `#f0f3f9`, muted `#9ea7b4`, accent/primary `#71b7ff` / `#1f6feb`, borders `#7a828e`. Light system theme uses Primer Light High Contrast. Do not use Flutter's default `Colors.deepPurple` seed.
- Tosses (transports): list installed plugins, configure each via its `settingsView`.
- **Storage** (ADR-27): shows current storage path. "Change location" button opens the native directory picker; new QuKis go to the new path, existing files stay put (no migration in v1). When app storage is active, a persistent subtitle reads "Files will be removed on uninstall. Change location." — always visible, not dismissible.
- Sync: empty in MVP ("No sync backends installed" placeholder; copy hints at v1.1+).
- **Privacy**: per-capability opt-in toggles (GPS first; camera/mic/etc. as transports require). All default OFF. See Privacy & Permissions below.
- About: version, link to docs, link to manifesto, no telemetry disclosure.

### 6. Privacy & Permissions (ADR-19)

Device-backed enrichments (GPS today; camera/mic/contacts later if transports demand) follow a **three-gate opt-in** model. All three must be ON before the OS-level permission dialog appears or the field appears in `TossContext`:

1. **Device capability** — if the platform doesn't have the hardware (e.g. GPS on a desktop tower), the capability is invisible. No toggles, no toasts, no "feature unavailable" banners. The setting just doesn't exist.
2. **App-wide Privacy setting** — `Settings → Privacy` shows one toggle per supported capability. Default **OFF** for every one. Onboarding does NOT ask. The user discovers these settings if/when they install a transport that wants the capability.
3. **Per-transport setting** — transports that want a capability declare it in their `settingsView` with a clear opt-in. Disabled by default per-install.

**Behavioral rules:**

- Capture is **never** gated by a permission dialog. Tapping the app icon takes you to a blank QuKi. Always.
- The OS permission dialog only appears at the **first fire** of a transport that needs the capability after all three gates are ON.
- If the app-wide toggle is OFF but a transport asks for the capability: transport's `settingsView` displays a hint ("GPS is disabled in app Privacy settings"); the transport still fires, just without the field.
- OS-level permission revocation = capability gate OFF. Graceful degradation, no nagging dialog on next launch.

**MVP scope:** only GPS is wired (because at least one candidate first-toss might want geotagging — OQ-NEW-1). Camera/mic/etc. land if and when a transport needs them.

### 7. What's NOT in MVP

- No accounts, no auth (until a plugin needs one).
- No sync, no GitHub OAuth, no remote storage.
- No JSON workflow DSL, no workflow editor (transports are code, not data — ADR-14).
- No MCP server.
- No CLI.
- No backup/export beyond the toss mechanism itself.

---

## UI Shapes

### Editor (always home — no back button, ever)

```
┌──────────────────────────────┐
│ [📋 icon]                [≡] │
├──────────────────────────────┤
│                              │
│  (QuKi content)              │
│  cursor here                 │
│                              │
│                              │
├──────────────────────────────┤
│ [B] [I] [~] [•] [1.] [</>]   │
│ [Link] [Image]  [⋯]          │
└──────────────────────────────┘
```

- Top-left icon → pushes QuKis list (primary nav)
- Top-right ≡ → hamburger: Send..., QuKis, Settings
- **No back button. Ever. Regardless of which QuKi is loaded.**
- Content changes (blank or loaded QuKi); chrome never changes.

### Hamburger menu

```
┌──────────────────────────────┐
│                          [≡] │
├──────────────────────────────┤
│  Send...                     │
│  QuKis                       │
│  Settings                    │
└──────────────────────────────┘
```

### QuKis list

```
┌──────────────────────────────┐
│ [←]  QuKis         [+ New]   │
│ [search...                 ] │
├──────────────────────────────┤
│ 5 min ago — I went to the    │
│ 1 hour ago — Meeting notes   │
│ Yesterday — Grocery list:    │
│ May 24 — Project ideas for   │
└──────────────────────────────┘
```

- Back arrow (←) → returns to root editor

### Send sheet

```
┌──────────────────────────────┐
│ Send this QuKi via...        │
├──────────────────────────────┤
│ ● Clipboard                  │
│ ● Share sheet                │
│                              │
│ Manage transports in Settings│
└──────────────────────────────┘
```

---

## Technical Architecture

### Tech Stack

- **Framework**: Flutter (Dart) — single codebase, Android + Windows + Linux active.
- **State / DI**: `riverpod` + `riverpod_generator` (`@riverpod` annotation). ADR-1.
- **Editor**: `markdown_live_editor` (monorepo path dep `packages/markdown_live_editor/`, ADR-26 package extraction, ADR-31 rendering engine) — custom `RenderObject` + `TextInputClient` live-preview model; see "Editor rendering engine" below.
- **Markdown flavor**: GFM (GitHub Flavored Markdown).
- **Local storage**: individual `.md` files via `dart:io` + `path_provider` (ADR-25).
- **Image clipboard**: `super_clipboard` — deferred; CargoKit archived 2026-03-26.
- **Share-in**: `receive_sharing_intent` (Android; Windows/Linux equivalents TBD).
- **Share-out / toss-to-share-sheet**: `share_plus`.
- **GPS** (per-toss opt-in only): `geolocator` + `geocoding` for reverse-geocoded address strings (platform-native, no API key).
- **Secrets** (plugin-owned): `flutter_secure_storage`. ADR-2.
- **Settings** (non-secret): `shared_preferences`.
- **HTTP** (for any transport that needs it): `dio`.
- **OAuth helper** (when first plugin needs it): `dio` + `url_launcher` for GitHub Device Flow. ADR-9.
- **IDs**: `uuid` (v4).
- **Paths**: `path_provider`.
- **Logging**: `package:logging`. ADR-12.

### Editor rendering engine (ADR-31) — live-preview markdown

Supersedes the `buildTextSpan()` zero-width-hiding model (ADR-30). Full rationale and rejected alternatives: `decisions.md` → ADR-31. Plain-English walkthrough (motivation, why prior attempts failed, accessible explanation of the approach): `notes/dev/live_preview_editor.md`.

**Ground truth**: the markdown source string is the only canonical representation, always. There is no intermediate document/AST model that owns editing — this constraint predates ADR-31 (it's why ADR-26 rejected `super_editor`/`flutter_quill`/`appflowy_editor`-style editors) and is unchanged by it.

**Rendering model — per element, not per line:**

1. A parse pass walks the buffer and produces a flat list of elements (heading, unordered/ordered list item, checkbox, bold/italic/strikethrough/code span, link, image, blockquote, code fence), each carrying a source range (`start`, `end` offsets into the buffer).
2. On every selection change, each element's source range is intersection-tested against the current cursor/selection. An element containing the cursor is **revealed** — shown as raw markdown source, directly editable. Every other element is **collapsed** — shown in its rendered form, which may differ in length and content from its source (heading text with `# ` fully removed and a larger font; a link showing only its label text; an image shown as an actual embedded image; a checkbox shown as a real glyph).
3. Reveal/collapse recomputation is a cheap intersection test against cached ranges — it does not require re-parsing the document. Re-parsing only happens after a text change.
4. A full reparse per text change is acceptable for this app's document sizes (short-form QuKis). Do not add incremental parsing until profiling proves it's needed.

**Cursor and selection mechanics** (do not exist in Flutter's `TextField`/`EditableText`; must be built ourselves):

- **Boundary-reveal movement**: an arrow key that would land the cursor at the boundary of a collapsed element triggers reveal; the cursor lands at the near boundary of the full source text and the user navigates character-by-character from there through the raw markdown. Exiting the far boundary collapses the element. There is no skip-over behavior — every element in QuKi-Notes has editable source, so all reveal on boundary entry rather than being skipped atomically.
- **Tap-to-boundary**: tapping inside a collapsed element's rendered bounds resolves the cursor to whichever boundary of its source range (start or end) is nearer the tap's x-coordinate. No fractional interpolation into collapsed content — this matches CodeMirror 6's own behavior (no surveyed editor does better).
- **Direct IME integration**: the editor widget implements `TextInputClient` and manages its own `TextInputConnection` via `TextInput.attach()` — it does not use `TextField`/`EditableText`/`RenderEditable`. This is required because `WidgetSpan` and `TextPainter`'s `TextPosition` offset math are hard-capped at the Flutter engine level to one character per element, with no API to represent "this rendered region stands in for N source characters" (confirmed via flutter/flutter#107432, #150864 — engine-level, not app-level; see ADR-31 for detail).

**Links vs. images**:
- Images always reveal source on tap (no navigate action) — no engine limitation blocks rendering an actual image inline once we own painting.
- Link tap behavior: tap navigates (opens URL); reveal-and-edit is triggered by cursor entering via keyboard (arrow key from either side, backspace from the right) or cursor landing at the element boundary — consistent with the boundary rule for all other element types. Resolved 2026-07-04 (OQ-6).

**Build stages** (each independently shippable; do not attempt this as one PR):

| Stage | What ships | Key milestone |
|---|---|---|
| 1 | Custom `RenderObject` + `TextInputClient` reimplementing today's plain-text editing behavior (no markdown rendering yet) | Proves the IME/caret/selection plumbing works before any rendering complexity is added — parity check against the current `TextField`-based editor |
| 2 | Parser produces element list with source ranges; reveal-on-cursor-intersect implemented for the simplest elements (headings, bold/italic) | Core reveal/collapse mechanic proven |
| 3 | Boundary-reveal cursor movement + tap-to-boundary hit-testing — arrow key reaching element boundary reveals source; navigate through full source text; exit far boundary collapses | Cursor navigation feels correct, not just visually correct |
| 4 | Lists — real bullet glyphs, real checkbox glyphs, position-computed ordered-list numbers | Closes out the PR #194 checkbox/ordered-list bugs correctly this time |
| 5 | Inline images — real embedded image widgets, not `WidgetSpan`-constrained | Was blocked entirely under ADR-30; unblocked by this architecture |
| 6 | Links — tap navigates; keyboard entry or boundary touch reveals source for editing (OQ-6 resolved) | Full live-preview feature complete |

### Riverpod conventions

- All app state through providers — no global singletons, no manual `InheritedWidget`, no `setState` outside trivial widget-local state.
- Code-gen `@riverpod` everywhere; do not hand-write `Provider<T>(...)`.
- Providers live next to the feature they belong to (`features/editor/editor_controller.dart`).
- Cross-cutting providers live in `core/` next to the service they own.
- Widgets that read providers extend `ConsumerWidget` or use `Consumer`.

| Flavor             | Used for                                                                          |
| ------------------ | --------------------------------------------------------------------------------- |
| `Provider`         | Stateless services: `AppDatabase`, `TransportRegistry`                            |
| `StreamProvider`   | `drift` queries: stream view, single QuKi watch                                   |
| `FutureProvider`   | One-shot async: plugin discovery, asset loads                                     |
| `NotifierProvider` | Stateful controllers: `EditorController` (auto-save, formatting), `TossController` |
| `StateProvider`    | Trivial mutable values: current QuKi ID, search query                             |

### Application flow

**First launch:**
1. Skip onboarding entirely — drop straight into a blank QuKi. (No "Connect GitHub" prompt; that was the old framing.)
2. A subtle Settings entry surfaces tosses + future sync.

**Subsequent launches:**
1. Honor `launch_behavior` setting: blank QuKi (default) or stream view.

**No auth state to restore in MVP.** When a plugin that needs auth is installed (v1.1+), token refresh happens lazily on its next operation.

### Save semantics (ADR-6)

- **Save** (local file): 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks the UI.
- **Toss** (transport): user-initiated. Pressing the toss button is the only path; no auto-toss.
- **Push** (sync, when sync exists): same debounce shape as save, but only triggers from foreground + manual sync button, never from periodic/lifecycle saves.

### Storage — individual `.md` files (ADR-25, supersedes Drift schema)

**Drift/SQLite removed in v0.9.5.** See ADR-25 in `notes/dev/decisions.md` for full rationale. Directory structure:

```
<app-documents>/qukis/
  {uuid}.md          ← body, plain markdown
  .meta/{uuid}.json  ← {"createdAt": "..."}
  .trash/            ← soft-deleted QuKis; user restores or hard-deletes
  .trash/.meta/
    {uuid}.json
```

`modifiedAt` = filesystem `mtime` — changes only on actual write. `lib/core/storage/` owns all file I/O (`QuKiStorage`, `QuKiIndex`, `TrashIndex`, `QuKiSearch`). No schema migrations.

### Image handling (ADR-4)

- On paste / share-in: copy bytes to `<app docs>/images/YYYY-MM-DD-{uuid8}.{ext}`; reference in QuKi markdown as `![](../images/{filename})`.
- The `../images/` prefix keeps the markdown portable into a tossed destination (transports may rewrite to whatever path makes sense at the destination).
- Cascade delete on QuKi delete.
- No base64-embed, ever (file bloat + editor perf + unreadable when tossed).

### Deletion (ADR-5, updated by ADR-25)

- User deletes a QuKi from the stream → file moved to `.trash/` subfolder. Hidden from main index immediately.
- Background sweep at user-configurable retention period (default 7 days) hard-deletes `.trash/` files.
- When a sync plugin is active: replace the sweep with sync-aware behavior (queue remote DELETE; hard-delete on ack).

### Logging & privacy (ADR-12)

- `package:logging` with hierarchical per-feature loggers (`quki.editor`, `quki.transport.github_daily_log`, etc.).
- Debug: console handler.
- Release: in-memory ring buffer (last ~500 entries) accessible from Settings → About → Logs (for user-driven bug reports).
- **Never** log: OAuth tokens, plugin secrets, full QuKi bodies.
- **No** analytics, **no** crash reporting, **no** telemetry SDK. Network traffic is whatever individual plugins make; core is offline.

---

## Project Structure

```
quki_notes/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/                  ← Flutter-free except where noted
│   │   ├── storage/           ← file I/O, pure Dart (ADR-25)
│   │   ├── transports/        ← plugin loader + base interfaces, pure Dart
│   │   ├── auth/              ← Device Flow helper (lazy-init by plugins)
│   │   └── settings/          ← shared_prefs wrapper
│   ├── features/              ← Flutter UI per feature
│   │   ├── editor/
│   │   ├── stream/
│   │   ├── onboarding/        ← stub in MVP (drops straight into editor)
│   │   └── settings/
│   ├── ui/                    ← cross-cutting widgets, theme
│   └── shared/
│       └── models/            ← pure Dart data classes (CLI-safe)
├── bin/                       ← future: quki.dart (CLI entry point)
├── android/
├── windows/
├── linux/
├── ios/                       ← scaffold present; not actively built
├── macos/                     ← scaffold present; not actively built
├── test/
│   ├── db/
│   │   └── schemas/           ← drift schema snapshots
│   ├── core/
│   ├── features/
│   └── widget/
├── docs/                      ← VitePress source
├── notes/dev/                 ← this folder (planning, ADRs, manifesto)
├── .github/
│   ├── workflows/             ← ci, build-android, build-windows, build-linux, build-ios (stub), docs, release-please
│   └── release-please.yml
├── pubspec.yaml
├── justfile
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .editorconfig
```

**`lib/core/` and `lib/shared/models/` must remain Flutter-free** per ADR-16 to keep the CLI option open. Flutter imports go in `lib/ui/`, `lib/features/`, `lib/app.dart`, `lib/main.dart`.

---

## Development Phases

| Phase | Goal                                                                   | Status         |
| ----- | ---------------------------------------------------------------------- | -------------- |
| 0     | Bootstrap scaffold (project, CI, docs)                                 | Complete       |
| 1     | Local QuKi capture on Android — editor, stream, drift, auto-save       | Complete (v0.3.0) |
| 2     | Transport plugin loader + built-in QuKi-Tosses + Settings → Tosses     | Complete (v0.5.0) |
| 3     | Polish + share-in + Windows + Linux desktop ports                      | In progress (v0.13.1) |
| 4     | Sync plugin axis (`core/sync/`) + first sync backend (probably GitHub) | v1.1+       |
| 5     | iPadOS / iOS / macOS builds (CI wiring + device QA)                    | Deferred    |
| 6     | MCP plugin axis                                                        | v2.0+       |

### Phase 0 — Bootstrap

See `notes/dev/bootstrap.md`. One PR, scaffold only, no features.

### Phase 1 — Local QuKi capture ✓ Complete (v0.3.0)

Sub-PRs completed in order:

1. **Drift schema v1**: `qukis` + `images` tables + repository providers + migration test scaffold. ✓ Complete (merged)
2. **Editor screen**: blank QuKi on launch, `super_editor`, formatting toolbar (no image button yet). ✓ Complete (merged)
3. **Stream screen**: list view with search; tap-to-edit; swipe-to-delete with undo. ✓ Complete (merged)
4. **Image paste**: `super_clipboard` integration; on-disk image store; markdown rewrite; image rendering in `super_editor`. ⛔ Blocked — `super_clipboard`/CargoKit archived 2026-03-26; permanently deferred until `super_native_extensions` migrates away from CargoKit.
5. **Auto-save controller**: ADR-6 save semantics (2s debounce + 30s periodic + lifecycle hooks); ADR-20 save-on-leave bridge removed. ✓ Complete (merged, v0.3.0)
6. **Settings stub**: theme indicator (system), about page with version, `package_info_plus` for version string. ✓ Complete (merged, v0.4.0)

### Phase 2 — Transports ✓ Complete (v0.5.0)

Delivered as a single PR:

1. **Transport registry + plugin interface**: `lib/core/transports/`; compile-time built-in registry (OQ-NEW-2 resolved — no dynamic loading in v1); ADR-14 contract. ADR-21 documents the Flutter-import exception for `settingsView()`.
2. **ClipboardToss**: copies markdown body to system clipboard. Proves loader + toss-button UX with zero network involvement.
3. **ShareSheetToss**: opens native Android share sheet via `share_plus`. Second built-in toss shipped in the same PR.
4. **Toss UI**: toss button in editor → `TossPickerSheet` bottom sheet → success/failure snackbar; retry offered on retryable failures.
5. **Settings → Tosses**: `SwitchListTile` per plugin; disabled plugins hidden from toss picker. `TransportSettingsNotifier` persists enabled state via `shared_preferences`.

### Phase 3 — Polish + Windows + Linux

Sub-tasks in priority order:

1. **Android share-in** — receive content shared from other Android apps via `receive_sharing_intent`. ✓ Complete (v0.6.0). Text only; multi-part shares joined with `\n\n`; cold-start and warm-start both handled. Images deferred (CargoKit still blocked).
   - Desktop platform guard: `Platform.isAndroid` guard in `lib/features/share_in/share_handler.dart` — no-ops cleanly on Windows/Linux. ✓ Complete (v0.6.2).
2. **Windows + Linux CI** — `build-windows.yml` and `build-linux.yml` produce working artifacts; OQ-NEW-3 resolved (tarball). ✓ Complete (v0.6.1).
3. **Desktop keyboard shortcuts + window-state persistence** — Ctrl+T (toss), Ctrl+N (new); `window_manager` persists bounds via `shared_preferences`; `WindowStateScope` listener saves on move/resize. ✓ Complete (v0.7.0). ADR-22.
4. **Snackbar auto-dismiss + paragraph spacing** — toss result snackbar 2s/4s duration; undo snackbar 4s via explicit `Timer` workaround (Flutter 3.44 + Material 3 bug); stylesheet paragraph padding reduced. ✓ Complete (v0.8.0).
5. **Editor navigation redesign** — `← Stream` and `Toss ▼` removed; top-left QuKis icon (Lucide) + top-right hamburger (≡) with Send…/QuKis/Settings; `TossPickerSheet` title → "Send this QuKi via…"; snackbar copy → "Sent!" / "Send failed"; Settings section "Tosses" → "Transports". ✓ Complete (v0.8.0). ADR-23 (Lucide icons).
6. **Editor single-root architecture** — replaced push-based QuKi loading with `activeQukiIdProvider` (NotifierProvider<String?>); editor is now the permanent root, `StreamScreen` sets the provider and pops; `AutoSaveController.resetForQuki(id:)` switches save target without disposal; share-in routes through provider (no second EditorScreen). ✓ Complete (v0.8.1).
7. **WYSIWYG markdown rendering (OQ-1 / #27)** — live GFM rendering (bold, italic, headings, task lists, code blocks, etc.). ✓ Complete (v0.9.1). Fenced code block rendering deferred per Scott's decision.
8. **Primer DHC color palette (#37)** — replace `Colors.deepPurple` seed with GitHub Primer Dark High Contrast `ColorScheme`. ✓ Complete (v0.9.2, PR #63). Primer LHC for light mode also applied.
9. **Auto-capitalization bug (#32)** — `TextCapitalization.none` on editor IME config. Partially addressed (v0.9.2). #74 (super_editor-specific root cause) closed when super_editor removed. Spell check (#83) and swipe-to-type remain open features — unblocked now that `markdown_live_editor` uses plain `TextField`.
10. **Editor auto-focus + keyboard dismiss** — cursor visible and keyboard raised on Android cold launch; keyboard dismiss button added then later removed (PR #137). Known follow-up: #72 keyboard not always raised on cold launch.
11. **Error handling + code review fixes** — share-in, toss, auto-save wrapped in try/catch; case-insensitive search; `relativeTime` utility extracted. ✓ Complete (v0.9.3, PR #90).
12. **Storage migration + Recently Deleted (#29)** — Drift/SQLite replaced with individual `.md` files (ADR-25); Recently Deleted screen (#29) shipped. ✓ Complete (v0.9.5–v0.9.6, PRs #103–#105).
13. **Replace `super_editor` with `markdown_live_editor` (ADR-26)** — block-flip Typora model in `packages/markdown_live_editor/`. ✓ Complete (v0.10.0–v0.11.0): Stage 1 plain-text foundation, Stage 2 formatting toolbar + list auto-continue, Stage 3 block-flip WYSIWYG, Stage 4 task checkbox tap / cross-block nav / flip animations.
14. **App icon** — QuKi Notes branded icon: Android adaptive, iOS, Windows, Linux. ✓ Complete (v0.12.0–v0.13.0, PRs #124, #126, #128).
15. **Storage location choice + first-launch setup (ADR-27, #134)** — one-time modal on first launch: Filesystem (SAF/directory picker) or App storage. `StorageSetupScreen`, `StorageLocationService`, `file_picker` dep, Settings → Storage section. Not started.
16. **Stream performance** — lazy loading / pagination for large QuKi counts. Defer until a real threshold is hit.
17. **Onboarding** — drops straight to editor; coachmarks deferred unless user testing reveals a need.

#### Share-in: behavior spec

- **Trigger**: another app invokes Android share and the user selects QuKi-Notes.
- **Cold start** (app not running): app launches directly into a new `EditorScreen` with `initialBody` set to the joined shared text.
- **Warm start** (app already open): a new `EditorScreen` is pushed on top of the current screen with `initialBody` set to the joined shared text.
- **Multi-part shares**: all `SharedMediaType.text` items from the intent are joined with `\n\n`. Neither text-only nor URL-only items are stripped — the user sees exactly what was shared and can edit before saving.
- **Auto-save**: shares flow through the same `EditorScreen(initialBody:)` → `AutoSaveController` path as normal QuKis. No special save behavior.
- **Images**: not handled in Phase 3. If an intent includes only images (no text), ignore silently — do not open the editor with empty body.
- **Scope**: Android only. Windows/Linux share-in is Phase 3 stretch at earliest; no platform channel work in this PR.

### Phase 4+ — Sync, iOS, MCP (post-MVP)

Designed-in via the plugin axes. Not specified in detail in this v1 spec.

---

## Local Development Tasks (`just` recipes)

```just
default:
    @just --list

android:
    flutter run -d android
windows:
    flutter run -d windows
linux:
    flutter run -d linux

test:
    flutter test

lint:
    flutter analyze
    dart format --output=none --set-exit-if-changed lib/ test/

gen:
    dart run build_runner build --delete-conflicting-outputs

build-android-debug:
    flutter build apk --debug
build-android-release:
    flutter build apk --release
build-windows:
    flutter build windows --release
build-linux:
    flutter build linux --release

docs:
    cd docs && npm run dev
```

---

## CI / Release

- **`ci.yml`** — every PR: `flutter analyze`, `dart format` check, `flutter test`. Runner: `ubuntu-latest`.
- **`build-android.yml`** — tag `v*`: signed APK + AAB attached to GitHub Release.
- **`build-windows.yml`** — tag `v*`: zipped Windows release build attached.
- **`build-linux.yml`** — tag `v*`: tarball / AppImage attached. (Format TBD at Phase 3 — recorded as OQ-NEW-3.)
- **`build-ios.yml`** — stub, `workflow_dispatch` only, deferred per ADR/CLAUDE.md.
- **`docs.yml`** — push to `main` with paths filter on `docs/**`: VitePress build → GitHub Pages.
- **`release-please.yml`** — `release-type: dart`, `package-name: quki_notes`. Opens / maintains a Release PR as conventional commits accumulate. Merging the Release PR creates the tag → fires build workflows.

---

## Testing Strategy

See `notes/dev/testing.md` for the full doctrine.

Headlines:
- Tests ship **with** the code, every PR. Not deferred to a "polish phase".
- Bug fixes follow regression-test-first: failing test committed first, then the fix.
- Layers: unit (pure Dart logic + services), widget (`super_editor` smoke + toolbar), integration (drift + UI flow), drift migration (per version bump, ADR-8).
- Mock services with `mocktail`. Never mock data classes or drift itself (`NativeDatabase.memory()`).
- No coverage gates.

---

## Manifesto Alignment Audit

QuKi-Notes makes four promises in the manifesto: **velocity**, **open data**, **information-first UI**, and **extensibility**. This section tracks discovered gaps between those promises and the current implementation. It is a living record — resolve an entry by closing the linked issue and noting the version.

### Gaps identified (2026-06-28 review)

#### 1. Open data — file accessibility and uninstall safety

**Gap**: The manifesto promises that QuKis are "plain files the user owns." On Android, the default storage path is app-sandboxed (`getApplicationDocumentsDirectory()`), which means:
- Files are not accessible via any file manager.
- Files are **permanently deleted on uninstall.**

For beta testers reinstalling frequently, this makes every reinstall a data-loss event. The promise is broken at the storage layer, not at the file format layer.

**Priority: Critical — address before open beta.**

**Tracking**: #134 · **Spec**: ADR-27 · **Status**: Specced (phase 3.19), not yet implemented.

---

#### 2. Velocity — keyboard not raised on cold launch

**Gap**: The manifesto promises "open the app → start typing." On cold launch on Android, the soft keyboard is not raised automatically, requiring an extra tap before the user can type. This directly violates the Velocity principle — an extra tap at the moment the app opens is maximum friction at minimum tolerance.

**Priority: High — but not data-critical. Address in phase 3 after #134.**

**Tracking**: #72 · **Status**: Open, not yet scoped for implementation.

---

#### 3. Extensibility — transports are compile-time only

**Gap**: The manifesto promises user-defined destinations. The current transport system (ADR-14) uses a compile-time registry with only ClipboardToss and ShareSheetToss built in. Users cannot add their own transport without forking the codebase and rebuilding. This is a known MVP limitation, not a regression — but the extensibility axis is the load-bearing promise that distinguishes QuKi-Notes from a plain notes app.

**Priority: Medium — deferred to v1.1+ per ADR-14. The transport *architecture* is in place; the user-facing plugin discovery mechanism is not.**

**Tracking**: OQ-NEW-2 (plugin discovery model) · **Status**: Deferred, not yet scoped.

---

### Priority order

| Priority | Gap | Issue | Target |
|---|---|---|---|
| Critical | Open data — uninstall safety on Android | #134 | Phase 3.19 (next) |
| High | Velocity — keyboard on cold launch | #72 | Phase 3, after #134 |
| Medium | Extensibility — transport plugin discovery | OQ-NEW-2 | v1.1+ |

---

## Open Questions

Tracked in `notes/dev/open_questions.md`. Snapshot of what's outstanding at spec time:

- OQ-1: `super_editor` ↔ GFM round-trip fidelity.
- OQ-2: `super_editor` image node integration.
- OQ-3: GitHub OAuth `client_id` distribution (deferred to first plugin that needs OAuth).
- OQ-4: Initial-sync progress UX (deferred to first sync plugin).
- OQ-NEW-1: Which built-in QuKi-Toss ships first?
- OQ-NEW-2: Plugin discovery model — built-in registry only in v1, or pubspec-declared optional packages?
- OQ-NEW-3: Linux distribution format (AppImage vs tarball vs Flatpak vs Snap).
- OQ-NEW-4: Linux + `flutter_secure_storage` keyring availability matrix.

---

## References

- `notes/dev/manifesto.md` — normative philosophy + tonality
- `notes/dev/decisions.md` — ADR-lite log of every locked decision
- `notes/dev/dependencies.md` — approved packages by phase
- `notes/dev/open_questions.md` — unresolved items
- `notes/dev/bootstrap.md` — Phase 0 task list (one-shot)
- `notes/dev/session_protocol.md` — start/end-of-session checklist
- `notes/dev/testing.md` — testing strategy + bug-fix discipline
- `notes/dev/pr_template.md` — PR title format + body template
- `notes/dev/cli_design.md` — working hypothesis for a future CLI
- `notes/dev/dev_env_setup.md` — Scott's Windows 11 setup guide

---

**Last Updated**: 2026-06-28
