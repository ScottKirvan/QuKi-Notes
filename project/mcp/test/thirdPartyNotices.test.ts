import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { build } from 'esbuild';
import { expect, it } from 'vitest';

import { collectNotices, packageDirsFromMetafile } from '../../scripts/notices/lib.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

it('every third-party package bundled into quki-mcp has licence text', async () => {
  const result = await build({
    entryPoints: [path.join(root, 'src/server.ts')],
    write: false,
    bundle: true,
    platform: 'node',
    format: 'esm',
    target: 'node18',
    metafile: true,
    logLevel: 'silent',
  });
  const notices = collectNotices(packageDirsFromMetafile(result.metafile, root));
  expect(notices.missing.map((p) => `${p.name}@${p.version}`)).toEqual([]);
  expect(notices.packages.map((p) => p.name)).toContain('zod');
});
