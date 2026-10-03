import { execFileSync } from "node:child_process";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { collectBuildInfo, defaultGitRunner, readGitFacts, type GitRunner } from "./buildInfoGit";

const NOW = new Date("2026-09-21T08:32:00Z");
const SHA = "0123456789abcdef0123456789abcdef01234567";

function runnerFrom(answers: Record<string, string | Error>): GitRunner {
  return (args) => {
    const answer = answers[args.join(" ")];
    if (answer === undefined) throw new Error(`unexpected git call: ${args.join(" ")}`);
    if (answer instanceof Error) throw answer;
    return answer;
  };
}

describe("readGitFacts", () => {
  it("reads the commit, the branch and whether tracked files have uncommitted changes", () => {
    const facts = readGitFacts(
      runnerFrom({
        "rev-parse HEAD": `${SHA}\n`,
        "branch --show-current": "feat/x\n",
        "status --porcelain --untracked-files=no": " M project/src/main.ts\n",
      }),
    );
    expect(facts).toEqual({ commit: SHA, branch: "feat/x", dirty: true });
  });

  it("reports a clean tree as not dirty", () => {
    const facts = readGitFacts(
      runnerFrom({ "rev-parse HEAD": SHA, "branch --show-current": "main", "status --porcelain --untracked-files=no": "" }),
    );
    expect(facts.dirty).toBe(false);
  });

  it("returns nulls, without throwing, when git is not installed", () => {
    const missing = Object.assign(new Error("spawnSync git ENOENT"), { code: "ENOENT" });
    const facts = readGitFacts(() => {
      throw missing;
    });
    expect(facts).toEqual({ commit: null, branch: null, dirty: null });
  });

  it("keeps the facts that succeeded when only some git commands fail (e.g. no branch on a detached HEAD)", () => {
    const facts = readGitFacts(
      runnerFrom({
        "rev-parse HEAD": SHA,
        "branch --show-current": new Error("boom"),
        "status --porcelain --untracked-files=no": "",
      }),
    );
    expect(facts).toEqual({ commit: SHA, branch: null, dirty: false });
  });
});

describe("collectBuildInfo", () => {
  it("falls back to the GitHub Actions environment when git is unavailable", () => {
    const info = collectBuildInfo({
      cwd: ".",
      env: { GITHUB_SHA: "abcdef0123456789abcdef0123456789abcdef01", GITHUB_REF_NAME: "the-branch" },
      now: NOW,
      run: () => {
        throw new Error("no git");
      },
    });
    expect(info).toEqual({ commit: "abcdef0", branch: "the-branch", builtAt: "2026-09-21 08:32 UTC", dirty: false });
  });

  it("yields 'unknown' fields rather than failing when neither git nor the environment can answer", () => {
    const info = collectBuildInfo({
      cwd: ".",
      env: {},
      now: NOW,
      run: () => {
        throw new Error("no git");
      },
    });
    expect(info).toEqual({ commit: "unknown", branch: "unknown", builtAt: "2026-09-21 08:32 UTC", dirty: false });
  });

  it("reads this checkout's real commit through real git", () => {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const expected = execFileSync("git", ["rev-parse", "--short=7", "HEAD"], { cwd: here, encoding: "utf-8" }).trim();
    const info = collectBuildInfo({ cwd: here, env: {}, now: NOW, run: defaultGitRunner(here) });
    expect(info.commit).toBe(expected);
  });
});
