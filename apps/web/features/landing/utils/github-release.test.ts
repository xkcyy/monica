import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchLatestRelease } from "./github-release";

const SAMPLE_LATEST_ASSET = {
  name: "multica-desktop-0.2.14-mac-arm64.dmg",
  browser_download_url:
    "https://github.com/multica-ai/multica/releases/download/v0.2.14/multica-desktop-0.2.14-mac-arm64.dmg",
};

const SAMPLE_PREV_ASSET = {
  name: "multica-desktop-0.2.13-mac-arm64.dmg",
  browser_download_url:
    "https://github.com/multica-ai/multica/releases/download/v0.2.13/multica-desktop-0.2.13-mac-arm64.dmg",
};

function releasePayload(overrides: {
  tag: string;
  publishedMinutesAgo?: number;
  asset?: { name: string; browser_download_url: string };
  prerelease?: boolean;
  draft?: boolean;
}) {
  const published = new Date(
    Date.now() - (overrides.publishedMinutesAgo ?? 0) * 60_000,
  ).toISOString();
  return {
    tag_name: overrides.tag,
    published_at: published,
    html_url: `https://github.com/multica-ai/multica/releases/tag/${overrides.tag}`,
    prerelease: overrides.prerelease ?? false,
    draft: overrides.draft ?? false,
    assets: overrides.asset ? [overrides.asset] : [],
  };
}

function mockFetchWithReleases(releases: unknown[]) {
  const fetchMock = vi.fn().mockResolvedValue(
    new Response(JSON.stringify(releases), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }),
  );
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  vi.unstubAllGlobals();
});

describe("fetchLatestRelease", () => {
  it("uses previous release when latest was published within the fresh window", async () => {
    mockFetchWithReleases([
      releasePayload({
        tag: "v0.2.14",
        publishedMinutesAgo: 10,
        asset: SAMPLE_LATEST_ASSET,
      }),
      releasePayload({
        tag: "v0.2.13",
        publishedMinutesAgo: 60 * 24,
        asset: SAMPLE_PREV_ASSET,
      }),
    ]);

    const result = await fetchLatestRelease();
    expect(result.version).toBe("v0.2.13");
    expect(result.assets.macArm64Dmg).toBe(SAMPLE_PREV_ASSET.browser_download_url);
  });

  it("uses latest release once it is older than the fresh window", async () => {
    mockFetchWithReleases([
      releasePayload({
        tag: "v0.2.14",
        publishedMinutesAgo: 120,
        asset: SAMPLE_LATEST_ASSET,
      }),
      releasePayload({
        tag: "v0.2.13",
        publishedMinutesAgo: 60 * 24,
        asset: SAMPLE_PREV_ASSET,
      }),
    ]);

    const result = await fetchLatestRelease();
    expect(result.version).toBe("v0.2.14");
    expect(result.assets.macArm64Dmg).toBe(SAMPLE_LATEST_ASSET.browser_download_url);
  });

  it("falls back to latest when there is no previous release", async () => {
    mockFetchWithReleases([
      releasePayload({
        tag: "v0.0.1",
        publishedMinutesAgo: 5,
        asset: SAMPLE_LATEST_ASSET,
      }),
    ]);

    const result = await fetchLatestRelease();
    expect(result.version).toBe("v0.0.1");
  });

  it("skips prereleases and drafts in the candidate list", async () => {
    mockFetchWithReleases([
      releasePayload({
        tag: "v0.2.15-rc.1",
        publishedMinutesAgo: 30,
        prerelease: true,
      }),
      releasePayload({
        tag: "v0.2.14",
        publishedMinutesAgo: 120,
        asset: SAMPLE_LATEST_ASSET,
      }),
    ]);

    const result = await fetchLatestRelease();
    expect(result.version).toBe("v0.2.14");
  });

  it("returns an empty release shape when the API errors", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response("rate limited", { status: 403 }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    const result = await fetchLatestRelease();
    expect(result).toEqual({
      version: null,
      publishedAt: null,
      htmlUrl: null,
      assets: {},
    });
    expect(warnSpy).toHaveBeenCalled();
    warnSpy.mockRestore();
  });

  it("returns an empty release shape when all candidates are filtered out", async () => {
    mockFetchWithReleases([
      releasePayload({ tag: "v0.2.15-rc.1", prerelease: true }),
      releasePayload({ tag: "v0.2.14-draft", draft: true }),
    ]);

    const result = await fetchLatestRelease();
    expect(result.version).toBeNull();
    expect(result.assets).toEqual({});
  });

  it("uses local desktop downloads before querying GitHub", async () => {
    const dir = await mkdtemp(join(tmpdir(), "multica-downloads-"));
    try {
      await writeFile(
        join(dir, "multica-desktop-0.0.0-380c6b51-windows-x64.exe"),
        "installer",
      );
      process.env.MULTICA_LOCAL_DOWNLOADS_DIR = dir;
      process.env.MULTICA_LOCAL_DOWNLOADS_PUBLIC_BASE = "/downloads";
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);

      const result = await fetchLatestRelease();

      expect(fetchMock).not.toHaveBeenCalled();
      expect(result.version).toBe("0.0.0-380c6b51");
      expect(result.assets.winX64Exe).toBe(
        "/downloads/multica-desktop-0.0.0-380c6b51-windows-x64.exe",
      );
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
