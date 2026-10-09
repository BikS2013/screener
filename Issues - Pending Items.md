# Issues - Pending Items

## Pending

- **Mixed Greek + English regions in `auto`:** when a region contains any Greek, the whole region comes from
  Tesseract, even though Vision would read the English lines slightly better. A per-line merge of both results is possible.
- **Selection is limited to one screen:** a drag is clamped to the screen where it started.
- **Look-alike correction limits:** an English word made only of Greek look-alike letters, sitting between Greek
  words, is converted when it is also a Greek word (e.g. a stray "to" → "το"). All-caps English words that are
  valid in lower case ("OK") and words with non-look-alike letters ("Apple") are always kept.
- **Keyboard overlay not driven end-to-end by automation:** the desktop-automation daemon was unavailable on
  2026-09-26. Navigation and config are unit-tested; the on-screen key flow still needs a hands-on check.

- **Config rename in 0.2.0:** `output.preserveLineBreaks` (0.1.0) became `output.preserveFormat`, and
  `keyboard.toggleFormat` is new. A 0.1.0 config fails validation with "missing required key" until the user renames
  the key and adds `"toggleFormat": "f"` (no silent migration, per the no-fallback rule). The 0.2.0 release notes
  explain the edit.
- **Preserved layout is approximate for proportional fonts:** columns are aligned on a grid from the median character
  width, so column starts can be off by a character; sentence text keeps single spaces.
- **Accent repair on split word halves:** in preserved mode the second half of a hyphenated Greek word ("μή" of
  "γραμ-μή") can lose its accent, because the spell-checker sees only the fragment. Plain mode re-joins the word first.

## Resolved

- 2026-10-09 — **Text mode cut multi-line selections to the width of the end lines.** Selecting from a short line
  over a long line to another short line captured only the short lines' width (reported with a 184 × 84 selection
  that truncated "The filename exceeds … then"). Cause: the selection was the union of the anchor and focused
  rectangles only. Fix: `LineNavigator.span` also includes every detected line lying vertically between the two ends
  and overlapping them horizontally, at full width, repeating until stable; a separate column beside the selection
  stays out. Tests: `testSpanIncludesFullWidthOfMiddleLines`, `testSpanLeavesSeparateColumnOut`. Local build 4.

- 2026-09-26 — Slow first capture: the ~23 s cost is system-wide (Vision model load, cached across processes
  until macOS evicts it). `Warmup` runs the pipeline in the background when the config loads and re-warms
  Vision when the overlay opens. If a capture follows a cold model within seconds, it can still wait for the
  load to finish.

- 2026-09-26 — Greek look-alike letters: fixed by `GreekCorrector` (look-alike mapping + macOS Greek
  spell-checker + accent repair + digit fix). The six test images read perfectly at 11–20 pt.

- **First-run flow not exercised on a clean account:** "Create Config from Example" + bundled tessdata install is
  unit-tested (`BundledTessdataTests`) but was not run end-to-end on a machine without `~/.tool-agents/screener`.
- **Screen Recording re-grant after the bundle-id switch:** builds before 0.1.0 used `com.giorgosmarinos.screener`;
  `com.local.screener` needs the permission granted once (the old entry was reset with `tccutil`).

## Release log

- 2026-10-09 — **0.2.1 build 5** (`v0.2.1`): full-width text-mode selections, plus the switch to Jumpee's Homebrew deployment:
  - `build.sh` / `package.sh` at the root, output in `build.noindex/` and `dist/`;
  - plain `v<version>` tags;
  - the cask installs from the release zip, with a post-install notification and caveats listing the permission and every hotkey;
  - the tap repository is updated with one commit `screener 0.2.1`, no subtree; the `homebrew-tap` remote was removed and
    `scripts/package-macos-app.sh` / `scripts/update-homebrew-cask.sh` were deleted.
  Command: `CODESIGN_IDENTITY=2C7D6068C232BA74073D56085DDBB04E5F14DF30 NOTARY_PROFILE=screener-notary bash package.sh`,
  run from the commit tagged `v0.2.1`. 33 tests passed. Notarization `status: Accepted` for the app and the disk image;
  Gatekeeper `source=Notarized Developer ID` for both.
  SHA-256: `0475eea3b053650a373d254eca1c91400112f7d383a61eb1937fb20a5519d4fb  screener-0.2.1.zip`,
  `cba7b6a3e0e73a1b7d9de92701bf7dbbca19862a2a279371b19a46a718c8229c  screener-0.2.1.dmg`.
  Published: https://github.com/BikS2013/screener/releases/tag/v0.2.1 (Latest; anonymous zip download checksum verified).
  Cask `0.2.1` in BikS2013/homebrew-screener (commit `06bcbbe`): `brew style` clean, `brew audit --strict --online` passed,
  livecheck `0.2.1`, and a scratch-folder install was Gatekeeper-accepted with the caveats shown.
  Installed at `/Applications/screener.app`; build 4 was backed up to `dist/backup/`.

- 2026-09-26 — **0.2.0 build 3** (`v0.2.0-b3`): capture-time format switch (preserve screen format / plain text).
  Command: `scripts/package-macos-app.sh --bundle-id com.local.screener --version 0.2.0 --build 3
  --sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30 --notary-profile screener-notary --dmg` from commit `c7ff6f7`.
  31 tests passed. Notarization `status: Accepted` for the app and the disk image; Gatekeeper `accepted`,
  `source=Notarized Developer ID` for both.
  SHA-256: `450764bdd3a47d619e79cb1115c6c6803d852c384b4974cf61e59adcaac9bd64  screener-0.2.0.dmg`,
  `178060843793cf38786c54992fb95428608ee27b28b1e6979c6daef5f224a3b0  screener-0.2.0-notarized.zip`.
  Published: https://github.com/BikS2013/screener/releases/tag/v0.2.0-b3 (marked Latest; the anonymous `latest/download`
  checksum was verified). Homebrew cask `0.2.0,3`: `brew style` clean, `brew audit --strict --online` passed, livecheck `0.2.0,3`.
  Unusual: build 2 was a local-only, signed but not notarized 0.1.0 package, so the release uses build 3.
  Installed at `/Applications/screener.app`; build 2 was backed up to `.build/deploy/backup/`.

- 2026-09-26 — **0.1.0 build 1** (`v0.1.0-b1`), first public release.
  Command: `scripts/package-macos-app.sh --bundle-id com.local.screener --version 0.1.0 --build 1
  --sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30 --notary-profile screener-notary --dmg` from commit `8e3a846`.
  29 tests passed. Notarization `status: Accepted` for the app and the disk image; Gatekeeper `accepted`,
  `source=Notarized Developer ID` for both.
  SHA-256: `b228d30dfbf8c1223afd3502f2154c4ecd5729cc33cb3ecbaa9bf596a6ef6e53  screener-0.1.0.dmg`,
  `22f2b1fdc8fa30c9333c32aec1cdb52655cd9b00ff6159a39b0b0db8677b77c9  screener-0.1.0-notarized.zip`.
  Published: https://github.com/BikS2013/screener/releases/tag/v0.1.0-b1 (anonymous download checksum verified).
  Homebrew cask `0.1.0,1` in https://github.com/BikS2013/homebrew-screener: `brew style` clean, `brew audit --strict --online`
  passed, livecheck `0.1.0,1`, a scratch-folder install was Gatekeeper-accepted.
  Unusual: build 1 was packaged twice; the first package preceded a refactor, so the published artifacts
  were rebuilt from the tagged commit. A notary profile `screener-notary` was created from the untype API key.
  Installed at `/Applications/screener.app`; the old `~/Applications/Screener.app` was moved to `.build/deploy/backup/`.

## Dependency vetting log

- 2026-09-26 — No third-party Swift packages. Only Apple system frameworks are used (AppKit, SwiftUI, Carbon,
  ScreenCaptureKit, Vision, CoreImage, ServiceManagement).
- 2026-09-26 — External runtime tool: Tesseract 5.5.2 (Homebrew, already installed), invoked as a subprocess
  on local images only. Models: `tessdata_best` `ell` and `eng` from github.com/tesseract-ocr/tessdata_best.
