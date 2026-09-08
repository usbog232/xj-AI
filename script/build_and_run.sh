#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="xj-AI"
BUNDLE_ID="net.xj-ai.desktop"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
SWIFT_BIN="$XCODE_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"

CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  CONFIGURATION="release"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
"$SWIFT_BIN" build --disable-sandbox -c "$CONFIGURATION"
BUILD_BINARY="$("$SWIFT_BIN" build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

if [[ -d "$ROOT_DIR/Resources/Tools" ]]; then
  cp -R "$ROOT_DIR/Resources/Tools" "$APP_RESOURCES/Tools"
  chmod +x "$APP_RESOURCES/Tools/whisper-cli"
fi

if [[ -d "$ROOT_DIR/Resources/ThirdParty" ]]; then
  cp -R "$ROOT_DIR/Resources/ThirdParty" "$APP_RESOURCES/ThirdParty"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>xj-AI 需要访问麦克风，以便在本机进行实时语音识别与翻译。</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>xj-AI 使用 Apple 设备端语音识别，把采集的音频实时转换为文字。</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>xj-AI 需要访问你指定的局域网翻译或语音识别服务。</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
PLIST

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cat >>"$INFO_PLIST" <<PLIST
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
PLIST
fi

cat >>"$INFO_PLIST" <<PLIST
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    echo "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
