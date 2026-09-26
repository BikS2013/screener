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

## Resolved

- 2026-09-26 — Slow first capture: the ~23 s cost is system-wide (Vision model load, cached across processes
  until macOS evicts it). `Warmup` runs the pipeline in the background when the config loads and re-warms
  Vision when the overlay opens. If a capture follows a cold model within seconds, it can still wait for the
  load to finish.

- 2026-09-26 — Greek look-alike letters: fixed by `GreekCorrector` (look-alike mapping + macOS Greek
  spell-checker + accent repair + digit fix). The six test images read perfectly at 11–20 pt.

## Dependency vetting log

- 2026-09-26 — No third-party Swift packages. Only Apple system frameworks are used (AppKit, SwiftUI, Carbon,
  ScreenCaptureKit, Vision, CoreImage, ServiceManagement).
- 2026-09-26 — External runtime tool: Tesseract 5.5.2 (Homebrew, already installed), invoked as a subprocess
  on local images only. Models: `tessdata_best` `ell` and `eng` from github.com/tesseract-ocr/tessdata_best.
