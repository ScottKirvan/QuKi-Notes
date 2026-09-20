/**
 * Node-only entry point. Kept separate from index.ts so a browser bundler
 * importing the platform-agnostic barrel never has to resolve node:fs /
 * node:path - only code that explicitly imports from here does.
 */
export { NodeFsBackend } from './nodeFsBackend.js';
