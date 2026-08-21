#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Codex Usage.app"
CONTENTS="$APP/Contents"
VERSION="${CODEX_USAGE_VERSION:-1.1.0}"

cd "$ROOT"
if [[ "${CODEX_BUILD_UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp "$BIN_DIR/CodexUsageMenuBar" "$CONTENTS/MacOS/CodexUsageMenuBar"

/usr/libexec/PlistBuddy -c 'Clear dict' "$CONTENTS/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.rorschachwilpeng.codex-usage-menubar' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Codex Usage' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Codex Usage' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodexUsageMenuBar' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP"
"$ROOT/scripts/verify-app.sh" "$APP"
echo "Built: $APP"
