import * as fsp from 'node:fs/promises';
import { tmpdir } from 'node:os';
import * as path from 'node:path';

export async function makeTempQuKiDir(): Promise<string> {
  return fsp.mkdtemp(path.join(tmpdir(), 'quki-core-test-'));
}

export async function cleanupTempDir(dir: string): Promise<void> {
  await fsp.rm(dir, { recursive: true, force: true });
}

export async function wait(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}
