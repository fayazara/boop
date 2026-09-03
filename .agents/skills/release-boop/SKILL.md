---
name: release-boop
description: "Release the Boop macOS app to GitHub using the boop-release CLI tool. Use this skill whenever the user wants to publish a new version, create a release, ship an update, cut a build, push a release to GitHub, or update the appcast. Also use when they mention archiving, notarization, DMG creation, Sparkle signing, bumping the version/build, or anything related to building and distributing a new Boop version."
---

# Release Boop

Releases new versions of Boop using a Go CLI (`cmd/boop-release`), ported from
the Screendrop release tool. It runs **fully automated and non-interactively**,
so a release can be triggered directly from a chat session.

Two modes:

- **Full auto (`-build`)** — archive, export (Developer ID), notarize, staple,
  package, sign, and publish. Nothing in Xcode's GUI is required.
- **Package-only** (no `-build`) — assumes a notarized `~/Downloads/Boop.app`
  already exists, then packages & publishes.

Prefer **full auto** unless the user says they've already exported the app.

## Prerequisites

1. `create-dmg` (brew), `gh` (authenticated), `git`, `plutil`, `go`.
2. Sparkle's `sign_update` in DerivedData — produced by building/archiving once.
3. A **notarytool keychain profile**. Defaults to `screendrop-notary`, which
   already exists on this machine — notarytool profiles are per Apple *team*, not
   per app, so the same credentials notarize every one of Fayaz's apps. To use a
   different one, pass `-notary-profile <name>`, or create it with:
   ```bash
   xcrun notarytool store-credentials "<name>" \
     --key /path/to/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
   ```

## Flags

- `-build` — run archive → export → notarize → staple first.
- `-set-version <x.y.z>` — set `MARKETING_VERSION` before archiving (and commit).
- `-set-build <n>` — set `CURRENT_PROJECT_VERSION` before archiving (and commit).
- `-scheme <name>` — Xcode scheme (default `Boop`).
- `-notes "<text>"` — release notes, one bullet per line. Skips the prompt.
- `-notes-file <path>` — read notes from a file instead.
- `-notary-profile <name>` — notarytool keychain profile (default `screendrop-notary`).
- `-yes` / `-y` — assume yes for all confirmations (non-interactive).

## Cutting a release

1. **Decide version and build number.** `CURRENT_PROJECT_VERSION` **must
   increase** every release or Sparkle won't offer the update:
   ```bash
   grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" \
     Boop.xcodeproj/project.pbxproj | sort -u
   ```
   Never regress `MARKETING_VERSION` (don't go `0.10` → `0.2`).
2. **Commit and push code changes to `main` first**, so the tag points at the
   released source.
3. **Run it** (non-interactive, safe from a tool call — allow ~7 min, notarization
   blocks for a few minutes and that is not a hang):
   ```bash
   \
   go run ./cmd/boop-release -build -yes \
     -set-version <x.y.z> -set-build <n> \
     -notes "First note
   Second note"
   ```

## What it does (in order)

With `-build`: set version/build (commit) → archive → export with Developer ID →
notarize (`notarytool submit --wait`, verifying `status: Accepted`) → staple →
place app at `~/Downloads/Boop.app`.

Then always: preflight checks → validate version/build and Sparkle keys →
collect notes → `create-dmg` → sign the DMG with Sparkle `sign_update` (EdDSA) →
push local commits → `gh release create vX.Y.Z` with the DMG → prepend and push
the `appcast.xml` entry → regenerate the Homebrew cask (non-fatal).

**Ordering & robustness:** the GitHub release is created **before** the appcast is
pushed, so a published appcast never points at a missing release. Network calls
retry with backoff. Re-running is safe: the DMG is re-uploaded with `--clobber`
and the appcast entry for that build is replaced, not duplicated.

## Sparkle configuration

- **SUFeedURL**: `https://raw.githubusercontent.com/fayazara/boop/main/appcast.xml`
- **SUPublicEDKey**: `MA/6n0fqT0T2updDlkXr8BjhJKoHWik9uf6Lh5pUG7U=`
- **Keys live in the login keychain** under service `https://sparkle-project.org`,
  account `ed25519` — a **single key shared by all of Fayaz's apps**, Screendrop
  included. Never run `generate_keys` without `-p`: regenerating would overwrite
  that key and break updates for every previously shipped app. To read the public
  key: `generate_keys -p`.
- `UpdaterManager.swift` — singleton, started at launch in Release builds only,
  wired to the menu bar and Settings.

## After releasing

```bash
gh release view v<x.y.z> --repo fayazara/boop --json tagName,assets \
  -q '{tag: .tagName, assets: [.assets[].name]}'
git pull --ff-only origin main   # the CLI pushed the appcast commit itself
```

## Troubleshooting

- **Partial failure mid-release** — re-run the exact same command; the pipeline is idempotent.
- **notarytool credentials error** — the keychain profile is missing/invalid; re-run `store-credentials` or pass `-notary-profile`.
- **Notarization "Invalid"** — `xcrun notarytool log <submission-id> --keychain-profile <profile>` (usually signing/entitlements).
- **`sign_update` not found** — build/archive once so DerivedData has the Sparkle artifacts.
- **SPM fails with `Couldn't get revision '<tag>^{commit}'`** — stale clone cache:
  `rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/Sparkle-*` and re-resolve.
- **Build already in appcast** — re-running is safe, but a *new* release needs a higher build number.
- **Update never offered** — check `CURRENT_PROJECT_VERSION` actually increased; Sparkle compares builds, not marketing versions.
