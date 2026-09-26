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

- **Config rename in the next release:** `output.preserveLineBreaks` (0.1.0) became `output.preserveFormat`, and
  `keyboard.toggleFormat` is new. A 0.1.0 config fails validation with "missing required key" until the user renames
  the key and adds `"toggleFormat": "f"` (no silent migration, per the no-fallback rule). Mention it in the release notes.
- **Preserved layout is approximate for proportional fonts:** columns are aligned on a grid from the median character
  width, so column starts can be off by a character; sentence text keeps single spaces.
- **Accent repair on split word halves:** in preserved mode the second half of a hyphenated Greek word ("μή" of
  "γραμ-μή") can lose its accent, because the spell-checker sees only the fragment. Plain mode re-joins the word first.

## Resolved

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
