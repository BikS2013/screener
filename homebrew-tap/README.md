# homebrew-screener

Homebrew tap for [screener](https://github.com/BikS2013/screener), a macOS menu-bar tool: press a hotkey, select any screen area with the mouse or the keyboard, and its text (English and Greek) is copied to the clipboard. The cask installs the notarized `screener.app` from the project's GitHub Releases, plus `tesseract` for Greek OCR.

## Install

```bash
brew tap BikS2013/screener
brew install --cask screener
```

## Upgrade

```bash
brew update
brew upgrade --cask screener
```

## After installation

1. Open screener (it lives in the menu bar, no Dock icon) and click **Create Config from Example**. This writes `~/.tool-agents/screener/config.json` and installs the Greek and English OCR data next to it.
2. Press **⌃⌥⌘T** and allow **Screen Recording** when macOS asks (System Settings → Privacy & Security → Screen & System Audio Recording). Then quit and reopen screener.

## Uninstall

```bash
brew uninstall --cask screener        # removes the app, keeps ~/.tool-agents/screener
brew uninstall --zap --cask screener  # also removes the configuration and OCR data
```

## Maintainers

This repository is the Homebrew tap that `brew tap BikS2013/screener` clones. It is maintained as a git subtree (`homebrew-tap/`) of the application repository [BikS2013/screener](https://github.com/BikS2013/screener): edit the cask there and push the subtree back here, never commit here directly. After each release:

```bash
# in screener
scripts/update-homebrew-cask.sh --version <version> --build <N> --sha256 <dmg sha256> --push
git push origin main
```
