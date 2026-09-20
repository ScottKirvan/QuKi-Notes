import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

function mkTempDir(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

/**
 * Every launch in this script needs a *fresh* app: QUKI_ELECTRON_USERDATA_DIR
 * points Electron's userData directory (where preferences.json lives - see
 * electron/src/preferences.ts) at a throwaway temp dir, so no real developer
 * profile is ever read or written. Unlike e2e/electron.e2e.ts, this script
 * deliberately does *not* set QUKI_ELECTRON_DIR - that env var bypasses the
 * setup screen entirely (kept only for backward/dev-test compatibility, see
 * main.ts), which is exactly the flow this script exists to exercise.
 *
 * QUKI_ELECTRON_DOCUMENTS_DIR and QUKI_ELECTRON_FLUTTER_PREFS_PATH are the
 * same kind of seam, added for Flutter-migration detection (main.ts,
 * electron/src/flutterMigration.ts): without them, "Use app storage" and the
 * migration check would resolve against this machine's real Documents
 * folder and real Flutter shared_preferences.json - on a machine that has
 * actually run the published Flutter app (this one does), that folder
 * contains real QuKis. Every scenario below sets both explicitly so no
 * scenario can accidentally read or adopt real user data.
 */
function baseEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  delete env.ELECTRON_RUN_AS_NODE;
  delete env.QUKI_ELECTRON_DIR;
  delete env.QUKI_ELECTRON_USERDATA_DIR;
  delete env.QUKI_ELECTRON_DOCUMENTS_DIR;
  delete env.QUKI_ELECTRON_FLUTTER_PREFS_PATH;
  delete env.QUKI_TEST_FORCE_DIALOG_PATH;
  return env;
}

interface LaunchOptions {
  userDataDir: string;
  /** Stands in for app.getPath('documents') - see the comment above baseEnv(). */
  documentsDir: string;
  /**
   * Stands in for the real per-platform path to the Flutter app's
   * shared_preferences.json (see flutterMigration.ts). Omitted means an
   * explicit empty string - "no Flutter install found" - rather than
   * falling through to a real path on this machine.
   */
  flutterPrefsPath?: string;
  /**
   * Stands in for the user's choice in the native directory picker -
   * Playwright cannot drive an OS-native dialog directly, so main.ts's
   * quki:setup:chooseFilesystem handler checks this env var first and, if
   * set, uses it instead of calling the real dialog.showOpenDialog (see
   * electron/src/main.ts). An empty string stands in for the user
   * cancelling the picker.
   */
  forceDialogPath?: string;
}

async function launch(options: LaunchOptions): Promise<{ app: ElectronApplication; page: Page }> {
  const env: NodeJS.ProcessEnv = {
    ...baseEnv(),
    QUKI_ELECTRON_USERDATA_DIR: options.userDataDir,
    QUKI_ELECTRON_DOCUMENTS_DIR: options.documentsDir,
    QUKI_ELECTRON_FLUTTER_PREFS_PATH: options.flutterPrefsPath ?? "",
  };
  if (options.forceDialogPath !== undefined) env.QUKI_TEST_FORCE_DIALOG_PATH = options.forceDialogPath;
  const app = await electron.launch({ executablePath: electronExecutablePath, args: [electronMain], env });
  const page = await app.firstWindow();
  return { app, page };
}

async function readEditorBody(page: Page): Promise<string> {
  return page.evaluate(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
  );
}

function mdFilesIn(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => f.endsWith(".md"));
}

async function typeAndWaitForSave(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
  await page.waitForTimeout(2500); // 2s debounce + margin, same as electron.e2e.ts
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  // --- Scenario 1: a genuinely fresh app (no prior preferences.json, no
  // Flutter install found, no pre-existing app-storage folder) shows the
  // setup screen instead of the editor, with the exact spec'd copy and no
  // cancel option (a choice is mandatory on first launch). This also stands
  // as the migration regression check: neither adoption route applies, so
  // the real setup screen must still show. ---
  const userDataA = mkTempDir("quki-electron-setup-a-");
  const documentsA = mkTempDir("quki-electron-setup-a-documents-");
  let { app, page } = await launch({ userDataDir: userDataA, documentsDir: documentsA });

  await page.waitForSelector(".setup-overlay:not([hidden])");
  assert((await page.locator(".cm-content").count()) === 0, "the editor must not be constructed while the setup screen is showing");

  const title = await page.textContent(".setup-title");
  const subtitle = await page.textContent(".setup-subtitle");
  assert(title === "Where should QuKis be saved?", `unexpected setup title: ${title}`);
  assert(subtitle === "Choose once. You can change this later in Settings.", `unexpected setup subtitle: ${subtitle}`);
  const cancelHidden = await page.getAttribute(".setup-cancel-btn", "hidden");
  assert(cancelHidden !== null, "first-launch setup screen must not offer a cancel option");
  console.log("[e2e-setup] PASS: fresh app shows the setup screen (not the editor), exact copy, no cancel option");

  // --- Scenario 2: choosing "Use app storage" proceeds to the editor, and
  // a QuKi created afterward lands in the app-private qukis/ folder. ---
  await page.click(".setup-card-appstorage");
  await page.waitForSelector(".cm-content");
  assert((await page.locator(".setup-overlay:not([hidden])").count()) === 0, "the setup overlay must be hidden once the editor is showing");

  const markerA = `Electron setup e2e - app storage ${Date.now()}`;
  await typeAndWaitForSave(page, markerA);

  // "Use app storage" now matches the Flutter app's own convention:
  // <Documents>/qukis (see main.ts's resolveAppStorageDir), not a hidden
  // userData folder - so a migrating Flutter app-storage user's QuKis are
  // found in the same place a fresh install's "app storage" choice lands.
  const appStorageDir = path.join(documentsA, "qukis");
  let mdFiles = mdFilesIn(appStorageDir);
  assert(mdFiles.length === 1, `expected exactly one .md file in ${appStorageDir}, found: ${mdFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(appStorageDir, mdFiles[0]!), "utf8") === markerA, "on-disk file should equal the typed marker");
  console.log(`[e2e-setup] PASS: "Use app storage" proceeded to the editor; QuKi landed in ${appStorageDir}`);

  await app.close();

  // --- Scenario 3: relaunching against the same (now non-fresh) userData
  // dir skips the setup screen entirely and goes straight to the editor,
  // reloading the previously-saved content from disk. ---
  ({ app, page } = await launch({ userDataDir: userDataA, documentsDir: documentsA }));
  await page.waitForSelector(".cm-content");
  assert((await page.locator(".setup-overlay:not([hidden])").count()) === 0, "a relaunch with existing preferences must not show the setup screen");
  const reloadedBody = await readEditorBody(page);
  assert(reloadedBody === markerA, `expected the previously-saved QuKi to reload directly, got: ${reloadedBody}`);
  console.log("[e2e-setup] PASS: relaunch with an existing preferences file skips straight to the editor");

  await app.close();

  // --- Scenario 4: a separate fresh app, this run choosing "Filesystem
  // storage". The native picker is stubbed (QUKI_TEST_FORCE_DIALOG_PATH -
  // see main.ts) since Playwright cannot drive it directly; a QuKi created
  // afterward lands in the chosen folder, not app storage. ---
  const userDataB = mkTempDir("quki-electron-setup-b-");
  const documentsB = mkTempDir("quki-electron-setup-b-documents-");
  const chosenFolder = mkTempDir("quki-electron-setup-chosen-");
  ({ app, page } = await launch({ userDataDir: userDataB, documentsDir: documentsB, forceDialogPath: chosenFolder }));

  await page.waitForSelector(".setup-overlay:not([hidden])");
  await page.click(".setup-card-filesystem");
  await page.waitForSelector(".cm-content");

  const markerB = `Electron setup e2e - filesystem storage ${Date.now()}`;
  await typeAndWaitForSave(page, markerB);

  mdFiles = mdFilesIn(chosenFolder);
  assert(mdFiles.length === 1, `expected exactly one .md file in ${chosenFolder}, found: ${mdFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(chosenFolder, mdFiles[0]!), "utf8") === markerB, "on-disk file should equal the typed marker");
  assert(mdFilesIn(path.join(documentsB, "qukis")).length === 0, "nothing should have been written to the app-storage folder");
  console.log(`[e2e-setup] PASS: "Filesystem storage" (native picker stubbed) proceeded to the editor; QuKi landed in ${chosenFolder}`);

  await app.close();

  // --- Scenario 4b: cancelling the native picker leaves the user on the
  // setup screen, with nothing saved. ---
  const userDataC = mkTempDir("quki-electron-setup-c-");
  const documentsC = mkTempDir("quki-electron-setup-c-documents-");
  ({ app, page } = await launch({ userDataDir: userDataC, documentsDir: documentsC, forceDialogPath: "" }));
  await page.waitForSelector(".setup-overlay:not([hidden])");
  await page.click(".setup-card-filesystem");
  await page.waitForTimeout(500);
  assert((await page.locator(".cm-content").count()) === 0, "cancelling the picker must leave the user on the setup screen, not the editor");
  assert((await page.locator(".setup-overlay:not([hidden])").count()) === 1, "the setup screen must still be visible after a cancelled picker");
  console.log("[e2e-setup] PASS: cancelling the native picker leaves the user on the setup screen with nothing saved");
  await app.close();

  // --- Scenario 5: Settings -> Change location. A QuKi created before the
  // change stays in the old folder untouched; the editor resets (reloads
  // against the new, still-empty folder) the moment the change completes;
  // a QuKi created after the change lands in the new folder. Also checks
  // that this entry point's setup screen is cancelable, and that cancelling
  // it changes nothing. ---
  const userDataD = mkTempDir("quki-electron-setup-d-");
  const documentsD = mkTempDir("quki-electron-setup-d-documents-");
  const initialFolder = mkTempDir("quki-electron-setup-initial-");
  const newFolder = mkTempDir("quki-electron-setup-new-");

  // First launch: pick filesystem storage pointed at initialFolder, create QuKi X.
  ({ app, page } = await launch({ userDataDir: userDataD, documentsDir: documentsD, forceDialogPath: initialFolder }));
  await page.waitForSelector(".setup-overlay:not([hidden])");
  await page.click(".setup-card-filesystem");
  await page.waitForSelector(".cm-content");
  const markerX = `Electron setup e2e - QuKi X ${Date.now()}`;
  await typeAndWaitForSave(page, markerX);
  await app.close();

  // Second launch, same userData (so preferences already point at
  // initialFolder - setup screen must not appear), this run's dialog stub
  // points at newFolder for when Change location invokes it.
  ({ app, page } = await launch({ userDataDir: userDataD, documentsDir: documentsD, forceDialogPath: newFolder }));
  await page.waitForSelector(".cm-content");
  assert((await page.locator(".setup-overlay:not([hidden])").count()) === 0, "relaunch must not show the setup screen even with a dialog stub set");

  await page.click("#btn-settings");
  await page.waitForSelector("#view-settings:not([hidden])");
  const shownPathBefore = await page.textContent(".storage-location-value");
  assert(shownPathBefore === initialFolder, `Settings should show the current folder, got: ${shownPathBefore}`);
  console.log(`[e2e-setup] PASS: Settings shows the current storage location: ${shownPathBefore}`);

  // Change location is reachable and cancelable; cancelling changes nothing.
  await page.click(".change-location-btn");
  await page.waitForSelector(".setup-overlay:not([hidden])");
  const cancelHiddenInChangeMode = await page.getAttribute(".setup-cancel-btn", "hidden");
  assert(cancelHiddenInChangeMode === null, "Settings -> Change location must offer a cancel option");
  await page.click(".setup-cancel-btn");
  await page.waitForSelector("#view-settings:not([hidden])");
  const shownPathAfterCancel = await page.textContent(".storage-location-value");
  assert(shownPathAfterCancel === initialFolder, "cancelling Change location must not change the stored location");
  console.log("[e2e-setup] PASS: cancelling Change location leaves the storage location unchanged");

  // Now actually change it.
  await page.click(".change-location-btn");
  await page.waitForSelector(".setup-overlay:not([hidden])");
  await page.click(".setup-card-filesystem");
  await page.waitForSelector("#view-settings:not([hidden])");
  const shownPathAfterChange = await page.textContent(".storage-location-value");
  assert(shownPathAfterChange === newFolder, `Settings should show the new folder after Change location, got: ${shownPathAfterChange}`);
  console.log(`[e2e-setup] PASS: Change location updated the shown storage location to ${newFolder}`);

  await page.click("#view-settings .back-btn");
  await page.waitForSelector("#view-editor:not([hidden])");

  // PROPOSAL (see main.ts's changeStorageLocation): a location change
  // reloads the editor as if freshly launched against the new folder -
  // newFolder has no QuKis yet, so the editor should now be blank, not
  // still showing QuKi X (which belongs to initialFolder).
  const bodyAfterChange = await readEditorBody(page);
  assert(bodyAfterChange === "", `expected the editor to reset to blank after changing location to an empty folder, got: ${bodyAfterChange}`);
  console.log("[e2e-setup] PASS: the editor reset to blank immediately after the location change (new folder is empty)");

  const markerY = `Electron setup e2e - QuKi Y ${Date.now()}`;
  await typeAndWaitForSave(page, markerY);

  const newFolderFiles = mdFilesIn(newFolder);
  assert(newFolderFiles.length === 1, `expected exactly one .md file in ${newFolder}, found: ${newFolderFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(newFolder, newFolderFiles[0]!), "utf8") === markerY, "QuKi Y should be written into the new folder");

  const initialFolderFiles = mdFilesIn(initialFolder);
  assert(initialFolderFiles.length === 1, `expected QuKi X to remain untouched in ${initialFolder}, found: ${initialFolderFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(initialFolder, initialFolderFiles[0]!), "utf8") === markerX, "QuKi X's content must be unchanged in the old folder");
  console.log("[e2e-setup] PASS: after Change location, a new QuKi lands in the new folder and the old folder's QuKi is untouched");

  await app.close();

  // --- Scenario 6: Flutter-migration, route 1 - a genuinely fresh app (no
  // preferences.json of its own) finds a Flutter shared_preferences.json
  // recording an explicitly-chosen location, and silently adopts it: no
  // setup screen, straight to the editor, showing that folder's content. ---
  const userDataE = mkTempDir("quki-electron-setup-migrate-choice-");
  const documentsE = mkTempDir("quki-electron-setup-migrate-choice-documents-");
  const flutterChosenFolder = mkTempDir("quki-electron-setup-migrate-choice-folder-");
  const flutterMarker = `Flutter migration e2e - explicit choice ${Date.now()}`;
  fs.writeFileSync(path.join(flutterChosenFolder, "existing-quki.md"), flutterMarker, "utf8");

  const flutterPrefsPathE = path.join(documentsE, "fake-flutter-shared-preferences.json");
  fs.writeFileSync(
    flutterPrefsPathE,
    JSON.stringify({ "flutter.storage.location_chosen": true, "flutter.storage.base_path": flutterChosenFolder }),
    "utf8",
  );

  ({ app, page } = await launch({ userDataDir: userDataE, documentsDir: documentsE, flutterPrefsPath: flutterPrefsPathE }));
  await page.waitForSelector(".cm-content");
  assert(
    (await page.locator(".setup-overlay:not([hidden])").count()) === 0,
    "a Flutter-recorded explicit choice must skip the setup screen",
  );
  const bodyE = await readEditorBody(page);
  assert(bodyE === flutterMarker, `expected the editor to load the migrated Flutter QuKi content, got: ${bodyE}`);
  console.log(
    `[e2e-setup] PASS: Flutter-recorded chosen location (${flutterChosenFolder}) was adopted silently - no setup screen, content loaded`,
  );

  await app.close();

  // --- Scenario 7: Flutter-migration, route 2 - no Flutter shared_preferences.json
  // at all (simulating no Flutter install found), but the Flutter
  // app-storage default folder (<Documents>/qukis) already has a QuKi in
  // it. Silently adopted the same way, mirroring the Flutter app's own
  // adoptAppStorageIfUpgrading() fallback. ---
  const userDataF = mkTempDir("quki-electron-setup-migrate-fallback-");
  const documentsF = mkTempDir("quki-electron-setup-migrate-fallback-documents-");
  const appStorageDirF = path.join(documentsF, "qukis");
  fs.mkdirSync(appStorageDirF, { recursive: true });
  const fallbackMarker = `Flutter migration e2e - app storage fallback ${Date.now()}`;
  fs.writeFileSync(path.join(appStorageDirF, "existing-quki.md"), fallbackMarker, "utf8");

  ({ app, page } = await launch({ userDataDir: userDataF, documentsDir: documentsF, flutterPrefsPath: "" }));
  await page.waitForSelector(".cm-content");
  assert(
    (await page.locator(".setup-overlay:not([hidden])").count()) === 0,
    "an existing Flutter app-storage folder with QuKis must skip the setup screen",
  );
  const bodyF = await readEditorBody(page);
  assert(bodyF === fallbackMarker, `expected the editor to load the migrated app-storage QuKi content, got: ${bodyF}`);
  console.log(
    `[e2e-setup] PASS: Flutter app-storage default folder (${appStorageDirF}) was adopted silently by fallback - no setup screen, content loaded`,
  );

  await app.close();

  // --- Scenario 8: Flutter-migration, route 1, stale path - a Flutter
  // shared_preferences.json records an explicit choice, but the folder it
  // points at no longer exists on disk (moved, deleted, or on a
  // now-disconnected drive after being recorded). This must NOT be
  // silently adopted - a stale recorded path is worse than showing setup
  // again, since the app would otherwise treat an empty/freshly-created
  // folder as the user's whole library while they believe their existing
  // QuKis are still there. The real first-launch setup screen must show,
  // exactly as if neither migration route had matched. ---
  const userDataG = mkTempDir("quki-electron-setup-migrate-stale-");
  const documentsG = mkTempDir("quki-electron-setup-migrate-stale-documents-");
  const staleFolder = mkTempDir("quki-electron-setup-migrate-stale-folder-");
  fs.rmSync(staleFolder, { recursive: true, force: true });
  assert(!fs.existsSync(staleFolder), "the stale folder must not exist before launch - that's the scenario under test");

  const flutterPrefsPathG = path.join(documentsG, "fake-flutter-shared-preferences.json");
  fs.writeFileSync(
    flutterPrefsPathG,
    JSON.stringify({ "flutter.storage.location_chosen": true, "flutter.storage.base_path": staleFolder }),
    "utf8",
  );

  ({ app, page } = await launch({ userDataDir: userDataG, documentsDir: documentsG, flutterPrefsPath: flutterPrefsPathG }));
  await page.waitForSelector(".setup-overlay:not([hidden])");
  assert(
    (await page.locator(".cm-content").count()) === 0,
    "a Flutter-recorded path pointing at a folder that no longer exists must not be silently adopted - the editor must not be constructed",
  );
  const titleG = await page.textContent(".setup-title");
  assert(titleG === "Where should QuKis be saved?", `expected the real first-launch setup screen, got title: ${titleG}`);
  console.log(
    `[e2e-setup] PASS: a Flutter-recorded basePath pointing at a missing folder (${staleFolder}) was rejected - real setup screen shown, nothing silently adopted`,
  );

  await app.close();

  // --- Scenario 9: normal startup, not a Flutter migration case at all -
  // this app's own preferences.json already recorded a chosen storagePath
  // (storageChosen: true), but the folder it points at no longer exists
  // (drive unplugged, folder deleted/moved, network share not mounted).
  // Must NOT silently create an empty folder there and open it as the
  // user's whole library (main.ts's setBackendRoot -> NodeFsBackend.mkdirp
  // would otherwise do exactly that). Must also NOT show the plain
  // first-launch copy ("Where should QuKis be saved? Choose once...") -
  // that would wrongly read to this already-set-up user as "your whole
  // library is gone". A distinct recovery screen must show instead, with a
  // cancel option (unlike first launch), and choosing a new location from
  // it must work and update the stored preference. ---
  const userDataH = mkTempDir("quki-electron-setup-recovery-");
  const documentsH = mkTempDir("quki-electron-setup-recovery-documents-");
  const goneFolderH = mkTempDir("quki-electron-setup-recovery-gone-");
  fs.rmSync(goneFolderH, { recursive: true, force: true });
  assert(!fs.existsSync(goneFolderH), "the previously-chosen folder must not exist before launch - that's the scenario under test");

  const prefsPathH = path.join(userDataH, "preferences.json");
  fs.writeFileSync(prefsPathH, JSON.stringify({ storagePath: goneFolderH, storageChosen: true }, null, 2), "utf8");

  const newFolderH = mkTempDir("quki-electron-setup-recovery-new-");
  ({ app, page } = await launch({ userDataDir: userDataH, documentsDir: documentsH, forceDialogPath: newFolderH }));

  await page.waitForSelector(".setup-overlay:not([hidden])");
  assert(
    (await page.locator(".cm-content").count()) === 0,
    "an unreachable previously-chosen folder must not be silently adopted - the editor must not be constructed",
  );
  assert(!fs.existsSync(goneFolderH), "the missing folder must not have been silently recreated on disk");

  const titleH = await page.textContent(".setup-title");
  assert(titleH !== "Where should QuKis be saved?", `expected distinct recovery copy, not the plain first-launch title, got: ${titleH}`);
  const subtitleH = await page.textContent(".setup-subtitle");
  assert(
    subtitleH !== null && subtitleH.includes(goneFolderH),
    `expected the recovery copy to name the unreachable path, got: ${subtitleH}`,
  );
  const cancelHiddenH = await page.getAttribute(".setup-cancel-btn", "hidden");
  assert(cancelHiddenH === null, "the recovery screen must offer a cancel option - choosing again is optional, not mandatory");
  console.log(
    `[e2e-setup] PASS: an unreachable previously-chosen folder (${goneFolderH}) was not silently adopted - distinct recovery screen shown ("${titleH}"), cancel option offered`,
  );

  await page.click(".setup-card-filesystem");
  await page.waitForSelector(".cm-content");
  assert((await page.locator(".setup-overlay:not([hidden])").count()) === 0, "the setup overlay must be hidden once the editor is showing");

  const markerH = `Electron setup e2e - recovery new location ${Date.now()}`;
  await typeAndWaitForSave(page, markerH);
  mdFiles = mdFilesIn(newFolderH);
  assert(mdFiles.length === 1, `expected exactly one .md file in ${newFolderH}, found: ${mdFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(newFolderH, mdFiles[0]!), "utf8") === markerH, "on-disk file should equal the typed marker");

  const prefsAfterH = JSON.parse(fs.readFileSync(prefsPathH, "utf8")) as { storagePath: string; storageChosen: boolean };
  assert(prefsAfterH.storagePath === newFolderH, `expected preferences.json to be updated to the newly chosen folder, got: ${prefsAfterH.storagePath}`);
  assert(prefsAfterH.storageChosen === true, "expected storageChosen to remain true after recovery");
  console.log(`[e2e-setup] PASS: choosing a new location from the recovery screen worked and updated preferences.json to ${newFolderH}`);

  await app.close();

  // --- Scenario 10: same unreachable-folder situation, but this time
  // cancelling the recovery screen instead of choosing a new location. The
  // app cannot usefully run with no storage backend at all (every
  // read/write would fail), so declining must not fall through into a
  // broken editor - it quits the app cleanly instead, leaving the stored
  // preference and the missing folder exactly as they were. ---
  const userDataI = mkTempDir("quki-electron-setup-recovery-cancel-");
  const documentsI = mkTempDir("quki-electron-setup-recovery-cancel-documents-");
  const goneFolderI = mkTempDir("quki-electron-setup-recovery-cancel-gone-");
  fs.rmSync(goneFolderI, { recursive: true, force: true });

  const prefsPathI = path.join(userDataI, "preferences.json");
  const originalPrefsRawI = JSON.stringify({ storagePath: goneFolderI, storageChosen: true }, null, 2);
  fs.writeFileSync(prefsPathI, originalPrefsRawI, "utf8");

  ({ app, page } = await launch({ userDataDir: userDataI, documentsDir: documentsI }));
  await page.waitForSelector(".setup-overlay:not([hidden])");
  const cancelHiddenI = await page.getAttribute(".setup-cancel-btn", "hidden");
  assert(cancelHiddenI === null, "the recovery screen must offer a cancel option");

  const closed = new Promise<void>((resolve) => app.once("close", () => resolve()));
  await page.click(".setup-cancel-btn");
  await closed;
  console.log("[e2e-setup] PASS: cancelling the recovery screen quit the app instead of proceeding with no storage backend");

  assert(!fs.existsSync(goneFolderI), "the missing folder must still not exist - nothing should have been silently created");
  // The storage-location fields specifically must survive untouched - that's
  // this scenario's point. A byte-for-byte comparison against originalPrefsRawI
  // no longer applies: app.quit() still closes the BrowserWindow first, and
  // window bounds are now saved on close (BEHAVIOR_SPEC.md §10, a later
  // chunk than this recovery flow) - that's a legitimate, additive write to
  // the same preferences.json, not a regression of the storage-recovery
  // contract this scenario actually tests.
  const prefsAfterCancelI = JSON.parse(fs.readFileSync(prefsPathI, "utf8")) as { storagePath: string; storageChosen: boolean };
  assert(prefsAfterCancelI.storagePath === goneFolderI, "storagePath must be unchanged after cancelling recovery");
  assert(prefsAfterCancelI.storageChosen === true, "storageChosen must be unchanged after cancelling recovery");
  console.log("[e2e-setup] PASS: cancelling recovery left the stored storage location and the missing folder untouched");

  for (const dir of [
    userDataA,
    documentsA,
    userDataB,
    documentsB,
    userDataC,
    documentsC,
    userDataD,
    documentsD,
    chosenFolder,
    initialFolder,
    newFolder,
    userDataE,
    documentsE,
    flutterChosenFolder,
    userDataF,
    documentsF,
    userDataG,
    documentsG,
    userDataH,
    documentsH,
    newFolderH,
    userDataI,
    documentsI,
  ]) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

main()
  .then(() => {
    console.log("[e2e-setup] ALL ELECTRON SETUP SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e-setup] FAILED:", err);
    process.exit(1);
  });
