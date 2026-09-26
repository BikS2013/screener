#!/usr/bin/env bash
# Installs Tesseract models pinned in packaging/macos/tessdata.lock into ~/.tool-agents/screener/tessdata
# (development setup; the packaged app bundles the same files and installs them on "Create Config from Example").
# Usage: scripts/install-tessdata.sh <lang> [lang...]   e.g. scripts/install-tessdata.sh ell eng
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/packaging/macos/tessdata.lock"
DEST="$HOME/.tool-agents/screener/tessdata"

[[ $# -gt 0 ]] || { echo "ERROR: pass the Tesseract languages to install, e.g.: $0 ell eng" >&2; exit 1; }
command -v tesseract >/dev/null || { echo "ERROR: tesseract not found — run: brew install tesseract" >&2; exit 1; }
mkdir -p "$DEST"
chmod 700 "$HOME/.tool-agents/screener"
for lang in "$@"; do
  line="$(grep -E "^$lang " "$LOCK")" || { echo "ERROR: '$lang' is not listed in $LOCK" >&2; exit 1; }
  read -r _ sha url <<< "$line"
  echo "Downloading $lang.traineddata…"
  curl -fsSL -o "$DEST/$lang.traineddata.tmp" "$url"
  actual="$(shasum -a 256 "$DEST/$lang.traineddata.tmp" | cut -d' ' -f1)"
  [[ "$actual" == "$sha" ]] || { rm -f "$DEST/$lang.traineddata.tmp"; echo "ERROR: checksum mismatch for $lang" >&2; exit 1; }
  mv "$DEST/$lang.traineddata.tmp" "$DEST/$lang.traineddata"
done
tesseract --list-langs --tessdata-dir "$DEST"
