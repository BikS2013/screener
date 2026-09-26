#!/usr/bin/env bash
# Copies config.example.json to ~/.tool-agents/screener/config.json. Never overwrites an existing file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$HOME/.tool-agents/screener"
DEST="$DIR/config.json"

mkdir -p "$DIR"
chmod 700 "$DIR"
if [[ -e "$DEST" ]]; then
  echo "ERROR: $DEST already exists — edit it (or use the Settings window) instead." >&2
  exit 1
fi
cp "$ROOT/config.example.json" "$DEST"
chmod 600 "$DEST"
echo "Created $DEST"
