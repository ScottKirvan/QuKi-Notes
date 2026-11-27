// Produces a single self-contained ESM file with quki-core, the MCP SDK and
// zod all inlined. See cli/scripts/bundle.mjs for why: `quki-core` is a
// `file:../core` dependency npm resolves as a symlink outside this package,
// which an installer can't carry onto an end user's machine. This is the
// file the desktop packaging (Windows NSIS component, Linux AppImage) ships
// and runs directly through the app's own bundled Electron binary via
// ELECTRON_RUN_AS_NODE=1.
import { build } from 'esbuild';
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';

import {
  assertNoMissing,
  collectNotices,
  NOTICES_FILE_NAME,
  packageDirsFromMetafile,
  renderNotices,
} from '../../scripts/notices/lib.mjs';

mkdirSync('dist-bundle', { recursive: true });

// No banner option: src/server.ts already carries its own shebang, and
// esbuild hoists an entry point's existing shebang to the top of the bundle
// on its own - adding a banner here would duplicate it.
// .mjs, not .js: this file ships standalone into installer resources with no
// package.json nearby to declare "type": "module" - Node/Electron treats a
// bare .js as CommonJS without one and refuses the bundle's `import`
// syntax. .mjs is unambiguous regardless of where it ends up (confirmed by
// running the plain-.js version copied to an empty directory and watching it
// fail exactly this way).
const result = await build({
  entryPoints: ['src/server.ts'],
  outfile: 'dist-bundle/server.mjs',
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
  metafile: true,
});

// esbuild keeps no licence files, so the notices for what it inlined are
// written beside the bundle, which ships as a whole directory.
const notices = collectNotices(packageDirsFromMetafile(result.metafile, process.cwd()));
assertNoMissing(notices.missing);
writeFileSync(
  `dist-bundle/${NOTICES_FILE_NAME}`,
  renderNotices(notices, 'QuKi Notes - third-party notices (quki-mcp server)'),
);

chmodSync('dist-bundle/server.mjs', 0o755);
