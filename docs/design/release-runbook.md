# screener Release Runbook: build, sign, package, publish, Homebrew

This is the step-by-step procedure for producing a new `screener.app` release, installing it on this Mac, publishing it on GitHub and updating the Homebrew tap. The layout and the Homebrew flow follow the sibling project **Jumpee**:

- `build.sh` and `package.sh` sit at the repository root.
- Builds go to `build.noindex/` and release files to `dist/`.
- Releases are tagged `v<version>`, and the cask downloads `screener-<version>.zip`.
- The tap repository `BikS2013/homebrew-screener` gets one commit `screener <version>` per release.

Follow the steps in order; each one ends with a check that must pass before the next.

Last verified: 2026-10-09 (`v0.2.1`, cask `0.2.1`). Environment: macOS 27.0, Xcode 27.0, Swift 6.4.

---

## 0. One-time setup (skip if this Mac already released a build)

| # | What | Check | How to (re)create |
|---|------|-------|-------------------|
| 0.1 | Full Xcode (`notarytool`, `stapler`, `swift`) | `xcode-select -p` prints `/Applications/Xcode.app/Contents/Developer` | Install Xcode, then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 0.2 | Developer ID Application certificate with its private key | `security find-identity -v -p codesigning` lists `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` | Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. Export a `.p12` backup. |
| 0.3 | notarytool keychain profile `screener-notary` | `xcrun notarytool history --keychain-profile screener-notary` prints a history without an error | See 0.3 below |
| 0.4 | GitHub CLI logged in as `BikS2013` | `gh auth status` | `gh auth login` |
| 0.5 | Homebrew clone of the tap | `git -C "$(brew --repo biks2013/screener)" remote -v` shows `homebrew-screener` | `brew tap BikS2013/screener` |

**Two identities share the same name.** Two valid `Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` certificates exist: `2C7D6068C232BA74073D56085DDBB04E5F14DF30` (2026-09-11) and `CEC7876107F7ED244ACA2B9ED7D6E9DE0056931C` (2026-09-18), both expiring 2027-02-01. Signing by name fails as "ambiguous", so pass the SHA-1. Releases use `2C7D6068…`. The app's designated requirement is tied to the team ID, so the Screen Recording permission survives switching between the two.

**0.3 Creating the notary profile.** It reuses the App Store Connect API key created for untype (Key ID `8X27HG66C4`, Issuer ID `4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab`, key file `~/.tool-agents/untype/AuthKey_8X27HG66C4.p8`). Never commit the `.p8`.

```sh
xcrun notarytool store-credentials screener-notary \
  --key ~/.tool-agents/untype/AuthKey_8X27HG66C4.p8 --key-id 8X27HG66C4 \
  --issuer 4100965f-7ed7-4a45-bd2c-3f7ffab3f1ab
```

---

## 1. Set the version

Edit `VERSION="…"` and `BUILD="…"` at the top of `build.sh`:

- `VERSION` (`CFBundleShortVersionString`) names the release, its tag `v<version>` and the cask version.
- `BUILD` (`CFBundleVersion`) must go up on **every** packaging run, including local-only ones. Find the last one with `/usr/libexec/PlistBuddy -c "Print CFBundleVersion" /Applications/screener.app/Contents/Info.plist`.

---

## 2. Make sure the tree is what you want to ship

```sh
cd ~/aiwork/tools/screener && git status --short
```

Every listed change will be compiled into the release. Commit it first: the tag must point at the exact source of the build.

---

## 3. Test, build, sign, notarize, package

```sh
CODESIGN_IDENTITY=2C7D6068C232BA74073D56085DDBB04E5F14DF30 NOTARY_PROFILE=screener-notary bash package.sh
```

This single command does the following:

1. Runs `swift test`.
2. Calls `build.sh`, which builds `build.noindex/screener.app`: the release binary, `config.example.json`, the notices, the icon and the Tesseract models pinned in `packaging/macos/tessdata.lock`. The models are cached in `.build/tessdata-cache` and verified by SHA-256.
3. Signs the app with the hardened runtime and checks that the signature is Developer ID with the runtime flag.
4. Zips, notarizes and staples the app, then re-zips it.
5. Builds the disk image, which includes `INSTALL.txt`, then signs, notarizes and staples it.
6. Writes `dist/SHA256SUMS` and the cask `homebrew-tap/Casks/screener.rb` for this version, pointing at the zip's checksum.

It takes about 5–10 minutes. The output must show `status: Accepted` twice, `The validate action worked!` for the app and the image, and `source=Notarized Developer ID` in both Gatekeeper assessments.

If Apple rejects a submission, run `xcrun notarytool log <submission-id> --keychain-profile screener-notary`, fix the cause, bump `BUILD` and rerun. To rebuild only the image from the existing stapled app, run `bash package.sh --dmg-only` with the same variables.

Local-only builds:

- Leave out `NOTARY_PROFILE` for a signed but un-notarized package, for this Mac only.
- `CODESIGN_IDENTITY=- bash build.sh` produces an ad-hoc development build. **Never install it** in `/Applications`: it changes the app's identity and macOS drops the Screen Recording permission.

---

## 4. Verify the artifacts independently

```sh
cd ~/aiwork/tools/screener
codesign -dvv build.noindex/screener.app 2>&1 | grep -E "^Identifier|Authority=Developer ID App|flags"
xcrun stapler validate build.noindex/screener.app
spctl --assess --type execute --verbose=2 build.noindex/screener.app
xcrun stapler validate dist/screener-<version>.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 dist/screener-<version>.dmg
cat dist/SHA256SUMS
brew style homebrew-tap/Casks/screener.rb
```

Check that all of the following hold:

- `Identifier=com.local.screener`, `Authority=Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)` and `flags=0x10000(runtime)`.
- Both Gatekeeper assessments say `source=Notarized Developer ID`.
- `brew style` reports `no offenses detected`.

---

## 5. Install the new build on this Mac

```sh
osascript -e 'tell application id "com.local.screener" to quit'
mkdir -p dist/backup && ditto /Applications/screener.app "dist/backup/screener.app.build<PREVIOUS>"
rm -rf /Applications/screener.app && ditto build.noindex/screener.app /Applications/screener.app
codesign --verify --deep --strict /Applications/screener.app && echo INSTALLED-OK
open -a /Applications/screener.app
```

The Screen Recording permission is kept across builds signed with the same Developer ID. If it is lost, run `tccutil reset ScreenCapture com.local.screener`, relaunch, capture once and enable screener again under System Settings → Privacy & Security → Screen & System Audio Recording.

---

## 6. Smoke-test by hand

1. ⌃⌥⌘T, then drag over text. The toast reads "Copied N characters" and the clipboard holds the text.
2. ⌃⌥⌘T, then **T**, ↓, ⇧↓ over lines of different length, then ⏎. The whole width of every selected line is captured.
3. ⌃⌥⌘T, then **F**, then capture a table. Plain text arrives as one line; preserved keeps the columns.
4. Capture Greek text. The toast names `Tesseract`, and the text has no Latin look-alikes.

---

## 7. Publish the GitHub release

```sh
git push origin main
git tag -a v<version> -m "screener <version>" HEAD && git push origin v<version>
gh release create v<version> --repo BikS2013/screener --title "screener v<version>" --notes-file <notes.md> \
  "dist/screener-<version>.zip" "dist/screener-<version>.dmg" "dist/SHA256SUMS"
curl -sL -o /tmp/dl.zip https://github.com/BikS2013/screener/releases/download/v<version>/screener-<version>.zip
shasum -a 256 /tmp/dl.zip   # must equal the zip line in dist/SHA256SUMS
```

The release notes must list the downloads, the SHA-256s, the macOS 14 / Apple silicon requirement, install steps, what changed, and any config edits users need.

Tag history: up to 0.2.0 the tags were `v<version>-b<build>` (`v0.1.0-b1`, `v0.2.0-b3`). From 0.2.1 on they are `v<version>`, as in Jumpee.

---

## 7c. Update the Homebrew tap

The tap repository `BikS2013/homebrew-screener` is what `brew tap BikS2013/screener` clones. As with `homebrew-jumpee`, it receives one commit per release. Commit it in Homebrew's own clone of the tap, which is then immediately what `brew` sees:

```sh
TAP="$(brew --repo biks2013/screener)"
git -C "$TAP" pull -q origin main
cp homebrew-tap/Casks/screener.rb "$TAP/Casks/screener.rb"
cp homebrew-tap/README.md "$TAP/README.md"
git -C "$TAP" add Casks/screener.rb README.md
git -C "$TAP" commit -m "screener <version>"
git -C "$TAP" push origin main
git add homebrew-tap && git commit -m "homebrew: screener <version>" && git push origin main
```

`homebrew-tap/` in this repository is a plain copy of the tap content, kept in sync by the step above. It is not a git subtree.

Then verify:

```sh
brew style biks2013/screener/screener                          # "no offenses detected"
brew audit --cask --online --strict biks2013/screener/screener # no output = pass
brew livecheck --cask biks2013/screener/screener               # "<version> ==> <version>"
brew info --cask biks2013/screener/screener | head -1          # shows <version>
```

Do not run `brew install --cask screener` into `/Applications` on the development Mac while screener runs: the cask's `uninstall quit:` stanza would quit it. Test in a scratch folder instead: `brew install --cask --appdir="$(mktemp -d)" biks2013/screener/screener`, then `brew uninstall --cask screener` and reopen `/Applications/screener.app`.

---

## 8. Record the release

Add one entry to `Issues - Pending Items.md` under *Release log* containing:

- the date and the version + build;
- the command and test count;
- `status: Accepted` for the app and the image;
- both SHA-256s, the release URL and the cask checks;
- anything unusual.

---

## 9. Maintenance calendar

| Item | Expires / action | Consequence if missed |
|------|------------------|-----------------------|
| Developer ID Application certificates (`2C7D6068…`, `CEC78761…`) | **2027-02-01**. Renew a few weeks before and export a `.p12`. | Signing fails; existing installs keep working. |
| App Store Connect API key `8X27HG66C4` (shared with untype) | Does not expire; revoke and recreate if the `.p8` leaks, then redo 0.3. | Notarization fails with an authentication error. |
| Tesseract models (`packaging/macos/tessdata.lock`) | Pinned to tessdata_best commit `e12c65a9`; bump deliberately (new URL + SHA-256). | None; the pin keeps builds reproducible. |
| Apple Developer Program membership | Yearly renewal | Notarization stops. |
