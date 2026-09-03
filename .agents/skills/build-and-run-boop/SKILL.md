---
name: build-and-run-boop
description: "Build the Boop macOS app with xcodebuild, kill any running instance, and launch the fresh build. Use this skill whenever the user asks to run, launch, relaunch, or try out the app, or says things like 'build and run' or 'restart the app'."
---

# Build and Run Boop

Builds Boop via `xcodebuild`, kills any running instance, then launches the
newly built app.

## Steps

1. **Resolve build settings** — don't hardcode the output path, DerivedData
   paths change between clean builds:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "/Users/fayazahmed/Developer/fayazara/mac/Boop/Boop.xcodeproj" \
  -scheme Boop -showBuildSettings 2>/dev/null \
  | grep -E "^\s*(CONFIGURATION|BUILT_PRODUCTS_DIR|FULL_PRODUCT_NAME|EXECUTABLE_NAME) "
```

2. **Build**:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project "/Users/fayazahmed/Developer/fayazara/mac/Boop/Boop.xcodeproj" \
  -scheme Boop \
  -configuration Debug \
  -destination "platform=macOS" \
  2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | head -20
```

If the output shows `BUILD FAILED`, stop, read the `error:` lines, and fix them.
Do not run a broken build.

3. **Kill every running instance.** Boop is a menu-bar agent with no Dock icon,
   so stale copies are easy to miss — and each one registers the same global hot
   key, which makes the app look broken. Always check for more than one:

```bash
pgrep -fl "Boop.app/Contents/MacOS/Boop"
killall Boop 2>/dev/null
```

4. **Run** using the path resolved in step 1:

```bash
open "<BUILT_PRODUCTS_DIR>/<FULL_PRODUCT_NAME>"
```

## Notes

- Boop needs **Accessibility** permission to read the selection and paste. macOS
  ties that grant to the binary's signature, so a rebuild can silently revoke it.
  If the hot key stops doing anything, re-add the app under
  System Settings → Privacy & Security → Accessibility.
- Debug builds skip the Sparkle updater entirely.
