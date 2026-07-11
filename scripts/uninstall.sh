#!/bin/bash
set -euo pipefail

LABEL="io.github.rorschachwilpeng.codex-usage-menubar"
LEGACY_LABEL="com.pkfare.codex-usage-menubar"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
pkill -x CodexUsageMenuBar 2>/dev/null || true
rm -rf "$HOME/Applications/Codex Usage.app"
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -f "$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
rm -rf "$HOME/Library/Application Support/CodexUsageMenuBar"

echo "Codex Usage Menu Bar has been removed."
