# Privacy

Codex Usage Menu Bar runs entirely on your Mac.

## Data accessed

- Remaining percentage and reset timestamp for the current Codex usage window.
- Your existing local Codex authentication state, used internally by Codex's own app-server.

## Data stored

The app caches the last successful remaining percentage, reset timestamp, and update timestamp in `~/Library/Application Support/CodexUsageMenuBar/last-usage.json`.

It also stores local observations of remaining percentage in `~/Library/Application Support/CodexUsageMenuBar/weekly-usage-history.json` so it can draw daily usage for the current cycle. It does not store tokens, prompts, conversation content, or authentication data.

## Data not collected

- Authentication tokens or credentials.
- Prompt or conversation content.
- Screenshots, keystrokes, clipboard data, or browsing activity.
- Analytics, telemetry, crash reports, or device identifiers.

The app does not send data to the project author or any third-party service. Network activity performed by the Codex app-server remains subject to OpenAI's product terms and privacy policy.
