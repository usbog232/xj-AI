---
name: build-xj-ai
description: Build, test, package, sign, launch, or diagnose the xj-AI SwiftPM macOS app in this repository. Use for xj-AI compilation, release App generation, build verification, and build-failure triage; do not use for Developer ID distribution or notarization.
---

# Build xj-AI

Produce a verified macOS App bundle from the repository without replacing the
project's build contract or disturbing unrelated user changes.

## Repository contract

Work from the directory containing all of these paths:

- `Package.swift`
- `script/build_and_run.sh`
- `Resources/Tools/whisper-cli`
- `Sources/xj-AI/`

Treat `script/build_and_run.sh` as the only App-bundling entry point. It owns
SwiftPM compilation, bundle staging, `Info.plist`, embedded resources, ad-hoc
signing, and launch behavior. Do not launch the raw SwiftPM executable as the
finished GUI App and do not recreate the bundle with an ad-hoc command chain.

The checked-in `whisper-cli` is an arm64 helper, so the complete packaged App
targets Apple Silicon. The development deployment target is macOS 14 or newer.

## Before building

1. Resolve the repository root and run `git status --short` so existing changes
   remain visible. Never reset, discard, or overwrite unrelated work.
2. Verify the required files and host:

   ```bash
   test -f Package.swift
   test -x script/build_and_run.sh
   test -x Resources/Tools/whisper-cli
   test "$(uname -m)" = "arm64"
   test -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
   ```

3. Do not download models, change API keys, accept privacy permissions, or
   contact configured AI providers merely to prove that the App builds.

## Required verification workflow

Run the tests with the same Xcode and module-cache locations used by the project:

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  test --disable-sandbox
```

The LAN ASR integration test may report one intentional skip when
`XJ_AI_TEST_LAN_URL` is not set. Any test failure is a build failure; do not
hide it by excluding the test target.

Create the release bundle:

```bash
./script/build_and_run.sh --package
```

Then verify the artifact instead of trusting the build command alone:

```bash
test -x dist/xj-AI.app/Contents/MacOS/xj-AI
test -x dist/xj-AI.app/Contents/Resources/Tools/whisper-cli
test -f dist/xj-AI.app/Contents/Resources/ThirdParty/whisper.cpp/LICENSE
plutil -lint dist/xj-AI.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 dist/xj-AI.app
/usr/bin/file dist/xj-AI.app/Contents/MacOS/xj-AI
/usr/bin/file dist/xj-AI.app/Contents/Resources/Tools/whisper-cli
```

Both executables must be arm64 Mach-O files. The final deliverable is
`dist/xj-AI.app`, not `.build/.../xj-AI`.

## Optional launch check

When the user asks to launch or verify startup, open the already packaged
release App and confirm the process remains alive:

```bash
/usr/bin/open -n "$PWD/dist/xj-AI.app"
sleep 2
pgrep -x xj-AI
```

Do not treat microphone, Speech, or ScreenCaptureKit permission prompts as
compiler failures. Never accept privacy prompts without the user's permission.
After automated startup checks, leave the App open unless the user asks to stop
it.

## Completion report

Report:

- whether tests passed and which expected tests were skipped;
- whether release compilation, `Info.plist` validation, and deep signature
  verification passed;
- the absolute path to `dist/xj-AI.app`;
- the executable architectures;
- the smallest actionable compiler, linker, signing, or startup error if any
  required check failed.

Do not claim microphone capture, system-audio capture, translation-provider
connectivity, or downloaded-model inference was validated unless those flows
were separately and explicitly tested.

For known failure modes, read
[references/troubleshooting.md](references/troubleshooting.md).
