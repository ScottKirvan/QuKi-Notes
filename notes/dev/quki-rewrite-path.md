# Taking QuKi Notes off Flutter

**Migration proposal · from v0.24.1**

What the current app does, where each piece lands in a web-based stack, and what the move actually costs.

> **Recommendation:** Rebuild the editor on **CodeMirror** and build the web app first, then wrap it in **Electron** for Windows and Linux and **Capacitor** for Android. Everything you write is TypeScript, and the entire interface is styled with CSS.

**Day-one targets:** web, Android, Windows, Linux. iOS and macOS wait behind their fees and hoops; the web app covers those users in the meantime.

**Scope:** the current feature set only. The spatial/flow version — field notes and creativity rather than GTD — is a later QuKi+ tier. Nothing here builds for it, and nothing here blocks it.

---

## How to read this document

This is a spec, which means its words are load-bearing. The previous build acquired a storage design nobody chose, because the word *database* entered an early spec in its broad sense — any organized store, a filesystem included — and was implemented in its narrow sense: a registry that decides what exists. The implementation was defensible against what was written, which is why arguing it back out was so expensive.

So the sections below state some things as constraints rather than descriptions, and name what must *not* be built alongside what must. That asymmetry is deliberate. A happy path can be satisfied by a conventional design that's wrong; a prohibition can't.

**Vocabulary:** QuKi Notes is the application. A QuKi is the thing it captures. The app has two pages — the QuKi editor and the QuKi list.

---

## What these three things actually are

**CodeMirror** is a text editor you embed in a page. It holds your raw markdown as plain text and paints formatting on top of it — which is exactly the model you already built. You tell it "when the cursor is inside this `**bold**`, show the asterisks; otherwise hide them and draw it bold." That instruction is a few dozen lines, not a rendering engine.

**Electron** is a browser packaged as a desktop app, with full access to the file system. Your app runs inside it like a web page, but it can read and write `.md` files anywhere on disk. VS Code, Slack, and Obsidian's desktop app all work this way.

**Capacitor** does the same job for phones: it wraps your web app in a real Android app, and gives it native abilities — files, share sheet, keyboard — through small bridges you call from ordinary TypeScript. Obsidian's mobile app is Capacitor.

The important part: **one codebase feeds all three targets.** The web app is the thing; Electron and Capacitor are wrappers around it that swap in a different storage backend and add native abilities. You write the editor once.

The cost is more build pipelines than you have today — one Flutter toolchain currently produces Android, Windows and Linux, and afterwards it's a web deploy plus an Electron build plus a Capacitor build. Your CI and release-please setup carry over; there's just more of it. What it buys is the same browser engine everywhere rather than whatever each machine happens to ship with, plus a web target you can't reach at all right now.

---

## Your two questions

### Is it all TypeScript on the backend?

On desktop, yes, completely. Electron runs Node.js behind your interface, so reading and writing QuKis, sidecars and media is the same file API you'd use in any Node script. Your `lib/core/` logic becomes a TypeScript module and nothing else changes shape.

On Android, your code is still all TypeScript — but file access, the share sheet and the keyboard go through Capacitor bridges that are native underneath. You call them from TypeScript; you don't usually write the native side. The exceptions are receiving shared text *into* QuKi Notes, and the all-files storage permission you already have Kotlin for.

This is the main reason I'd steer you away from Tauri, the other popular desktop wrapper. It's lighter and it covers Android too, but its backend is Rust. Electron keeps you in one language.

### Do we get CSS for theming and UI?

Yes — all of it, and this is a straight upgrade over Flutter's theme system. Every part of the interface is HTML styled with CSS, and CodeMirror is no exception: it exposes class names for each piece it draws, so your headings, code spans, checkboxes and cursor are all just CSS rules.

Following the system's light/dark preference is one line (`prefers-color-scheme`), and a palette swap is a handful of CSS variables — which makes your Primer High Contrast theme a small file rather than a Dart class. It also makes user themes realistic later: Obsidian's entire theme ecosystem is people sharing CSS snippets.

---

## The storage contract

*Kept as a standalone file for pasting at the top of storage tasks. Summarised here.*

**The folder is the index.** The set of `.md` files in the QuKi folder is the complete set of QuKis. Nothing else decides what exists.

- **Identity is the filename**, and no naming scheme is required. Generated QuKis get an opaque id; a file placed in the folder keeps its name forever. Mixed naming is correct and must not be normalized. A QuKi isn't philosophically a file — the filename is an address, not a title.
- **`modifiedAt` comes from the filesystem**, never from a stored copy.
- **The sidecar may describe a QuKi; it may never determine which QuKis there are.** That's the only permanent prohibition. Fields are *derived* (disposable, and **none are implemented today**), *intrinsic* (`createdAt`, `deletedAt` now; manual sort, pins, tags later), or *existence* — banned.
- **A missing sidecar never hides a file.**
- **Images live in one shared `media/` folder**, linked relatively as `![alt](media/file.png)` so the QuKi still renders in any other markdown reader. Orphans are deleted when their last referencing QuKi is purged — checking trash for references too, so restore doesn't come back broken. User setting, defaults to delete.
- **Trash is a 30-day hold**, purged at app launch, with an empty-trash action. `deletedAt` is intrinsic, because moving a file preserves its mtime.
- **The folder is flat.** `.meta/`, `.trash/` and `media/` are structural, never content.

### Storage is an interface, not a filesystem

| Backend | Used by | Folder |
|---|---|---|
| Node `fs` | Electron — Windows, Linux | A real folder chosen at onboarding |
| Capacitor filesystem | Android | A real folder, via all-files access |
| OPFS | Web — all browsers | Origin-private, persistent, not user-visible |

The web app uses **OPFS only** — no folder picker, no File System Access API, since the audience there is macOS and iOS where it doesn't exist. With no folder to choose, the web app skips the storage-location onboarding step entirely. Content arrives by **paste**, becoming a generated QuKi like any other.

**The web app is installable**, and that's a day-one requirement rather than a nicety: on iOS, WebKit evicts origin storage under pressure and inactivity, and the heuristic that most reliably grants a persistence exemption is being on the home screen. It also needs to work offline, which the same service worker covers.

That makes sync the durability story on iOS rather than a convenience — a much easier thing to charge for than a nicety.

### Two API requirements with no day-one screen

**Export everything** — one call producing the complete library, QuKis plus sidecars plus media, as a portable bundle. It's the backup story and also the migration path: OPFS web users move to a desktop folder this way, and off the web app entirely when native iOS exists.

**Share is one action with no picker** — system share sheet via `navigator.share()` on Windows, Android and macOS; clipboard on Linux, which has no cross-desktop share mechanism at all. No transport abstraction, no registry. Further destinations go through the API if ever wanted.

**Known deficiency, Electron/Windows specifically (2026-09-19):** `navigator.share()` has no bridge in Electron at all — the Windows Web Share implementation lives in Chrome's own browser-UI code, not the engine layer Electron builds on, and a Windows feature request for it was closed "not planned" upstream. Reaching the real Windows Share UI needs a native addon (COM interop via `IDataTransferManagerInterop`); the only existing community wrapper compiles an unmaintained separate C# helper, which was declined. Electron/Windows currently falls back to the Linux clipboard behavior as a stand-in, accepted deliberately rather than fixed. This may be worth a real native addon later — and possibly worth publishing, since no clean solution for this appears to exist anywhere in the Electron ecosystem yet.

### What the contract creates

Inviting people to put files in the folder also invites other programs to edit them, and the auto-save controller has no awareness of the file at all — it decides whether to write by comparing against the last body it wrote in memory. So an external edit is invisible to it and the next save overwrites unconditionally. The fix is small and its location is obvious: record the file's modification time when a QuKi is loaded or written, compare at the top of every save, and branch when it doesn't match.

This isn't hypothetical — you've edited these files externally before. Opaque filenames and the sidecar made it high-friction enough to stay rare.

Two smaller things belong with it: a failed save currently disappears into a log with the caller never informed, which matters more once real folders and real permissions are involved; and an empty body is never written, so clearing a QuKi leaves its last content on disk. That second one is worth keeping on purpose.

---

## Migration

The existing folder opens as-is. Onboarding points the new app at the same folder; nothing is converted, renamed or rewritten.

- Existing sidecars already hold `createdAt`, which is kept.
- `modifiedAt` moves from the sidecar to the filesystem, so anything whose sidecar timestamp had drifted — most likely files edited outside the app — shifts position in the list. The correction working, not a regression.
- The 113 trashed QuKis have no `deletedAt`. They're stamped at first launch, so the 30-day clock starts then rather than purging anything immediately.
- Existing opaque filenames stay exactly as they are.

---

## What the current code actually does

*Read from the v0.24.1 source — `lib/core/storage/` and `lib/features/editor/` — from what the code executes, not from what its comments claim.*

**The scan is already correct.** `_scan()` enumerates every `.md` file in the folder. The folder is being read as the index exactly as it should be.

**One guard throws the result away.** In `_readMeta()`, a missing sidecar returns `null`, and `_scan` drops every null. That is the entire reason files placed in the folder are invisible — two lines, not an architecture.

**Identity is already the filename.** `_scan` derives `id` from `basenameWithoutExtension`, and every path is built back from it. Opaque ids appear in exactly one place, `create()`, which the contract permits.

**`modifiedAt` currently comes from the sidecar, not the filesystem.** `update()` writes it into `.meta/{id}.json` and `_readMeta()` prefers that value, falling back to `stat.modified` only when the field is absent. The contract inverts this back.

**The same pattern repeats in memory.** `QuKiIndexNotifier` keeps a list and mutates it through `addMeta`/`updateMeta`/`removeMeta`, alongside a `refresh()` that rescans. Fix the sidecar and leave this, and the bug has moved rather than gone.

**Auto-save has no idea what's on disk.** The controller is 71 lines and purely write-side — no read-back, no modification-time check, no conflict detection. It skips a write when the body matches the last body *it* wrote, an in-memory value that says nothing about the file. So an external edit is invisible and the next save overwrites it. Save failures are caught, logged and swallowed; the caller never learns.

**Empty bodies are never written.** `save()` returns early on `body.isEmpty`, so deleting all the text leaves the last non-empty content on disk. Worth keeping deliberately — it's what stops a stray select-all-delete from destroying a QuKi.

**The file is created on first save.** The save callback takes a nullable id and returns the new one; a null id routes to `create()`, which generates the filename. That's exactly the hook the naming rule needs, already in place.

**Port the atomic write; leave the rename retry behind.** `_writeAtomic`'s temp-then-rename is correct and standard. `_renameIfExists`'s five-attempt retry loop is not worth carrying: the identical rename runs in `_writeAtomic` on every save with no retry, so a defense that exists only on the delete path looks like a reaction to one incident rather than a real finding; on exhaustion it returns normally, so a failed delete reports success and leaves an orphan the list no longer points at; and it retries the rename rather than the `exists()` check, so it doesn't address the race its comment blames. Surface rename failures instead, and handle a real transient if one ever shows up under Node.

**Estimated cost of fixing storage in Flutter today: about twenty lines.**

---

## Piece by piece

Read the middle column as the honest cost. "Rewrite" doesn't always mean hard — several of these get smaller, and two disappear.

| Piece | Fate | Notes |
|---|---|---|
| Storage model | **Fix first** | Do not port as-is. The contract replaces it. |
| Storage primitives | Port selectively | The atomic temp-then-rename write carries across. The rename retry loop does not. |
| Auto-save | Extend | Keep the debounce and periodic cadence. Add the disk-state check, surface failed writes, keep the empty-body guard. |
| `lib/core/` | Translate | Already free of Flutter so a CLI could share it. That discipline makes the port a language translation, and makes the CLI and MCP adapters cheap. |
| Live editor | Translate | The reveal rules survive as logic; the custom render object and text-input plumbing disappear. This piece gets dramatically smaller. |
| In-memory index | **Redesign** | `QuKiIndexNotifier` mutates a list through add/update/remove alongside a rescan — the sidecar problem one layer up. Derive the list from the folder; don't maintain it. |
| Formatting toolbar | Needs work | The buttons are easy. Keeping it glued above the Android keyboard is the bug that started all this. |
| Images | **Fix** | `media/` at the folder root with relative links. The current path resolves to a sibling of the storage root, outside the user's folder, which is why images don't render. |
| Send | **Simplify** | The abstraction wraps exactly one implementation — the share sheet. There is no clipboard destination in the code, so the picker can never appear, and the enable/disable preference has no UI. Drop it: one action, `navigator.share()` on Windows, Android and macOS. Clipboard on Linux is **new behavior**, since Linux has no cross-desktop share mechanism. |
| Android share-in | Needs work | Receiving text from other apps isn't in Capacitor's standard set — a community bridge, or a small piece of Kotlin. |
| Android storage permission | Port the Kotlin | All-files access with real filesystem paths, already through Play review. Direct Capacitor equivalent. |
| Recently Deleted | Extend | The screen and its restore/delete mechanism carry over. Add the 30-day hold and the empty-trash action. |
| Window state | Carries over | Electron remembers size and position in a few lines, replacing `window_manager`. |
| Riverpod | Replace | A small state library, or none. QuKi Notes holds one open QuKi and a derived list. No code generation is involved — there is no `build_runner` and no `riverpod_generator`, and every provider is hand-written — so there is no codegen step to replace. |
| Selection handles, magnifier | **Delete** | Each is its own source file today. CodeMirror provides both. |
| HTML paste | Translate | Stays yours, but `html2md` is a Dart port of Turndown, so it moves across nearly unchanged. |

---

## The editor

*Inventory read from the source: the toolbar widget and the parser's `MdElKind` in `packages/markdown_live_editor/lib/src/`.*

### What it does today

**Toolbar — ten buttons:** bold, italic, strikethrough, inline code, heading, unordered list, ordered list, task list, indent, dedent. Heading is a single button calling `toggleLinePrefix('# ')` — H1 only, no level picker.

**Rendered inline — the parser's twenty element kinds:** `h1` through `h6`, bold, italic, strikethrough, inline code, unordered and ordered lists, checked and unchecked task boxes, images, links, autolinks, blockquotes, horizontal rules, and backslash escapes. So headings render at all six levels even though the button only inserts one. Nested blockquote and block-indent depth sit on top of that.

**Span-level reveal, symmetric.** Typing `**` opens bold, the closing `**` collapses the markers immediately, and moving the cursor back into existing bold text brings them back. This is CodeMirror's native model — decorations recomputed against the current selection — so it comes structurally rather than as a special case.

**Checkbox substitution** — `- [ ]` plus a space becomes a real checkbox mid-typing, with the cursor landing sensibly afterwards.

**Images render inline**, and paste writes them to `media/` with the link inserted at the cursor. Substantially easier here than in Flutter: the paste event hands you the image as a blob, so it's write-the-file plus insert-the-link with no platform plumbing.

**Plain-text toggle** — CodeMirror switches a whole feature off at runtime, so the type icon becomes flipping the formatting rules off.

**Three things you built by hand that CodeMirror provides:** selection handles and the selection magnifier are each their own source file today, and both come free. HTML paste conversion stays yours, but `html2md` is a Dart port of Turndown, so that piece moves across nearly unchanged.

### What the port changes

**The heading button cycles instead of toggling.** Each click advances the line: normal → H1 → H2 → H3 → normal. Two rules so the behavior is fully defined:

- A line already at H4, H5 or H6 — reachable by typing, outside the cycle — goes to **normal text** on the next press. The button is always a way out.
- For a multi-line selection, the **first line's level decides the next state**, and that level is applied to every selected line. A mixed selection converges rather than each line cycling independently.

The icon tracks the line's current level rather than sitting fixed at `heading1`, so the cycle explains itself.

### What the port adds

**Tables and fenced code blocks.** Neither appears in `MdElKind`, so neither renders today. The port is the natural place to add them, and they're render-only: tables **revert to raw markdown when the cursor enters them**, one replace-decoration with a widget, skipped when the selection intersects the table — the same mechanism used everywhere else. Editable rendered tables would mean holding a grid and its source in sync on every keystroke plus building row, column and alignment controls; that's a sub-project, and a natural QuKi+ candidate.

These are additions rather than ports, so they sit slightly outside "current feature set only" — worth deciding deliberately rather than letting them ride along.

### On scale

The reference library is ~100 active QuKis and ~113 in trash. At that size, reading every file body for search is imperceptible on all three backends. **No caching is needed and none should be built.** The derived sidecar category stays defined for whenever it earns its place; today the sidecar has two fields.

---

## The toolbar bug, for closure

The problem that pushed you toward a rewrite has a first-class answer in this stack. Browsers expose the actual on-screen keyboard geometry as it moves, and Capacitor adds native keyboard-shown and keyboard-hidden events on top. You get told when the keyboard appears and disappears, rather than inferring it from a screen measurement that lags behind.

That fixes all three symptoms from one source — the toolbar hiding with the keyboard, the cursor staying visible, and the scroll position landing correctly.

**The blast radius is larger than the toolbar, and the code says exactly why.** Toolbar visibility, the mode icon, and therefore reading-versus-edit mode are all gated on one value — and that value is literally the editor's focus state. The app has no keyboard-visibility signal at all; it uses focus as a proxy for one. On Android, dismissing the keyboard doesn't clear focus, so the proxy is simply wrong, and everything derived from it is wrong at the same moment. One real signal fixes the mode system and the toolbar together.

What doesn't change is that Android keyboards are awkward for every editor on every platform, and CodeMirror has its own rough patches with predictive text. The difference is filing a bug against a maintained library with thousands of users, instead of working around framework internals alone.

---

## Proposed sequence

### 01 — Prove the editor in a browser tab

No app, no wrapper, no file system. CodeMirror plus the reveal rules above. Type in it until it feels like QuKi Notes. This page doesn't get thrown away — it becomes the editor.

*Answers:* **can this library actually do what I built?**

### 02 — Fix storage in Flutter, in place *(optional)*

Roughly twenty lines against the contract, in the app you already have. The cheapest way to validate the contract against QuKis you actually own, before committing it to a new language. Skip it if the port is moving fast.

*Answers:* **is the contract actually right?**

### 03 — Port the core, with two adapters

Translate `lib/core/` to TypeScript — storage behind the interface, settings, trash, export. Then put a CLI and an MCP server over it, both thin.

The adapters aren't features here, they're the proof: **if either one has to reach around the core to do its job, the abstraction is wrong.** Two callers test that better than one, and this is the cheapest moment to find out. Keep the core as the API and MCP as an adapter over it — never let MCP's coarse, schema-shaped tools define the core, or the UI ends up reaching around it later.

*Produces:* **a working core, a CLI, and an MCP surface — with the boundary proven.**

### 04 — The web app

The editor from phase one plus the core from phase three, running against OPFS. Installable, offline, paste-to-import. A shipping target, not a stepping stone — it's what Apple users get until iOS and macOS are worth the fees.

*Produces:* **the first shippable QuKi Notes.**

### 05 — Electron: Windows and Linux

The same app, wrapped. Swap the storage backend to Node, gain the real folder and the onboarding step that chooses it, add window state and Send. Not a port — a wrapper and a backend swap.

*Produces:* **desktop, on the corrected storage model, opening your existing folder.**

### 06 — Capacitor: Android

The same app again. Swap the storage backend to Capacitor's, port your all-files permission Kotlin, add the keyboard-aware toolbar, share out and share in. Last because it's where the surprises live.

**Ships under the existing Play listing and package id** — this is the same app with its defects fixed, not a successor. The approved all-files permission, the install base and the beta testers travel with the listing. Set the package id accordingly when the Capacitor project is created; it is annoying to change afterwards.

*Produces:* **the full day-one target set.**

---

## Before committing

- [ ] **Reveal at the span level, not the line.** Confirm the cursor can sit inside a bold run and reveal only that run, with everything else on the line still formatted. This is the differentiator — verify it before anything else.
- [ ] **The checkbox swap, mid-typing.** Type `- [ ]` and a space, and watch where the cursor lands once the checkbox appears.
- [ ] **Paste an image.** The one feature that was broken enough to abandon. Worth proving early, since it's much cheaper here.
- [ ] **The acceptance test.** Put a file in the folder; delete the sidecar directory. If both survive, the contract holds and it ports cleanly.
- [ ] **The toolbar, pinned, on the Pixel.** Ten minutes in a browser tab settles whether the original bug is genuinely gone.
- [ ] **Your worst QuKi.** Longest, most nested, most images. Paste it in early.

---

## Tests worth having in CI

Acceptance is manual and per-step — this list is only about **automated regression**: the behaviors that break quietly, or that look like bugs and get "fixed" by someone who doesn't know they're deliberate.

Most of these already exist as assertions in the Flutter suite. Porting them as test cases turns roughly three hundred recorded decisions into an executable specification, which is a far stronger position than prose.

### Storage — the contract's own acceptance tests

- **A `.md` file placed in the folder appears in the list**, with the correct modified time, having never had a sidecar.
- **Deleting the entire sidecar directory loses nothing but intrinsic data.** Every QuKi still lists and still opens.
- **An external edit is not overwritten.** Modify a file on disk behind an open editor, then trigger a save; the save must detect the change rather than clobber it.
- **An emptied QuKi is not written.** Clearing all text leaves the previous content on disk.
- **A pending save cannot resurrect a deleted QuKi.** Delete with a save already queued; the file must stay deleted. *(Exists in the Flutter suite.)*
- **The list reflects the folder, not a cache.** Add and remove files externally, rescan, and the list matches the directory.

### Images — the bug that lived the app's entire life

- **A resolved image path is always inside the QuKi folder.** Assert on the resolved absolute path, not on whether the image renders. The original defect resolved to a *sibling* of the storage root and merely showed a grey placeholder, which is exactly why it survived so long.
- **A pasted image lands in `media/` and its link resolves.**
- **Orphan cleanup counts references in the trash**, so restoring a QuKi brings its images back.

### Reveal — the differentiator

- **The outermost element reveals, never the innermost.** Caret inside the inner emphasis of `**bold *italic* text**` reveals the whole outer span.
- **The end boundary is inclusive.** Caret immediately past a closing delimiter still shows it; one more keystroke collapses it.
- **A block marker reveals only itself.** Caret in heading text leaves `# ` collapsed and the text styled.
- **Plain-text mode reveals nothing and collapses nothing.**
- **With a selection, reveal resolves against the anchor**, not the moving end.

### Parsing — the rules most likely to be "corrected"

Each of these is deliberate, and each looks like a defect to someone encountering it cold:

- No inline element crosses a line break.
- `#notaheading` and `not # heading` are plain text.
- Intraword `*` emphasises; intraword `_` does not. `5_6_78` stays literal.
- `- [x] ` is a task item, not an unordered item.
- Ordered lists renumber block-relative — `1. / 1. / 1.` renders 1, 2, 3.
- `a < b`, `2 < 3` and `i <3 you` are not HTML tags, and an unclosed `<` isn't either.
- A backslash escapes punctuation only; `\# foo` stays a paragraph.

### Interaction

- **Enter continues a list**, and **exits it** on a line holding only a marker.
- **List buttons convert in place** — the full matrix, at both root and indented depth. *(Thirty-one cases in the Flutter suite.)*
- **A programmatic value change does not fire the change event.** Without this, loading a QuKi triggers a save, and you get a write loop.
- **A checkbox toggle preserves the caret and does not scroll.**
- **Indent then dedent round-trips exactly**, and both are no-ops on headings, blockquotes, block images and rules.

### What automation won't catch

Worth stating so nobody mistakes a green suite for a working app. The keyboard-aware toolbar, the feel of reveal while typing at speed, paste-to-image, selection handles and share targets all pass headless and fail on a device. These stay manual, on real hardware — a Pixel for Android, a real iPhone for the web app, since WebKit is where text input diverges most.

---

## Reference: the landscape this came from

**Why not Flutter packages.** Three packages on pub attempt live markdown editing. `markdown_editor_live` (janek-w, Mar 2026) reveals syntax per *line*, which is a mode flip at line scope. `live_markdown_editor` and `livemd_flutter` both appeared within the last month, went 0.1 → 0.9+ in under three weeks, and both rewrote their parser core mid-sprint. `live_markdown_editor` benchmarks its live projection at 411ms on a 100k-line fixture, which rules out per-keystroke reparse. None attempts span-level immediate reveal.

**Why not the other web editors.** ProseMirror, Tiptap, Lexical and Milkdown convert as you type, which looks like the right behavior, but the document tree is canonical and markdown is serialize-on-save. You'd lose "the `.md` file is the truth."

**Why not Monaco.** VS Code's editor, available standalone, but the maintainers state it doesn't support mobile browsers — which rules it out for Android. It also assumes uniform line heights and has no widget-substitution model, so images and checkboxes have nowhere to live.

**Why not Compose Multiplatform.** The closest Flutter-shaped migration, but `BasicTextField` + `OutputTransformation` has no per-range styling and no inline composables — exactly the two things you need. You'd be writing a text layout engine again.

**Why the original bug isn't an editor bug.** Flutter exposes no authoritative keyboard-visibility signal; `MediaQuery.viewInsets` is animated and lags, and on Android a user-dismissed keyboard doesn't close the input connection, so focus still reports focused. That's below the editor layer, which is why it shows up in other apps and why a rewrite within Flutter wouldn't have fixed it. `keyboard_insets` (2GIS) is the Flutter-side workaround if one is ever needed.

**Prior art worth reading.** `zhulidr/notebook_editor_md` (CodeMirror + Tauri, local-first `.md` files) is closest to this architecture. `kenforthewin/atomic-editor` and `Type-32/codemirror-rich-obsidian` both do inline live preview. `blueberrycongee/codemirror-live-markdown` ships a design document explaining the decoration strategy — including the table-as-widget approach — and lists its own limitations honestly.

---

*Built from two sources only: the v0.24.1 Flutter source, and the design decisions made in conversation. Prior planning documents, comments and issue history are deliberately not referenced — this works from first principles. Current behavior is specified separately in `BEHAVIOR_SPEC.md`; the storage rules are in `STORAGE_CONTRACT.md`.*
