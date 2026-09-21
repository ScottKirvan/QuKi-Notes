export interface BuildInfo {
  commit: string;
  branch: string;
  builtAt: string;
  dirty: boolean;
}

export interface GitFacts {
  commit: string | null;
  branch: string | null;
  dirty: boolean | null;
}

export interface BuildEnv {
  GITHUB_SHA?: string;
  GITHUB_HEAD_REF?: string;
  GITHUB_REF_NAME?: string;
}

export interface BuildInfoInputs {
  git: GitFacts;
  env: BuildEnv;
  now: Date;
}

const UNKNOWN = "unknown";
const SHORT_COMMIT_LENGTH = 7;
const HEX_HASH = /^[0-9a-f]{7,64}$/i;

function shortCommit(candidate: string | null | undefined): string | null {
  const trimmed = candidate?.trim() ?? "";
  return HEX_HASH.test(trimmed) ? trimmed.slice(0, SHORT_COMMIT_LENGTH).toLowerCase() : null;
}

function branchName(candidate: string | null | undefined): string | null {
  const name = (candidate?.trim() ?? "").replace(/^refs\/heads\//, "");
  return name === "" || name === "HEAD" ? null : name;
}

function formatUtc(date: Date): string {
  const iso = date.toISOString();
  return `${iso.slice(0, 10)} ${iso.slice(11, 16)} UTC`;
}

export function resolveBuildInfo({ git, env, now }: BuildInfoInputs): BuildInfo {
  return {
    commit: shortCommit(git.commit) ?? shortCommit(env.GITHUB_SHA) ?? UNKNOWN,
    branch: branchName(git.branch) ?? branchName(env.GITHUB_HEAD_REF) ?? branchName(env.GITHUB_REF_NAME) ?? UNKNOWN,
    builtAt: formatUtc(now),
    dirty: git.dirty === true,
  };
}

const UNCOMMITTED = "uncommitted changes";

export function formatBuildLine(info: BuildInfo): string {
  const parts = [info.commit, info.branch, info.builtAt];
  if (info.dirty) parts.push(UNCOMMITTED);
  return parts.join(" · ");
}

export function formatBuildString(version: string, info: BuildInfo): string {
  const parts = [`commit ${info.commit}`, `branch ${info.branch}`, `built ${info.builtAt}`];
  if (info.dirty) parts.push(UNCOMMITTED);
  return `QuKi Notes ${version} (${parts.join(", ")})`;
}
