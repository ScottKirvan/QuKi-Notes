# Architecture Decision Records

Compact log of every locked decision. Format: **what**, **why**, **rejected alternatives**. Order: most recent first.

When implementation surfaces a need to change one of these, propose an ADR update in the PR rather than deviating silently. New decisions made during implementation must be appended here.

Full detail for every entry lives in `design_spec.md`; this file is the index + rationale.

Normative framing in `manifesto.md` — read that first.

---

## ADR-31: Custom RenderObject + TextInputClient live-preview markdown engine — supersedes ADR-30

**Date**: 2026-07-04

**Superseded**: ADR-30 (`buildTextSpan()` zero-width-hiding, single-buffer model). ADR-30 stays in this log for history — do not implement against it; see its entry below for the "Superseded" note.

**What**: Replace the `TextField` + `TextEditingController.buildTextSpan()` approach entirely with a custom `RenderObject` that implements `TextInputClient` directly, bypassing `EditableText` and `RenderEditable`. The markdown source buffer remains the single source of truth (unchanged principle from ADR-30). A parse pass produces a flat set of elements — headings, list items, checkboxes, bold/italic/code spans, links, images, etc. — each anchored to a source range (`start`, `end` offsets into the buffer). The editor owns its own model-offset ↔ view-offset mapping and paints its own caret, selection highlight, and rendered content; none of this goes through Flutter's `TextPainter`/`RenderEditable` cursor-offset math.

Full technical detail: `notes/dev/design_spec.md` → "Editor rendering engine (ADR-31)". Plain-English walkthrough (motivation, prior failures, accessible explanation of the approach): `notes/dev/live_preview_editor.md`.

**Model**:

- **Reveal/collapse by cursor intersection**: an element whose source range contains the current selection shows its raw markdown source, in place, directly editable. Every other element shows its collapsed/rendered form, which may be an entirely different length and content than its source — a heading loses its `# ` completely and grows in size; a link `[text](url)` shows only `text`; an image `![alt](url)` shows an actual embedded image; a checkbox shows a real glyph. Recomputing which elements are revealed is a cheap intersection test against cached element ranges on every selection change — it does not require a reparse.
- **Reparse on edit, not on cursor move**: a text change re-runs the parse. QuKis are short-form notes; full reparse per keystroke is acceptable. Do not add incremental parsing until profiling proves it's needed.
- **Boundary-reveal cursor movement**: an arrow key that would land the cursor at the boundary of a collapsed element triggers reveal; the cursor lands at the near boundary of the full source text and navigates character-by-character from there. There is no skip-over behavior — every element in QuKi-Notes has editable source, so all elements reveal on boundary entry rather than being skipped atomically. (CodeMirror 6's `atomicRanges` facet skips over truly non-editable decorations; that concept does not apply here.) Exiting the far boundary collapses the element and returns to normal navigation in the surrounding text.
- **Tap-to-boundary hit-testing**: tapping inside a collapsed element's rendered bounds places the cursor at whichever boundary (start or end of its source range) is nearer the tap's x-coordinate — not a fractional offset inside the collapsed content. This matches CodeMirror 6's own behavior; no editor surveyed in research does true sub-collapsed-element interpolation either.
- **Direct IME integration**: the widget implements `TextInputClient`, opens its own `TextInputConnection` via `TextInput.attach()`, and receives `TextEditingValue` updates from the platform IME directly — it does not delegate to `EditableText`.
- **Links**: tapping a rendered link navigates (opens the URL). Reveal-and-edit is triggered by cursor entering the element from the keyboard: arrow-key into it from either side, or backspace into it from the right. Cursor landing at the start or end boundary of the link's source range (e.g., clicking on empty space just past the link, then arrowing in) also triggers reveal — consistent with the boundary rule for all other element types. Rationale: QuKi-Notes is a scratchpad and pastebin as much as a capture surface; following links out of a note is a primary use case (e.g., a parts list with product URLs). Navigate-on-tap matches that use and matches user expectation from every other reading surface. Keyboard-entry is the natural edit path and needs no special gesture. Resolved 2026-07-04 (OQ-6).
- **Images**: always reveal source on tap (no navigate action). No engine limitation blocks rendering an actual image inline once we own painting — we are no longer bound by `WidgetSpan`'s one-character limitation.

**Why**: Research (2026-07-04) confirmed Flutter's `EditableText`/`RenderEditable` stack cannot support this feature at all, at the engine level — not a framework inconvenience we can code around:

- `TextPosition` offsets used for caret placement and hit-testing index directly into the *rendered* `TextSpan`'s flattened plain text, with no reconciliation against `TextEditingController.text`. Nothing enforces or checks that the two match — a mismatch just produces silently wrong caret/selection behavior (flutter/flutter#49860).
- `WidgetSpan` — the obvious tool for embedding a real image or any variable-length rendered content inline — always consumes exactly one UTF-16 code unit of cursor-offset space, confirmed directly by a Flutter engine maintainer in flutter/flutter#107432: "The entire WidgetSpan is treated as a single character by the Flutter engine's text APIs... this mismatch will cause problems for the text editor." This is baked into the text-layout engine itself, not app or framework code, and cannot be patched around from userland. Cursor placement in/around WidgetSpans is separately confirmed broken (flutter/flutter#150864).
- No Flutter package or published project has solved true variable-length live-preview markdown editing on stock `TextField` primitives. `extended_text_field`'s `actualText` field patches serialization only (so copy/paste can reconstruct real markup), not cursor accuracy — same wall.
- ADR-30's "character-count invariant" (rendered `TextSpan` length always equals buffer length) was, in retrospect, not a real design decision but a symptom of `buildTextSpan()`'s constraints — the only trick available within that model, and one that structurally cannot support real rendering. Every attempted fix on top of it (PR #194's list-bullet, checkbox, and ordered-list changes) inherited this same-length constraint and was therefore incapable of correct behavior no matter how carefully implemented — this was a documentation and architecture failure, not an implementation-quality failure.
- CodeMirror 6 (the engine behind Obsidian's Live Preview) solves exactly this problem via an anchored-range decoration model (`Decoration.replace`, `RangeSet`, `atomicRanges`) that never requires rendered and source text to be the same length. This is proven, shipping architecture for exactly this feature — it is just not achievable through Flutter's high-level text-editing widgets, only through a custom render/input layer.

**Rejected alternatives**:
- *Continue patching `buildTextSpan()` (ADR-30)* — cannot support variable-length rendering at all; every fix inherits the same-length constraint. Rejected as a dead end, not merely incomplete.
- *`WidgetSpan`-per-element* — blocked by the engine-level one-character-per-`WidgetSpan` limitation. Would require the same amount of custom offset-mapping work as the chosen approach, while still fighting an engine constraint the chosen approach avoids entirely by not routing through `TextPainter`'s built-in `TextPosition` math at all.
- *Document-model editor (`super_editor`, `flutter_quill`, `appflowy_editor`-style)* — rejected in ADR-26 for markdown round-trip corruption risk (an AST/tree is authoritative, markdown is serialized at the edges), and that risk is unchanged today. The manifesto's open-data requirement (`.md` files are the real data, always) rules this out regardless of rendering sophistication.
- *Accept same-length rendering permanently, ship a lesser feature* — does not meet the actual product requirement (real heading sizes, real link text, real inline images); rejected as insufficient for the app's core value proposition.

**Scope note**: this is a new rendering/input engine, not a patch — build in independently-shippable stages (see `live_preview_editor.md` → "Build stages"), not as one PR. Long-term intent is to extract and publish this as a standalone pub.dev package once proven — no Flutter package currently does this correctly — but that goal must not distort near-term decisions into premature generality. Build for QuKi-Notes's actual needs first.

---

## ADR-30: Single-buffer TextSpan editor — replace block-flip `markdown_live_editor`

**Superseded by ADR-31** (2026-07-04) — the `buildTextSpan()` zero-width-hiding model cannot support variable-length rendering (real heading sizes, real link text, real inline images), which turned out to be a hard Flutter engine-level limitation, not a solvable framework inconvenience. Kept below for history; do not implement against this entry.

**Date**: 2026-07-01

**What**: Replace the block-flip Typora model (one `TextField` per markdown block, flip on tap) with a single `TextField` and a custom `TextEditingController` that overrides `buildTextSpan()` to render markdown inline. The buffer always holds raw markdown; the visual layer interprets it on every paint call.

**Model**: Per-line cursor awareness. The line containing the cursor ("cursor line") shows raw text with syntax characters rendered in `syntaxColor` (visible but muted) — the user sees exactly what they are typing. All other lines ("rendered lines") hide syntax prefix characters via `color: Colors.transparent, fontSize: 0.001` and apply block/inline transforms: headings use `headingStyle`; `- ` and `* ` list prefixes display as `• ` (same 2-char width, cursor alignment preserved); `**bold**` renders bold with transparent `**`; `_italic_` renders italic; `` `code` `` renders in monospace. Character-count invariant: total characters across all returned `TextSpan` children always equals `text.length`, preserving exact cursor offset alignment.

**Why**: The block-flip model cannot support standard OS cross-document text selection — drag handles, double-tap word select, and triple-tap line select all work within a single widget but not across widget boundaries. A QuKi can contain multiple blocks, so drag-selection across blocks was architecturally impossible. The single-buffer model resolves this: the OS treats the entire note as one `TextField`, all selection affordances work without special handling. Secondary benefits: note switching is instant (one `setValue()` call, no block rebuild), the package has a stable public API ready for pub.dev contribution, and the test surface is a pure Dart class (`MarkdownSpanParser`) with no widget tree required.

**Rejected alternatives**:
- *Block-flip (existing)* — architecturally precludes cross-block OS selection; `super_editor` had the same limitation.
- *`super_editor` with selection patches* — `super_editor` owns its own selection model and does not expose Flutter's standard `TextField` selection affordances. Cross-block drag would require implementing the entire OS selection protocol from scratch.
- *`flutter_quill`* — Delta format; not plain-text-in-buffer; round-trips through a custom AST. Open-data principle requires the buffer to be raw markdown.
- *`re_editor`* — code editor oriented; no markdown awareness; would require the same `buildTextSpan()` approach anyway.
- *AST-based rendering* — the `markdown` package provides a GFM AST but does not expose source character offsets, making it impossible to map AST nodes back to buffer positions for cursor-line detection. Regex per-line parsing is sufficient for v1 patterns (headings, lists, bold, italic, code, strikethrough).

---

## ADR-29: Transport plugin system — QuickJS runtime scripting (supersedes compile-time registry)

**Date**: 2026-07-01

**What**: Replace the compile-time transport registry with a runtime plugin system. Plugins are JavaScript files (authored in TypeScript, distributed as compiled `.js`) discovered from a `plugins/` directory in the user's QuKi storage root at app launch. The embedded engine is QuickJS via `flutter_js`. A plugin registers one or more transports by calling a sandboxed Dart-exposed API; the app loads and executes plugin files without recompiling or releasing a new build.

**Plugin model**:

- **Discovery**: on launch, scan `<storage-root>/plugins/*.js`. Each file is executed once; any `QuKi.registerTransport(...)` call it makes is recorded.
- **Hooks per transport**: `onBeforeSend(markdown) → markdown` (transform outgoing content), `onReceive(content) → content` (transform incoming content), `openModal(config) → result` (optional pre-send UI — a Dart-rendered modal driven by plugin-supplied field definitions).
- **Sandboxed API surface** (Dart-exposed to plugin JS scope): `QuKi.registerTransport`, `QuKi.getLocation`, `QuKi.readExif(path)`, `QuKi.showModal(config)`, `QuKi.fetch(url, options)` (explicit network permission per plugin). Plugins cannot read other QuKis, access the filesystem beyond what the API exposes, or call arbitrary platform code.
- **Installation**: user places a `.js` file in the `plugins/` directory using any file manager. No in-app marketplace in v1.
- **Authoring**: TypeScript with a published `@quki/plugin-types` type definition package. Compiled to plain JS before distribution.

**Why**: The compile-time registry satisfied the code structure of a plugin system but not the user promise. Adding a transport requires a code change, a PR, a build, and a release — the user has no agency. The manifesto principle is *user-defined destinations*; the compile-time registry delivers *developer-defined destinations*. QuickJS (via `flutter_js`) runs in AOT release builds on Android and iOS, is ~600KB, supports `async/await`, and has a mature enough API surface for the transform-and-send use case. The Obsidian community — the most likely QuKi-Notes power-user audience — already knows TypeScript, making the authoring story familiar with no new language to learn.

**Rejected alternatives**:
- *Compile-time registry (current)* — not a plugin system; requires recompile to extend. Superseded.
- *Lua* — lighter (~280KB) but unfamiliar to the target audience; no type safety without Teal (which nobody uses); async story is awkward.
- *WebAssembly* — any language compiles to WASM but the host/plugin API boundary is narrow FFI; overkill for text transforms; no mature Flutter embedding.
- *Python (Chaquopy/Pyodide)* — Android-only or 20MB+; iOS is not viable. Cross-platform requirement disqualifies it.
- *MCP only* — MCP requires a running external server process; not suitable for device-local operations (geotag, EXIF). MCP remains the v2 AI-agent axis and is not a replacement for local scripting.

---

## ADR-28: Android filesystem storage via MANAGE_EXTERNAL_STORAGE

**Date**: 2026-06-29

**What**: When the user chooses "Filesystem storage" on Android, request the `MANAGE_EXTERNAL_STORAGE` ("All files access") permission and store QuKis at a fixed well-known path: `<external storage>/Documents/QuKi_Notes/`. No folder picker is shown; the choice is binary (app storage vs filesystem storage), matching the Obsidian model. All file I/O continues to use `dart:io` — `QuKiStorage` is unchanged.

**Behavior details**:

- **Setup modal on Android**: "Filesystem storage" card replaces "Choose a folder" as the second option. Tapping it triggers the Android system permission flow (`Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`). On grant → `StorageLocationService.setPath(externalDocsPath)` → editor opens. On deny → stay on modal (same cancel-stays-on-screen rule as the SAF picker cancel).
- **Fixed path**: `Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).path + "/QuKi_Notes"`. Created on first use if absent.
- **Settings → Storage**: shows "Filesystem storage — /Documents/QuKi_Notes". "Change location" navigates back to `StorageSetupScreen` (the full two-choice modal) so the user can switch to app storage. No custom folder picker in settings.
- **Reinstall**: `MANAGE_EXTERNAL_STORAGE` is revoked by the OS on uninstall (app permissions are cleared). Files remain in `Documents/QuKi_Notes`. On first launch after reinstall, setup modal appears; user picks "Filesystem storage" → grants permission in one system tap → existing notes immediately visible. Not data loss — access loss, which one tap resolves.
- **Desktop (Windows/Linux)**: unchanged — `dart:io` + `file_picker` for optional custom path. No `MANAGE_EXTERNAL_STORAGE` needed (desktop has no scoped storage).

**Implementation notes**:

- Add `MANAGE_EXTERNAL_STORAGE` to `android/app/src/main/AndroidManifest.xml`.
- In `StorageSetupScreen._pickFilesystemStorage()` (Android): check `Environment.isExternalStorageManager()`; if false → launch settings intent and await return via `AppLifecycleState.resumed`; if true → call `setPath(externalDocsPath)` → navigate to editor.
- `externalDocsPath` is resolved in `main.dart` via a Kotlin platform channel call (one method: `getExternalDocumentsPath`) or via the `path_provider` package's `getExternalStorageDirectory()` + `Documents/QuKi_Notes` suffix.
- `StorageLocationService` is unchanged in structure — still stores a file path. `isAppStorage` logic unchanged.
- `file_picker` is no longer used on Android at all; the dependency stays for desktop. Guard all `file_picker` calls with `!Platform.isAndroid`.
- Google Play declaration: select "File manager or browser" as the use-case category; justify with "QuKi-Notes stores user notes as plain .md files in a user-chosen location accessible to file managers and sync tools."

**Why**: `MANAGE_EXTERNAL_STORAGE` is the only mechanism that gives `dart:io`-compatible access to shared external storage on Android 11+. Scoped storage alternatives (SAF DocumentFile API, MediaStore) require entirely different I/O APIs — a complete reimplementation of `QuKiStorage` with no material UX benefit. The open-data manifesto requires notes to be user-accessible outside the app; app-only storage violates this. Obsidian uses this same permission for the same reason. Closed-beta users who reinstall frequently are the primary audience; the one-tap re-grant is acceptable friction; actual data loss is not.

**Rejected alternatives**:
- *SAF + DocumentFile API* — correct for general use but requires reimplementing all file I/O, has no simpler UX (still needs one user tap), and is significantly more code and test surface.
- *SAF + dart:io path conversion* — what ADR-27 originally implemented; unreliable on modern Android; notes silently disappear on restart. Rejected as broken.
- *`getExternalFilesDir()`* — cleared on uninstall; not acceptable.
- *`file_picker.getDirectoryPath()` + `dart:io`* — same as SAF+path conversion; broken on Android 10+ scoped storage.
- *Custom folder picker* — adds complexity and UX friction with no benefit over a fixed well-known path for the target use case.

---

## ADR-27: Storage location — first-launch modal, SAF or app storage

**Date**: 2026-06-28

**What**: On first launch, before the editor appears, show a one-time setup modal with two choices:

1. **Filesystem storage** — user-chosen folder via the platform's native directory picker (SAF on Android; native dialog on Windows/Linux). Files stored there survive uninstall and are accessible via file manager without opening the app.
2. **App storage** — standard sandboxed app documents directory (`getApplicationDocumentsDirectory()`). Files are private to the app and deleted on uninstall.

The choice is saved to `shared_preferences`. The modal never appears again. The editor opens immediately after.

**Behavior details**:

- **"Filesystem storage" chosen**: native directory picker opens (SAF on Android, native dialog on desktop). User picks folder → path saved → editor opens. If the user cancels the picker, return to the modal — do not fall back silently to app storage.
- **Modal dismissed without choosing**: app storage is used; `storage.location_chosen = true` saved to prefs so the modal does not reappear; persistent warning shown in Settings → Storage.
- **Settings → Storage** (always accessible): shows current storage path. "Change location" button reopens the picker. On change, new QuKis go to the new path; existing files remain in the old location. A note in Settings explains this. No automated migration in v1.
- **App storage warning**: shown as a subtitle in Settings → Storage — "Files will be removed on uninstall. Change location." Always visible when app storage is active; not a one-time dismissible toast.
- **Subsequent launches**: path read from `shared_preferences`; `QuKiStorage` initialized with that path. No modal.

**Implementation notes**:

- New `shared_preferences` keys: `storage.base_path` (resolved absolute path), `storage.location_chosen` (bool — suppresses modal on subsequent launches).
- `QuKiStorage` base directory injected at construction time (read from `StorageLocationService`) rather than hardcoded.
- New `StorageLocationService` in `lib/core/storage/` — reads/writes prefs, exposes `isFirstLaunch()`, `basePath`, `setPath(String)`, `isAppStorage` (comparison against `getApplicationDocumentsDirectory()`).
- New `StorageSetupScreen` in `lib/features/setup/` — shown as the app home when `isFirstLaunch()` is true; navigates to `EditorScreen` after choice is saved.
- New dependency: `file_picker` — cross-platform directory picker; SAF on Android, native dialogs on Windows/Linux. Also supports iOS (Files.app) so no code changes will be needed when iOS builds are enabled.

**Why**: The manifesto promises "you can read, copy, or move [QuKis] without opening the app." App storage violates this on Android — files are inaccessible via file manager and deleted on uninstall. This is especially acute during beta when testers reinstall frequently. The first-launch modal ensures users make an informed choice rather than being silently locked into an unsafe default.

The modal appears before the editor, which adds one step to first launch. This is acceptable: (a) it happens exactly once; (b) the manifesto's velocity intent applies to the ongoing capture experience, not a one-time setup; (c) silently defaulting to app storage causes data loss.

**Rejected alternatives**:
- *`getExternalFilesDir()` as a third option* — accessible via USB but still deleted on uninstall; relevant only to developers, not users.
- *Three-option modal* — unnecessary complexity for no user benefit.
- *Silent default to app storage* — testers lose notes on reinstall; violates manifesto open-data promise.
- *Trigger picker on first save* — interrupts the capture flow with a dialog; worse than a one-time setup step before the editor.
- *Migration on location change* — deferred to v1.1+; files are plain markdown and user-moveable manually.

---

## ADR-26: Replace `super_editor` with `markdown_live_editor` — Typora block-flip model

**Superseded by ADR-30** (2026-07-01), itself superseded by ADR-31 (2026-07-04) — the block-flip rendering model was replaced by single-buffer `buildTextSpan()`, now replaced again by a custom RenderObject/TextInputClient engine. The package structure, extraction rationale, and rejection of document-model editors below remain valid; only the rendering mechanism changed.

**Date**: 2026-06-15

**What**: Remove `super_editor` entirely. Extract the replacement editor as a standalone Flutter package (`packages/markdown_live_editor/`) within this monorepo, consumed by the app as a path dependency. The package implements a block-by-block flip model: each markdown block is rendered via `flutter_markdown` when idle; tapping switches it to a raw `TextField`; unfocusing re-renders it. A plain-text mode toggle (via `MarkdownEditorController`) collapses the whole note to a single `TextField` of raw markdown. The canonical data is always the raw markdown string — no intermediate document model exists anywhere in the stack.

**Why**: `super_editor` is a dev-preview library (`0.3.0-dev.51`) that interposes a document model between the user's text and the `.md` file on disk. That model's markdown serializer/deserializer is unreliable: mixed list types (task + bullet + numbered) corrupt on round-trip, blank lines are stripped, Windows cursor was invisible by default, Android controls leaked to other platforms. Every fix broke something adjacent. The manifesto requires that `.md` files are clean, human-readable plain text — `super_editor` violates this at the data layer. The block-flip model eliminates the serializer entirely: the `TextField` content IS the stored markdown, character for character.

The editor is extracted as a package rather than left as a feature module because (a) the Dart package system enforces the boundary — it cannot accidentally import QuKi business logic — and (b) no reliable lightweight Typora-model editor exists in the Flutter ecosystem; this fills a genuine gap and can be published to pub.dev if it proves solid.

**Package structure**:
```
packages/markdown_live_editor/
├── lib/
│   ├── markdown_live_editor.dart      ← public barrel export
│   └── src/
│       ├── markdown_editor.dart       ← MarkdownEditor widget (main entry point)
│       ├── markdown_block.dart        ← single block: render↔edit flip
│       ├── block_splitter.dart        ← splits/joins raw markdown ↔ block list
│       ├── editor_config.dart         ← MarkdownEditorConfig (feature flags + styles)
│       └── editor_controller.dart     ← MarkdownEditorController (plain-text toggle, value access)
├── test/
│   ├── block_splitter_test.dart
│   └── markdown_block_test.dart
└── pubspec.yaml                       ← depends on flutter + flutter_markdown only
```

**Public API**:
```dart
// Main widget — drop-in for a text editor
MarkdownEditor({
  required String initialValue,
  ValueChanged<String>? onChanged,
  MarkdownEditorController? controller,
  MarkdownEditorConfig config = const MarkdownEditorConfig(),
  FocusNode? focusNode,
  bool autofocus = false,
})

// Controller — held by the host (EditorScreen)
class MarkdownEditorController {
  bool get plainTextMode;
  void togglePlainTextMode();
  String get currentValue;         // read current markdown without waiting for onChanged
}

// Config — which markdown features to render
class MarkdownEditorConfig {
  final bool enableHeadings;        // # ## ###
  final bool enableBold;            // **x**
  final bool enableItalic;          // _x_ *x*
  final bool enableStrikethrough;   // ~~x~~
  final bool enableUnorderedLists;  // - *
  final bool enableOrderedLists;    // 1. 2.
  final bool enableTaskLists;       // - [ ] - [x]
  final MarkdownStyleSheet? styleSheet;  // passed through to flutter_markdown
  final TextStyle? textStyle;            // applied to TextFields in edit mode
}
```

Anything not in the enabled set (code blocks, blockquotes, tables, HTML) is rendered as raw markdown text — not interpreted, not stripped.

**Markdown subset rendered by QuKi-Notes** (via `MarkdownEditorConfig`):
- Headings, bold, italic, strikethrough, unordered lists, ordered lists, task lists — all enabled.
- Code blocks, blockquotes — disabled; render as raw markdown text so pasted code is never corrupted.

**Block splitting rules**:
- Blocks delimited by blank lines (`\n\n`).
- Contiguous list lines (`-`, `*`, `1.`–`9.`, `- [ ]`, `- [x]`) grouped into one block regardless of blank lines between items.
- Headings always their own block.
- Everything else split on double-newline.

**Keyboard behaviour**:
- Enter at end of a non-list block → new empty block below, focus moves there.
- Enter inside a list block → `TextField` native newline (stays in block).
- Backspace at position 0 of a block → merge with block above, cursor at join point.

**Plain-text mode**: `MarkdownEditorController.togglePlainTextMode()` collapses the whole note into one `TextField`. Useful for bulk edits or pasting complex content. The file on disk is identical in both modes.

**Dependencies removed from app**: `super_editor`, `super_clipboard`. **Package dependencies**: `flutter` SDK + `flutter_markdown` + `lucide_flutter` (ADR-23 — Lucide is the project icon standard). App adds `markdown_live_editor` as a path dep.

**Files removed from app**: `lib/features/editor/markdown_inline_reactions.dart`, `lib/features/editor/formatting_toolbar.dart`. **Files changed**: `editor_screen.dart` rewritten around `MarkdownEditor` + `MarkdownEditorController`; plain-text toggle moves to app-bar action.

**Rejected alternatives**:
- *Continue with `super_editor`* — data corruption at the storage layer is a hard blocker.
- *`appflowy_editor`* — same document-model problem, different API.
- *`flutter_quill`* — Delta format; markdown is bolted on.
- *Inline feature module* — no enforced boundary; editor could couple to QuKi internals.
- *Separate repo immediately* — extra CI/release overhead before the design is proven; monorepo path dep is lower friction and extractable later.
- *Split-pane edit/preview* — wastes screen space on mobile.
- *Full-note `TextField` only* — viable fallback; block-flip costs little extra and gives rendered output with zero round-trip risk.

**Staged implementation** — each stage is an independently shippable PR:

| Stage | What ships | Key milestone |
|---|---|---|
| 1 | `packages/markdown_live_editor/` scaffolded; `MarkdownEditor` wraps a single `TextField`; `super_editor` removed | Data corruption eliminated; plain markdown in, plain markdown out |
| 2 | Wrap-selection toolbar (bold, italic, strikethrough, heading prefix); auto-continue lists on Enter; task toggle button | Editing feel without rendering |
| 3 | `block_splitter.dart` + `markdown_block.dart`; idle blocks render via `flutter_markdown`; plain-text toggle functional | Full block-flip WYSIWYG |
| 4 | Task checkbox tappable in rendered mode; cross-block keyboard navigation; flip animations | Polish |

Stage 1 is the critical delivery — it eliminates data corruption. Stages 2–4 are enhancements on a working foundation.

---

## ADR-25: Storage backend — individual `.md` files, supersedes implicit SQLite choice

**Date**: 2026-06-14

**What**: Replace Drift/SQLite with individual `.md` files stored in the app's documents directory. One file per QuKi, named `{uuid}.md`. `createdAt` stored in a `.meta/{uuid}.json` sidecar (SQLite cannot provide filesystem `mtime`; Android `dart:io` cannot provide file creation time reliably). `modifiedAt` is the filesystem `mtime` — only changes when the file is actually written. Recently Deleted = `.trash/` subfolder; user empties or restores manually, no timer. Search = file content scan at query time. In-memory `List<QuKiMeta>` index rebuilt on app start and updated synchronously on every write/delete.

**Why**: The manifesto's open data principle says QuKi data must be directly accessible to a non-technical user as plain files — SQLite satisfies the letter but not the spirit. More concretely, SQLite introduced a class of bugs (modifiedAt bumped on open, #75, two failed fix attempts) that do not exist when `mtime` is the single source of truth for modification time. With files, you write when content changes; `mtime` reflects that automatically.

**Structure**:
```
<app-documents>/qukis/
  {uuid}.md          ← QuKi body, plain markdown
  .meta/
    {uuid}.json      ← {"createdAt": "2026-06-14T17:00:00.000Z"}
  .trash/
    {uuid}.md        ← soft-deleted; user restores or hard-deletes
    .meta/
      {uuid}.json
```

**Rejected alternatives**:
- *Continue with SQLite + timing workarounds* — violates manifesto, #75 already had two failed fixes.
- *SQLite + mirror mtime into DB on every save* — two sources of truth, fragile.
- *Timestamp-embedded filename* (`{created}-{uuid}.md`) — createdAt is immutable in the name but filenames become opaque and parsing timestamps from names is fragile.
- *Single index file* (`index.json`) — single point of failure, write contention, recreates DB problems.
- *Parallel SQLite index alongside .md files* — two sources of truth; defeats the purpose.

**Consequences**: Drift, `sqlite3_flutter_libs`, and `build_runner` drop out of the dependency tree. All schema migrations are eliminated. `lib/core/database/` is replaced by `lib/core/storage/`. `AutoSaveController` simplifies — debounce still useful to avoid thrashing disk, but `mtime` is now truth so no guard flag needed. `modifiedAt` bug (#75) is eliminated by design.

---

## ADR-24: Inline markdown input reactions — custom `EditReaction` subclasses

Live inline conversion (typing `**bold**` → bold span, `_italic_` → italic span, `` `code` `` → code span, `- [ ] ` → task node) is implemented as custom `EditReaction` subclasses registered after `defaultEditorReactions` in the `Editor.reactionPipeline`.

**Approach**: each reaction watches `changeList` for the closing delimiter character, scans the current node's plain text for a matching opening delimiter, strips both delimiters via `DeleteContentRequest`, and applies the attribution via `AddTextAttributionsRequest`. No new dependencies — all types are public exports from `super_editor`.

**Task list edge case**: `- ` triggers `UnorderedListItemConversionReaction` first, converting the paragraph to a `ListItemNode`. `TaskListMarkdownReaction` therefore watches for a `ListItemNode` with content `[ ] ` (the remainder after `- ` is stripped) and replaces it with `TaskNode` via `ReplaceNodeRequest`.

**`createDefaultDocumentEditor` not used**: that factory hardcodes `List.from(defaultEditorReactions)` with no injection point. Both `EditorScreen` `initState` and `_switchDocument` now build the `Editor` directly using `[...defaultEditorReactions, ...customReactions]`.

**Rejected**: patching `createDefaultDocumentEditor` at the super_editor source level (fragile across upgrades); replacing the entire editor with appflowy_editor (unnecessary — super_editor's reaction API is sufficient).

## ADR-23: Icon library — Lucide (`lucide_icons`)

Flutter's bundled `Icons` class covers the classic Material Design set. Material Symbols (the newer Google icon set) is not bundled and requires a separate package. Lucide was chosen instead: it is MIT-licensed, has a consistent stroke-based aesthetic that matches the app's clean visual intent, and the `lucide_icons` pub.dev package covers the full Lucide catalogue.

- **What**: `lucide_flutter ^1.17.0` added to `dependencies`. Font-based (not SVG), works with the standard `Icon()` widget. All app-bar and navigation icons in `lib/features/editor/editor_screen.dart` use `LucideIcons.*`; other screens may migrate incrementally. (`lucide_icons` was tried first but is incompatible with Flutter 3.29+ — `LucideIconData extends IconData` fails since `IconData` became `final`.)
- **Why**: Scott's explicit preference. Lucide's stroke style is cleaner than Material's filled defaults for this app's aesthetic. `Icons.*` remain available for anything not yet migrated.
- **Rejected**: `material_symbols_icons` (Google's newer set, heavier package); Lucide-via-SVG assets (requires custom rendering, no `Icon` widget compatibility); staying with `Icons.*` (Scott rejected).

---

---

## ADR-22: Window-state persistence — `window_manager`

Desktop (Windows + Linux) opens at the OS default size and position every launch. Persisting the last-used size and position improves the daily-driver desktop experience.

- **What**: `window_manager ^0.5.1` added to `dependencies`. On launch (`main()`, before `runApp`), restore saved `{x, y, width, height}` from `shared_preferences`. `WindowStateScope` widget (mounted at app root) listens via `WindowListener` and persists bounds on `onWindowMoved`, `onWindowResized`, `onWindowClose`.
- **Why**: `window_manager` is the Flutter ecosystem standard for desktop window control. No platform-side C++ modifications needed at 0.5.x — `windowManager.ensureInitialized()` in Dart is sufficient.
- **Rejected**: Raw platform channels (higher maintenance burden; `window_manager` already wraps them correctly for both targets).
- **Scope**: Windows + Linux only. Android branch skipped via `Platform.isWindows || Platform.isLinux` guard. iOS/macOS deferred per manifesto platform priority.
- **Keys in `shared_preferences`**: `window.x`, `window.y`, `window.width`, `window.height` (all `double`). Keys absent on first launch → OS chooses position.
- **Save timing**: `onWindowMoved` / `onWindowResized` use the `*d` (post-gesture) variants so SharedPreferences is not written on every drag pixel.

---

## ADR-21: Flutter import allowed in `lib/core/transports/` (settingsView exception)

The `TransportPlugin` interface defines `settingsView(WidgetRef ref) → Widget` as part of its contract so that each plugin can provide its own configuration UI shown in Settings → Tosses. This requires importing `package:flutter/material.dart` and `package:flutter_riverpod/flutter_riverpod.dart` in `lib/core/transports/transport_plugin.dart`, which technically violates the ADR-16 Flutter-free constraint on `lib/core/`.

- **What**: `lib/core/transports/` is the one approved exception to the ADR-16 Flutter-free rule. All other `lib/core/` subdirectories (`database/`, `auth/`, `settings/`) remain Flutter-free.
- **Why**: Keeping `settingsView` in the plugin contract (rather than in a separate Flutter-side adapter) avoids a three-way dependency between the plugin, the core registry, and a feature-layer adapter for every plugin ever added. The CLI (ADR-16) uses only `toss()` and can simply ignore `settingsView()` — it is never called by non-Flutter hosts.
- **Rejected**: A separate `TransportPluginUI` mixin in `lib/features/` that Flutter hosts mix in alongside the core interface — adds indirection with no practical benefit for the single-developer, single-codebase scenario; revisit if a headless server deployment is ever a real target.
- **Scope**: only `lib/core/transports/`. The rest of `lib/core/` and all of `lib/shared/` remain Flutter-free per ADR-16.

---

## ADR-20: Save-on-leave bridge (Phase 1.3) → superseded by Phase 1.5 auto-save

Phase 1.3 (stream screen) requires content to appear in the list after the user types something in the editor. Full auto-save (ADR-6 debounce + lifecycle) lands in Phase 1.5. A minimal "save when the user explicitly navigates away" bridge was added to `EditorScreen` for Phase 1.3 so the stream is testable.

- **What**: `_saveIfNeeded()` fires when the user taps `← Stream`. First call on a new QuKi inserts a row; subsequent calls update it (tracked via `_savedQukiId` state).
- **Not triggered by**: hardware back button (known limitation; Phase 1.5 fixes this).
- **Superseded by**: Phase 1.5 auto-save controller (2s debounce + 30s periodic + lifecycle hooks). When Phase 1.5 lands, `_saveIfNeeded()` and `_savedQukiId` are removed and replaced by the controller.
- **Rejected**: pre-creating an empty row in `_openNew()` — produces permanent `(empty)` entries when the user abandons without typing.

---

## ADR-19: Privacy & device permissions — three-gate opt-in, capability-aware

Device-backed enrichments (GPS, future: camera, microphone, contacts, calendar) are never requested unless ALL three gates are ON:

1. **Device capability gate** — if the platform doesn't expose the capability (e.g. GPS on a desktop Windows tower without a Bluetooth GPS), the field is omitted from `TossContext` and the corresponding setting is hidden. No "this feature requires a device with GPS" toast; the affordance simply does not exist.
2. **App-wide setting gate** — `Settings → Privacy` exposes one toggle per capability: "Allow transports to request GPS" (etc.). **Default OFF** for every capability. Onboarding does NOT ask about these; the app boots into a blank QuKi and any later toss that would need permission is what surfaces the prompt.
3. **Per-transport setting gate** — each transport that wants the capability declares it in its `settingsView`; the user opts in per transport. Only when all three gates are ON does the OS permission dialog appear, and only on the **first fire** of a transport that needs the capability.

**Implications:**

- A user can install a "GitHub Daily Log with GPS" transport, leave the app-wide GPS toggle OFF, and the transport's GPS feature is silently disabled (toss still works, no GPS in the appended payload). The transport's `settingsView` shows a hint: "GPS is disabled in app Privacy settings."
- A user who turns ON app-wide GPS but doesn't enable it for a specific transport gets the same result for that transport.
- Permission revocation at the OS level is treated as "capability gate OFF" — graceful, no nag.
- The OS permission dialog appears at first toss-with-permission, not at install time and not at onboarding. **Capture is never gated by a permission dialog.**

**Rejected:**
- Asking for permissions at onboarding (violates frictionless-capture; primes the user with a security prompt before they've typed a word).
- Default-on for any device capability (privacy posture — the user must consciously opt in).
- A single app-wide "Enable all transport capabilities" toggle (too coarse; defeats per-transport intent).

**Why this matters specifically:** the manifesto says capture must be frictionless. A permission dialog at any point between "tap app icon" and "cursor in editor" is friction. This ADR makes that contract enforceable.

## ADR-18: MVP scope — local-only, transports built in, no sync, no MCP

- **MVP = v1.0 = local-only capture + at least one transport plugin.** No GitHub sync. No MCP.
- Sync is **opt-in** and ships as a **plugin axis**, not as a core feature. Skeleton (`lib/core/sync/`) lands with the first sync plugin in v1.1+, not in MVP.
- MCP is reserved as a third plugin axis, documented in the spec, but **no code lands** until v2.0+.
- Single-user default: install the app, write QuKis, toss them, done. No accounts, no auth, no cloud round-trips required to use it.
- **Rejected**: ship-with-GitHub-sync-as-the-defining-feature (couples MVP to OAuth + rate limits + conflict UX — slows v1 by months; and overstates QuKi's actual job, which is capture-and-dispatch, not durable storage).
- **Why this matters**: prevents Phase 2 (sync) from being scoped into Phase 1; prevents transport plugins from accidentally depending on sync primitives.

## ADR-17: Sync as an opt-in plugin axis (not a core feature)

- "Sync" is **one of three plugin axes** (transports, sync, MCP) — not a feature baked into core.
- The sync API is `SyncBackend` (interface): pull-changes(since: timestamp) → list of QuKi diffs; push-changes(list) → ack/conflict.
- **GitHub is one possible sync backend**, not privileged. Others on the long list: S3-compatible buckets, WebDAV, local filesystem (Syncthing-paired folder), Dropbox, raw HTTP webhook target.
- Off by default. Users in Settings → Sync can install/enable a sync plugin.
- **Conflict resolution** is sync-plugin-specific. The GitHub sync plugin uses SHA-based conflict detection (former ADR-6 behavior); other backends choose their own.
- **Rejected**: GitHub-as-the-only-sync (locks ~95% of users out who don't want GitHub for personal scratch notes); generic "sync engine" with adapters (over-engineered — let each plugin be opinionated).

## ADR-16: CLI lives in the same repo, sharing the core library

- CLI is a **future Dart console app** under `bin/quki.dart` sharing the core library at `lib/core/` and `lib/shared/models/`.
- Core library MUST remain Flutter-free. Anything `import 'package:flutter/...'` lives under `lib/ui/` or `lib/features/`.
- CLI **not** built in MVP. This ADR locks the architectural constraint so the MVP doesn't paint into a corner.
- **Rejected**: separate `packages/quki_core` + `packages/quki_cli` melange (premature monorepo split); CLI as a feature flag in the Flutter app (UX confusion + binary size).
- Working hypothesis: `cli_design.md`.

## ADR-15: Ephemerality model — Gmail-style, no auto-delete

- QuKis are **framed** as ephemeral via UI affordances (newest-first stream, no folders, no tagging) but **persisted forever** locally by default.
- Search exists for recall but is not promoted to a primary organization tool.
- A tossed QuKi is **copied**, not moved — the local QuKi remains in the stream.
- User-initiated delete is the only deletion mechanism. No auto-archive, no expire-after-N-days in MVP.
- **Rejected**: hard auto-delete after N days (data loss surprise); explicit archive folder (folders are vault behavior — ADR-15 forbids it); soft delete that hides from stream but keeps DB row (already covered by ADR-5 mechanically; the UX-level intent is "deleted means gone from the user's mental model").
- **Why**: the friction of organising is what makes vaults heavy. The framing of "ephemeral but searchable" is what keeps QuKis weightless without surprising the user with data loss.

## ADR-14: Plugin architecture — three independent axes, Dart-only

- QuKi-Notes exposes **three plugin axes** with separate lifecycles and interfaces:
  - **Transports** (a.k.a. **QuKi-Tosses**): take (text, [images]) → success/failure. Stateless per fire. Multiple may exist; user picks at toss time.
  - **Sync backends**: bidirectional QuKi diff transport across this user's devices. At most one active at a time per ADR-17.
  - **MCP servers**: expose QuKi-Notes state (list/read/append/toss) to AI agents via Model Context Protocol. v2.0+.
- All plugins are **Dart-only**. No JS/TS, no native bindings, no embedded interpreters. (Obsidian gets a glue **TypeScript** plugin that talks to a Dart-shaped QuKi-Notes HTTP/IPC endpoint — that glue lives in its own repo and is out of scope for QuKi-Notes core.)
- Plugin manifests + UI registration through `lib/core/transports/`, `lib/core/sync/`, `lib/core/mcp/` respectively.
- **Transport interface (MVP)** — drives Phase 2:
  ```dart
  abstract class TransportPlugin {
    String get id;
    String get displayName;
    String get description;
    Widget settingsView(WidgetRef ref);  // configuration UI

    Future<TossResult> toss({
      required String markdown,
      required List<Image> images,
      required TossContext ctx,
    });
  }

  class TossResult {
    final bool success;
    final String? message;     // user-facing detail
    final bool retryable;      // hint for UI
  }

  class TossContext {
    final DateTime firedAt;              // when toss was triggered
    final QukiMetadata quki;             // id, createdAt, modifiedAt — for templating
    final Geolocation? gps;              // null unless all GPS gates ON (ADR-19)
    final Map<String, String> userOverrides;
  }
  ```
- **`List<Image>`, not `List<Attachment>`** — deliberate. A QuKi is GFM markdown, which renders text + images. Generalising to "attachments" (PDFs, videos, archives) violates the manifesto's ephemeral/frictionless framing — a QuKi hauling a 50MB MP4 isn't a QuKi anymore. Revisit only if a concrete use case forces it.
- **`TossContext.firedAt` vs `TossContext.quki.createdAt`** — distinct on purpose. `firedAt` is when the toss button was pressed; `quki.createdAt` / `quki.modifiedAt` are properties of the QuKi itself. Transports may template either (e.g. an "append to daily log" toss uses `firedAt`; a "publish to wiki" toss may use `quki.createdAt` for backdated entries).
- **`TossContext.gps`** is opt-in at multiple gates per **ADR-19**; nullable in the type so transports must always handle absence.
- **Rejected**: a single "workflow JSON DSL" living in a repo (was the original ADR-7 framing — see deprecation notice on ADR-7); embedding a scripting language (Lua/JS) for user-authored transports (security + maintenance burden); shipping a "marketplace" UI (premature); a generic `List<Attachment>` (see images note above).

## ADR-13: Testing discipline — tests with code, regression tests for fixes

- **Tests ship with code, every PR.** No "tests come later in Phase 4" — that line is removed from the design_spec.
- **Bug fixes follow strict regression-test-first discipline**: write a failing test that reproduces the bug, commit it, then write the fix. The test stays in the suite permanently.
- Layers: unit (pure logic + services), widget (stateful UI), integration (DB + UI flows), drift migration (schema verification).
- Mock services with `mocktail`; never mock data classes or drift itself (use `NativeDatabase.memory()`).
- No coverage threshold — perverse incentive. PR review asks "where's the test?" instead.
- Flaky tests: zero tolerance. Tag and fix immediately; do not let them accumulate.
- **Rejected**: deferred testing (lets bugs land + locks in untestable architectures); coverage gates (incentivizes noise tests); mocking the database (couples tests to ORM internals).
- Full operational detail: `notes/dev/testing.md`.

## ADR-12: Theme / Logging / Privacy posture

- **Theme**: follow system (`ThemeMode.system`); ship light + dark in v1; no manual override in MVP.
- **Logging**: `package:logging`; console in debug, in-memory ring buffer in release; per-feature hierarchical loggers; sensitive data never logged.
- **Privacy**: no analytics, no crash reporting, no telemetry. Network limited to `github.com` / `api.github.com`.
- **Rejected**: Sentry/Crashlytics/Firebase (privacy posture; revisit only if distribution broadens).

## ADR-11: Rate limiting & lazy image download (sync-plugin scope)

- **Applies only when a sync plugin is active** (v1.1+). MVP has no rate-limit considerations because nothing leaves the device until the user tosses.
- GitHub sync plugin: GitHub auth limit 5,000 req/hr; throttle when `X-RateLimit-Remaining < 100`. QuKis pulled newest-first; **images lazy-fetched** on first view (row inserted with `localPath = null`).
- **Why lazy for images**: QuKi bodies are KB-sized, images can be MB each; bulk image pull would burn bandwidth + rate budget for files the user may never view.
- Per-transport rate-limit behavior is the **transport plugin's responsibility**, not core's.

## ADR-10: Cross-device timestamps on pull (sync-plugin scope)

- **Applies only when a sync plugin is active.** MVP keeps `createdAt` / `modifiedAt` purely local with sub-second precision.
- Sync plugin contract for a remote-only QuKi pulled to this device: generate fresh local UUID for `id`; capture remote-identifier (e.g. `githubPath`) verbatim in a plugin-owned field; `createdAt` = derived from remote metadata (filename date prefix + `00:00:00` local for the GitHub plugin); `modifiedAt` = pull time.
- Sub-day precision loss on cross-device round-trip is acceptable for the first sync plugin; revisit if it bites.
- **Rejected**: YAML frontmatter (commits us to non-empty file content schema and adds parsing); extra `GET /commits` per file (rate-limit cost).

## ADR-9: OAuth (deferred to sync / transport plugins)

- **No OAuth in MVP** — nothing in core needs to call an authenticated service. Local-only.
- When the GitHub sync plugin or any GitHub-flavoured transport ships, it uses **GitHub Device Flow** with `client_id` only (public client, no secret).
- Scopes for the GitHub sync plugin: `repo`, `read:user`. Transport plugins request their own minimum scope (e.g. an "append to issue" transport may need only `public_repo`).
- Common helper code (device-flow dance + `flutter_secure_storage` round-trip) lives in `lib/core/auth/` so multiple GitHub-aware plugins share it without reimplementing the flow.
- **Rejected**: PKCE-per-platform via `flutter_appauth` (platform-specific URL scheme registration; Windows + Linux support immature); raw client-secret flow (cannot keep secret in a client app).

## ADR-8: Drift migration discipline

- Integer `schemaVersion` + `MigrationStrategy.onUpgrade`.
- Schema snapshots committed under `test/db/schemas/`; verified via `drift_dev schema verify`.
- Every version bump = a migration test that runs the upgrade against the prior snapshot.
- v1 = `qukis` + `images` (Phase 1, single-device, no sync columns yet — sync columns added in the version bump that lands the first sync plugin).
- **Why**: drift migrations are manual; without a snapshot test, additive changes silently work and destructive changes silently break.
- **Superseded fragment**: earlier wording mentioned a `workflows` table (workflow-as-data). With workflow JSON dropped per ADR-14, no such table exists. Transport plugin configuration lives in plugin-owned tables/prefs, not in a global registry.

## ADR-7: Workflow target SHAs — always re-fetch  ⚠️ DEPRECATED

**Superseded by ADR-14** (transport plugins replace JSON workflow DSL) and **ADR-17** (sync is a plugin axis, not a built-in).

Original framing (workflows as JSON files in GitHub doing read-modify-write append) is gone. The behavior it described — "fetch latest SHA before each PUT to avoid 409" — is now a **per-transport-plugin implementation detail** for any GitHub-flavoured transport (e.g. an "append to daily log" toss). Plugins that need this pattern should follow it; the core app does not enforce it generically.

Retained as a historical note so future Claude doesn't think we forgot about the 409 retry pattern when implementing a GitHub-append transport.

## ADR-6: Save vs Push — separate concerns (MVP: save only)

- **Save** (local SQLite): 2s idle debounce + 30s periodic + lifecycle `inactive`/`paused`/`detached`. Never blocks, never networks.
- **Push** (sync plugin): NOT IN MVP. When the first sync plugin lands (v1.1+), it uses the same debounce + manual button pattern: 2s idle + foreground + manual sync only; periodic/lifecycle saves do **not** trigger push.
- **Toss** (transport): user-initiated, never automatic. Pressing a QuKi-Toss button is the only way a QuKi leaves the device. No auto-toss in MVP.
- **Why**: protects against long-typing-run data loss without networking. Max unsaved window ≈ 30s. Sync is a separate, deferred axis (ADR-17).

## ADR-5: Deletion model — Recently Deleted with user-configurable retention

- `qukis.deletedAt` nullable column. Set on user delete; row hidden from main QuKis list queries immediately.
- **Recently Deleted screen**: shows soft-deleted QuKis newest-first for the retention period. This is **data recovery**, not organization — no sort, filter, or filing within it.
  - Tap → restore (clears `deletedAt`; QuKi returns to top of QuKis list).
  - Swipe → permanent delete (hard-delete immediately; modal confirmation dialog).
- **Retention period**: user-configurable in Settings (default TBD — 7 days is a reasonable starting point; 24h is too short for a fat-finger recovery scenario). Background sweep hard-deletes rows + cascades to images after the retention period expires.
- **Post-MVP (sync active)**: soft-delete + queue for push; on successful remote DELETE → hard-delete local row + cascade to images. 404 = success.
- **Why**: 24h was too short for the "fat-fingered an important note and didn't notice until later" scenario. Making retention configurable respects that different users have different recovery windows. The Recently Deleted screen is a safety net, not a filing feature — its design must resist feature creep toward vault-like behavior.
- **Rejected**: auto-expire only with no recovery UI (too easy to lose important notes permanently); archive folder (organization feature — violates manifesto).

## ADR-4: Image storage — separate binary files

- Binary files in `<app docs>/images/{filename}` on disk; tracked in `images` table.
- In-QuKi markdown reference: `![](../images/{filename})` — kept relative so the markdown remains portable into a tossed destination (the transport rewrites paths as needed).
- Filename: `YYYY-MM-DD-{uuid8}.{ext}`.
- Cascade delete on QuKi delete.
- When a sync plugin is active: push image before referencing QuKi (avoids broken-link window); images have their own sync state.
- **Rejected**: base64-embed in markdown (file bloat, editor performance, unreadable when tossed to GitHub); threshold hybrid (complexity not worth MVP).

## ADR-3: QuKi IDs & filenames — UUID v4 + 8-hex suffix

- QuKi `id` = UUID v4 (`uuid` package).
- **MVP**: no on-disk markdown file is produced by the app. QuKi body lives in SQLite. The filename pattern below only matters when a transport or sync plugin needs a stable path.
- Transport/sync-plugin-derived filename: `YYYY-MM-DD-{uuid8}.md`, deterministic from `createdAt` + `id` on the originating device. Once chosen, captured in a plugin-owned field and never recomputed.
- **Rejected**: `YYYY-MM-DD-NNN.md` (offline-device collisions; requires GET-before-write to assign NNN); `YYYY-MM-DDTHHMMSS.md` (clock-skew collisions).
- 2^32 collision space per day = effectively zero collision risk without coordination.

## ADR-2: Token storage — `flutter_secure_storage` for any plugin secret

- Any plugin that needs to hold a secret (OAuth token, API key, signed JWT) uses `flutter_secure_storage` namespaced by plugin id (e.g. `quki.transports.github_daily_log.token`).
- All other settings stay in `shared_preferences` (plaintext is fine for non-secrets).
- **Why**: a `repo`-scope GitHub token = read/write all user repos; plaintext on Android (`/data/data/.../shared_prefs/*.xml`) or Windows (`%APPDATA%`) is an unacceptable threat surface for ~zero implementation cost.
- Core enforces no API-level distinction; convention is plugin authors use `flutter_secure_storage` for anything that would be embarrassing in a screenshot.

## ADR-1: State management — Riverpod (code-gen)

- `riverpod` + `riverpod_generator` with `@riverpod` annotation throughout.
- No global singletons, no manual `InheritedWidget`, no `setState` outside trivial widget-local state.
- Provider lives next to the feature it serves; cross-cutting providers live in `core/`.
- **Rejected**: Bloc (more ceremony than warranted for solo project); plain `provider` (Riverpod is the maintained successor); manual DI (loses testability and reactive streams).
