#!/bin/bash
set -euo pipefail

REPOSITORY="https://github.com/rorschachwilpeng/codex-usage-menubar.git"
SOURCE_ROOT="${CODEX_USAGE_SOURCE_ROOT:-$HOME/Library/Application Support/CodexUsageMenuBar/source}"

if ! command -v git >/dev/null 2>&1; then
  echo "Git is required. Install Xcode Command Line Tools with: xcode-select --install"
  exit 1
fi

if [[ -e "$SOURCE_ROOT" && ! -d "$SOURCE_ROOT/.git" ]]; then
  echo "Refusing to overwrite non-repository path: $SOURCE_ROOT"
  exit 1
fi

if [[ -d "$SOURCE_ROOT/.git" ]]; then
  git -C "$SOURCE_ROOT" fetch --depth=1 origin main
  git -C "$SOURCE_ROOT" checkout --detach FETCH_HEAD
else
  mkdir -p "$(dirname "$SOURCE_ROOT")"
  git clone --depth=1 "$REPOSITORY" "$SOURCE_ROOT"
fi

exec "$SOURCE_ROOT/scripts/install.sh"
