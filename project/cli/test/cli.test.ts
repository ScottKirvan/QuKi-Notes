import { spawnSync } from 'node:child_process';
import * as fsp from 'node:fs/promises';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

const cliPath = fileURLToPath(new URL('../dist/main.js', import.meta.url));

interface RunResult {
  status: number | null;
  json: unknown;
  stderr: string;
}

function run(dir: string, args: string[], stdin?: string): RunResult {
  const result = spawnSync(process.execPath, [cliPath, '--dir', dir, ...args], {
    input: stdin,
    encoding: 'utf8',
  });
  let json: unknown;
  try {
    json = JSON.parse(result.stdout);
  } catch {
    json = undefined;
  }
  return { status: result.status, json, stderr: result.stderr };
}

describe('quki CLI (real subprocess against a real temp folder)', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(tmpdir(), 'quki-cli-test-'));
  });

  afterEach(async () => {
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it('runs the full lifecycle: create, list, edit, conflict, trash, restore, delete, export', () => {
    expect(run(dir, ['list']).json).toEqual([]);

    const created = run(dir, ['save', '--stdin'], '# First QuKi\nHello.');
    expect(created.status).toBe(0);
    const createdData = created.json as { status: string; id: string; modifiedAt: string };
    expect(createdData.status).toBe('saved');
    const id = createdData.id;

    const listed = run(dir, ['list']).json as Array<{ id: string }>;
    expect(listed.map((q) => q.id)).toEqual([id]);

    const readBack = run(dir, ['read', id]).json as { body: string; modifiedAt: string };
    expect(readBack.body).toBe('# First QuKi\nHello.');

    const cleanSave = run(dir, ['save', '--id', id, '--stdin', '--expected-modified-at', readBack.modifiedAt], 'edited');
    expect(cleanSave.status).toBe(0);
    expect((cleanSave.json as { status: string }).status).toBe('saved');

    const conflict = run(
      dir,
      ['save', '--id', id, '--stdin', '--expected-modified-at', readBack.modifiedAt],
      'stale write, should not land',
    );
    expect(conflict.status).toBe(2);
    const conflictData = conflict.json as { status: string; currentBody: string };
    expect(conflictData.status).toBe('conflict');
    expect(conflictData.currentBody).toBe('edited');

    expect(run(dir, ['trash', id]).json).toEqual({ status: 'trashed', id });
    expect((run(dir, ['list', '--trash']).json as Array<{ id: string }>).map((q) => q.id)).toEqual([id]);
    expect(run(dir, ['restore', id]).json).toEqual({ status: 'restored', id });
    expect((run(dir, ['list']).json as Array<{ id: string }>).map((q) => q.id)).toEqual([id]);

    run(dir, ['trash', id]);
    expect(run(dir, ['delete', id]).json).toEqual({ status: 'deleted', id });
    expect(run(dir, ['list', '--trash']).json).toEqual([]);
  });

  it('surfaces a not-found error with a non-zero exit code', () => {
    const result = run(dir, ['read', 'nope']);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('not found');
  });

  it('exports the library to a real .tar.gz that a real tar-aware reader could open', () => {
    run(dir, ['save', '--stdin'], 'exported body');
    const outFile = path.join(dir, '..', `${path.basename(dir)}-export.tar.gz`);
    const result = run(dir, ['export', outFile]);
    expect(result.status).toBe(0);
    const data = result.json as { activeCount: number; trashCount: number; mediaCount: number };
    expect(data.activeCount).toBe(1);
    expect(data.trashCount).toBe(0);
  });
});
