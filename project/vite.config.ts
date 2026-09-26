import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import { VitePWA } from "vite-plugin-pwa";

import { collectBuildInfo } from "./src/buildInfoGit";

const pkg = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf-8")) as {
  version: string;
};

const buildInfo = collectBuildInfo({ cwd: fileURLToPath(new URL(".", import.meta.url)) });

export default defineConfig({
  root: ".",
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    __BUILD_INFO__: JSON.stringify(buildInfo),
  },
  server: {
    host: true,
    allowedHosts: ["thehumanton.tail6388a4.ts.net"],
  },
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
  plugins: [
    VitePWA({
      // generateSW (the default strategy) builds a Workbox service worker
      // that precaches the full build output and answers matching requests
      // from cache with no network dependency - what STORAGE_CONTRACT.md's
      // iOS-eviction rationale actually needs (an installable, working-
      // offline app), not just a manifest.
      registerType: "autoUpdate",
      // Registration is handled manually in main.ts so it can be skipped when
      // running as a Capacitor native app. In native context assets are served
      // from the APK bundle directly; a service worker that pre-caches them
      // persists across APK updates and causes stale-content on every install.
      injectRegister: false,
      manifest: {
        name: "QuKi Notes",
        short_name: "QuKi Notes",
        description: "A fast, distraction-free markdown notes app.",
        start_url: "/",
        scope: "/",
        display: "standalone",
        // BEHAVIOR_SPEC.md §11's light theme: --surface-subtle (the app
        // header's own background) for theme_color, since that's the color
        // that actually borders installed-window/status-bar chrome; --surface
        // (the page body) for background_color, the splash-screen color
        // shown before CSS paints. [Proposed — unconfirmed: no manifest
        // color role is specified in BEHAVIOR_SPEC.md, so this pairing is a
        // judgment call, not a restatement of a stated decision.]
        theme_color: "#f6f8fa",
        background_color: "#ffffff",
        icons: [
          { src: "icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
          { src: "icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
          { src: "icons/maskable-icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: {
        // Default globPatterns only covers js/css/html; the manifest and
        // icon assets vite copies from public/ need to be precached too, or
        // an offline reload would load the app shell but the installed
        // manifest's own icons would 404 offline.
        globPatterns: ["**/*.{js,css,html,ico,png,svg,webmanifest}"],
        navigateFallback: "/index.html",
      },
    }),
  ],
});
