import { z } from 'zod';

export const quKiSummaryShape = {
  id: z.string(),
  filename: z.string(),
  createdAt: z.string().describe('ISO 8601 timestamp. Intrinsic; falls back to a filesystem timestamp if the sidecar is missing.'),
  modifiedAt: z.string().describe('ISO 8601 timestamp, always read from the file on disk - never from a cached value.'),
};

export const trashedQuKiSummaryShape = {
  ...quKiSummaryShape,
  deletedAt: z
    .string()
    .nullable()
    .describe('ISO 8601 timestamp the QuKi was trashed, or null if unknown (in which case it is never auto-purged).'),
};

export const listActiveOutputShape = {
  qukis: z.array(z.object(quKiSummaryShape)),
};

export const listTrashOutputShape = {
  qukis: z.array(z.object(trashedQuKiSummaryShape)),
};

export const searchOutputShape = {
  results: z.array(z.object(quKiSummaryShape)),
};

export const quKiDetailShape = {
  id: z.string(),
  filename: z.string(),
  body: z.string(),
  createdAt: z.string(),
  modifiedAt: z.string(),
};

export const saveResultShape = {
  status: z.enum(['saved', 'skipped-empty', 'conflict']),
  id: z.string().nullable(),
  filename: z.string().optional(),
  createdAt: z.string().optional(),
  modifiedAt: z.string().optional(),
  reason: z.enum(['modified', 'deleted']).optional().describe('Present only when status is "conflict".'),
  currentModifiedAt: z.string().nullable().optional().describe('The file\'s actual modifiedAt, present only on conflict.'),
  currentBody: z.string().nullable().optional().describe('The file\'s actual current body, present only on conflict.'),
};

export const writeImageOutputShape = {
  relativePath: z.string(),
  absolutePath: z.string(),
};

export const exportOutputShape = {
  bytesBase64: z.string().describe('The gzipped tar archive, base64-encoded.'),
  activeCount: z.number(),
  trashCount: z.number(),
  mediaCount: z.number(),
};
