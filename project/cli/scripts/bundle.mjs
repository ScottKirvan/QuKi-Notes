// Produces a single self-contained ESM file with quki-core inlined.
//
// The desktop packaging (Windows NSIS component, Linux AppImage) ships this
// file, not `dist/` from `tsc -b`. `quki-core` is a `file:../core` dependency
// resolved by npm as a symlink to a path outside this package (see
// node_modules/quki-core) - copying `dist/` + `node_modules/` verbatim into
// an installer would carry that dangling symlink onto the end user's
// machine. Bundling avoids that: one plain .js file, no node_modules lookup
// at runtime, run directly by the app's own bundled Electron binary via
// ELECTRON_RUN_AS_NODE=1 (see project/electron/build/installer.nsh and the
// Linux AppRun dispatch script).
import { build } from 'esbuild';
import { chmodSync, mkdirSync } from 'node:fs';

mkdirSync('dist-bundle', { recursive: true });

// No banner option: src/main.ts already carries its own shebang (needed
// independently so the tsc-built dist/main.js works as an npm `bin` entry),
// and esbuild hoists an entry point's existing shebang to the top of the
// bundle on its own - adding a banner here would duplicate it.
// .mjs, not .js: this file ships standalone into installer resources with no
// package.json nearby to declare "type": "module" - Node/Electron treats a
// bare .js as CommonJS without one and refuses the bundle's `import`
// syntax. .mjs is unambiguous regardless of where it ends up (confirmed by
// running the plain-.js version copied to an empty directory and watching it
// fail exactly this way).
await build({
  entryPoints: ['src/main.ts'],
  outfile: 'dist-bundle/main.mjs',
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
});

chmodSync('dist-bundle/main.mjs', 0o755);
