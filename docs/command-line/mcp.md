# quki-mcp (MCP server)

`quki-mcp` lets an AI assistant work with your QuKis: list, read, search, write, trash and restore them. It's a [Model Context Protocol](https://modelcontextprotocol.io) server that talks over standard input and output, so any MCP client that can launch a local ("stdio") server can use it.

```
quki-mcp <folder>
```

or, with `QUKI_DIR` set, just `quki-mcp`. Your client starts and stops it for you; you don't normally run it by hand. Without a folder it prints a usage line and exits with code `1`.

::: warning
Whatever the assistant reads from your QuKis goes to the assistant's provider, under their privacy terms. The assistant can also change and permanently delete QuKis. The tools that permanently delete are marked as destructive, for clients that use that hint when asking you to approve a call. Read what you're approving.
:::

## Connecting a client

Replace the folder path with your own. See [Pointing the tools at your QuKis](/command-line/#pointing-the-tools-at-your-qukis) for how to find it.

**Claude Desktop, and other clients configured with an `mcpServers` JSON file:**

```json
{
  "mcpServers": {
    "quki": {
      "command": "quki-mcp",
      "args": ["/home/you/Documents/qukis"]
    }
  }
}
```

On Windows, write backslashes in the path twice: `"C:\\Users\\you\\Documents\\qukis"`.

**Claude Code:**

```sh
claude mcp add quki -- quki-mcp /home/you/Documents/qukis
```

If the client reports that it can't start the server, it usually can't find `quki-mcp` on its `PATH`. Desktop apps often don't see the same `PATH` as your terminal. Put the tool's full path in `command` instead.

## Tools

IDs are file names without `.md`, as in the [CLI](/command-line/cli). Every result is returned both as JSON text and as structured content.

| Tool | Inputs | Returns | Changes files? |
|---|---|---|---|
| `quki_list_active` | none | `qukis`: `id`, `filename`, `createdAt`, `modifiedAt` for each QuKi, newest first | No |
| `quki_list_trash` | none | `qukis`: the same fields plus `deletedAt` (`null` if unknown) | No |
| `quki_read` | `id` | `id`, `filename`, `body`, `createdAt`, `modifiedAt` | No |
| `quki_read_trash` | `id` | The same, for a trashed QuKi (without restoring it) | No |
| `quki_search` | `query`; `includeTrash` (default `false`) | `results`: matching QuKis. Case-insensitive, anywhere in the text; an empty query returns everything. | No |
| `quki_save` | `body`; `id` and `expectedModifiedAt` to update | `status`: `saved`, `skipped-empty` or `conflict`, plus details | Yes |
| `quki_trash` | `id` | `status: "trashed"` | Yes (recoverable) |
| `quki_restore` | `id` | `status: "restored"` | Yes |
| `quki_delete` | `id`; `deleteOrphanedImages` (default `true`) | `status: "deleted"` | **Permanent** |
| `quki_empty_trash` | `deleteOrphanedImages` (default `true`) | `deletedCount` | **Permanent** |
| `quki_purge_expired_trash` | `deleteOrphanedImages` (default `true`) | `purgedIds` | **Permanent** |
| `quki_write_image` | `bytesBase64`, `extension` (e.g. `png`) | `relativePath` to use in `![](…)`, plus `absolutePath` | Yes |
| `quki_export` | none | `bytesBase64`: the whole library as a `.tar.gz`, plus counts | No |

### Saving and conflicts

`quki_save` works exactly like [`quki save`](/command-line/cli#save):

- Leave out `id` to create a new QuKi.
- To update, pass `id` and `expectedModifiedAt`, which is the `modifiedAt` from the last read or save of that QuKi. Leaving `expectedModifiedAt` out returns an error.
- If the file has changed or been deleted since, nothing is written. The result is `status: "conflict"` with `reason` (`modified` or `deleted`), `currentModifiedAt` and `currentBody`. It's a normal result, not an error, so the assistant can merge and try again.
- An empty `body` is never written: the result is `skipped-empty` and the existing file stays as it was.

### Errors

A failed tool call returns an error result whose text starts with `Error:`. For an unknown ID it adds a hint to check the ID against `quki_list_active` or `quki_list_trash`. `quki_delete` is the exception: it reports `deleted` even for an ID that isn't in Trash.

### Limits

- **`quki_export` returns the entire library, images included, inside the tool result.** For anything but a small library that's likely more than your client or model will accept. Use [`quki export`](/command-line/cli#export) from a terminal for backups.
- **Trash isn't emptied on a schedule.** Nothing runs `quki_purge_expired_trash` for you; the desktop app does the 30-day clean-up when it starts.
- **`quki_write_image` only stores the image.** Add the returned `relativePath` to a QuKi with `quki_save` to show it.
