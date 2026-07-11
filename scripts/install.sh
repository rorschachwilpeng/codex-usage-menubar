#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/build/Codex Usage.app"
TARGET_APP="$HOME/Applications/Codex Usage.app"
LABEL="io.github.rorschachwilpeng.codex-usage-menubar"
LEGACY_LABEL="com.pkfare.codex-usage-menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT/scripts/build-app.sh"
fi
"$ROOT/scripts/verify-app.sh" "$SOURCE_APP"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
pkill -x CodexUsageMenuBar 2>/dev/null || true

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

/usr/libexec/PlistBuddy -c 'Clear dict' "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string /usr/bin/open' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:1 string -g' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:2 string $TARGET_APP" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :KeepAlive bool false' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :ProcessType string Interactive' "$PLIST"

launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl kickstart -k "$DOMAIN/$LABEL"
echo "Installed and started: $TARGET_APP"
