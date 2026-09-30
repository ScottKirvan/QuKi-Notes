# QuKis List

## Opening the list

Tap the **QuKis** button (stacked pages) at the far left of the editor's top bar. It's greyed out until you have at least one QuKi.

The list is read fresh from your QuKi folder every time you open it, so it always shows what's actually there. That includes `.md` files other programs have put in the folder.

The list's top bar has **Back** (to the editor), **New**, **Help** and **Settings**.

## What you see

QuKis are listed newest first, by when each file was last modified, whether by QuKi Notes or by another program. Each row shows:

- **A preview**: the first line that isn't blank, with any leading `#` heading markers removed, cut off at 80 characters. A QuKi with no text shows `(empty)`.
- **When it was last changed**:

| Age | Shown as |
|---|---|
| Under a minute | `just now` |
| Under an hour | `5 min ago` |
| Under a day | `3h ago` |
| 24 to 48 hours | `Yesterday` |
| Older, this year | `May 14` |
| Older, earlier year | `May 14, 2025` |

::: info
A QuKi whose file can't be read also shows `(empty)` in the list, so an `(empty)` row isn't proof the file is blank.
:::

If you have no QuKis yet, the list says so.

## Searching

Type in the **Search QuKis** box to filter the list. Search:

- runs on every keystroke
- matches anywhere in a QuKi's full text, not just the preview
- ignores upper/lower case and leading/trailing spaces

If nothing matches, the list says `No results for "…"`. Clear the box to see everything again. The search box resets each time you open the list.

## Opening a QuKi

Tap a row, or focus it with the keyboard and press **Enter** or **Space**. The QuKi opens in the editor in reading mode.

## Deleting a QuKi

Swipe a row from right to left. With a mouse, drag it to the left. A red background with a trash can shows through as you drag. Let go once you're past about 40% of the row's width, or flick quickly, and the QuKi moves to Trash with the message "QuKi moved to Trash.". Let go earlier and the row slides back.

There's no confirmation and no Undo button, but nothing is lost: the QuKi is in Trash and you can restore it from there. If the QuKi you delete is the one open in the editor, the editor switches to a new, blank QuKi.

::: tip
A short, fast flick counts as a delete, even over a small distance. If a QuKi vanishes unexpectedly, look in Trash.
:::

## Trash

Open Trash from **Settings → Notes → Trash**. Rows show the same preview and time as the QuKis list.

- **Tap a row** to restore it. You'll be asked "Restore note?". Choose **Restore** and the QuKi goes back to your list, and Trash closes.
- **Swipe a row** right to left to delete it permanently. You'll be asked "Delete forever?" first.
- **Empty Trash** (top right) permanently deletes everything in Trash, after a confirmation.

**Trash empties itself after 30 days.** Each time QuKi Notes starts, it permanently deletes anything that's been in Trash for 30 days or more. QuKis that were already in Trash before this version of QuKi Notes aren't removed automatically; empty them yourself when you're ready.

Permanently deleting a QuKi also deletes images in the `media` folder that no other QuKi, whether in your list or in Trash, still links to. An image used by a trashed QuKi stays until that QuKi is gone for good, so restoring brings its images back with it.

If a restore or delete fails in Trash, no message appears. The row simply stays where it was.
