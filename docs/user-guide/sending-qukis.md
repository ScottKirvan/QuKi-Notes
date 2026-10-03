# Sending QuKis

## How sending works

Send is one button: the <i-lucide-send /> paper plane in the editor's top bar. There's no list of destinations to pick from. It does the natural thing for the platform you're on:

| Platform | What Send does                                                  |
| -------- | --------------------------------------------------------------- |
| Android  | Opens the system share sheet. Pick any app to receive the text. |
| Windows  | Copies the QuKi's full text to the clipboard                    |
| Linux    | Copies the QuKi's full text to the clipboard                    |
| Web      | Opens your device's share sheet where the browser supports it; otherwise copies the QuKi's full text to the clipboard |

Send always sends the markdown source, exactly as you'd see it in plain-text mode.

Before sending, QuKi Notes saves the QuKi, so what you send is also what's on disk.

## After sending

A short message confirms it: "Copied to clipboard." on Windows and Linux, and on the web when it copies. Where the web version opens the share sheet, the share sheet is the confirmation, and backing out of it does nothing. On Android the share sheet itself is the confirmation, though the same "Copied to clipboard." message currently appears there too. Nothing was copied; the text went only to the app you picked.

If sending fails, you'll see "Send failed — unexpected error." with a **Retry** button.

## When nothing happens

- **Empty QuKi**: "Nothing to send — write something first." A QuKi containing only spaces isn't empty and will send.

There are no keyboard shortcuts for Send.
