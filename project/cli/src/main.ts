import { readFileSync, writeFileSync } from 'node:fs';

import { QuKiStore } from 'quki-core';
import { NodeFsBackend } from 'quki-core/node';

import { parseArgs, stringFlag } from './argv.js';

function printJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function fail(message: string): never {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk as Buffer));
  return Buffer.concat(chunks).toString('utf8');
}

const USAGE =
  'usage: quki --dir <path> <command> [args]\n' +
  'commands: list [--trash] | read <id> [--trash] | save [--id <id>] (--file <path> | --stdin) [--expected-modified-at <iso>] | ' +
  'trash <id> | restore <id> | delete <id> [--keep-images] | empty-trash [--keep-images] | purge-expired [--keep-images] | ' +
  'search <query> [--trash] | export <outFile> | write-image <path> [--ext <ext>]';

async function main(): Promise<void> {
  const { positional, flags } = parseArgs(process.argv.slice(2));
  const dir = stringFlag(flags, 'dir') ?? process.env.QUKI_DIR;
  if (!dir) fail(`--dir <path> is required (or set QUKI_DIR)\n${USAGE}`);

  const command = positional[0];
  if (!command) fail(USAGE);

  const store = new QuKiStore(new NodeFsBackend(dir));

  switch (command) {
    case 'list': {
      printJson(flags.trash ? await store.listTrash() : await store.list());
      break;
    }
    case 'read': {
      const id = positional[1];
      if (!id) fail('read requires an id');
      printJson(flags.trash ? await store.readTrash(id) : await store.read(id));
      break;
    }
    case 'save': {
      const id = stringFlag(flags, 'id') ?? null;
      const filePath = stringFlag(flags, 'file');
      let body: string;
      if (filePath !== undefined) {
        body = readFileSync(filePath, 'utf8');
      } else if (flags.stdin) {
        body = await readStdin();
      } else {
        fail('save requires --file <path> or --stdin');
      }
      const expectedModifiedAt = stringFlag(flags, 'expected-modified-at');
      const result = await store.save({ id, body, expectedModifiedAt });
      printJson(result);
      if (result.status === 'conflict') process.exitCode = 2;
      break;
    }
    case 'trash': {
      const id = positional[1];
      if (!id) fail('trash requires an id');
      await store.moveToTrash(id);
      printJson({ status: 'trashed', id });
      break;
    }
    case 'restore': {
      const id = positional[1];
      if (!id) fail('restore requires an id');
      await store.restore(id);
      printJson({ status: 'restored', id });
      break;
    }
    case 'delete': {
      const id = positional[1];
      if (!id) fail('delete requires an id');
      await store.permanentlyDelete(id, { deleteOrphanedImages: !flags['keep-images'] });
      printJson({ status: 'deleted', id });
      break;
    }
    case 'empty-trash': {
      printJson(await store.emptyTrash({ deleteOrphanedImages: !flags['keep-images'] }));
      break;
    }
    case 'purge-expired': {
      printJson(await store.purgeExpiredTrash({ deleteOrphanedImages: !flags['keep-images'] }));
      break;
    }
    case 'search': {
      const query = positional[1] ?? '';
      printJson(await store.search(query, { includeTrash: Boolean(flags.trash) }));
      break;
    }
    case 'export': {
      const outFile = positional[1];
      if (!outFile) fail('export requires an output file path');
      const result = await store.exportLibrary();
      writeFileSync(outFile, result.bytes);
      printJson({
        path: outFile,
        activeCount: result.activeCount,
        trashCount: result.trashCount,
        mediaCount: result.mediaCount,
      });
      break;
    }
    case 'write-image': {
      const filePath = positional[1];
      if (!filePath) fail('write-image requires a source file path');
      const ext = stringFlag(flags, 'ext') ?? filePath.split('.').pop() ?? 'bin';
      printJson(await store.writeImage(readFileSync(filePath), ext));
      break;
    }
    default:
      fail(`unknown command: ${command}\n${USAGE}`);
  }
}

main().catch((err: unknown) => {
  fail(err instanceof Error ? err.message : String(err));
});
