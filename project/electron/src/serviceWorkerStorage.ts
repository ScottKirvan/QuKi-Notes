import type { Session } from 'electron';

// Older builds registered the web build's service worker on each launch's
// random-port origin; one of those can serve an old bundle when a later
// launch lands on the same port. No origin is given, so every origin is
// cleared - but only service workers and their caches, nothing else.
export function clearServiceWorkerStorage(session: Pick<Session, 'clearStorageData'>): Promise<void> {
  return session.clearStorageData({ storages: ['serviceworkers', 'cachestorage'] });
}
