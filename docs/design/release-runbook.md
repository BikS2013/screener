# screener Release Runbook: rebuild, sign, package, distribute

This is the step-by-step procedure for producing a new `screener.app` release on this Mac, installing it locally, publishing it on GitHub and updating the Homebrew tap. It follows the same conventions as the sibling project `untype-s`. Follow the steps in order; each one ends with a check that must pass before the next.

Last verified: 2026-09-26 (build 1, `screener-0.1.0.dmg`, release `v0.1.0-b1`, Homebrew cask `0.1.0,1`). Environment: macOS 27.0, Xcode 27.0, Swift 6.4.

---

## 0. One-time setup (skip if this Mac already released a build)

| # | What | Check | How to (re)create |
|---|------|-------|-------------------|
| 0.1 | Full Xcode (`notarytool`, `stapler`, `swift`) | `xcode-select -p` prints `/Applications/Xcode.app/Contents/Developer` | Install Xcode, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 0.2 | Developer ID Application certificate with its private key | `security find-identity -v -p codesigning` lists `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` | Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. Export a `.p12` backup. |
| 0.3 | notarytool keychain profile `screener-notary` | `xcrun notarytool history --keychain-profile screener-notary` prints a history without an error | See 0.3 below |
| 0.4 | GitHub CLI logged in as `BikS2013` | `gh auth status` | `gh auth login` |
| 0.5 | Project builds and tests pass | `swift build && swift test` is green | Fix the code first; never release from a red tree |

**Two identities share the same name.** This Mac holds two valid `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` certificates: `2C7D6068C232BA74073D56085DDBB04E5F14DF30`, issued 2026-09-11, and `CEC7876107F7ED244ACA2B9ED7D6E9DE0056931C`, issued 2026-09-18. Both expire 2027-02-01. Signing by name fails as "ambiguous", so pass the SHA-1. Releases use `2C7D6068…`. The app's designated requirement is tied to the team ID, so macOS permissions survive switching between the two.

**0.3 Creating the notary profile.** It reuses the App Store Connect API key created for untype (Key ID `8X27HG66C4`, Issuer ID `4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab`, key file `~/.tool-agents/untype/AuthKey_8X27HG66C4.p8`). Never commit the `.p8`.

```sh
xcrun notarytool store-credentials screener-notary \
  --key ~/.tool-agents/untype/AuthKey_8X27HG66C4.p8 \
  --key-id 8X27HG66C4 \
  --issuer 4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab
```

Expected: `Credentials saved to Keychain.`

---

## 1. Decide the version numbers

- **Version** (`CFBundleShortVersionString`), e.g. `0.1.0`. Bump it when users should notice a new release.
- **Build** (`CFBundleVersion`), an integer that must go up on **every** packaging run.

```sh
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" /Applications/screener.app/Contents/Info.plist
```

Use that number + 1.

---

## 2. Make sure the tree is what you want to ship

```sh
cd ~/aiwork/tools/screener
git status --short
```

Every listed change will be compiled into the release.

---

## 3. Build, test, sign, notarize, and create the disk image

```sh
scripts/package-macos-app.sh \
  --bundle-id com.local.screener \
  --version 0.1.0 \
  --build <N> \
  --sign-identity 2C7D6068C232BA74073D56085DDBB04E5F14DF30 \
  --notary-profile screener-notary \
  --dmg
```

This single command does the following:

1. Builds the release binary and runs the test suite.
2. Assembles `screener.app`: the binary as `screener`, `config.example.json`, the third-party notices, the icon, and the Tesseract models pinned in `packaging/macos/tessdata.lock`. The models are downloaded once into `.build/tessdata-cache` and verified by SHA-256.
3. Signs the app with the hardened runtime. It needs no entitlements, because Screen Recording is a TCC grant rather than an entitlement.
4. Notarizes and staples the app, then runs Gatekeeper on it.
5. Repeats signing, notarization, stapling and the Gatekeeper check for the DMG.

It takes about 5–10 minutes. The output must contain `status: Accepted` twice, `The staple and validate action worked!`, and `accepted` with `source=Notarized Developer ID` for both the app and the image.

If notarization is rejected, run `xcrun notarytool log <submission-id> --keychain-profile screener-notary`, fix the cause, bump the build and rerun.

Variants: `--skip-tests` (tests just ran on this tree), `--dmg-only` (rebuild only the image from the existing stapled app).

---

## 4. Verify the artifacts independently

```sh
cd ~/aiwork/tools/screener/.build/deploy
codesign -dvv screener.app 2>&1 | grep -E "Authority|TeamIdentifier|flags|Identifier"
codesign --verify --deep --strict --verbose=2 screener.app
xcrun stapler validate screener.app
spctl --assess --type execute --verbose=4 screener.app
codesign --verify --verbose=2 screener-0.1.0.dmg
xcrun stapler validate screener-0.1.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 screener-0.1.0.dmg
M=$(hdiutil attach -readonly -nobrowse -noautoopen screener-0.1.0.dmg | grep -o "/Volumes/.*")
ls -la "$M" "$M/screener.app/Contents/Resources/tessdata"
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$M/screener.app/Contents/Info.plist"
hdiutil detach "$M"
shasum -a 256 screener-0.1.0.dmg screener-0.1.0-notarized.zip > SHA256SUMS && cat SHA256SUMS
```

Check that all of the following hold:

- `Authority=Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)`, `flags=0x10000(runtime)` and `Identifier=com.local.screener`.
- Every `spctl` line says `accepted` with `source=Notarized Developer ID`.
- The image contains `screener.app`, `Applications` and `INSTALL.txt`, and the bundle carries `ell.traineddata` and `eng.traineddata`.

---

## 5. Install the new build on this Mac

```sh
osascript -e 'tell application id "com.local.screener" to quit'
mkdir -p .build/deploy/backup && mv /Applications/screener.app ".build/deploy/backup/screener.app.build<PREVIOUS>" 2>/dev/null
ditto .build/deploy/screener.app /Applications/screener.app
codesign --verify --deep --strict /Applications/screener.app && echo INSTALLED-OK
open -a /Applications/screener.app
```

Screen Recording is tied to the signing identity (team `9F9H8NCAUB`) and bundle id. It survives upgrades signed with the same Developer ID. If it is lost (certificate renewal, bundle id change), run `tccutil reset ScreenCapture com.local.screener`, relaunch, capture once, and enable screener in System Settings → Privacy & Security → Screen & System Audio Recording.

---

## 6. Smoke-test by hand

1. ⌃⌥⌘T. Every screen dims slightly. Drag over some text; the toast reads "Copied N characters" and the clipboard holds the text.
2. ⌃⌥⌘T, then ↑↓←→ (⇧ faster, ⌥ fine), Space, arrows, ⏎. This captures the keyboard rectangle.
3. ⌃⌥⌘T, then **T**, then ↓ ↓, ⇧↓, ⏎. This captures the selected lines.
4. Capture Greek text. The toast names `Tesseract`, and the text has no Latin look-alikes.
5. Check the warm-up log: `/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.local.screener"' | grep warm-up`.

---

## 7. Publish the GitHub release

The repository `BikS2013/screener` is public, so the release gives a login-free download URL.

1. Commit and push the source the build came from (`git status --short` must be clean).
2. Write the release notes: downloads, SHA-256, the macOS 14 / Apple silicon requirement, install steps and what changed.
3. Tag the commit with the version **and** build, push, and create the release:
   ```sh
   git tag -a v<version>-b<N> -m "screener <version> build <N> (notarized Developer ID release)" HEAD
   git push origin main
   git push origin v<version>-b<N>
   gh release create v<version>-b<N> --repo BikS2013/screener \
     --title "screener <version> (build <N>)" \
     --notes-file <notes.md> \
     ".build/deploy/screener-<version>.dmg#screener-<version>.dmg (disk image, recommended)" \
     ".build/deploy/screener-<version>-notarized.zip#screener-<version>-notarized.zip" \
     ".build/deploy/SHA256SUMS#SHA256SUMS"
   ```
4. Verify that the link works without a login and serves the same bytes:
   ```sh
   curl -sL -o /tmp/dl.dmg https://github.com/BikS2013/screener/releases/download/v<version>-b<N>/screener-<version>.dmg
   shasum -a 256 /tmp/dl.dmg   # must equal SHA256SUMS
   ```

---

## 7c. Update the Homebrew tap

`brew tap BikS2013/screener && brew install --cask screener` clones the tap repository `BikS2013/homebrew-screener`. It is maintained as a **git subtree** of this repository at `homebrew-tap/` (git remote `homebrew-tap`). Never commit in the tap directly.

```sh
scripts/update-homebrew-cask.sh --version <version> --build <N> --sha256 <dmg sha256> --push
git push origin main
```

On a fresh clone, add the remote once with `git remote add homebrew-tap https://github.com/BikS2013/homebrew-screener.git`. Then verify:

```sh
brew tap BikS2013/screener 2>/dev/null; git -C "$(brew --repo biks2013/screener)" pull -q origin main
brew style biks2013/screener/screener
brew audit --cask --online --strict biks2013/screener/screener
brew livecheck --cask biks2013/screener/screener
```

Do not run `brew install --cask screener` on the development Mac while screener runs: the `uninstall quit:` stanza would quit it. Test in a scratch folder instead: `brew install --cask --appdir="$(mktemp -d)" biks2013/screener/screener`, then `brew uninstall --cask screener`.

---

## 8. Record the release

Add one entry to `Issues - Pending Items.md` under *Release log* containing:

- the date and version + build;
- the command used and the test count;
- `status: Accepted` for the app and the image;
- the DMG SHA-256;
- anything unusual.

---

## 9. Maintenance calendar

| Item | Expires / action | Consequence if missed |
|------|------------------|-----------------------|
| Developer ID Application certificates (`2C7D6068…`, `CEC78761…`) | **2027-02-01**. Renew a few weeks before and export a `.p12`. | Signing fails; existing installs keep working. |
| App Store Connect API key `8X27HG66C4` (shared with untype) | Does not expire; revoke and recreate if the `.p8` leaks, then redo 0.3 for both profiles. | Notarization fails with an authentication error. |
| Tesseract models (`packaging/macos/tessdata.lock`) | Pinned to tessdata_best commit `e12c65a9`. Bump deliberately (new URL + SHA-256). | None; the pin keeps builds reproducible. |
| Apple Developer Program membership | Yearly renewal | Notarization stops. |
