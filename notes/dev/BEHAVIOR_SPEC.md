# QuKi Notes — Behavior Specification

**Source:** the Flutter application at v0.24.1, read from code and from its test suite. Every behavior below was traced to an implementation or to a test asserting it — not to documentation or comments. Where the code's comments disagreed with the code, the code is what's recorded.

**On the tests:** the suite is the most reliable record of *intent* in the project, because a test states what someone decided should happen rather than what happened to be written. Many rules below exist only there. If a question arises that this document doesn't answer, the tests are the next place to look, ahead of any prose.

**Purpose:** this describes what QuKi Notes *does*, so the rewrite can reproduce it without reading the Flutter source. It does not describe how the Flutter version achieves it, except where that detail is the requirement.

**Vocabulary:** *QuKi Notes* is the application. A *QuKi* is what it captures. The app has two pages — the **QuKi editor** and the **QuKi list** — plus three subordinate screens: Settings, Trash, and the storage-location setup.

---

## 1. Startup sequence

In order, before the UI exists:

1. On Windows and Linux only — initialise the window manager and **restore the saved window bounds**. This happens before the first frame, so the window never appears at a default size and then jump.
2. Load preferences and resolve the app's private documents directory. App storage lives in a `qukis` subfolder of it.
3. Construct the storage-location service, then run an upgrade check: if no location was ever chosen but the private directory already contains QuKis, silently adopt app storage rather than showing the setup screen to an existing user.
4. Start the app with the storage-location service injected.

---

## 2. Navigation model

The **editor is the permanent root**. It never shows a back button, and no second editor is ever pushed.

A single piece of app state holds the id of the QuKi currently loaded in the editor. `null` means a blank, unsaved QuKi. The QuKi list sets that id and pops back; the editor observes it and loads accordingly.

From the editor, the QuKi list slides in **from the left** and Settings slides in **from the right** — matching the side each control sits on. Settings opened from the QuKi list uses a plain push instead.

---

## 3. First launch and storage location

On launch, if no storage location has ever been chosen, the setup screen appears instead of the editor. Two preferences record the outcome: the chosen absolute path, and a flag marking that a choice was made. The flag's absence is what defines "first launch."

**The setup screen** reads:

> **Where should QuKis be saved?**
> Choose once. You can change this later in Settings.

and offers two cards:

| Card | Behavior |
|---|---|
| **Filesystem storage** | **Android:** if all-files access is already granted, resolve a fixed path under the external documents directory, create it, and continue. If not, send the user to the system permission screen and **resume the flow when the app comes back to the foreground** — the permission grant returns no result, so app lifecycle is the only signal. **Desktop:** a native directory picker; cancelling leaves the user on this screen. |
| **Use app storage** | *"QuKis are kept private to this app. They will be removed if you uninstall."* Uses a `qukis` subfolder of the app's private documents directory. |

Note the two options produce differently-shaped locations: app storage is a `qukis` subfolder, filesystem storage is a named folder the user can see. Choosing either **replaces** the setup screen with the editor rather than stacking on top of it.

The same screen is reachable later from **Settings → Change location**, in a mode that allows cancelling. Returning from it refreshes the QuKi list.

---

## 4. The QuKi editor

The root screen. A blank canvas on launch.

### App bar

Leading: a **QuKis** button opening the list. **Disabled when no QuKis exist.**

Actions, in this order:

1. **Mode toggle** — switches the whole QuKi between rendered and plain-text. Its icon reports the current state: a code icon in plain-text mode, a markdown mark when the editor has focus, an open book otherwise. The choice persists across launches.
2. **New QuKi**
3. **Help** — opens the help/about dialog
4. **Send**
5. **Settings**
6. **Delete** — disabled until the QuKi has been saved at least once. It sits last, separated from Send by every other action, so a mistaken tap can't land on it instead of the primary action. **Preserve that ordering.**

### Editing surface

Fills the screen above the toolbar. Text renders at 16px with 1.4 line height; content is inset 12px on three sides and 36px at the bottom so the last line clears the toolbar.

The editor reports three events: content changed (which notifies auto-save), a link tapped, and a checkbox tapped.

### Modes

**Reading vs. edit mode is derived from editor focus** — nothing else. When the editor has focus the formatting toolbar is shown; when it doesn't, the toolbar is hidden and the mode icon shows a book.

Opening a QuKi sets focus accordingly: **a new, blank QuKi takes focus** (edit mode), **an existing QuKi does not** (reading mode).

> **This is the defect that motivated the rewrite.** The app has no keyboard-visibility signal; it uses focus as a proxy for one. On Android the user can dismiss the keyboard without clearing focus, so the toolbar stays on screen with no keyboard under it, and the mode is wrong. The rewrite must drive this from a real keyboard-visibility signal, not from focus.

**Plain-text mode** is a separate, persisted toggle, orthogonal to reading/edit: it switches the entire QuKi to a raw text surface for bulk edits and raw pasting.

### Checkbox tap

Tapping a rendered checkbox toggles it in place. The marker is located by skipping any leading indentation, then reading six characters: `- [ ] ` becomes `- [x] `, and `- [x] ` or `- [X] ` becomes `- [ ] `. Anything else is ignored.

The toggle **preserves the cursor and does not scroll** — the tap didn't move the selection, so the view must not jump.

### Link tap

Opens the URL in the platform's default browser. Malformed URLs and missing handlers fail silently.

### Auto-save

- **2 seconds** after the last change, debounced
- **every 30 seconds**, regardless
- **on app lifecycle** — inactive, paused, or detached
- **before** switching QuKis, opening the list, deleting, and sending

A save is skipped when the body is **empty** or **unchanged since the last write**. The empty-body rule is deliberate: it prevents a stray select-all-delete from destroying a QuKi, and it is what makes the delete flow safe (see below).

The QuKi's **file is created by its first save**, not when the editor opens.

### Delete

**No confirmation** — matching the list's swipe-to-delete.

The editor is cleared and the save target reset **before** the file operation begins, not after. This is load-bearing: the debounce and periodic timers run independently and could otherwise fire mid-delete and write the still-displayed body back under the same id, recreating the file that was just moved to trash. Clearing the body first makes any such write a no-op, because empty bodies are never saved.

Afterwards the editor lands on a blank new QuKi, and a snackbar reads **"QuKi moved to Trash."** for 1.5 seconds.

### Send

In order:

| Condition | Result |
|---|---|
| Body empty | *"Nothing to send — write something first."* (2s) |
| No destination available | *"No transports enabled."* (2s) |
| Exactly one destination | Fires immediately, no picker |
| Two or more | A picker sheet |

Content is flushed to disk before sending. On unexpected failure: *"Send failed — unexpected error."* (4s) with a **Retry** action. On completion, the destination's own message, or *"Sent!"* / *"Send failed."* — 2 seconds on success, 4 on failure, with Retry offered when the failure is retryable.

**In practice only one destination exists.** The registry contains exactly one entry — the system share sheet. There is no clipboard destination in the code. So the picker sheet can never appear, the two-or-more branch is unreachable, and the "no destination" branch only fires during the brief window before preferences finish loading. Enable/disable state is persisted per destination and defaults to on, but **no screen exposes it** — Settings has no section for it.

The share sheet itself splits by platform: **Android** goes through a small native channel issuing a plain send intent, deliberately avoiding the cross-platform package's result-tracking chooser, which had confirmed cases of targets silently losing the shared content. **Windows and Linux** use the cross-platform package.

> The rewrite drops the abstraction entirely — it wraps a single implementation behind a picker that can't appear and settings with no UI. Send becomes one action: the system share sheet where one exists, clipboard on Linux. **Note that clipboard-on-Linux is new behavior**, not something being preserved; today Linux calls the same share path as Windows. The empty-body guard and the flush-before-send stay.

### List auto-continue

Pressing Enter at the end of a list item **continues the list**: after `- item` the next line begins `- `; after `- [ ] item` it begins `- [ ] `. Pressing Enter on an item that is empty apart from its marker **exits the list** instead, removing the marker.

### Toolbar toggle semantics

The list buttons — unordered, ordered, task — **convert in place** rather than stacking markers. Pressing ordered on a line that is already an unordered item replaces the marker; pressing it on a line that is already ordered removes it. Every pairing converts: unordered ↔ ordered ↔ task, in both directions, and each removes its own type.

All of this works identically on **indented lines**. A marker added to an indented line goes after the leading whitespace, preserving depth.

Ordered markers are removed regardless of their number, including multi-digit ones.

The inline-format buttons — bold, italic, strikethrough, code — **wrap a selection** when there is one, and when there isn't they insert the delimiter pair and **place the caret between them**.

Heading adds its prefix when absent and removes it when present. Prefix operations act on the line containing the caret.

For a **multi-line selection**, if every touched line already carries the marker being applied, the operation removes it from all of them.

### Text selection

Selection resolves against **rendered** text, not source, so hidden delimiters never truncate a selection:

- A word next to emphasis delimiters selects the word only, not the delimiters.
- A word inside a rendered link selects **the whole link label**.
- A bare autolinked URL selects **the whole URL**; an email address selects the whole address.
- Double-tap selects a word. Long-press selects a word or the entity containing it.
- Dragging a selection handle is **character-level, not word-snapped**.

A floating toolbar offers cut, copy, paste and select-all. It is dismissed by the next tap and must not leak when the screen is disposed.

### Programmatic updates

Setting the editor's value programmatically **resets the caret to the start** and **does not fire the change event** — this is what stops a load from triggering a save. In-place edits that must keep the caret, such as a checkbox toggle, use a separate path that preserves the selection.

A literal tab renders at roughly **four times the width of a space**, in both rendered and plain-text modes.

### Keyboard shortcuts — Windows and Linux only

`Ctrl+T` sends. `Ctrl+N` creates a new QuKi.

---

## 5. The QuKi list

Titled **QuKis**, with a back button — unlike the editor, this screen is pushed. Actions: New, Help, Settings. The list refreshes from the folder each time it opens.

### Search

A rounded, filled field with a search icon and a clear button that appears once there's text. It filters on **every keystroke** with no debounce, trimmed, case-insensitive, matching anywhere in a QuKi's full body. Results from a superseded query are discarded.

### Rows

Newest first by modification time.

Each row shows a **preview**: the first non-blank line, with any leading heading markers stripped, truncated to 80 characters with an ellipsis. Empty or unreadable QuKis show `(empty)`. The preview is read from the file per row, so opening the list reads every QuKi's body.

Below it, a **relative timestamp** (see §9).

Tapping a row opens that QuKi and returns to the editor. **Swiping right-to-left deletes it** — red background, trash icon, no confirmation — with the same *"QuKi moved to Trash."* snackbar. If the deleted QuKi was the one open in the editor, the editor resets to blank.

### Empty states

- No QuKis at all: *"No QuKis yet.\nTap + to capture your first thought."*
- No search results: *"No results for "<query>"."*

`Ctrl+N` creates a new QuKi here too, on Windows and Linux.

---

## 6. Trash

Titled **Trash**, reached from Settings → Trash. Refreshes on open. Same preview and timestamp treatment as the QuKi list.

- **Tap a row** → *"Restore note?"* with Cancel / Restore. Restoring moves the QuKi back, refreshes the list, and closes the screen.
- **Swipe** → confirmation, then permanent deletion.
- Empty: *"No notes in Trash."*

> The rewrite adds a **30-day hold** purged at app launch, and an **empty-trash** action. The deletion timestamp must be recorded when a QuKi is trashed — it cannot be derived, because moving a file preserves its modification time.

---

## 7. Settings

Sections with small uppercase, letter-spaced, accent-colored headers:

| Section | Contents |
|---|---|
| **Appearance** | Theme — displays `System`, not adjustable |
| **Storage** | Current location. App storage shows *"Files will be removed on uninstall. Change location."* in the error color; filesystem storage shows the path over up to two lines. Below it, **Change location**. |
| **Notes** | **Trash** |
| **Sync** | *"No sync backends installed"*, disabled |
| **About** | App name and version. **Tapping copies the version string to the clipboard** and confirms with *"Copied to clipboard."* |

There is **no section for send destinations**, despite the per-destination enable/disable preference existing in code. Nothing can reach it.

### Help dialog

Reachable from both pages. Shows the app icon, name and version — **tapping the version copies it** — then four rows, each with an icon, a title, a one-line description and a button: **Documentation** (emphasised), **Discord**, **GitHub**, and **Buy me a coffee**. Each opens in the external browser. A **Close** button sits bottom-right.

---

## 8. Share-in — Android and iOS

When another app shares text to QuKi Notes, the text becomes a new QuKi immediately and opens in the editor. **No screen is ever pushed** for this.

Both paths are handled: text shared while the app was closed, and text shared while it's already running. Multiple shared items are joined with a blank line between them; non-text items are ignored. On failure: *"Failed to save shared content."* (4s).

---

## 9. Relative timestamps

| Age | Display |
|---|---|
| Under a minute | `just now` |
| Under an hour | `N min ago` |
| Under a day | `Nh ago` |
| Exactly one day | `Yesterday` |
| Same calendar year | `Jan 7` |
| Earlier year | `Jan 7, 2025` |

---

## 10. Window state — Windows and Linux

Window position and size are stored as four preferences and restored at launch, before the first frame. If any is missing, the OS places the window instead.

Bounds are saved on **move, resize and close** — on the completed-gesture events, not continuously, so a drag doesn't hammer the preference store.

---

## 11. Theme

Follows the system light/dark setting. **Corrected 2026-09-18:** the Flutter app's palette was always described as GitHub Primer High Contrast but never actually matched it — the values below were hand-transcribed from the Flutter app's `ColorScheme` at some point and drifted from the real thing. The table now reflects the actual Primer Dark High Contrast primitives (`@primer/primitives/dist/css/functional/themes/dark-high-contrast.css`, via Scott's own `ScottKirvan/GitHubDHC` Obsidian theme, which implements it accurately) for dark mode, and GitHub's standard Light Default primitives for light mode — Primer does not ship a materially different "light high contrast" variant the way it does for dark. **This is now the actual target — the rewrite should carry these values, not the ones previously recorded here, and not the Flutter app's current on-screen colors where the two disagree.**

| Role | Light | Dark |
|---|---|---|
| Surface | `#ffffff` | `#010409` |
| Surface, subtle | `#f6f8fa` | `#151b23` |
| Text | `#1f2328` | `#ffffff` |
| Text, muted | `#59636e` | `#b7bdc8` |
| Accent | `#0969da` | `#71b7ff` |
| Accent, emphasis | `#0550ae` | `#a5d6ff` |
| Danger | `#cf222e` | `#ff9492` |
| Border | `#d1d9e0` | `#b7bdc8` |

Accent is the base link/interactive color (Primer's `fgColor-accent`); Accent-emphasis is its hover/stronger-state shade — darker in light mode, lighter in dark mode, both taken directly from Primer's own hover values rather than invented. The previous table had light mode's Accent and Accent-emphasis swapped relative to their actual Primer roles.

---

## 12. What the editor renders

Twenty element kinds, from the parser:

`h1`–`h6`, bold, italic, strikethrough, inline code, unordered lists, ordered lists, checked and unchecked task boxes, images, links, autolinks, blockquotes, horizontal rules, and backslash escapes.

Block indentation and nested blockquote depth are tracked per line and rendered as real layout indentation.

**Not rendered today:** tables and fenced code blocks. Both are **in scope for the rewrite**.

### Parsing rules that are pinned by tests

These are decisions, not incidental behavior. Each is asserted somewhere in the suite.

**Block detection**

- A heading requires `#` **at line start followed by a space**. `#notaheading` and `not # heading` are both plain text.
- `-`, `*` and `+` all open an unordered item.
- `- [ ] ` and `- [x] ` are task items, **not** unordered items — the checkbox wins.
- `- [X] ` with a capital X counts as checked.
- An image is a block element **only on a line of its own**. An image reference inside surrounding text is not a block image.
- Ordered lists renumber **block-relative**: consecutive items are numbered from the first item's own digit, so `1. / 1. / 1.` renders 1, 2, 3, and a block starting at `5.` renders 5, 6, 7. A break in the run starts a new block that keeps its own source digit.

**Inline detection**

- **No inline element spans a line break.** `**crosses\nlines**` produces nothing.
- An opening delimiter followed by a space cannot open emphasis: `a * foo bar*` is plain text.
- `*` works **intraword** — `foo*bar*baz` italicises `bar`. `_` does **not** — `foo_bar_baz` and `5_6_78` are plain text.
- `***x***` resolves to strong containing emphasis.
- Emphasis nests arbitrarily: `~~**_text_**~~` is strike containing strong containing emphasis.
- Inline code is literal inside — `` `*a*` `` contains no emphasis — but emphasis may **span across** a code span.
- A backslash escapes ASCII punctuation only. `\*not italic\*` is literal, `\A` leaves both characters literal, and a trailing lone backslash produces nothing. An escaped delimiter cannot open emphasis. Escapes are **inline-only**: `\# foo` is a paragraph, not a heading.
- Links may contain emphasis, strikethrough and code in their label, but **not** a nested link or autolink. An image reference is an image, never a link. A link with empty text and empty url is still a link. Links are parsed on heading lines too.

**HTML**

Single-line HTML is detected and passed through as literal text, and its internals never produce markdown. Attribute values containing `*`, `_`, `` ` `` or `[` stay literal, and real emphasis elsewhere on the line still resolves — emphasis may even span across a skipped inline tag.

Detection is deliberately conservative about what counts as a tag: `a < b`, `2 < 3` and `i <3 you` are not tags, and a `<` with no closing `>` on the same line is not a tag. **Multi-line HTML blocks are not tracked** — an open tag on one line has no effect on the next.

### Indentation

Indent and dedent act on whole lines, and are bound to both the toolbar buttons and Tab / Shift+Tab.

On a list, task or ordered item the whitespace goes **before the marker**, changing real depth and preserving checked state. On a plain paragraph it inserts or removes a leading literal tab. Indent and dedent **round-trip** exactly.

They are **no-ops** on headings, blockquotes, block images and horizontal rules, in both directions — prefixing those with whitespace would break their detection, and for a horizontal rule no caret position preserves it at all.

A multi-line selection applies the per-line rule to every touched line and **remaps the selection endpoints** to match.

### How indentation renders

Consecutive lines sharing an indentation depth are grouped into a single run and laid out together. Runs split exactly where depth changes, are contiguous, and cover the whole document with no gaps. A **revealed** line — one showing raw source — contributes a depth-zero run, breaking any run it sits inside.

### Reveal semantics — the precise rules

This is the app's defining behavior and the hardest part of the port. The rules below are taken from the implementation and its tests, not from description.

**The reveal decision is made per element, against a single caret position.**

**1. The reveal unit is the OUTERMOST element, never the innermost.** Where elements nest — `***bold italic***`, emphasis inside a link label — the whole outer span reveals as one raw unit. It is never partially revealed, and an inner element never reveals on its own while its parent stays collapsed.

**2. Boundaries are inclusive at both ends, and the end is one past the last character.** An element spanning source range `[start, end)` reveals whenever the caret offset satisfies `start ≤ caret ≤ end`. Because `end` is exclusive, **the caret resting immediately after the element's final character still reveals it.**

> Worked example, straight from a test: `**x**` occupies offsets 0–4, so `end` is 5. A caret at offset 5 — immediately past the closing `*` — **still shows the asterisks.** They collapse once the caret moves away, or as soon as one more character is typed.
>
> **This is intended and must be preserved.** Typing `**bold**` and stopping leaves the delimiters visible; typing the next character collapses them. The caret sitting at the closing boundary is still working *on* that element, so the source stays available — and it means the delimiters don't flicker away and back if editing continues at the end of the run.

**3. Block markers reveal only their own marker span, not the line.** For headings, list bullets, ordered-list numbers, checkboxes and blockquote markers, the reveal range is just `[start, start + markerLength]`. Past the marker, the line behaves exactly like an unadorned paragraph — content defers to whatever inline element covers the caret, and the marker stays rendered.

> Two tests pin this. In `# A`: a caret at offset 2 — the boundary between `# ` and `A` — reveals the marker. A caret at offset 3, inside the heading text, leaves the marker collapsed and the text styled as a heading. Without this rule, putting the cursor anywhere on a heading line snapped the entire line to raw source.

**4. Images and horizontal rules are the exception** — their marker spans the whole line by definition, so rule 3 degenerates and they reveal wholly.

**5. With a selection, the caret position used is the selection's ANCHOR** — where the selection began — not its moving end and not both. A selection dragged across several elements resolves reveal against its starting point only.

**6. Plain-text mode passes an invalid caret**, so nothing is ever revealed and nothing is ever collapsed — the whole buffer renders as raw source.

**7. Collapsed elements are interactive; revealed ones are not.** A collapsed link opens on tap and a collapsed checkbox toggles on tap. Once revealed, both behave as ordinary text — the caret moves normally and no action fires. Slots for tap-handling are recorded only for collapsed elements.

### Formatting toolbar — ten buttons

Bold, italic, strikethrough, inline code, heading, unordered list, ordered list, task list, indent, dedent.

The heading button currently toggles `# ` on and off — H1 only.

> The rewrite changes this to cycle: normal → H1 → H2 → H3 → normal, with any line already at H4–H6 dropping to normal on the next press, and a multi-line selection taking its next state from the first line and applying it to all. The icon tracks the current level.

Indent and dedent apply to whole lines and are also bound to Tab and Shift+Tab.

---

## 13. Dependencies the rewrite must replace

| Current | Purpose | Replacement |
|---|---|---|
| `flutter_riverpod` | State and dependency injection | A small state library, or none |
| `window_manager` | Desktop window size and position | Electron |
| `share_plus` + a native Android channel | Share sheet | `navigator.share()` |
| `receive_sharing_intent` | Android share-in | Capacitor bridge or Kotlin |
| `file_picker` | Choosing the storage folder | Electron's dialog |
| `url_launcher` | Opening tapped links | Platform default |
| `shared_preferences` | Settings and window state | Any key/value store |
| `uuid` | Generated filenames | `crypto.randomUUID()` |
| `path`, `path_provider` | Path handling | Node `path` |
| `package_info_plus` | Version display | Build-time constant |
| `lucide_flutter`, `flutter_svg` | Icons | Lucide has a web build |
| `logging` | Diagnostics | Any logger |
| `html`, `html2md` *(editor package)* | Rich paste → markdown | Turndown — `html2md` is its Dart port |
| `quill_native_bridge` *(editor package)* | Reading HTML off the clipboard | The browser's own clipboard API |
| `markdown` *(editor package)* | Markdown parsing | CodeMirror's markdown language |

**No code generation is used.** There is no `build_runner` and no `riverpod_generator` — every provider is hand-written. Nothing in the port needs to replace a codegen step.
