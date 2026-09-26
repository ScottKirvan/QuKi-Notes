# quki (CLI)

```
quki --dir <folder> <command> [arguments] [options]
```

`--dir` can be left out if `QUKI_DIR` is set (see [Pointing the tools at your QuKis](/command-line/#pointing-the-tools-at-your-qukis)). The examples below assume it is.

## Output and exit codes

Every command prints JSON to standard output, so it pipes straight into tools like `jq`.

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | Error. A one-line message starting `Error:` goes to standard error. |
| `2` | `save` was refused because of a conflict (see [save](#save)). The conflict details are printed as JSON on standard output. |

::: warning
Put options **after** the command's other arguments: `quki search milk --trash`, not `quki search --trash milk`. An option placed before an argument swallows that argument as its value. For `search` that means the search silently runs with no query and returns every QuKi. Unrecognised options are ignored without an error, so a typo such as `--keep-image` (instead of `--keep-images`) has no effect.
:::

## Commands

### list

```sh
quki list            # your QuKis, newest first
quki list --trash    # what's in Trash
```

```json
[
  {
    "id": "cacc9b0e-4063-412d-80ee-dc001366871a",
    "filename": "cacc9b0e-4063-412d-80ee-dc001366871a.md",
    "createdAt": "2026-09-26T15:05:49.807Z",
    "modifiedAt": "2026-09-26T15:05:49.805Z"
  }
]
```

`modifiedAt` is the file's modification time on disk. `createdAt` comes from QuKi Notes' own record where one exists, otherwise from the file. With `--trash`, each entry also has `deletedAt`: when it was trashed, or `null` if that isn't known. A QuKi with a `null` `deletedAt` is never removed automatically.

### read

```sh
quki read <id>
quki read <id> --trash    # read a trashed QuKi without restoring it
```

```json
{
  "id": "cacc9b0e-4063-412d-80ee-dc001366871a",
  "filename": "cacc9b0e-4063-412d-80ee-dc001366871a.md",
  "body": "Buy milk\n- [ ] eggs\n",
  "createdAt": "2026-09-26T15:05:49.807Z",
  "modifiedAt": "2026-09-26T15:05:49.805Z"
}
```

An unknown ID prints `Error: QuKi not found: <id>` and exits with `1`.

### save

Creates a new QuKi, or updates an existing one. The text comes from a file or from standard input:

```sh
echo "Call the dentist" | quki save --stdin          # new QuKi
quki save --file notes.md                            # new QuKi from a file
quki save --id <id> --expected-modified-at <time> --file notes.md   # update
```

A new QuKi gets a random ID, returned in the result:

```json
{
  "status": "saved",
  "id": "cacc9b0e-4063-412d-80ee-dc001366871a",
  "filename": "cacc9b0e-4063-412d-80ee-dc001366871a.md",
  "createdAt": "2026-09-26T15:05:49.807Z",
  "modifiedAt": "2026-09-26T15:05:49.805Z"
}
```

**Updating needs `--expected-modified-at`**: the `modifiedAt` from your last `read` or `save` of that QuKi. It proves you're editing the version you last saw. Leaving it out is an error. If the file changed after that time (in the app, another editor, a sync client), or was deleted, nothing is written. Instead you get the current state and exit code `2`:

```json
{
  "status": "conflict",
  "id": "cacc9b0e-4063-412d-80ee-dc001366871a",
  "reason": "modified",
  "currentModifiedAt": "2026-09-26T15:05:50.025Z",
  "currentBody": "changed elsewhere\n"
}
```

`reason` is `"deleted"` (with `null` for both `current…` fields) if the file is gone. There's no option to force an overwrite. Merge your change into `currentBody` and save again with `currentModifiedAt`:

```sh
QUKI=cacc9b0e-4063-412d-80ee-dc001366871a
seen=$(quki read "$QUKI" | jq -r .modifiedAt)
result=$(printf 'Updated text\n' | quki save --id "$QUKI" --expected-modified-at "$seen" --stdin) && status=0 || status=$?
case $status in
  0) echo "$result" | jq -r .modifiedAt ;;      # the baseline for your next update
  2) echo "Changed elsewhere; current text is:" >&2
     echo "$result" | jq -r .currentBody >&2
     exit 2 ;;
  *) exit "$status" ;;                          # the error message is already on stderr
esac
```

**Empty text is never written.** Saving an empty body returns `{"status": "skipped-empty", "id": …}` and leaves any existing file untouched. Only completely empty text counts. `echo` adds a newline, so `echo "" | quki save --stdin` *does* create a QuKi containing a blank line.

The text is saved exactly as given, trailing newline included.

### trash and restore

```sh
quki trash <id>      # {"status": "trashed", "id": "…"}
quki restore <id>    # {"status": "restored", "id": "…"}
```

Both exit with `1` and `Error: … not found` for an unknown ID.

::: warning
`trash` replaces a QuKi already in Trash with the same ID, and `restore` replaces an active QuKi with the same ID, without asking. IDs created by QuKi Notes never collide, so this only matters for files you've named yourself.
:::

### delete

```sh
quki delete <id>                  # permanently delete a trashed QuKi
quki delete <id> --keep-images    # ...but keep its images
```

Deletes a QuKi that's in Trash for good. By default it also deletes any image in `media/` that the QuKi linked to and no other QuKi, active or trashed, still links to. `delete` only works on trashed QuKis; `trash` first.

It prints `{"status": "deleted", "id": "…"}` even if there was no trashed QuKi with that ID, so don't treat the output as proof something was deleted.

### empty-trash

```sh
quki empty-trash [--keep-images]    # {"deletedCount": 3}
```

Permanently deletes everything in Trash, whatever its age.

### purge-expired

```sh
quki purge-expired [--keep-images]  # {"purgedIds": ["…"]}
```

Permanently deletes only QuKis that have been in Trash for 30 days or more. It's the same clean-up the app runs at every launch. Run it from a scheduled job if you use the tools without the app.

### search

```sh
quki search "dentist"
quki search "dentist" --trash    # also search Trash
```

Returns the same entries as `list`, for every QuKi whose text contains the query anywhere. Matching ignores case and leading or trailing spaces. An empty query returns everything. With `--trash`, active matches come first, then trashed ones.

### export

```sh
quki export ~/backups/qukis-2026-09-26.tar.gz
```

```json
{ "path": "/home/you/backups/qukis-2026-09-26.tar.gz", "activeCount": 42, "trashCount": 7, "mediaCount": 5 }
```

Writes the whole library to one `.tar.gz` archive: every QuKi, everything in Trash, QuKi Notes' records of when each was created and trashed, and the `media` folder. Extracting it gives you a folder QuKi Notes can open as-is. It overwrites the output file if it exists.

::: warning
Export fails with an error if the `media` folder contains a subfolder. It also doesn't yet include the folder's `.quki` settings folder, if you have one.
:::

### write-image

```sh
quki write-image ~/Pictures/receipt.jpg
```

```json
{ "relativePath": "media/5b1e….jpg", "absolutePath": "/home/you/QuKi/media/5b1e….jpg" }
```

Copies an image into the QuKi folder's `media` folder under a new random name. Nothing links to it yet: put `![](media/5b1e….jpg)` into a QuKi to show it. The extension comes from the source file name; override it with `--ext png`.
