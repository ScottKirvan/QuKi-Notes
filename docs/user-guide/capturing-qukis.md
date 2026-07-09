# Capturing QuKis

## The editor

The editor is the first thing you see when you open the app. It is always home.

Open QuKi Notes. Type. That is the full workflow for capture.

## Auto-save

There is no save button and no draft state. Your QuKi is always current.

## Creating a new QuKi

The app opens to a blank editor — that's a new QuKi. Just type.

Tap **+** in the top bar to start a new QuKi from anywhere in the app.

## How the editor works

The editor shows your QuKi in rendered form as you type. Headings appear as headings, links show their label, images appear inline, and checkboxes look like checkboxes. The one exception is whatever element your cursor is currently inside — that element reveals its raw markdown source so you can edit it character by character. Move the cursor away, and it renders again.

There is no "edit mode" and no tap-to-flip. The note is always live.

**Navigating into rendered elements:**

- Pressing an arrow key into a rendered element reveals it and places the cursor at the near boundary. Navigate through it character by character. Move past the far end and it collapses again.
- Tapping inside a rendered element reveals it and places the cursor at the character you tapped on.
- Tapping a rendered link opens it in the browser. To edit a link's source, navigate into it with the keyboard.

### Plain-text toggle

Tap the **Type** icon (T) in the app bar to collapse the entire note to a single plain-text field. Use this for bulk selection, raw markdown paste, or any operation that is easier without live rendering. Tap the icon again to return to live-preview mode.

## Formatting toolbar

A toolbar appears at the bottom of the editor with these buttons:

| Button | Action |
|---|---|
| **B** | Bold — wraps selection with `**` |
| _I_ | Italic — wraps selection with `_` |
| ~~S~~ | Strikethrough — wraps selection with `~~` |
| `</>` | Inline code — wraps selection with `` ` `` |
| H1 | Heading — adds or removes `# ` prefix on the current line |
| List | Unordered list — adds or removes `- ` prefix |
| 1. | Ordered list — adds or removes `1. ` prefix |
| ☐ | Task list — adds `- [ ] ` prefix |

### List auto-continue

Press Enter at the end of a list item and the next line starts with the same list prefix. Press Enter on an empty list item to exit the list.

## Supported markdown

The following elements render in the editor:

| Markdown | Renders as |
|---|---|
| `# Heading` through `###### Heading` | Headings H1–H6 |
| `**bold**` | Bold |
| `_italic_` or `*italic*` | Italic |
| `~~strikethrough~~` | Strikethrough |
| `` `code` `` | Inline code |
| `- item` or `* item` | Unordered list with bullet glyph |
| `1. item` | Ordered list with computed number |
| `- [ ] task` / `- [x] task` | Task checkbox (unchecked / checked) |
| `[label](url)` | Link — shows label; tap to open URL |
| `![alt](path)` | Embedded image |
| `> text` | Blockquote |
| `---` | Horizontal rule |
| `http://...` bare URL | Autolink |

Fenced code blocks (` ``` `) and tables are not rendered — they display as raw text so pasted code is never altered.

## Task checkboxes

Tap a rendered checkbox to toggle it between unchecked (`- [ ]`) and checked (`- [x]`) without entering edit mode.

## Android: share text into QuKi Notes

On Android, you can share text from any other app directly into QuKi Notes. Use the standard share sheet and choose **QuKi Notes**. A new QuKi opens with the shared text pre-loaded.
