/**
 * Wraps an async function so only the most recently *started* call can ever
 * deliver a result. If a newer call starts before an older one resolves,
 * the older one resolves to undefined instead of its real value - this is
 * what BEHAVIOR_SPEC.md §5 means by "results from a superseded query are
 * discarded" for the QuKi list's every-keystroke search: a fast-typing user
 * must not see a slow, stale response overwrite a faster, newer one.
 */
export function guardLatest<Args extends unknown[], T>(
  fn: (...args: Args) => Promise<T>,
): (...args: Args) => Promise<T | undefined> {
  let token = 0;

  return async (...args: Args): Promise<T | undefined> => {
    const myToken = ++token;
    const result = await fn(...args);
    if (myToken !== token) return undefined;
    return result;
  };
}
