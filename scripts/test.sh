#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/tests

swiftc \
  Sources/CodexUsageMenuBar/UsageModels.swift \
  Sources/CodexUsageMenuBar/WeeklyUsage.swift \
  Sources/CodexUsageMenuBar/AppServerClient.swift \
  Sources/CodexUsageMenuBar/UsageStore.swift \
  Tests/TestRunner.swift \
  -o .build/tests/CodexUsageTests

.build/tests/CodexUsageTests "$@"
