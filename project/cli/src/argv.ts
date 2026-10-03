export interface ParsedArgs {
  positional: string[];
  flags: Record<string, string | boolean>;
}

export interface ArgSpec {
  /** Flags that never consume the next word - always parse to `true` when present. */
  booleanFlags: readonly string[];
  /** Flags that always consume the next word as their value. */
  valueFlags: readonly string[];
}

export class UnknownFlagError extends Error {
  constructor(flag: string) {
    super(`unknown flag: --${flag}`);
    this.name = 'UnknownFlagError';
  }
}

/**
 * Every flag must be declared as boolean or value-taking up front - there is
 * no more guessing from the shape of the next argument. Without this, a
 * boolean flag (e.g. --trash) followed by a real positional word (a query,
 * an id) swallowed that word as its own string value, leaving the command
 * with no positional and no error - see cli/README or the fix commit this
 * type accompanies for the concrete failures that caused.
 */
export function parseArgs(argv: string[], spec: ArgSpec): ParsedArgs {
  const booleanFlags = new Set(spec.booleanFlags);
  const valueFlags = new Set(spec.valueFlags);
  const positional: string[] = [];
  const flags: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      if (booleanFlags.has(key)) {
        flags[key] = true;
        continue;
      }
      if (valueFlags.has(key)) {
        const next = argv[i + 1];
        if (next === undefined) {
          throw new Error(`--${key} requires a value`);
        }
        flags[key] = next;
        i++;
        continue;
      }
      throw new UnknownFlagError(key);
    } else {
      positional.push(arg);
    }
  }
  return { positional, flags };
}

export function stringFlag(flags: Record<string, string | boolean>, key: string): string | undefined {
  const value = flags[key];
  return typeof value === 'string' ? value : undefined;
}
