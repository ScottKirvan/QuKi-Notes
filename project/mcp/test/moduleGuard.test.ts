import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { describe, expect, it } from 'vitest';

const serverPath = fileURLToPath(new URL('../dist/server.js', import.meta.url));
const serverUrl = pathToFileURL(serverPath).href;

/**
 * Real subprocess, real dynamic import of the real compiled server module -
 * same "spawn a fresh node process against the real build" spirit as
 * integration.test.ts's stdio round-trip, just checking what happens at
 * import time rather than over the MCP protocol. Without the run guard,
 * `import()` here triggers module-level main(), which - given no rootDir
 * argument and no QUKI_DIR in this subprocess's env - fails with a usage
 * message and process.exit(1) before the importer's own code ever runs.
 */
describe('mcp/src/server.ts module-load guard', () => {
  it('importing the module does not run main() or exit the process', () => {
    const script = `
      import(${JSON.stringify(serverUrl)}).then((mod) => {
        console.log(JSON.stringify({ hasCreateServer: typeof mod.createServer === 'function' }));
      });
    `;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
      encoding: 'utf8',
      timeout: 10_000,
    });

    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout.trim())).toEqual({ hasCreateServer: true });
  });

  it('running the module directly still works (the usage error still fires with no rootDir)', () => {
    const result = spawnSync(process.execPath, [serverPath], { encoding: 'utf8', timeout: 10_000 });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('Usage: quki-mcp');
  });
});
