// Dev workflow for the Electron wrapper: starts the existing Vite dev
// server (unchanged - the same one `npm run dev` uses) programmatically,
// then launches Electron pointed at it via ELECTRON_RENDERER_URL (read by
// project/electron/src/main.ts). No electron-vite or other bundler-
// coordination tool: this project already has a working Vite setup for the
// renderer and a plain tsc build for the electron/ package (matching
// core/cli/mcp's pattern) - a ~40-line script covers what electron-vite
// would otherwise add as a dependency, for one dev command.
//
// Electron's own subprocess env can carry ELECTRON_RUN_AS_NODE=1 in some
// host environments (e.g. when this very script runs inside an
// Electron-based tool) - inherited by the launched app it would make
// Electron start as plain Node instead of opening a window, so it is
// stripped before spawning.
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { createServer } from "vite";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.join(__dirname, "..");
const electronDir = path.join(projectRoot, "electron");
const electronMain = path.join(electronDir, "dist", "main.js");

async function main() {
  const server = await createServer({ root: projectRoot, server: { host: "127.0.0.1" } });
  await server.listen();
  const url = server.resolvedUrls?.local[0];
  if (!url) throw new Error("Vite dev server did not report a local URL");
  console.log(`[electron-dev] renderer dev server: ${url}`);

  const electronRequire = createRequire(path.join(electronDir, "package.json"));
  const electronExecutablePath = electronRequire("electron");

  const env = { ...process.env, ELECTRON_RENDERER_URL: url };
  delete env.ELECTRON_RUN_AS_NODE;

  const child = spawn(electronExecutablePath, [electronMain], {
    cwd: electronDir,
    env,
    stdio: "inherit",
  });

  const shutdown = async () => {
    child.kill();
    await server.close();
  };

  child.on("exit", (code) => {
    void server.close().then(() => process.exit(code ?? 0));
  });
  process.on("SIGINT", () => void shutdown());
  process.on("SIGTERM", () => void shutdown());
}

main().catch((err) => {
  console.error("[electron-dev] failed:", err);
  process.exit(1);
});
