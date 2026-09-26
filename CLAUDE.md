# screener

A native macOS menu-bar app in Swift. A global hotkey dims every screen slightly, the user drags a rectangle,
and the text inside it is OCR'd and copied to the clipboard.

- Language: Swift 6 toolchain (Swift 5 language mode), SwiftPM, macOS 14+. It is written in Swift at the user's
  explicit request, which overrides the TypeScript default for tools.
- Build / test: `swift build`, `swift test`.
- App bundle: `screener.app`, bundle id `com.local.screener` (sibling convention: `com.local.untype`, `com.local.ntakker`),
  installed in `/Applications`. Always package with `scripts/package-macos-app.sh ... --sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30
  --notary-profile screener-notary --dmg` (see `docs/design/release-runbook.md`). Two Developer ID identities share one name, so sign by SHA-1.
  Never install an ad-hoc build: it changes the TCC identity and drops the Screen Recording grant.
- Releases: GitHub `BikS2013/screener` (public), tags `v<version>-b<build>`, assets dmg + notarized zip + SHA256SUMS.
- Headless checks: `.build/debug/Screener --check-config`, `.build/debug/Screener --ocr-file <png>`.
- Config: `~/.tool-agents/screener/config.json`. Every key is required and validated in `ConfigStore.validate`.
  There are no defaults (no-fallback rule). A new config key must go into `AppConfig`, `validate`,
  `config.example.json`, the Settings window and `docs/tools/screener.md`.
- OCR: Apple Vision cannot read Greek, so in `auto` mode Tesseract (`ell+eng`) runs in parallel and wins when Greek is present.
  `GreekCorrector` then repairs look-alike letters, accents and digits, using NSSpellChecker on the main actor.
- Overlay: `OverlayController` owns the mouse and keyboard state for all screens: free mode (crosshair + anchor)
  and text mode (Vision line boxes + `LineNavigator`).
- `Warmup` hides Vision's system-wide ~20 s model load (it runs when the config loads and when the overlay opens).
- Open issues and the dependency vetting log: `Issues - Pending Items.md`.

## Homebrew Tap Convention

- The tap that `brew tap BikS2013/screener && brew install --cask screener` clones is https://github.com/BikS2013/homebrew-screener.
  It is **maintained from this repository only**, as a git subtree at `homebrew-tap/` (git remote `homebrew-tap`). Never commit in the tap
  repository directly.
- The cask (`homebrew-tap/Casks/screener.rb`) is generated, never hand-edited. After every published release run
  `scripts/update-homebrew-cask.sh --version <v> --build <N> --sha256 <dmg sha256> --push`, then `git push origin main`.
- Full procedure: `docs/design/release-runbook.md`, step 7c.

## Tools

- **screener**: native macOS menu-bar app that captures a user-selected screen region, OCRs it (Apple Vision /
  Tesseract, English + Greek auto-detected) and copies the recognised text to the clipboard.
  See `docs/tools/screener.md`.
