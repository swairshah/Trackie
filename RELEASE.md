# Releasing Trackie

## 1. Bump the version

Version is set in `scripts/build-app.sh` (`VERSION="…"`). Update it and commit
the bump.

```bash
$EDITOR scripts/build-app.sh   # update VERSION
git add scripts/build-app.sh
git commit -m "Bump version to X.Y.Z"
```

## 2. Build, sign, notarize, DMG

Prerequisites (one-time):
- Developer ID Application cert in the login keychain.
- `~/.env` exports `APPLE_APP_PASSWORD` (Apple app-specific password).
- `brew install create-dmg`.

```bash
./scripts/release.sh                 # full build + notarize + staple + DMG
./scripts/release.sh --skip-notarize # iterate locally without the Apple round-trip
./scripts/release.sh --version X.Y.Z # override CFBundleShortVersionString in-place
```

Artifacts land in `dist/`:
- `dist/Trackie-X.Y.Z.dmg` — notarized, stapled DMG for the cask download URL.

The script prints the DMG path and its sha256 at the end — copy that hash into
the cask.

## 3. Tag and push

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

## 4. Publish the GitHub release

```bash
gh release create vX.Y.Z dist/Trackie-X.Y.Z.dmg \
  --title "Trackie vX.Y.Z" \
  --notes "Release notes for vX.Y.Z"
```

## 5. Update the Homebrew tap

The cask lives at `~/work/projects/homebrew-tap/Casks/trackie.rb`.

```bash
# Grab the sha256 from the release-script output (or recompute):
shasum -a 256 dist/Trackie-X.Y.Z.dmg

# Update version + sha256 in the cask:
$EDITOR ~/work/projects/homebrew-tap/Casks/trackie.rb

cd ~/work/projects/homebrew-tap
git add Casks/trackie.rb
git commit -m "Update trackie to X.Y.Z"
git push
```

Verify the install end-to-end:

```bash
brew update
brew install --cask swairshah/tap/trackie
```

This should drop `Trackie.app` into `/Applications` and symlink the CLI to
`/opt/homebrew/bin/trackie` (or `/usr/local/bin/trackie` on Intel). Run
`trackie ping` after launching the app to confirm the broker answers.
