import { describe, expect, it } from "vitest";
import { parseReleaseAssets } from "./parse-release-assets";

describe("parseReleaseAssets", () => {
  it("parses Windows desktop assets whose version contains prerelease separators", () => {
    const assets = parseReleaseAssets([
      {
        name: "multica-desktop-0.0.0-380c6b51-windows-x64.exe",
        browser_download_url:
          "/downloads/multica-desktop-0.0.0-380c6b51-windows-x64.exe",
      },
    ]);

    expect(assets.winX64Exe).toBe(
      "/downloads/multica-desktop-0.0.0-380c6b51-windows-x64.exe",
    );
  });
});
