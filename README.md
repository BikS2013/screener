# screener

A macOS menu-bar tool: press a hotkey, drag a rectangle over any text on any screen, and the text is
OCR'd and copied to the clipboard. English and Greek are recognised and detected automatically.

Full reference (config keys, hotkey syntax, permissions): [`docs/tools/screener.md`](docs/tools/screener.md).

## Install

Homebrew (installs `tesseract` too):

```bash
brew tap BikS2013/screener
brew install --cask screener
```

Or download the notarized disk image from the [latest GitHub release](https://github.com/BikS2013/screener/releases/latest), drag `screener.app` to Applications, and run `brew install tesseract`. Requires macOS 14 or later on Apple silicon.

On first launch screener offers **Create Config from Example**. This writes `~/.tool-agents/screener/config.json` and installs the bundled Greek and English OCR models next to it. The first capture asks for **Screen Recording** permission; grant it, then quit and reopen screener.

The tap repository [BikS2013/homebrew-screener](https://github.com/BikS2013/homebrew-screener) is maintained from this repository's `homebrew-tap/` folder, a git subtree. See [`docs/design/release-runbook.md`](docs/design/release-runbook.md).

## Use

| Action | Example-config hotkey |
|---|---|
| Start a capture (overlay on every screen) | ⌃⌥⌘T |
| Cancel the overlay | ⎋ (or right-click) |
| Open the menu with recent captures | ⌃⌥⌘H |

Inside the overlay you can also select with the keyboard (example-config keys):

| Free mode | Text mode (press **T**) |
|---|---|
| ↑↓←→ move the crosshair 20 pt (⇧ 100 pt, ⌥ 2 pt for precision) | ↑↓←→ jump to the nearest text line |
| **Space** drops the anchor, arrows stretch the box | **⇧**+arrows (or **Space** anchor) extend over several lines |
| **⏎** captures | **⏎** captures (a click also focuses a line) |

**⇥** moves to the next screen, **⎋** cancels, and the mouse keeps working throughout.

**Format switch.** A switch at the bottom of the active screen decides how the text arrives. Press **F** or click it; it works during a drag too:

| ◉ Preserve screen format | ◉ Plain text |
|---|---|
| Line breaks, indentation, table columns and paragraph gaps as on screen | One sequential text: lines joined, line-end hyphenation removed |

It starts at `output.preserveFormat` each time the overlay opens.

Change any of these keys in **Settings…** (menu-bar icon): click a field and press the new combination.

## How it works

| Stage | Implementation |
|---|---|
| Global hotkeys | Carbon `RegisterEventHotKey` (no Accessibility permission needed) |
| Warm-up | Background run of the whole pipeline when the config loads, plus a Vision re-warm each time the overlay opens. This hides Vision's ~20 s first-model-load delay |
| Overlay | One borderless window per `NSScreen`, `.screenSaver` level, joins all Spaces and full-screen apps |
| Capture | ScreenCaptureKit `SCScreenshotManager`, native pixel resolution, Screener's windows excluded |
| OCR | `auto`: Apple Vision and Tesseract (`ell+eng`) run in parallel. Tesseract's result wins when it contains Greek |
| Greek correction | Look-alike letters (µ→μ, "Eva"→"ένα", "kat"→"και"), accents and digits repaired, each word change confirmed by the macOS Greek spell-checker |
| Text mode | Vision `.fast` finds line boxes on the whole screen (~0.2 s). Spatial navigation moves between them |
| Layout | Word boxes from both engines, grouped into rows and rendered either on a character grid (preserved) or as one flowing text (plain) |
| Output | Polytonic → monotonic Greek, `NSPasteboard` |

**Why two engines:** on this macOS version (27.0), Apple Vision, `RecognizeTextRequest` and VisionKit Live Text
all lack Greek. Vision reads "Καλημέρα" as "KalnuÉpa". Tesseract's `tessdata_best` Greek model gets it right,
and Vision is still the better engine for Latin-only text.

## Development

```bash
swift build && swift test
.build/debug/Screener --check-config
.build/debug/Screener --ocr-file some-screenshot.png
scripts/install-tessdata.sh ell eng   # pinned models → ~/.tool-agents/screener/tessdata (dev setup)
scripts/install-config.sh             # config.example.json → ~/.tool-agents/screener/config.json
```

Release (build, test, sign, notarize, DMG), see [`docs/design/release-runbook.md`](docs/design/release-runbook.md):

```bash
scripts/package-macos-app.sh --bundle-id com.local.screener --version 0.1.0 --build <N> \
  --sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30 --notary-profile screener-notary --dmg
```

Layout: `Sources/Screener/` app code · `Tests/` unit tests · `scripts/` packaging, cask, icon and dev-setup scripts ·
`packaging/macos/` icon, `INSTALL.txt`, notices, pinned `tessdata.lock` · `homebrew-tap/` tap subtree ·
`docs/tools/` tool reference · `docs/design/` release runbook.

Sources: `Sources/Screener/` — `Config` (model + validation), `HotKey`, `Overlay`, `ScreenCapture`, `OCR`,
`TextProcessing`, `GreekCorrection`, `Feedback` (toast, history, clipboard), `Settings` (SwiftUI window + hotkey recorder),
`AppDelegate` (menu + flow), `main` (entry point + headless modes).
