---
name: build-boop
description: "Build the Boop macOS app using xcodebuild. Use this skill whenever the user asks to build, compile, or check if the Boop project compiles successfully. Also use it when the user asks to fix build errors, verify changes compile, or run a debug build."
---

# Build Boop

This skill handles building the Boop macOS application via `xcodebuild`.

## Build Command

Run this exact command to build the project:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project "/Users/fayazahmed/Developer/fayazara/mac/Boop/Boop.xcodeproj" \
  -scheme Boop \
  -configuration Debug \
  -destination "platform=macOS" \
  2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | head -20
```

## Interpreting Results

- **BUILD SUCCEEDED** -- the build passed, report success to the user.
- **BUILD FAILED** with `error:` lines -- read each error, identify the source file and line, and help the user fix them. After fixing, re-run the build to verify.
- If the output is empty or unclear, re-run without the grep filter to get full output for diagnosis.

## Notes

- Boop depends on **Sparkle** via Swift Package Manager. If resolution fails with
  `Couldn't get revision '<tag>^{commit}'`, the SPM clone cache is stale:
  ```bash
  rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/Sparkle-*
  rm -rf ~/Library/Developer/Xcode/DerivedData/Boop-*/SourcePackages
  ```
  then re-run with `-resolvePackageDependencies`.
- The updater is compiled out in Debug (`#if DEBUG` in `UpdaterManager`), so
  update behaviour can only be exercised in a Release build.

## When to Build

- After making code changes, if the user asks to verify they compile
- When the user explicitly says "build", "compile", or "check if it builds"
- After fixing build errors, to confirm the fix worked
