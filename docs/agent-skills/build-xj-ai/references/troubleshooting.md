# xj-AI build troubleshooting

Read this file only after a required build, test, packaging, signing, or launch
check fails.

## Xcode or SDK is not found

- Require the full `/Applications/Xcode.app`, not only Command Line Tools.
- Keep `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on the failing
  command. Do not change the user's global `xcode-select` setting unless they
  explicitly request it.
- Confirm the Swift executable named in `SKILL.md` exists before retrying.

## SwiftPM cache warnings

Warnings that user-level SwiftPM cache directories are read-only are not fatal
when compilation and tests continue. The project-local `CLANG_MODULE_CACHE_PATH`
and `SWIFTPM_MODULECACHE_OVERRIDE` are intentional. Diagnose the first actual
`error:` line rather than treating a cache warning as the root cause.

## Embedded whisper helper is missing or wrong architecture

The bundle must contain `Contents/Resources/Tools/whisper-cli`, and the source
copy must be executable at `Resources/Tools/whisper-cli`. Restore the tracked
file from the repository if it is missing. Do not substitute an arbitrary
download or silently package a Homebrew path.

The helper and main executable must both be arm64. An Intel host cannot produce
the repository's complete supported bundle without separately rebuilding the
embedded helper; report that limitation instead of claiming success.

## Bundle or signature verification fails

- Re-run `./script/build_and_run.sh --package`; it recreates `dist/xj-AI.app`
  and signs the complete bundle after copying resources.
- Check the first changed or unsigned nested executable reported by `codesign`.
- Do not hand-edit `dist/xj-AI.app`; it is generated output.
- Ad-hoc signing is correct for local development. Developer ID signing and
  notarization are separate distribution tasks.

## App launches without a usable window

Launch the `.app` bundle with `/usr/bin/open -n`, not the raw SwiftPM binary.
Inspect the process and unified log before changing window code. Privacy prompts
can block recording features but should not prevent the main window from
appearing.

## LAN ASR test is skipped

One skipped integration test is expected when no test server URL is supplied.
Only when the user provides a disposable compatible server should the test be
run with `XJ_AI_TEST_LAN_URL`. Never point automated tests at an unknown or
production service.
