import {
  EditorView,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  highlightActiveLine,
  keymap,
  type KeyBinding,
} from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { history, defaultKeymap, historyKeymap } from "@codemirror/commands";
import { indentOnInput, HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { tags } from "@lezer/highlight";
import { createElement, FileStack, CodeXml, BookOpen, Plus, CircleHelp, Send, Settings, Trash2 } from "lucide";
import { Capacitor } from "@capacitor/core";
import { App as CapacitorApp } from "@capacitor/app";
import { QuKiStore, type StorageBackend } from "quki-core";
import { OpfsBackend } from "quki-core/opfs";
import { ElectronIpcBackend } from "./electronIpcBackend";
import { CapacitorFsBackend, CapacitorStorage } from "./capacitorBackend";
import { createStorageAccessGate } from "./androidStorageAccess";
import { resolveMigratedStorageRoot, type AndroidFlutterMigrationDeps } from "./androidFlutterMigration";
import { applyDedent, applyIndent } from "./toolbar/indentDedent";
import { runToolbarCommand } from "./toolbarAdapter";
import { createFormattingToolbar, type FormattingToolbarHandle } from "./screens/formattingToolbar";
import { revealPlugin } from "./reveal/decorations";
import { plainTextMode, setPlainTextMode } from "./reveal/plainTextMode";
import { createEditModeTracker, resolveModeIconState, shouldFocusOnOpen } from "./editMode";
import { imageResolver } from "./reveal/imageResolver";
import { createImagePastePlugin } from "./pasteImage";
import { AutoSaveController, loadInitialQuKi, type InitialQuKi } from "./persistence";
import { sendQuKi, selectShareTransport } from "./send";
import { shareTextViaAndroid } from "./androidShare";
import { onSharedTextReceived } from "./shareIn";
import { Navigator, type ViewName } from "./navigation";
import { createListView } from "./screens/listView";
import { createSettingsView } from "./screens/settingsView";
import { createSetupView } from "./screens/setupView";
import { createAndroidPermissionView } from "./screens/androidPermissionView";
import { createTrashView } from "./screens/trashView";
import { createToast } from "./screens/toast";
import { createConfirmDialog } from "./screens/confirmDialog";

// basicSetup's defaultHighlightStyle (from @codemirror/language) hardcodes
// colors tuned for a light background — most notably tags.meta at #404740,
// which is what markdown delimiter marks (the `**`, `#`, backtick, etc.
// tokens raw source reveals) are tagged with. Registered as a non-fallback
// highlighter, this mirrors defaultHighlightStyle's rules exactly but ties
// the colors that were only readable on light backgrounds to the page's own
// CSS custom properties — the same fix pattern as the cursor/selection
// colors below. A non-fallback syntaxHighlighting() extension fully
// supersedes basicSetup's fallback one (see @codemirror/language's
// getHighlighters), so this replaces it deterministically regardless of
// extension order.
const qukiSyntaxHighlighting = HighlightStyle.define([
  { tag: tags.meta, color: "var(--text-muted)" },
  { tag: tags.link, textDecoration: "underline" },
  { tag: tags.heading, textDecoration: "underline", fontWeight: "bold" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strong, fontWeight: "bold" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.keyword, color: "#708" },
  {
    tag: [tags.atom, tags.bool, tags.url, tags.contentSeparator, tags.labelName],
    color: "var(--accent)",
  },
  { tag: [tags.literal, tags.inserted], color: "#164" },
  { tag: [tags.string, tags.deleted], color: "var(--text)" },
  {
    tag: [tags.regexp, tags.escape, tags.special(tags.string)],
    color: "var(--text-muted)",
  },
  { tag: tags.definition(tags.variableName), color: "#00f" },
  { tag: tags.local(tags.variableName), color: "#30a" },
  { tag: [tags.typeName, tags.namespace], color: "#085" },
  { tag: tags.className, color: "#167" },
  { tag: [tags.special(tags.variableName), tags.macroName], color: "#256" },
  { tag: tags.definition(tags.propertyName), color: "#00c" },
  { tag: tags.comment, color: "var(--text-muted)" },
  { tag: tags.invalid, color: "#f00" },
]);

type IconNode = Parameters<typeof createElement>[0];

function setButtonIcon(button: HTMLButtonElement, iconNode: IconNode, label: string): void {
  button.replaceChildren(createElement(iconNode, { width: 24, height: 24, "aria-hidden": "true", focusable: "false" }));
  button.title = label;
  button.setAttribute("aria-label", label);
}

const SVG_NS = "http://www.w3.org/2000/svg";

/**
 * The Markdown Mark logo, replicated from lib/features/editor/editor_screen.dart's
 * _MarkdownMarkPainter (viewBox 208x128: a rounded-rect outline containing an
 * "M" and a down arrow) - not a Lucide icon, so it doesn't go through
 * setButtonIcon's createElement path. This is the mode toggle's rendered/
 * markdown-mode icon (BEHAVIOR_SPEC.md §4); see updateModeToggleIcon for why
 * it's used instead of an open-book icon.
 */
function createMarkdownMarkIcon(): SVGSVGElement {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 208 128");
  svg.setAttribute("width", "24");
  svg.setAttribute("height", "15");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("focusable", "false");

  const outline = document.createElementNS(SVG_NS, "rect");
  outline.setAttribute("x", "5");
  outline.setAttribute("y", "5");
  outline.setAttribute("width", "198");
  outline.setAttribute("height", "118");
  outline.setAttribute("rx", "10");
  outline.setAttribute("fill", "none");
  outline.setAttribute("stroke", "currentColor");
  outline.setAttribute("stroke-width", "10");
  outline.setAttribute("stroke-linejoin", "round");

  const letterM = document.createElementNS(SVG_NS, "path");
  letterM.setAttribute(
    "d",
    "M30,98 L30,30 L50,30 L70,55 L90,30 L110,30 L110,98 L90,98 L90,59 L70,84 L50,59 L50,98 Z",
  );
  letterM.setAttribute("fill", "currentColor");

  const arrow = document.createElementNS(SVG_NS, "path");
  arrow.setAttribute("d", "M155,98 L125,65 L145,65 L145,30 L165,30 L165,65 L185,65 Z");
  arrow.setAttribute("fill", "currentColor");

  svg.append(outline, letterM, arrow);
  return svg;
}

/**
 * BEHAVIOR_SPEC.md §3's Android paragraph: "if all-files access is already
 * granted, resolve a fixed path under the external documents directory,
 * create it, and continue. If not, send the user to the system permission
 * screen and resume the flow when the app comes back to the foreground —
 * the permission grant returns no result, so app lifecycle is the only
 * signal." createStorageAccessGate (androidStorageAccess.ts) is the pure
 * decision flow; this wires it to the real plugins and to a full-screen
 * explanatory view (screens/androidPermissionView.ts) rendered into the
 * shared overlay host, the same layer setupView.ts's Electron equivalent
 * uses. `gate`/`view` are declared before assignment so each can close
 * over the other — requestAccess needs the gate, and the gate's state
 * changes need to reach the view.
 */
async function ensureAndroidStorageAccess(overlayHost: HTMLElement): Promise<void> {
  let gate: ReturnType<typeof createStorageAccessGate>;
  const view = createAndroidPermissionView(overlayHost, () => void gate.requestAccess());
  gate = createStorageAccessGate(
    {
      isExternalStorageManager: async () => (await CapacitorStorage.isExternalStorageManager()).granted,
      requestAllFilesAccess: () => CapacitorStorage.requestAllFilesAccess(),
      onAppStateChange: (callback) => {
        const handle = CapacitorApp.addListener("appStateChange", (state) => callback(state.isActive));
        return { remove: () => void handle.then((h) => h.remove()) };
      },
    },
    (state) => view.render(state),
  );
  try {
    await gate.ready();
  } finally {
    gate.destroy();
  }
}

/**
 * Wires StoragePlugin.kt's real Context/File-backed migration primitives
 * to androidFlutterMigration.ts's platform-free deps interface — the same
 * pattern ensureAndroidStorageAccess below uses for createStorageAccessGate.
 */
const androidFlutterMigrationDeps: AndroidFlutterMigrationDeps = {
  getFlutterMigrationInfo: () => CapacitorStorage.getFlutterMigrationInfo(),
  isValidWritableDirectory: async (path) => (await CapacitorStorage.isValidWritableDirectory({ path })).valid,
  listDir: async (path) => (await CapacitorStorage.listDir({ path })).entries,
};

/**
 * `<external Documents>/QuKi_Notes`, matching the Flutter app's own
 * StoragePlugin.kt — the plain fixed default used once a migrated folder
 * isn't found below. All-files access is confirmed granted by the time this
 * runs (ensureAndroidStorageAccess above), on every platform this is
 * reachable from (see main() below) — so an mkdirp failure here is a
 * genuine unexpected error, not a missing-permission case.
 */
async function resolveAndroidStoragePath(overlayHost: HTMLElement): Promise<string> {
  // STORAGE_CONTRACT.md's migration section, Android side: a returning
  // Flutter user skips straight to their existing content — no permission
  // screen, no onboarding — the same outcome the desktop migration chunk
  // achieves. resolveMigratedStorageRoot only ever returns a path that
  // already passed a real write-probe (see androidFlutterMigration.ts), so
  // reaching the all-files-access permission screen below means neither a
  // recorded Flutter choice nor an existing app-storage folder validated.
  const migratedPath = await resolveMigratedStorageRoot(androidFlutterMigrationDeps);
  if (migratedPath !== null) return migratedPath;

  await ensureAndroidStorageAccess(overlayHost);
  const { path } = await CapacitorStorage.getExternalDocumentsPath();
  return path;
}

async function createCapacitorBackend(overlayHost: HTMLElement, onMkdirpError: (message: string) => void): Promise<StorageBackend> {
  const path =
    Capacitor.getPlatform() === "android"
      ? await resolveAndroidStoragePath(overlayHost)
      : (await CapacitorStorage.getExternalDocumentsPath()).path;
  const backend = new CapacitorFsBackend(CapacitorStorage, path);
  try {
    await backend.mkdirp("");
  } catch (error) {
    console.error("QuKi Capacitor storage root could not be created:", error);
    onMkdirpError("Could not create the QuKi Notes folder — an unexpected error occurred. Your QuKis will not load or save until it is.");
  }
  return backend;
}

const saveStatus = document.querySelector<HTMLDivElement>("#save-status");

function showSaveStatus(message: string): void {
  if (!saveStatus) return;
  saveStatus.textContent = message;
  saveStatus.hidden = false;
}

/**
 * STORAGE_CONTRACT.md: "navigator.storage.persist() can exempt an origin
 * [from iOS OPFS eviction] and the heuristic that most reliably grants it is
 * being installed to the home screen." This call is what actually asks for
 * that exemption; installability alone doesn't. Some engines lack the API
 * entirely and some reject the call outright — both are normal, not errors,
 * so this never throws past its own boundary. There's no settings screen to
 * surface the grant/deny outcome yet, so it's logged for now.
 */
async function requestPersistentStorage(): Promise<void> {
  if (!navigator.storage?.persist) {
    console.info("QuKi persistent storage: navigator.storage.persist() is not available in this environment.");
    return;
  }
  try {
    const granted = await navigator.storage.persist();
    console.info(`QuKi persistent storage: ${granted ? "granted" : "not granted"}.`);
  } catch (error) {
    console.warn("QuKi persistent storage: navigator.storage.persist() failed unexpectedly:", error);
  }
}

async function init(): Promise<void> {
  void requestPersistentStorage();

  const host = document.querySelector<HTMLDivElement>("#editor-host");
  if (!host) {
    throw new Error("missing #editor-host");
  }

  // Built and wired before anything storage-related, since the setup
  // screen (Electron only, see below) needs somewhere to render before a
  // backend or store can even be constructed.
  const overlayHost = document.querySelector<HTMLElement>("#overlay-host")!;
  const showToast = createToast(overlayHost);
  const confirm = createConfirmDialog(overlayHost);

  // Electron's preload script (project/electron/src/preload.ts) exposes
  // window.electronAPI/window.electronSetupAPI only when this app is
  // running inside the Electron wrapper; both are absent in the plain
  // browser/PWA build, which keeps using OPFS exactly as before and has no
  // concept of a storage-location setup screen at all (STORAGE_CONTRACT.md:
  // "the web app has no storage-location onboarding step; it simply
  // starts"). setupApi/setupView stay undefined on the web build, and
  // every use of them below is gated on that.
  const setupApi = window.electronAPI && window.electronSetupAPI ? window.electronSetupAPI : undefined;
  const setupView = setupApi ? createSetupView(overlayHost, setupApi) : undefined;

  // BEHAVIOR_SPEC.md §3: "if no storage location has ever been chosen, the
  // setup screen appears instead of the editor" - nothing below this may
  // construct a backend, a QuKiStore, or touch a file until a location is
  // known, on Electron. The web build has no such gate (setupApi is
  // undefined there) and proceeds immediately, unchanged from before.
  if (setupApi && setupView) {
    const state = await setupApi.getState();
    if (!state.chosen) {
      if (state.unreachablePath !== null) {
        // [Proposed — unconfirmed] A returning user whose previously-chosen
        // folder main.ts's app.whenReady() could not validate at this
        // launch (electron/src/main.ts) - not a genuine first launch. Shown
        // cancelable, since picking a new location right now is optional:
        // the original folder may simply come back (drive reconnected,
        // network share remounted) without the user wanting to switch.
        const chosenPath = await setupView.show({
          cancelable: true,
          recovery: { unreachablePath: state.unreachablePath },
          onError: (message) => showSaveStatus(message),
        });
        if (chosenPath === null) {
          // Declining leaves no storage backend to run against - every
          // read/write would fail - so this quits rather than falling
          // through into a broken editor. The user can just relaunch once
          // the original location is reachable again, or relaunch and
          // choose a new one from this same screen.
          await setupApi.quit();
          return;
        }
      } else {
        await setupView.show({
          cancelable: false,
          onError: (message) => showSaveStatus(message),
        });
      }
    }
  }

  const backend: StorageBackend = window.electronAPI
    ? new ElectronIpcBackend(window.electronAPI)
    : Capacitor.isNativePlatform()
      ? await createCapacitorBackend(overlayHost, showSaveStatus)
      : new OpfsBackend("quki");
  const store = new QuKiStore(backend);

  // STORAGE_CONTRACT.md rule 14 / BEHAVIOR_SPEC.md §6: the 30-day trash
  // hold is purged automatically at app launch, before anything (the list,
  // Trash itself) needs to read trash state.
  await store.purgeExpiredTrash().catch((error: unknown) => {
    console.error("QuKi trash purge failed unexpectedly:", error);
  });

  // Still a stand-in for real deep-linking (e.g. reopening the last-open
  // QuKi via a URL or session-restore) - there is no such mechanism yet, so
  // launch continues to load whichever active QuKi was modified most
  // recently, or starts blank if none exist. Once the list/editor id state
  // exists (see `autoSave.currentId` below), this is the only remaining
  // "no explicit selection" fallback.
  const initial = await loadInitialQuKi(store, () => {
    showSaveStatus("Could not load your QuKi — an unexpected error occurred. Starting with a blank QuKi.");
  });

  // Set once per editor content swap (loading a different QuKi, New QuKi,
  // clearing on delete) to suppress the change-notification below -
  // BEHAVIOR_SPEC.md §4: "Setting the editor's value programmatically...
  // does not fire the change event - this is what stops a load from
  // triggering a save."
  let suppressAutoSaveNotify = false;

  // Forward-declared and assigned once `view` exists (just below), the same
  // pattern `autoSave` already uses in this function: the closures inside
  // `state`'s extensions capture the binding, not a value, so it's safe as
  // long as `toolbarController` is assigned before any real edit/keypress
  // reaches these callbacks - which can only happen after `init()`'s
  // synchronous setup below has finished running.
  let toolbarController: FormattingToolbarHandle | undefined;

  // BEHAVIOR_SPEC.md §12 "Indentation": "Indent and dedent act on whole
  // lines, and are bound to both the toolbar buttons and Tab / Shift-Tab."
  // `defaultKeymap` (@codemirror/commands) does not bind Tab itself - that
  // binding lives in the separate `indentWithTab` export, which this
  // project never imports - so there is no existing Tab/Shift-Tab behavior
  // here to collide with or override. Routed through the same
  // `runToolbarCommand` the toolbar buttons use (screens/formattingToolbar.ts)
  // so Tab/Shift-Tab and the Indent/Dedent buttons behave identically.
  const indentDedentKeymap: KeyBinding[] = [
    {
      key: "Tab",
      run: (v) => {
        runToolbarCommand(v, applyIndent);
        return true;
      },
      shift: (v) => {
        runToolbarCommand(v, applyDedent);
        return true;
      },
    },
  ];

  const state = EditorState.create({
    doc: initial.body,
    extensions: [
      // Explicit stand-in for codemirror's basicSetup, trimmed to what
      // QuKi Notes actually uses (BEHAVIOR_SPEC.md §12) — no line-number
      // gutter, fold gutter, bracket matching/closing, autocomplete,
      // rectangular selection, crosshair cursor or selection-match
      // highlighting, none of which appear in the spec's editor surface.
      highlightSpecialChars(),
      history(),
      drawSelection(),
      dropCursor(),
      EditorState.allowMultipleSelections.of(true),
      indentOnInput(),
      highlightActiveLine(),
      keymap.of([...indentDedentKeymap, ...defaultKeymap, ...historyKeymap]),
      markdown({ extensions: GFM }),
      syntaxHighlighting(qukiSyntaxHighlighting),
      plainTextMode,
      imageResolver.of((relPath) => backend.readBinary(relPath)),
      revealPlugin,
      // STORAGE_CONTRACT.md rule 12 / web-specific "images paste in the
      // same way [as text]": a pasted image is written into the shared
      // media/ folder and its link inserted at the cursor. Plain-text
      // paste is untouched by this — see pasteImage.ts.
      createImagePastePlugin({
        writeImage: (bytes, extension) => store.writeImage(bytes, extension),
        onError: () => {
          showSaveStatus("Could not paste image — an unexpected error occurred.");
        },
      }),
      EditorView.lineWrapping,
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !suppressAutoSaveNotify) autoSave.notifyChange();
        toolbarController?.onUpdate(update);
      }),
      // The formatting toolbar overlays the scroller's own bottom edge
      // rather than pushing it up (style.css's .formatting-toolbar is
      // `position: absolute`) — CodeMirror's own scroll-into-view has no
      // way to know that band is visually covered, so typing to the true
      // bottom of a long QuKi can otherwise leave the caret hidden
      // underneath the toolbar. Confirmed on a real Android emulator with
      // the keyboard up (chunk 3's report). scrollMargins is CodeMirror's
      // documented mechanism for exactly this ("the plugin introduces
      // elements that cover part of [the scrolling element]") —
      // toolbarController is forward-declared/assigned the same way its
      // onUpdate call above already relies on.
      EditorView.scrollMargins.of(() => ({ bottom: toolbarController?.scrollMarginBottom() ?? 0 })),
      EditorView.theme({
        "&": { fontSize: "16px" },
        // BEHAVIOR_SPEC.md §4: "content is inset 12px on three sides and
        // 36px at the bottom so the last line clears the toolbar." This has
        // to be set through EditorView.theme() rather than a plain rule in
        // style.css: CodeMirror ships its own `.cm-content { padding: 4px
        // 0 }` baseTheme rule under a two-class selector, which beats a
        // plain `.cm-content` selector on specificity regardless of source
        // order — confirmed on a real device that content authored the
        // plain-CSS way never actually got the intended clearance, so the
        // toolbar (style.css's .formatting-toolbar, height: 36px, pinned
        // `position: absolute` over the scroller's own bottom edge) could
        // end up covering the caret's own line (chunk 3's report has the
        // measurements). 36px here must keep matching that height.
        ".cm-content": { lineHeight: "1.4", padding: "12px", paddingBottom: "36px" },
        // CodeMirror's default cursor/selection/active-line colors only switch
        // via the `dark: true` theme flag, which this project doesn't set —
        // the page's dark mode comes from prefers-color-scheme on CSS custom
        // properties instead, so all of these must be tied to those same
        // properties rather than CodeMirror's separate light/dark mechanism.
        ".cm-cursor, .cm-cursor-primary": {
          borderLeft: "1.5px solid var(--accent)",
        },
        ".cm-selectionBackground": {
          backgroundColor: "var(--accent)",
          opacity: "0.35",
        },
        ".cm-activeLine": {
          backgroundColor: "var(--surface-subtle)",
        },
      }),
    ],
  });

  const view = new EditorView({
    state,
    parent: host,
  });

  toolbarController = createFormattingToolbar(view, host);

  // PROPOSAL: a plain visible status banner is the minimal way to satisfy
  // STORAGE_CONTRACT.md rule 18 ("a failed save is surfaced, not just
  // logged") for this slice. It is not a merge UI or a real notification
  // system - just enough that a conflict, or an unexpected save error, is
  // never silently dropped.
  const autoSave = new AutoSaveController(
    store,
    () => view.state.doc.toString(),
    (info) => {
      const detail = info.reason === "deleted" ? "it was deleted elsewhere" : "it changed elsewhere";
      showSaveStatus(`Could not save — ${detail}. Your latest edits have not been written to disk.`);
    },
    initial,
    {
      onSaveError: () => {
        showSaveStatus("Could not save — an unexpected error occurred. Your latest edits have not been written to disk.");
      },
      onSaved: () => {
        updateDeleteButtonState();
        void refreshQuKisButton();
      },
    },
  );
  autoSave.start();

  const flushOnHide = (): void => {
    void autoSave.flush();
  };
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") flushOnHide();
  });
  window.addEventListener("pagehide", flushOnHide);

  // BEHAVIOR_SPEC.md §4: "a new, blank QuKi takes focus (edit mode), an
  // existing QuKi does not (reading mode)." At launch `initial` is
  // whichever QuKi loadInitialQuKi resolved (most-recently-modified, or
  // blank if none exist) - shouldFocusOnOpen's null-id check applies here
  // exactly as it does to startNewQuKi/openQuKiInEditor below.
  const editModeTracker = createEditModeTracker(view, shouldFocusOnOpen(initial.id), (isEditMode) => {
    updateModeToggleIcon();
    toolbarController?.setVisible(isEditMode);
  });
  if (shouldFocusOnOpen(initial.id)) view.focus();
  // Seeds the toolbar's initial shown/hidden state the same way
  // updateModeToggleIcon() below seeds the mode icon from
  // editModeTracker.isEditMode() - both read the one tracker, so the
  // toolbar and the mode icon can never disagree about edit vs. reading.
  toolbarController.setVisible(editModeTracker.isEditMode());

  // --- Navigation: list / settings / trash, and the app bar actions that open them ---

  const viewElements: Record<ViewName, HTMLElement> = {
    editor: document.querySelector<HTMLElement>("#view-editor")!,
    list: document.querySelector<HTMLElement>("#view-list")!,
    settings: document.querySelector<HTMLElement>("#view-settings")!,
    trash: document.querySelector<HTMLElement>("#view-trash")!,
  };
  const navigator_ = new Navigator(viewElements);

  const quKiListBtn = document.querySelector<HTMLButtonElement>("#btn-quki-list")!;
  const modeToggleBtn = document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!;
  const newQuKiBtn = document.querySelector<HTMLButtonElement>("#btn-new-quki")!;
  const helpBtn = document.querySelector<HTMLButtonElement>("#btn-help")!;
  const sendBtn = document.querySelector<HTMLButtonElement>("#btn-send")!;
  const settingsBtn = document.querySelector<HTMLButtonElement>("#btn-settings")!;
  const deleteBtn = document.querySelector<HTMLButtonElement>("#btn-delete")!;

  setButtonIcon(quKiListBtn, FileStack, "QuKis");
  setButtonIcon(newQuKiBtn, Plus, "New QuKi");
  // Help matches the reference app bar's icon, tooltip and position, but no
  // Help dialog exists yet in this rewrite - disabled until that work
  // lands, rather than shown enabled with no click handler.
  setButtonIcon(helpBtn, CircleHelp, "Help");
  helpBtn.disabled = true;
  setButtonIcon(sendBtn, Send, "Send");
  // KNOWN DEFICIENCY, accepted deliberately, not a design decision:
  // STORAGE_CONTRACT.md calls for the real OS share sheet on Windows via
  // navigator.share(), but Electron has no bridge to it at all - the
  // Chromium code that implements Web Share on Windows lives in
  // chrome/browser, which Electron doesn't build on, and a Windows feature
  // request for it was closed "not planned" upstream. Reaching the real
  // Windows Share UI (IDataTransferManagerInterop, COM-only) would need a
  // native addon; the one existing community wrapper compiles a separate
  // unmaintained C# helper, which the project owner declined to adopt.
  // Until a native addon is built - and this may be worth publishing for
  // other Electron apps in the same position, since no clean solution
  // appears to exist anywhere in the ecosystem - Windows falls back to the
  // same clipboard behavior already built for Linux (STORAGE_CONTRACT.md's
  // Linux clipboard fallback, reused here as a stand-in, not a match for
  // spec intent). See sendCurrentQuKi below.
  //
  // Android is not a fallback case at all: it gets the real system share
  // sheet (androidShare.ts, via the native Share plugin), matching
  // BEHAVIOR_SPEC.md's "Send becomes one action: the system share sheet
  // where one exists" for the one platform where it already exists here.
  const isAndroid = Capacitor.getPlatform() === "android";
  sendBtn.disabled = !isAndroid && window.electronPlatform !== "linux" && window.electronPlatform !== "win32";
  setButtonIcon(settingsBtn, Settings, "Settings");
  setButtonIcon(deleteBtn, Trash2, "Delete");

  /**
   * BEHAVIOR_SPEC.md §4: the mode toggle's icon has three states - a code
   * icon in plain-text mode, a markdown-mark icon in edit mode, an open
   * book in reading mode (editModeTracker/resolveModeIconState - see
   * editMode.ts for what actually drives edit vs. reading: Capacitor
   * keyboard events on Android, editor focus everywhere else). The
   * button's own action (toggle plain-text) is unaffected by edit/reading,
   * so its label always describes that action, not the icon currently
   * shown.
   */
  function updateModeToggleIcon(): void {
    const isPlainText = view.state.field(plainTextMode);
    const iconState = resolveModeIconState(isPlainText, editModeTracker.isEditMode());
    const icon =
      iconState === "plain-text"
        ? createElement(CodeXml, { width: 24, height: 24, "aria-hidden": "true", focusable: "false" })
        : iconState === "edit"
          ? createMarkdownMarkIcon()
          : createElement(BookOpen, { width: 24, height: 24, "aria-hidden": "true", focusable: "false" });
    modeToggleBtn.replaceChildren(icon);
    const label = isPlainText ? "Rendered mode" : "Plain text";
    modeToggleBtn.title = label;
    modeToggleBtn.setAttribute("aria-label", label);
    modeToggleBtn.setAttribute("aria-pressed", String(isPlainText));
  }
  updateModeToggleIcon();

  modeToggleBtn.addEventListener("click", () => {
    view.dispatch({
      effects: setPlainTextMode.of(!view.state.field(plainTextMode)),
    });
    updateModeToggleIcon();
    view.focus();
  });

  function updateDeleteButtonState(): void {
    deleteBtn.disabled = autoSave.currentId === null;
  }
  updateDeleteButtonState();

  async function refreshQuKisButton(): Promise<void> {
    try {
      const list = await store.list();
      quKiListBtn.disabled = list.length === 0;
    } catch (error) {
      console.error("QuKi list refresh (for the QuKis button state) failed unexpectedly:", error);
    }
  }
  void refreshQuKisButton();

  /**
   * Replaces the editor's document without treating it as a user edit -
   * BEHAVIOR_SPEC.md §4's "resets the caret to the start and does not fire
   * the change event." Every caller pairs this with autoSave.resetBaseline
   * so the two never disagree about what the "last saved" body is.
   */
  function loadDocumentIntoEditor(body: string): void {
    suppressAutoSaveNotify = true;
    try {
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: body },
        selection: { anchor: 0 },
      });
    } finally {
      suppressAutoSaveNotify = false;
    }
  }

  /**
   * Shared by the editor's own Delete button and the QuKi list's per-row
   * delete affordance. BEHAVIOR_SPEC.md §4: flush is one of the explicit
   * auto-save triggers ("before switching QuKis, opening the list,
   * deleting"); if the QuKi being deleted is the one open in the editor,
   * the editor is cleared and the save baseline reset to blank *before*
   * store.moveToTrash() runs - load-bearing ordering, see §4's own
   * explanation of why (the debounce/interval timers could otherwise
   * resave the still-displayed body back under the id that was just
   * trashed).
   */
  async function deleteQuKi(id: string): Promise<void> {
    await autoSave.flush();
    if (autoSave.currentId === id) {
      loadDocumentIntoEditor("");
      autoSave.resetBaseline({ id: null, body: "", modifiedAt: null });
      updateDeleteButtonState();
    }
    try {
      await store.moveToTrash(id);
    } catch (error) {
      console.error("QuKi delete (moveToTrash) failed unexpectedly:", error);
      showSaveStatus("Could not move QuKi to Trash — an unexpected error occurred.");
      return;
    }
    showToast("QuKi moved to Trash.", 1500);
    void refreshQuKisButton();
  }

  /**
   * BEHAVIOR_SPEC.md §4 "Send": flush is one of the explicit auto-save
   * triggers ("before switching QuKis, opening the list, deleting, and
   * sending"), so it runs first regardless of whether the body turns out
   * to be empty - matching deleteQuKi's ordering above. The body is then
   * read straight from the live editor (not re-read from disk), so a
   * keystroke landing during the flush's own await is still what gets
   * sent, never a stale pre-flush copy.
   */
  async function sendCurrentQuKi(): Promise<void> {
    await autoSave.flush();
    const body = view.state.doc.toString();
    const transport = selectShareTransport(isAndroid, shareTextViaAndroid, (text) => navigator.clipboard.writeText(text));
    const result = await sendQuKi(body, transport);
    showToast(result.message, result.durationMs, result.retryable ? { label: "Retry", onClick: () => void sendCurrentQuKi() } : undefined);
  }

  async function openQuKiInEditor(id: string): Promise<void> {
    await autoSave.flush();
    let detail;
    try {
      detail = await store.read(id);
    } catch (error) {
      console.error("QuKi open (read) failed unexpectedly:", error);
      showSaveStatus("Could not open that QuKi — an unexpected error occurred.");
      return;
    }
    loadDocumentIntoEditor(detail.body);
    autoSave.resetBaseline({ id: detail.id, body: detail.body, modifiedAt: detail.modifiedAt });
    updateDeleteButtonState();
    navigator_.popToRoot();
  }

  async function startNewQuKi(): Promise<void> {
    await autoSave.flush();
    const blank: InitialQuKi = { id: null, body: "", modifiedAt: null };
    loadDocumentIntoEditor("");
    autoSave.resetBaseline(blank);
    updateDeleteButtonState();
    navigator_.popToRoot();
    view.focus();
  }

  /**
   * BEHAVIOR_SPEC.md §8: text shared in from another app becomes a new QuKi
   * immediately and opens in the editor - no screen is ever pushed. Follows
   * openQuKiInEditor/startNewQuKi's exact shape (flush, then load, then
   * reset the auto-save baseline), except the "load" step is a real,
   * immediate, persisted create via store.save({ id: null, ... }) rather
   * than a blank QuKi waiting for input - matching lib/app.dart's
   * _ShareAwareHome, which calls storage.create(text) directly rather than
   * just loading the text into an unsaved editor.
   *
   * Flushing first (as every other entry point into the editor already
   * does) matters here specifically for the "already running" path
   * BEHAVIOR_SPEC.md §8 requires: whatever was open and unsaved before the
   * share arrived must be written to disk before the editor's content is
   * replaced with the shared text, or that edit would be lost.
   */
  async function handleSharedText(text: string): Promise<void> {
    await autoSave.flush();
    let result;
    try {
      result = await store.save({ id: null, body: text });
    } catch (error) {
      console.error("QuKi share-in (save) failed unexpectedly:", error);
      showToast("Failed to save shared content.", 4000);
      return;
    }
    if (result.status !== "saved") {
      // QuKiStore.save({ id: null, ... }) only ever returns "saved" or
      // "skipped-empty" (quKiStore.ts's createNew) - "conflict" is not
      // reachable when creating. "skipped-empty" means the shared text was
      // the empty string, so there is nothing to open; reported the same
      // way as a thrown save error since nothing was persisted either way.
      showToast("Failed to save shared content.", 4000);
      return;
    }
    loadDocumentIntoEditor(text);
    autoSave.resetBaseline({ id: result.id, body: text, modifiedAt: result.modifiedAt });
    updateDeleteButtonState();
    void refreshQuKisButton();
    navigator_.popToRoot();
  }

  /**
   * BEHAVIOR_SPEC.md §5 only says the list "refreshes from the folder each
   * time it opens," describing the editor->list push. It doesn't address
   * the nested case this app's stack navigation introduces: Settings and
   * Trash can also be reached *from* the list (§2's "plain push"), and an
   * action taken there - restoring a QuKi, most notably - changes what the
   * list should show once its child screens close back onto it. Popping
   * back onto the list re-opens it (refreshing from the folder) for that
   * reason; popping onto any other view is a no-op beyond the transition.
   */
  function popView(): void {
    navigator_.pop();
    if (navigator_.current === "list") void listView.open();
    if (navigator_.current === "editor") void refreshQuKisButton();
  }

  /**
   * Wired into Settings -> Change location (Electron only; settingsView's
   * `storage` callbacks are undefined on the web build, so this is never
   * reachable there). BEHAVIOR_SPEC.md §3 says only "returning from it
   * refreshes the QuKi list" - it doesn't spell out what happens to
   * whatever QuKi is open in the editor when the root folder changes
   * mid-session.
   *
   * PROPOSAL: treat this like a fresh launch against the new folder -
   * reload whichever QuKi is most-recently-modified there (or start blank
   * if none exist), the same fallback loadInitialQuKi uses at real launch.
   * The alternative (silently leave the editor showing the old folder's
   * QuKi) would leave it pointed at content that may not even exist at the
   * new root, and would disagree with what the QuKis button / list /
   * delete button state say about it.
   */
  async function changeStorageLocation(): Promise<void> {
    if (!setupView) return;
    // The currently open QuKi still belongs to the *old* folder - flush it
    // there before the root swaps underneath this same store/backend, or a
    // pending edit would otherwise get written into the new folder instead.
    await autoSave.flush();
    const chosenPath = await setupView.show({
      cancelable: true,
      onError: (message) => showSaveStatus(message),
    });
    if (chosenPath === null) return; // cancelled; nothing changed

    const reloaded = await loadInitialQuKi(store, () => {
      showSaveStatus("Could not load your QuKi — an unexpected error occurred. Starting with a blank QuKi.");
    });
    loadDocumentIntoEditor(reloaded.body);
    autoSave.resetBaseline(reloaded);
    updateDeleteButtonState();
    void refreshQuKisButton();
  }

  const listView = createListView(store, viewElements.list, {
    onOpenQuKi: openQuKiInEditor,
    onNewQuKi: startNewQuKi,
    onOpenSettings: () => navigator_.push("settings", { plain: true }),
    onDeleteQuKi: deleteQuKi,
    onBack: popView,
  });

  createSettingsView(viewElements.settings, {
    onBack: popView,
    onOpenTrash: () => {
      navigator_.push("trash");
      void trashView.open();
    },
    showToast,
    storage: setupApi
      ? {
          getCurrentPath: async () => {
            const state = await setupApi.getState();
            return state.path ?? "Unknown";
          },
          onChangeLocation: changeStorageLocation,
        }
      : undefined,
  });

  const trashView = createTrashView(store, viewElements.trash, {
    onBack: popView,
    showToast,
    confirm,
  });

  quKiListBtn.addEventListener("click", () => {
    navigator_.push("list");
    void listView.open();
  });
  newQuKiBtn.addEventListener("click", () => {
    void startNewQuKi();
  });
  settingsBtn.addEventListener("click", () => {
    navigator_.push("settings");
  });
  deleteBtn.addEventListener("click", () => {
    const id = autoSave.currentId;
    if (id === null) return;
    void deleteQuKi(id);
  });
  sendBtn.addEventListener("click", () => {
    void sendCurrentQuKi();
  });

  // BEHAVIOR_SPEC.md §8, Android only - same isAndroid gate already used
  // above for Send. Registered once for the life of the app, the same way
  // editModeTracker's Keyboard listeners above are never removed.
  if (isAndroid) {
    void onSharedTextReceived((text) => {
      void handleSharedText(text);
    });
  }

  // Exposed for interactive debugging from the browser console while proving
  // the mechanism out — not part of the reveal engine itself.
  (window as unknown as { qukiView: EditorView; qukiPlainTextMode: typeof plainTextMode }).qukiView = view;
  (window as unknown as { qukiView: EditorView; qukiPlainTextMode: typeof plainTextMode }).qukiPlainTextMode = plainTextMode;
}

void init();
