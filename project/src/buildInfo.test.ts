import { describe, expect, it } from "vitest";

import { formatBuildLine, formatBuildString, resolveBuildInfo, type BuildInfo } from "./buildInfo";

const NOW = new Date("2026-09-21T08:32:59.999Z");
const FULL_SHA = "0123456789abcdef0123456789abcdef01234567";

describe("resolveBuildInfo", () => {
  it("uses the git facts when git supplied them, shortening the commit to 7 characters", () => {
    const info = resolveBuildInfo({
      git: { commit: FULL_SHA, branch: "feat/about-box", dirty: false },
      env: {},
      now: NOW,
    });
    expect(info).toEqual({ commit: "0123456", branch: "feat/about-box", builtAt: "2026-09-21 08:32 UTC", dirty: false });
  });

  it("reports uncommitted changes only when git said so", () => {
    expect(resolveBuildInfo({ git: { commit: FULL_SHA, branch: "b", dirty: true }, env: {}, now: NOW }).dirty).toBe(true);
    expect(resolveBuildInfo({ git: { commit: FULL_SHA, branch: "b", dirty: null }, env: {}, now: NOW }).dirty).toBe(false);
  });

  it("falls back to GITHUB_SHA and GITHUB_REF_NAME when git supplied nothing", () => {
    const info = resolveBuildInfo({
      git: { commit: null, branch: null, dirty: null },
      env: { GITHUB_SHA: "FEDCBA9876543210FEDCBA9876543210FEDCBA98", GITHUB_REF_NAME: "release-branch" },
      now: NOW,
    });
    expect(info.commit).toBe("fedcba9");
    expect(info.branch).toBe("release-branch");
  });

  it("prefers a pull request's source branch (GITHUB_HEAD_REF) over its 'N/merge' ref name", () => {
    const info = resolveBuildInfo({
      git: { commit: FULL_SHA, branch: null, dirty: null },
      env: { GITHUB_HEAD_REF: "feat/from-the-pr", GITHUB_REF_NAME: "42/merge" },
      now: NOW,
    });
    expect(info.branch).toBe("feat/from-the-pr");
  });

  it("treats a detached HEAD (git prints an empty name, or the literal HEAD) as no branch and uses the environment", () => {
    for (const detached of ["", "  ", "HEAD"]) {
      const info = resolveBuildInfo({
        git: { commit: FULL_SHA, branch: detached, dirty: false },
        env: { GITHUB_REF_NAME: "from-env" },
        now: NOW,
      });
      expect(info.branch).toBe("from-env");
    }
  });

  it("prefers git over the environment when both are present", () => {
    const info = resolveBuildInfo({
      git: { commit: FULL_SHA, branch: "local-branch", dirty: false },
      env: { GITHUB_SHA: "f".repeat(40), GITHUB_REF_NAME: "env-branch" },
      now: NOW,
    });
    expect(info.commit).toBe("0123456");
    expect(info.branch).toBe("local-branch");
  });

  it("strips a refs/heads/ prefix from a branch name", () => {
    const info = resolveBuildInfo({ git: { commit: FULL_SHA, branch: "refs/heads/feat/x", dirty: false }, env: {}, now: NOW });
    expect(info.branch).toBe("feat/x");
  });

  it("falls back to 'unknown' when neither git nor the environment can say", () => {
    const info = resolveBuildInfo({ git: { commit: null, branch: null, dirty: null }, env: {}, now: NOW });
    expect(info).toEqual({ commit: "unknown", branch: "unknown", builtAt: "2026-09-21 08:32 UTC", dirty: false });
  });

  it("ignores a commit value that is not a hex hash and moves on to the next source", () => {
    const info = resolveBuildInfo({
      git: { commit: "fatal: not a git repository", branch: null, dirty: null },
      env: { GITHUB_SHA: "not-a-sha" },
      now: NOW,
    });
    expect(info.commit).toBe("unknown");
  });

  it("ignores a commit shorter than 7 characters", () => {
    const info = resolveBuildInfo({ git: { commit: "abc12", branch: null, dirty: null }, env: {}, now: NOW });
    expect(info.commit).toBe("unknown");
  });

  it("formats the build time in UTC regardless of the machine's zone, to the minute", () => {
    const info = resolveBuildInfo({ git: { commit: FULL_SHA, branch: "b", dirty: false }, env: {}, now: new Date("2026-01-02T23:05:59Z") });
    expect(info.builtAt).toBe("2026-01-02 23:05 UTC");
  });
});

describe("display strings", () => {
  const clean: BuildInfo = { commit: "0123456", branch: "feat/about-box", builtAt: "2026-09-21 08:32 UTC", dirty: false };
  const dirty: BuildInfo = { ...clean, dirty: true };

  it("formatBuildLine shows commit, branch and build time", () => {
    expect(formatBuildLine(clean)).toBe("0123456 · feat/about-box · 2026-09-21 08:32 UTC");
  });

  it("formatBuildLine appends the uncommitted-changes flag only when set", () => {
    expect(formatBuildLine(dirty)).toBe("0123456 · feat/about-box · 2026-09-21 08:32 UTC · uncommitted changes");
  });

  it("formatBuildString is the full self-describing string that gets copied", () => {
    expect(formatBuildString("0.1.0", clean)).toBe("QuKi Notes 0.1.0 (commit 0123456, branch feat/about-box, built 2026-09-21 08:32 UTC)");
    expect(formatBuildString("0.1.0", dirty)).toBe(
      "QuKi Notes 0.1.0 (commit 0123456, branch feat/about-box, built 2026-09-21 08:32 UTC, uncommitted changes)",
    );
  });
});
