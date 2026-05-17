import { readdir } from "node:fs/promises";
import { basename } from "node:path";
import {
  parseReleaseAssets,
  type GitHubAsset,
} from "./parse-release-assets";
import type { LatestRelease } from "./github-release";

const DESKTOP_VERSION_RE =
  /^multica-desktop-(.+)-(?:mac|windows|linux)-[a-z0-9_]+\.(?:dmg|zip|exe|AppImage|deb|rpm)$/i;

export async function fetchLocalRelease(): Promise<LatestRelease | null> {
  const dir = process.env.MULTICA_LOCAL_DOWNLOADS_DIR;
  if (!dir) return null;

  try {
    const publicBase =
      process.env.MULTICA_LOCAL_DOWNLOADS_PUBLIC_BASE ?? "/downloads";
    const entries = await readdir(dir, { withFileTypes: true });
    const assets: GitHubAsset[] = entries
      .filter((entry) => entry.isFile())
      .map((entry) => entry.name)
      .filter((name) => DESKTOP_VERSION_RE.test(name))
      .sort()
      .map((name) => ({
        name,
        browser_download_url: `${trimTrailingSlash(publicBase)}/${encodeURIComponent(name)}`,
      }));

    const parsed = parseReleaseAssets(assets);
    if (!Object.values(parsed).some(Boolean)) return null;

    return {
      version: versionFromName(assets[0]?.name) ?? null,
      publishedAt: null,
      htmlUrl: null,
      assets: parsed,
    };
  } catch (err) {
    console.warn("[download] fetchLocalRelease failed:", err);
    return null;
  }
}

function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, "");
}

function versionFromName(name: string | undefined): string | null {
  if (!name) return null;
  const match = DESKTOP_VERSION_RE.exec(basename(name));
  return match?.[1] ?? null;
}
