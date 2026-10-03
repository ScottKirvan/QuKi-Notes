import { execFileSync } from "node:child_process";

import { resolveBuildInfo, type BuildEnv, type BuildInfo, type GitFacts } from "./buildInfo";

export type GitRunner = (args: string[]) => string;

const GIT_TIMEOUT_MS = 10_000;

export function defaultGitRunner(cwd: string): GitRunner {
  return (args) => execFileSync("git", args, { cwd, encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"], timeout: GIT_TIMEOUT_MS });
}

function attempt(run: GitRunner, args: string[]): string | null {
  try {
    return run(args).trim();
  } catch {
    return null;
  }
}

export function readGitFacts(run: GitRunner): GitFacts {
  const status = attempt(run, ["status", "--porcelain", "--untracked-files=no"]);
  return {
    commit: attempt(run, ["rev-parse", "HEAD"]),
    branch: attempt(run, ["branch", "--show-current"]),
    dirty: status === null ? null : status !== "",
  };
}

export interface CollectBuildInfoOptions {
  cwd: string;
  env?: BuildEnv;
  now?: Date;
  run?: GitRunner;
}

export function collectBuildInfo({ cwd, env = process.env, now = new Date(), run = defaultGitRunner(cwd) }: CollectBuildInfoOptions): BuildInfo {
  return resolveBuildInfo({ git: readGitFacts(run), env, now });
}
