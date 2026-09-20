#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { NotFoundError, QuKiStore } from 'quki-core';
import { NodeFsBackend } from 'quki-core/node';
import { z } from 'zod';

import {
  exportOutputShape,
  listActiveOutputShape,
  listTrashOutputShape,
  quKiDetailShape,
  saveResultShape,
  searchOutputShape,
  writeImageOutputShape,
} from './schemas.js';

type ToolResult = {
  content: Array<{ type: 'text'; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

function ok(value: object): ToolResult {
  return {
    content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
    structuredContent: value as Record<string, unknown>,
  };
}

function errorResult(err: unknown): ToolResult {
  const message = err instanceof Error ? err.message : String(err);
  const hint = err instanceof NotFoundError ? ' Check the id against quki_list_active or quki_list_trash.' : '';
  return { content: [{ type: 'text', text: `Error: ${message}${hint}` }], isError: true };
}

function wrap(fn: () => Promise<ToolResult>): Promise<ToolResult> {
  return fn().catch((err: unknown) => errorResult(err));
}

export function createServer(rootDir: string): McpServer {
  const store = new QuKiStore(new NodeFsBackend(rootDir));

  const server = new McpServer({ name: 'quki-mcp', version: '0.1.0' });

  server.registerTool(
    'quki_list_active',
    {
      title: 'List active QuKis',
      description:
        'Lists every QuKi currently in the QuKi folder (not trashed). Scans the folder fresh on every call - ' +
        'there is no cache, so this always reflects the current filesystem state, including files placed there by other programs.',
      outputSchema: listActiveOutputShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    () => wrap(async () => ok({ qukis: await store.list() })),
  );

  server.registerTool(
    'quki_list_trash',
    {
      title: 'List trashed QuKis',
      description: 'Lists every QuKi currently in the trash, including its deletedAt timestamp (null if unknown).',
      outputSchema: listTrashOutputShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    () => wrap(async () => ok({ qukis: await store.listTrash() })),
  );

  server.registerTool(
    'quki_read',
    {
      title: 'Read an active QuKi',
      description: 'Reads one active QuKi\'s full body and metadata by id. Use the returned modifiedAt as expectedModifiedAt on a later quki_save.',
      inputSchema: { id: z.string().describe('The QuKi id, i.e. its filename without the .md extension.') },
      outputSchema: quKiDetailShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    ({ id }) => wrap(async () => ok(await store.read(id))),
  );

  server.registerTool(
    'quki_read_trash',
    {
      title: 'Read a trashed QuKi',
      description: 'Reads one trashed QuKi\'s full body and metadata by id, without restoring it.',
      inputSchema: { id: z.string().describe('The QuKi id, i.e. its filename without the .md extension.') },
      outputSchema: quKiDetailShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    ({ id }) => wrap(async () => ok(await store.readTrash(id))),
  );

  server.registerTool(
    'quki_save',
    {
      title: 'Create or update a QuKi',
      description:
        'Creates a new QuKi (omit id) or updates an existing one (pass id). Updating REQUIRES expectedModifiedAt - ' +
        'the modifiedAt from your most recent quki_read or quki_save on this id - so a concurrent edit is detected ' +
        'rather than overwritten; a mismatch comes back as status "conflict" with the current body, not an error. ' +
        'Saving an empty body never erases the QuKi: it comes back as status "skipped-empty" and the previous content stays on disk.',
      inputSchema: {
        id: z.string().optional().describe('Omit to create a new QuKi. Provide to update an existing one.'),
        body: z.string().describe('The full markdown body to save.'),
        expectedModifiedAt: z
          .string()
          .optional()
          .describe('Required when updating (id is set). The modifiedAt baseline from your last read of this QuKi.'),
      },
      outputSchema: saveResultShape,
      annotations: { readOnlyHint: false, idempotentHint: false, openWorldHint: false },
    },
    ({ id, body, expectedModifiedAt }) =>
      wrap(async () => ok(await store.save({ id: id ?? null, body, expectedModifiedAt }))),
  );

  server.registerTool(
    'quki_trash',
    {
      title: 'Move a QuKi to trash',
      description: 'Moves an active QuKi to trash. Recoverable with quki_restore for 30 days, after which purgeExpiredTrash removes it.',
      inputSchema: { id: z.string() },
      outputSchema: { status: z.literal('trashed'), id: z.string() },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    ({ id }) =>
      wrap(async () => {
        await store.moveToTrash(id);
        return ok({ status: 'trashed', id });
      }),
  );

  server.registerTool(
    'quki_restore',
    {
      title: 'Restore a QuKi from trash',
      description: 'Moves a trashed QuKi back to active. Its images, if any, come back intact.',
      inputSchema: { id: z.string() },
      outputSchema: { status: z.literal('restored'), id: z.string() },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    ({ id }) =>
      wrap(async () => {
        await store.restore(id);
        return ok({ status: 'restored', id });
      }),
  );

  server.registerTool(
    'quki_delete',
    {
      title: 'Permanently delete a trashed QuKi',
      description:
        'Permanently deletes a QuKi already in trash. Cannot be undone. By default, also deletes any image the ' +
        'QuKi referenced in media/ if no other active or trashed QuKi still references it.',
      inputSchema: {
        id: z.string(),
        deleteOrphanedImages: z.boolean().optional().describe('Default true. Set false to keep now-unreferenced images.'),
      },
      outputSchema: { status: z.literal('deleted'), id: z.string() },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    ({ id, deleteOrphanedImages }) =>
      wrap(async () => {
        await store.permanentlyDelete(id, { deleteOrphanedImages });
        return ok({ status: 'deleted', id });
      }),
  );

  server.registerTool(
    'quki_empty_trash',
    {
      title: 'Empty the entire trash',
      description: 'Permanently deletes every QuKi currently in trash, regardless of age. Cannot be undone.',
      inputSchema: {
        deleteOrphanedImages: z.boolean().optional().describe('Default true. Set false to keep now-unreferenced images.'),
      },
      outputSchema: { deletedCount: z.number() },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    ({ deleteOrphanedImages }) => wrap(async () => ok(await store.emptyTrash({ deleteOrphanedImages }))),
  );

  server.registerTool(
    'quki_purge_expired_trash',
    {
      title: 'Purge trash older than 30 days',
      description:
        'Permanently deletes only trashed QuKis whose deletedAt is at least 30 days old. There is no "app launch" ' +
        'in this environment, so callers decide when to invoke this - e.g. once per CLI/MCP session start.',
      inputSchema: {
        deleteOrphanedImages: z.boolean().optional().describe('Default true. Set false to keep now-unreferenced images.'),
      },
      outputSchema: { purgedIds: z.array(z.string()) },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    ({ deleteOrphanedImages }) => wrap(async () => ok(await store.purgeExpiredTrash({ deleteOrphanedImages }))),
  );

  server.registerTool(
    'quki_search',
    {
      title: 'Search QuKis by body text',
      description:
        'Case-insensitive substring search over every QuKi body (trimmed query). Reads every body on every call by ' +
        'design - the collection is small (~100 active) and no index is maintained.',
      inputSchema: {
        query: z.string().describe('Substring to search for. An empty/whitespace-only query returns the full active list.'),
        includeTrash: z.boolean().optional().describe('Default false. Set true to also search trashed QuKis.'),
      },
      outputSchema: searchOutputShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    ({ query, includeTrash }) => wrap(async () => ok({ results: await store.search(query, { includeTrash }) })),
  );

  server.registerTool(
    'quki_write_image',
    {
      title: 'Write an image into media/',
      description:
        'Writes base64-encoded image bytes into the shared media/ folder under a generated name and returns the ' +
        'relative link to embed in a QuKi body, e.g. ![alt](media/xxxx.png), plus the resolved absolute path.',
      inputSchema: {
        bytesBase64: z.string().describe('The image file contents, base64-encoded.'),
        extension: z.string().describe('File extension without the dot, e.g. "png" or "jpg".'),
      },
      outputSchema: writeImageOutputShape,
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    ({ bytesBase64, extension }) =>
      wrap(async () => ok(await store.writeImage(Buffer.from(bytesBase64, 'base64'), extension))),
  );

  server.registerTool(
    'quki_export',
    {
      title: 'Export the entire library',
      description:
        'Produces the complete library - every active and trashed QuKi, their sidecars, and every image in media/ - ' +
        'as one gzipped tar archive mirroring the QuKi folder layout, base64-encoded. This is the backup and migration story.',
      outputSchema: exportOutputShape,
      annotations: { readOnlyHint: true, idempotentHint: true, openWorldHint: false },
    },
    () =>
      wrap(async () => {
        const result = await store.exportLibrary();
        return ok({
          bytesBase64: Buffer.from(result.bytes).toString('base64'),
          activeCount: result.activeCount,
          trashCount: result.trashCount,
          mediaCount: result.mediaCount,
        });
      }),
  );

  return server;
}

async function main(): Promise<void> {
  const rootDir = process.argv[2] ?? process.env.QUKI_DIR;
  if (!rootDir) {
    process.stderr.write('Usage: quki-mcp <qukiFolderPath>  (or set QUKI_DIR)\n');
    process.exit(1);
  }
  const server = createServer(rootDir);
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err: unknown) => {
  process.stderr.write(`Fatal: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`);
  process.exit(1);
});
