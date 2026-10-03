import * as fsp from 'node:fs/promises';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const serverPath = fileURLToPath(new URL('../dist/server.js', import.meta.url));

/**
 * Drives the real MCP server (spawned as a child process, speaking real
 * stdio JSON-RPC) with the real MCP client SDK, against a real temp folder.
 * This is the "start the MCP server and exercise it end-to-end" proof - not
 * a mock of the protocol.
 */
describe('quki-mcp server (end-to-end over stdio)', () => {
  let dir: string;
  let client: Client;
  let transport: StdioClientTransport;

  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-test-'));
    transport = new StdioClientTransport({ command: process.execPath, args: [serverPath, dir] });
    client = new Client({ name: 'quki-mcp-test-client', version: '0.0.0' });
    await client.connect(transport);
  });

  afterEach(async () => {
    await client.close();
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it('lists the expected tools', async () => {
    const { tools } = await client.listTools();
    const names = tools.map((t) => t.name);
    expect(names).toEqual(
      expect.arrayContaining([
        'quki_list_active',
        'quki_list_trash',
        'quki_read',
        'quki_read_trash',
        'quki_save',
        'quki_trash',
        'quki_restore',
        'quki_delete',
        'quki_empty_trash',
        'quki_purge_expired_trash',
        'quki_search',
        'quki_write_image',
        'quki_export',
      ]),
    );
  });

  it('creates, reads, conflict-detects, trashes, restores and deletes a QuKi', async () => {
    const created = await client.callTool({ name: 'quki_save', arguments: { body: '# Hello from MCP' } });
    expect(created.isError).toBeFalsy();
    const createdData = created.structuredContent as { status: string; id: string };
    expect(createdData.status).toBe('saved');
    const id = createdData.id;

    const listed = await client.callTool({ name: 'quki_list_active', arguments: {} });
    expect((listed.structuredContent as { qukis: { id: string }[] }).qukis.map((q) => q.id)).toContain(id);

    const readBack = await client.callTool({ name: 'quki_read', arguments: { id } });
    const readData = readBack.structuredContent as { body: string; modifiedAt: string };
    expect(readData.body).toBe('# Hello from MCP');

    const updated = await client.callTool({
      name: 'quki_save',
      arguments: { id, body: '# Hello, edited', expectedModifiedAt: readData.modifiedAt },
    });
    expect((updated.structuredContent as { status: string }).status).toBe('saved');

    const conflict = await client.callTool({
      name: 'quki_save',
      arguments: { id, body: 'should not land', expectedModifiedAt: readData.modifiedAt },
    });
    const conflictData = conflict.structuredContent as { status: string; currentBody: string };
    expect(conflictData.status).toBe('conflict');
    expect(conflictData.currentBody).toBe('# Hello, edited');

    await client.callTool({ name: 'quki_trash', arguments: { id } });
    const trashList = await client.callTool({ name: 'quki_list_trash', arguments: {} });
    expect((trashList.structuredContent as { qukis: { id: string }[] }).qukis.map((q) => q.id)).toContain(id);

    await client.callTool({ name: 'quki_restore', arguments: { id } });
    const activeAgain = await client.callTool({ name: 'quki_list_active', arguments: {} });
    expect((activeAgain.structuredContent as { qukis: { id: string }[] }).qukis.map((q) => q.id)).toContain(id);

    await client.callTool({ name: 'quki_trash', arguments: { id } });
    const deleted = await client.callTool({ name: 'quki_delete', arguments: { id } });
    expect((deleted.structuredContent as { status: string }).status).toBe('deleted');

    const finalTrash = await client.callTool({ name: 'quki_list_trash', arguments: {} });
    expect((finalTrash.structuredContent as { qukis: { id: string }[] }).qukis.map((q) => q.id)).not.toContain(id);
  });

  it('reports a not-found error with an actionable message instead of throwing raw', async () => {
    const result = await client.callTool({ name: 'quki_read', arguments: { id: 'does-not-exist' } });
    expect(result.isError).toBe(true);
    const text = (result.content as Array<{ type: string; text: string }>)[0]?.text ?? '';
    expect(text).toContain('not found');
    expect(text).toContain('quki_list_active');
  });

  it('writes an image, references it, and exports the library to disk rather than inline bytes', async () => {
    const bytes = Buffer.from([1, 2, 3, 4]).toString('base64');
    const image = await client.callTool({
      name: 'quki_write_image',
      arguments: { bytesBase64: bytes, extension: 'png' },
    });
    const imageData = image.structuredContent as { relativePath: string; absolutePath: string };
    expect(imageData.relativePath).toMatch(/^media\/.+\.png$/);
    expect(imageData.absolutePath.startsWith(path.normalize(dir))).toBe(true);

    await client.callTool({ name: 'quki_save', arguments: { body: `![i](${imageData.relativePath})` } });

    const outputPath = path.join(dir, '..', `${path.basename(dir)}-export.tar.gz`);
    const exported = await client.callTool({ name: 'quki_export', arguments: { outputPath } });
    expect(exported.isError).toBeFalsy();
    const exportData = exported.structuredContent as {
      path: string;
      activeCount: number;
      trashCount: number;
      mediaCount: number;
    };
    expect(exportData.activeCount).toBe(1);
    expect(exportData.mediaCount).toBe(1);
    expect(exportData.path).toBe(outputPath);
    expect(exportData).not.toHaveProperty('bytesBase64');

    // The tool result itself must never carry the archive bytes inline -
    // only counts and the path, regardless of how large the real archive is.
    const resultText = JSON.stringify(exported);
    expect(resultText).not.toContain('bytesBase64');

    const onDisk = await fsp.readFile(outputPath);
    expect(onDisk.length).toBeGreaterThan(0);
    // A gzip member always starts with this two-byte magic number.
    expect(onDisk[0]).toBe(0x1f);
    expect(onDisk[1]).toBe(0x8b);

    await fsp.rm(outputPath, { force: true });
  });

  it('quki_delete on an id that was never trashed reports an error, not fake success', async () => {
    const result = await client.callTool({ name: 'quki_delete', arguments: { id: 'never-existed' } });
    expect(result.isError).toBe(true);
    const text = (result.content as Array<{ type: string; text: string }>)[0]?.text ?? '';
    expect(text).toContain('not found');
  });

  it('search finds a substring match, case-insensitively', async () => {
    await client.callTool({ name: 'quki_save', arguments: { body: 'a very unique phrase XYZZY here' } });
    const results = await client.callTool({ name: 'quki_search', arguments: { query: 'xyzzy' } });
    const data = results.structuredContent as { results: { id: string }[] };
    expect(data.results).toHaveLength(1);
  });
});
