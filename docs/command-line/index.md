# Command Line & MCP

The QuKi Notes desktop app comes with two command-line tools that work directly on your QuKi folder:

- **`quki`**: a command-line tool for listing, reading, writing, searching, trashing and exporting QuKis from a terminal or script. See [quki (CLI)](/command-line/cli).
- **`quki-mcp`**: a [Model Context Protocol](https://modelcontextprotocol.io) server that gives an AI assistant (Claude Desktop, Claude Code, or any other MCP client) the same abilities as tools it can call. See [quki-mcp (MCP server)](/command-line/mcp).

Both work on the same plain `.md` files the app uses, so anything they change shows up in the app, and the other way round. You don't need the app running to use them.

They're available on Windows and Linux. The Android and web versions don't include them.

## Installing

### Windows

The QuKi Notes installer has an optional **Command-line tools** component. Tick it during installation and `quki` and `quki-mcp` are added to your `PATH`. Open a new terminal afterwards so it picks up the change.

If you skipped it, run the installer again and select the component.

### Linux

The tools are included in the QuKi Notes AppImage. Link them into a folder on your `PATH` once, pointing at wherever you keep the AppImage:

```sh
ln -s ~/Applications/QuKi-Notes.AppImage ~/.local/bin/quki
ln -s ~/Applications/QuKi-Notes.AppImage ~/.local/bin/quki-mcp
```

When run as `quki` or `quki-mcp`, the AppImage runs that tool instead of opening the app.

The links point at that exact file. If you move or rename the AppImage, run the two commands again with the new path.

### Checking it works

```sh
quki
```

With no arguments, `quki` prints its usage and exits with code `1`. If you get "command not found" instead, the tool isn't on your `PATH` yet.

## Pointing the tools at your QuKis

Neither tool finds your QuKi folder on its own. Give it the folder path each time, or set the `QUKI_DIR` environment variable once:

| Tool | Folder from an argument | Or from the environment |
|---|---|---|
| `quki` | `quki --dir <folder> list` | `QUKI_DIR=<folder> quki list` |
| `quki-mcp` | `quki-mcp <folder>` | `QUKI_DIR=<folder> quki-mcp` |

To find the folder the app is using, open **Settings → Storage** in the app. If you chose **Use app storage** on Windows or Linux, it's the `qukis` folder inside your Documents folder.

Point the tools at the QuKi folder itself: the one containing your `.md` files, not its parent. If the folder doesn't exist yet, the first command that writes to it creates it.

## Things to know

- **IDs are file names.** A QuKi's ID is its file name without `.md`. QuKis created by the app have random IDs such as `cacc9b0e-4063-412d-80ee-dc001366871a`. A file you created yourself keeps its own name, so `shopping.md` has the ID `shopping`.
- **Every read is fresh.** The tools read the folder each time; there's no cache to get out of date. Files added by any program appear straight away.
- **Edits are checked against the file.** To update a QuKi you pass the modified time you last read. If the file has changed since, the update is refused and you get the current text back instead, so neither the app nor the tools silently overwrite each other.
- **The app notices changes made by the tools**, but only when it next tries to save. If you change the QuKi that's open in the app, the app shows a "Could not save — it changed elsewhere" banner rather than overwriting your change.
- **Empty text is never saved.** Saving an empty body is skipped and the existing file is left alone, exactly as in the app.
- **Trash isn't emptied automatically by the tools.** The 30-day clean-up runs when the app starts. From the tools, run it yourself with `quki purge-expired` or the `quki_purge_expired_trash` tool.
