import { describe, expect, it } from "vitest";

import { serviceWorkerAction } from "./serviceWorkerPolicy.js";

describe("serviceWorkerAction", () => {
  it("registers the service worker in the web build", () => {
    expect(serviceWorkerAction({ isCapacitorNative: false, isElectron: false })).toBe("register");
  });

  it("does not register the service worker in the Electron desktop app", () => {
    expect(serviceWorkerAction({ isCapacitorNative: false, isElectron: true })).toBe("none");
  });

  it("unregisters any stale service worker on Android, as before", () => {
    expect(serviceWorkerAction({ isCapacitorNative: true, isElectron: false })).toBe("unregisterStale");
  });
});
