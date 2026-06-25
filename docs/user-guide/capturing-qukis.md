# Capturing QuKis

## The editor

The editor is the first thing you see when you open the app. It is always home.

Open QuKi Notes. Type. That is the full workflow for capture.

## Auto-save

There is no save button and no draft state. Your QuKi is always current.

## Creating a new QuKi

The app opens to a blank editor — that's a new QuKi. Just type.

From anywhere in the app, tap **+** in the top bar to start a new QuKi.

## How the editor works

The editor uses a block-flip model. Each line is an independent block:

- When you are not editing a block, it renders as formatted markdown — bold text appears bold, headings appear large, task items appear as checkboxes.
- Tap a block to edit it. It flips to a plain text field showing the raw markdown.
- Tap away (or move to another block) and it flips back to rendered output.

This means you always see formatted output except on the line you are actively typing.

### Plain-text toggle

Tap the **T** icon in the app bar to switch the entire document to a single plain-text field. Tap it again to return to block-flip mode. Use this when you want to select across multiple blocks or paste raw markdown.

## Formatting toolbar

A toolbar appears at the bottom of the editor with these buttons:

| Button | Action |
|---|---|
| **B** | Bold — wraps selection with `**` |
| _I_ | Italic — wraps selection with `_` |
| ~~S~~ | Strikethrough — wraps selection with `~~` |
| H1 | Heading — adds or removes `# ` prefix on the current line |
| List | Unordered list — adds or removes `- ` prefix |
| 1. | Ordered list — adds or removes `1. ` prefix |
| ☐ | Task list — adds `- [ ] ` prefix |

### List auto-continue

Press Enter at the end of a list item and the next line starts with the same list prefix. Press Enter on an empty list item to exit the list.

### Inline shortcuts

Type these sequences and they convert immediately:

| Type | Result |
|---|---|
| `**word**` | **bold** |
| `_word_` or `*word*` | _italic_ |
| `` `word` `` | `inline code` |
| `- [ ] ` (at the start of a line) | task list item |

Heading markers (`# `, `## `, etc.) and blockquotes (`> `) are also recognised. Fenced code blocks (` ``` `) do not render — they display as plain text.

## Task checkboxes

In block-flip mode, tap a rendered checkbox to toggle it between unchecked (`- [ ]`) and checked (`- [x]`) without entering edit mode.

## Keyboard navigation between blocks

When editing a block, pressing the up arrow at the start of the text moves focus to the previous block. Pressing the down arrow at the end of the text moves focus to the next block.

## Android: share text into QuKi Notes

On Android, you can share text from any other app directly into QuKi Notes. Use the standard share sheet and choose **QuKi Notes**. A new QuKi opens with the shared text pre-loaded.
