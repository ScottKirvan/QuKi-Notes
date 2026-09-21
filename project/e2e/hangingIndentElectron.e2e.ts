import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

import { assert, runHangScenarios, type HangEnvironment } from "./hangSupport.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

// The Electron this project ships is Chromium 130; `text-indent: <length>
// hanging` arrived in Chromium 146. Pinning the engine here is what stops this
// script passing on some newer engine by accident.
const LAST_CHROMIUM_WITHOUT_HANGING = 145;

function baseEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  delete env.ELECTRON_RUN_AS_NODE;
  delete env.QUKI_ELECTRON_DIR;
  return env;
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "quki-hang-electron-e2e-"));
  const apps: ElectronApplication[] = [];

  const env: HangEnvironment = {
    name: "electron",
    async open(scheme, width, height) {
      const n = apps.length;
      const userData = path.join(scratch, `userdata-${n}`);
      const storage = path.join(scratch, `storage-${n}`);
      fs.mkdirSync(userData, { recursive: true });
      fs.mkdirSync(storage, { recursive: true });
      const app = await electron.launch({
        executablePath: electronExecutablePath,
        args: [electronMain],
        env: { ...baseEnv(), QUKI_ELECTRON_USERDATA_DIR: userData, QUKI_ELECTRON_DIR: storage },
      });
      apps.push(app);
      const page = await app.firstWindow();
      await page.waitForSelector(".cm-content");
      // nativeTheme.themeSource does not reach the renderer's prefers-color-scheme
      // under Playwright's Electron launch, so the scheme is emulated instead.
      await page.emulateMedia({ colorScheme: scheme });
      const resize = async (w: number, h: number): Promise<void> => {
        await app.evaluate(({ BrowserWindow }, [cw, ch]) => {
          const win = BrowserWindow.getAllWindows()[0]!;
          win.setMinimumSize(1, 1);
          win.setContentSize(cw!, ch!);
        }, [w, h]);
        await page.waitForFunction(([cw, ch]) => window.innerWidth === cw && window.innerHeight === ch, [w, h]);
      };
      await resize(width, height);
      const dark = await page.evaluate(() => matchMedia("(prefers-color-scheme: dark)").matches);
      assert(dark === (scheme === "dark"), `the window should be in ${scheme} mode`);
      return { page, resize, close: () => app.close() };
    },
    async assertEngine(page: Page) {
      const probe = await page.evaluate(() => ({
        hanging: CSS.supports("text-indent", "10px hanging"),
        userAgent: navigator.userAgent,
      }));
      const chromium = Number(/Chrome\/(\d+)/.exec(probe.userAgent)?.[1]);
      assert(!probe.hanging, `this must run on an engine without text-indent: hanging, but CSS.supports says it has it (${probe.userAgent})`);
      assert(/Electron\//.test(probe.userAgent), `expected the Electron desktop app, got ${probe.userAgent}`);
      assert(chromium <= LAST_CHROMIUM_WITHOUT_HANGING, `expected Chromium <= ${LAST_CHROMIUM_WITHOUT_HANGING}, got ${chromium}`);
      return `${probe.userAgent.match(/Electron\/[\d.]+/)?.[0]} on Chromium ${chromium}; CSS.supports("text-indent", "10px hanging") = ${probe.hanging}`;
    },
  };

  try {
    await runHangScenarios(env);
  } finally {
    await Promise.all(apps.map((app) => app.close().catch(() => undefined)));
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-hangingIndent:electron] FAILED:", err);
    process.exit(1);
  });
