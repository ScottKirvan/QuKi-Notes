# Capturing QuKis

## The editor

The editor is the first thing you see when you open the app, and it's always home. Open QuKi Notes, type, done. That's the whole capture workflow.

Tap **+** in the top bar to start another new QuKi.

## Auto-save

There's no save button. A QuKi is saved:

- 2 seconds after you stop typing
- every 30 seconds while it's open
- when you open the list, start a new QuKi, delete, or send
- when you switch away from the app or close it

A new QuKi doesn't become a file until its first save. A blank QuKi you never type in never creates a file.

**Clearing all the text doesn't save.** If you select everything and delete it, the file keeps its last non-empty version. This protects against a stray select-all-and-delete. To get rid of a QuKi, delete it instead (see [Deleting a QuKi](#deleting-a-quki)).

::: warning
On Windows and Linux, closing the window within a second or two of your last keystroke can lose that last bit of typing. Pause for a moment before closing.
:::

### When a save fails

If a QuKi's file was changed or deleted by another program since QuKi Notes last saved it, QuKi Notes won't overwrite it automatically. A banner appears at the top of the editor:

> Could not save — it changed elsewhere. Your latest edits have not been written to disk.

It says "it was deleted elsewhere" if the file is gone. Tap **Overwrite** to save what's on screen over the other version (or recreate the file), or copy your text somewhere safe first. A similar banner appears if a save fails for any other reason, such as a full disk or a folder that's no longer reachable.

::: warning
While that banner is showing, your latest edits exist only on screen. Opening another QuKi, starting a new one, or deleting this one throws them away without asking. Deal with the banner first.
:::

## Reading and editing

The editor has two states:

- **Editing**: the cursor is in the text (on Android, the keyboard is up). The formatting toolbar sits at the bottom, and the element under the cursor shows its raw markdown so you can edit it character by character.
- **Reading**: the cursor isn't in the text (on Android, the keyboard is down). Everything is rendered, and the toolbar is hidden.

A new QuKi opens in editing mode. A QuKi you open from the list opens in reading mode; tap into the text to start editing.

::: info
On Android, editing mode follows the on-screen keyboard. If you type with a hardware keyboard, the on-screen keyboard may never appear, and the toolbar and raw-markdown reveal with it.
:::

### How the rendered view works

While you're editing, headings look like headings, links show their label, images appear inline and checkboxes look like checkboxes, except for the element your cursor is in. That element shows its markdown source. Move the cursor away and it renders again.

- **Inline formatting** (bold, italic, strikethrough, code, links) reveals as a whole unit. If formatting is nested, such as a bold phrase with italics inside, the outermost element reveals all at once.
- **The cursor right after the closing marker still counts as inside.** Type `**bold**` and stop, and the asterisks stay visible. Type one more character and they disappear.
- **Headings, list bullets, numbers, checkboxes and quote markers** reveal only the marker itself, when the cursor is right at it. Elsewhere on the line, the marker stays rendered.
- **Images, horizontal rules, tables and fenced code blocks** reveal completely whenever the cursor is anywhere inside them.
- **If you select text**, what reveals follows where the selection *started*, not where you dragged to.

Tapping a rendered link opens it. To edit a link, move into it with the arrow keys. A revealed link is plain text and doesn't open.

::: warning
On Windows and Linux, links (including the ones in the Help dialog) currently open in a separate QuKi Notes window rather than your default web browser.
:::

### Plain-text mode

The **Mode** button switches the whole QuKi to plain text: every character of markdown shown, in a monospace font, nothing rendered. Use it for bulk edits, or for pasting raw markdown. Tap it again to go back to the rendered view.

The button's icon shows where you are:

| Icon | Meaning |
|---|---|
| Open book | Rendered view, reading |
| Markdown logo (M↓) | Rendered view, editing |
| Code brackets | Plain-text mode |

QuKi Notes doesn't remember plain-text mode between launches; every launch starts in the rendered view.

## Formatting toolbar

While you're editing, a toolbar sits at the bottom of the editor:

| Button | Action |
|---|---|
| **Bold** | Wraps the selection in `**`. With no selection, inserts `****` with the cursor in the middle. |
| **Italic** | Same, with `_` |
| **Strikethrough** | Same, with `~~` |
| **Inline code** | Same, with a backtick |
| **Heading** | Cycles the line through normal → `#` → `##` → `###` → normal. The icon shows what the *next* press gives you: H1, H2, H3, or "n" for normal text. A line already at `####` or deeper goes back to normal. |
| **Unordered list** | Adds `- `, or removes it if the line already has it. On a numbered or task line, swaps that marker for `- `. |
| **Ordered list** | Same, with `1. ` |
| **Task list** | Same, with `- [ ] ` |
| **Indent** | Indents the line. See below. |
| **Dedent** | Removes one level of indentation |

With several lines selected, the heading button sets every line to the same level, taking its cue from the first line.

::: info
With several lines selected, the list buttons toggle each line on its own, so a mix of list and non-list lines stays mixed, just flipped. The list buttons also don't recognise `+ ` bullets; they add a `- ` in front instead of converting it.
:::

### Indenting

**Tab** and the **Indent** button indent the current line (or every selected line). **Shift+Tab** and **Dedent** remove a level. It works like this:

- **List, numbered and task items** move a level deeper or shallower. The checkbox state is kept.
- **Plain paragraphs** get a leading tab added or removed.
- **Horizontal rules** are left alone.
- **Headings, quotes and image lines**: Indent inserts a tab at the cursor instead of indenting the line. Dedent does nothing.

::: warning
If you select several lines that are *all* headings, quotes or images and press Tab, the selected text is replaced by a single tab. Undo (Ctrl+Z) brings it back.
:::

### Lists and quotes continue on Enter

Press **Enter** at the end of a list item, task item or quote line, and the next line starts with the same marker at the same indentation. Press Enter on an item that has nothing after its marker to end the list. **Backspace** right after a marker removes it.

## Supported markdown

| Markdown | Renders as |
|---|---|
| `# Heading` through `###### Heading` | Headings H1–H6 (the `#` needs a space after it) |
| `**bold**` or `__bold__` | Bold |
| `_italic_` or `*italic*` | Italic. `*` also works inside a word (`foo*bar*baz`); `_` doesn't. |
| `~~strikethrough~~` | Strikethrough |
| `` `code` `` | Inline code |
| `- item`, `* item`, `+ item` | Bullet list |
| `1. item` | Numbered list, renumbered from the first item's number: `1. 1. 1.` shows as 1, 2, 3 |
| `- [ ] task` / `- [x] task` | Checkbox. Checked items are struck through. |
| `[label](url)` | Link showing its label |
| `https://…`, `www.…`, email addresses | Clickable link |
| `![alt](media/picture.png)` | Image, shown inline |
| `> text` | Blockquote with a bar on the left; `>>` nests deeper |
| `---` | Horizontal rule |
| GFM pipe tables (`\| a \| b \|`) | A table, with bold, italic, code and links inside cells |
| ` ``` ` fenced code blocks | A monospace block with a shaded background and the fence lines hidden. No syntax colouring. |

Lists, task lists and quotes nest by indentation, and wrapped lines stay indented under their item. Nested numbered lists count independently of their parent.

**What isn't rendered:**

- Backslash escapes: `\*not italic\*` shows the backslashes.
- HTML is shown as literal text.
- A list inside a blockquote shows its raw markers.
- In a code block inside a blockquote, the lines between the fences show their `>` markers as part of the code.

## Images

**Pasting an image** (PNG, JPEG, GIF or WebP) from the clipboard saves it as a new file in a `media` folder inside your QuKi folder, and inserts a link to it at the cursor, such as `![](media/3f2a….png)`. The link is an ordinary relative path, so other markdown apps that open the same folder show the image too. If the clipboard holds both an image and text, the image wins.

Images linked with a relative path (like `media/…`) are read from your QuKi folder. Images from the web (`https://…`) are downloaded when the QuKi is shown. Many image hosts don't allow apps to download their images this way, and those show as a broken image.

Deleting a QuKi from Trash also deletes images that no other QuKi, active or trashed, still links to.

## Pasting a link over text

Select some text and paste a web address, and QuKi Notes turns the selection into a link: `[your text](https://…)`.

## Task checkboxes

Tap a rendered checkbox to tick or untick it. Your cursor and scroll position don't move.

## Deleting a QuKi

Tap the red **Delete** button on the far right of the top bar. There's no confirmation. The QuKi moves to Trash, you'll see "QuKi moved to Trash.", and the editor starts a new, blank QuKi. You can restore it from Trash (see [QuKis List](/user-guide/qukis-list#trash)).

## Android: share text into QuKi Notes

In any app with a share button, share text and choose **QuKi Notes**. The text is saved straight away as a new QuKi and opens in the editor, whether QuKi Notes was already running or not. Only text can be shared in; shared images and files aren't accepted.
