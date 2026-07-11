#!/bin/bash
set -euo pipefail

APP="${1:?Usage: verify-app.sh /path/to/app}"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/CodexUsageMenuBar"

test -x "$EXECUTABLE"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = "io.github.rorschachwilpeng.codex-usage-menubar"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" = "CodexUsageMenuBar"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")" = "true"
codesign --verify --deep --strict "$APP"
echo "Verified: $APP"
