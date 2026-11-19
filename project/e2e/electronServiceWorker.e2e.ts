import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

const childEnv: NodeJS.ProcessEnv = { ...process.env };
delete childEnv.ELECTRON_RUN_AS_NODE;

const STALE_CACHE = "quki-e2e-stale";
const KEPT_LOCAL_STORAGE_KEY = "quki-e2e-kept";
const KEPT_IDB_NAME = "quki-e2e-kept";

async function launch(userDataDir: string, storageDir: string): Promise<{ app: ElectronApplication; page: Page }> {
  const app = await electron.launch({
    executablePath: electronExecutablePath,
    args: [electronMain],
    env: { ...childEnv, QUKI_ELECTRON_DIR: storageDir, QUKI_ELECTRON_USERDATA_DIR: userDataDir },
  });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

async function serviceWorkerState(page: Page): Promise<{ registrations: string[]; caches: string[] }> {
  return page.evaluate(async () => ({
    registrations: (await navigator.serviceWorker.getRegistrations()).map((r) => r.scope),
    caches: await caches.keys(),
  }));
}

// registerSW({ immediate: true }) registers as soon as the bundle runs; a
// few seconds after load is well past when a registration would appear.
async function settledServiceWorkerState(page: Page): Promise<{ registrations: string[]; caches: string[] }> {
  await page.waitForLoadState("load");
  const deadline = Date.now() + 4000;
  let state = await serviceWorkerState(page);
  while (state.registrations.length === 0 && Date.now() < deadline) {
    await page.waitForTimeout(250);
    state = await serviceWorkerState(page);
  }
  return state;
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "quki-electron-sw-e2e-"));
  const storageDir = path.join(tmp, "storage");
  fs.mkdirSync(storageDir);

  // --- Scenario 1: a fresh desktop app registers no service worker. ---
  {
    const userDataDir = path.join(tmp, "fresh-userdata");
    const { app, page } = await launch(userDataDir, storageDir);
    try {
      const state = await settledServiceWorkerState(page);
      assert(state.registrations.length === 0, `the desktop app should register no service worker, got: ${JSON.stringify(state.registrations)}`);
      assert(state.caches.length === 0, `the desktop app should create no CacheStorage entries, got: ${JSON.stringify(state.caches)}`);
      console.log("[e2e-electron-sw] PASS: a fresh launch has no service worker registration and no CacheStorage entries");
    } finally {
      await app.close();
    }
  }

  // --- Scenario 2: a service worker and cache left in userData by an older
  // build are cleared on the next launch; other storage is kept. The stale
  // registration is seeded on a fixed origin served by this test, because
  // the app's own renderer gets a new random port each launch. ---
  const { server, url: seededOrigin } = await serveDist();
  try {
    const userDataDir = path.join(tmp, "seeded-userdata");

    {
      const { app, page } = await launch(userDataDir, storageDir);
      try {
        await page.goto(seededOrigin);
        await page.waitForSelector(".cm-content");
        await page.evaluate(
          async ({ cacheName, lsKey, idbName }) => {
            await navigator.serviceWorker.register("/sw.js");
            await navigator.serviceWorker.ready;
            const cache = await caches.open(cacheName);
            await cache.put("/stale-marker", new Response("stale"));
            localStorage.setItem(lsKey, "kept");
            await new Promise<void>((resolve, reject) => {
              const open = indexedDB.open(idbName, 1);
              open.onupgradeneeded = () => open.result.createObjectStore("kv");
              open.onerror = () => reject(open.error);
              open.onsuccess = () => {
                const tx = open.result.transaction("kv", "readwrite");
                tx.objectStore("kv").put("kept", "marker");
                tx.oncomplete = () => {
                  open.result.close();
                  resolve();
                };
                tx.onerror = () => reject(tx.error);
              };
            });
          },
          { cacheName: STALE_CACHE, lsKey: KEPT_LOCAL_STORAGE_KEY, idbName: KEPT_IDB_NAME },
        );
        const seeded = await serviceWorkerState(page);
        assert(seeded.registrations.length > 0, "seeding should leave a service worker registration");
        assert(seeded.caches.includes(STALE_CACHE), `seeding should leave the ${STALE_CACHE} cache, got: ${JSON.stringify(seeded.caches)}`);
        console.log(`[e2e-electron-sw] seeded a service worker and cache on ${seededOrigin}`);
      } finally {
        await app.close();
      }
    }

    {
      const { app, page } = await launch(userDataDir, storageDir);
      try {
        await page.goto(seededOrigin);
        await page.waitForSelector(".cm-content");
        const state = await settledServiceWorkerState(page);
        assert(state.registrations.length === 0, `the stale service worker should be cleared on launch, got: ${JSON.stringify(state.registrations)}`);
        assert(state.caches.length === 0, `stale CacheStorage entries should be cleared on launch, got: ${JSON.stringify(state.caches)}`);
        console.log("[e2e-electron-sw] PASS: a stale service worker and its cache are cleared on the next launch");

        const kept = await page.evaluate(
          async ({ lsKey, idbName }) => {
            const ls = localStorage.getItem(lsKey);
            const idb = await new Promise<unknown>((resolve, reject) => {
              const open = indexedDB.open(idbName, 1);
              open.onupgradeneeded = () => open.result.createObjectStore("kv");
              open.onerror = () => reject(open.error);
              open.onsuccess = () => {
                const req = open.result.transaction("kv").objectStore("kv").get("marker");
                req.onsuccess = () => {
                  open.result.close();
                  resolve(req.result);
                };
                req.onerror = () => reject(req.error);
              };
            });
            return { ls, idb };
          },
          { lsKey: KEPT_LOCAL_STORAGE_KEY, idbName: KEPT_IDB_NAME },
        );
        assert(kept.ls === "kept", `localStorage should survive the clearing, got: ${JSON.stringify(kept.ls)}`);
        assert(kept.idb === "kept", `IndexedDB should survive the clearing, got: ${JSON.stringify(kept.idb)}`);
        console.log("[e2e-electron-sw] PASS: localStorage and IndexedDB are kept");
      } finally {
        await app.close();
      }
    }
  } finally {
    server.close();
  }

  fs.rmSync(tmp, { recursive: true, force: true });
  console.log("[e2e-electron-sw] all scenarios passed");
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
