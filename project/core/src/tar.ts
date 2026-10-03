export interface TarEntry {
  path: string;
  content: Uint8Array;
  mtimeSeconds: number;
}

const BLOCK_SIZE = 512;
const encoder = new TextEncoder();

function octal(value: number, width: number): string {
  return value.toString(8).padStart(width - 1, '0') + '\0';
}

function writeString(block: Uint8Array, offset: number, value: string, width: number): void {
  const bytes = encoder.encode(value).subarray(0, width);
  block.set(bytes, offset);
}

function splitName(name: string): { prefix: string; name: string } {
  const nameBytes = encoder.encode(name).byteLength;
  if (nameBytes <= 100) return { prefix: '', name };
  const parts = name.split('/');
  for (let i = parts.length - 1; i > 0; i--) {
    const prefix = parts.slice(0, i).join('/');
    const rest = parts.slice(i).join('/');
    if (encoder.encode(prefix).byteLength <= 155 && encoder.encode(rest).byteLength <= 100) {
      return { prefix, name: rest };
    }
  }
  throw new Error(`Path too long for tar archive: ${name}`);
}

function buildHeader(entry: TarEntry): Uint8Array {
  const block = new Uint8Array(BLOCK_SIZE);
  const { prefix, name } = splitName(entry.path);

  writeString(block, 0, name, 100);
  writeString(block, 100, octal(0o644, 8), 8);
  writeString(block, 108, octal(0, 8), 8);
  writeString(block, 116, octal(0, 8), 8);
  writeString(block, 124, octal(entry.content.byteLength, 12), 12);
  writeString(block, 136, octal(entry.mtimeSeconds, 12), 12);
  writeString(block, 148, '        ', 8);
  writeString(block, 156, '0', 1);
  writeString(block, 257, 'ustar', 6);
  writeString(block, 263, '00', 2);
  writeString(block, 345, prefix, 155);

  let sum = 0;
  for (let i = 0; i < BLOCK_SIZE; i++) sum += block[i]!;
  writeString(block, 148, octal(sum, 8), 8);

  return block;
}

export function buildTar(entries: TarEntry[]): Uint8Array {
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (const entry of entries) {
    const header = buildHeader(entry);
    chunks.push(header);
    total += header.byteLength;
    chunks.push(entry.content);
    total += entry.content.byteLength;
    const padLength = (BLOCK_SIZE - (entry.content.byteLength % BLOCK_SIZE)) % BLOCK_SIZE;
    if (padLength > 0) {
      const pad = new Uint8Array(padLength);
      chunks.push(pad);
      total += padLength;
    }
  }
  const trailer = new Uint8Array(BLOCK_SIZE * 2);
  chunks.push(trailer);
  total += trailer.byteLength;

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}
