#!/usr/bin/env bash
# Writes Casks/screener.rb for a published GitHub release into the Homebrew tap.
#
# The tap (github.com/BikS2013/homebrew-screener) lives in this repository as a
# git subtree at homebrew-tap/ (the default --tap-dir). In that mode --commit
# commits the cask on the current branch of this repository and --push
# pushes the subtree back to the tap repository (remote "homebrew-tap"),
# which is what `brew tap BikS2013/screener` clones. A standalone clone of the
# tap can still be targeted with --tap-dir <clone>.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

VERSION=""
BUILD=""
SHA256=""
TAP_DIR="$PROJECT_ROOT/homebrew-tap"
TAP_REMOTE="homebrew-tap"
TAP_BRANCH="main"
DO_COMMIT=0
DO_PUSH=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-homebrew-cask.sh \
    --version 0.1.0 --build 1 \
    --sha256 <sha256 of screener-<version>.dmg> \
    [--tap-dir homebrew-tap] [--tap-remote homebrew-tap] [--tap-branch main] \
    [--commit] [--push]

Rewrites <tap-dir>/Casks/screener.rb so that it points at the GitHub release
tag v<version>-b<build> and its screener-<version>.dmg asset.

Subtree mode (default, --tap-dir is the homebrew-tap/ subtree of this repo):
  --commit  commits homebrew-tap/Casks/screener.rb on the current branch here
  --push    also runs `git subtree push --prefix=homebrew-tap <remote> <branch>`
            so the tap repository (what `brew tap BikS2013/screener` clones)
            receives the change. Push this repository's branch separately.

Standalone mode (--tap-dir points at a clone of the tap, i.e. has .git):
  --commit  commits in that clone; --push pushes its current branch.
USAGE
}

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --sha256) SHA256="${2:-}"; shift 2 ;;
    --tap-dir) TAP_DIR="${2:-}"; shift 2 ;;
    --tap-remote) TAP_REMOTE="${2:-}"; shift 2 ;;
    --tap-branch) TAP_BRANCH="${2:-}"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --push) DO_COMMIT=1; DO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$VERSION" ]] || fail "--version is required"
[[ -n "$BUILD" ]] || fail "--build is required"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "--sha256 must be a 64-character hex digest"
[[ -n "$TAP_DIR" ]] || fail "--tap-dir is required"
[[ -d "$TAP_DIR" ]] || fail "tap directory does not exist: $TAP_DIR"

if [[ -d "$TAP_DIR/.git" ]]; then
  MODE="standalone"
else
  MODE="subtree"
  TAP_DIR="$(cd -- "$TAP_DIR" && pwd)"
  [[ "$TAP_DIR" == "$PROJECT_ROOT/"* ]] || fail "subtree mode expects --tap-dir inside this repository: $TAP_DIR"
  git -C "$PROJECT_ROOT" remote get-url "$TAP_REMOTE" >/dev/null 2>&1 \
    || fail "git remote '$TAP_REMOTE' is missing; add it with: git remote add $TAP_REMOTE https://github.com/BikS2013/homebrew-screener.git"
fi
SUBTREE_PREFIX="${TAP_DIR#"$PROJECT_ROOT"/}"

CASK="$TAP_DIR/Casks/screener.rb"
mkdir -p "$TAP_DIR/Casks"

cat > "$CASK" <<CASK
cask "screener" do
  version "${VERSION},${BUILD}"
  sha256 "${SHA256}"

  url "https://github.com/BikS2013/screener/releases/download/v#{version.csv.first}-b#{version.csv.second}/screener-#{version.csv.first}.dmg"
  name "screener"
  desc "Select any screen area and copy its text (English and Greek OCR)"
  homepage "https://github.com/BikS2013/screener"

  livecheck do
    url :url
    regex(/^v?(\\d+(?:\\.\\d+)+)-b(\\d+)$/i)
    strategy :github_latest do |json, regex|
      match = json["tag_name"]&.match(regex)
      next if match.blank?

      "#{match[1]},#{match[2]}"
    end
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma
  depends_on formula: "tesseract"

  app "screener.app"

  uninstall quit: "com.local.screener"

  zap trash: "~/.tool-agents/screener"

  caveats <<~EOS
    First launch:
      1. Open screener (menu-bar app, no Dock icon) and click
         "Create Config from Example". It writes ~/.tool-agents/screener/config.json
         and installs the Greek and English OCR data next to it.
      2. Press Ctrl-Option-Cmd-T and allow Screen Recording when macOS asks
         (System Settings > Privacy & Security > Screen & System Audio Recording),
         then quit and reopen screener.

    ~/.tool-agents/screener is kept on uninstall and removed on zap.
  EOS
end
CASK

printf '==> wrote %s (version %s, build %s)\n' "$CASK" "$VERSION" "$BUILD"

if [[ "$MODE" == "standalone" ]]; then
  if [[ "$DO_COMMIT" -eq 1 ]]; then
    git -C "$TAP_DIR" add Casks/screener.rb
    if git -C "$TAP_DIR" diff --cached --quiet; then
      printf '==> tap already up to date, nothing to commit\n'
    else
      git -C "$TAP_DIR" commit -q -m "screener ${VERSION} build ${BUILD}"
      printf '==> committed in %s\n' "$TAP_DIR"
    fi
  fi
  if [[ "$DO_PUSH" -eq 1 ]]; then
    git -C "$TAP_DIR" push -q origin HEAD
    printf '==> pushed\n'
  fi
else
  if [[ "$DO_COMMIT" -eq 1 ]]; then
    git -C "$PROJECT_ROOT" add "$SUBTREE_PREFIX/Casks/screener.rb"
    if git -C "$PROJECT_ROOT" diff --cached --quiet -- "$SUBTREE_PREFIX/Casks/screener.rb"; then
      printf '==> cask already up to date, nothing to commit\n'
    else
      git -C "$PROJECT_ROOT" commit -q -m "homebrew: screener ${VERSION} build ${BUILD}" -- "$SUBTREE_PREFIX/Casks/screener.rb"
      printf '==> committed %s/Casks/screener.rb on %s\n' "$SUBTREE_PREFIX" "$(git -C "$PROJECT_ROOT" branch --show-current)"
    fi
  fi
  if [[ "$DO_PUSH" -eq 1 ]]; then
    printf '==> pushing subtree %s to %s %s\n' "$SUBTREE_PREFIX" "$TAP_REMOTE" "$TAP_BRANCH"
    git -C "$PROJECT_ROOT" subtree push --prefix="$SUBTREE_PREFIX" "$TAP_REMOTE" "$TAP_BRANCH" 2>&1 | tail -1
    printf '==> tap pushed (remember to push this repository too: git push origin %s)\n' "$(git -C "$PROJECT_ROOT" branch --show-current)"
  fi
fi

cat <<NEXT

Next:
  brew update && brew upgrade --cask screener          # existing users
  brew tap BikS2013/screener && brew install --cask screener   # new users
NEXT
