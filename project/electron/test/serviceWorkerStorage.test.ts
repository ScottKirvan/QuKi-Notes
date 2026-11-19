import { describe, expect, it, vi } from 'vitest';

import { clearServiceWorkerStorage } from '../src/serviceWorkerStorage.js';

describe('clearServiceWorkerStorage', () => {
  it('clears only service workers and CacheStorage, for every origin', async () => {
    const clearStorageData = vi.fn(async () => {});

    await clearServiceWorkerStorage({ clearStorageData });

    expect(clearStorageData).toHaveBeenCalledTimes(1);
    expect(clearStorageData).toHaveBeenCalledWith({ storages: ['serviceworkers', 'cachestorage'] });
  });
});
