# Codex Usage Menu Bar

Stop opening Codex just to ask: "Will my quota last until reset?"

Codex Usage Menu Bar is a lightweight native macOS app that keeps the answer in your menu bar. It shows what remains now, then forecasts whether your current pace will reach the next reset.

![Codex Usage Menu Bar in the macOS menu bar](docs/usage-menubar-context.png)

<img src="docs/usage-menubar-closeup.png" alt="Close-up of the weekly quota forecast popover" width="406">

## What it shows

- `💰 88% ｜ 📅 8/27`: remaining quota and next reset date, always visible in the menu bar.
- Hover for a forecast: expected quota at reset, or the estimated time it runs out.
- A daily usage review for the current reset cycle. Today is marked separately; future days are never presented as zero usage.
- Refreshes automatically every 30 seconds and works while the Codex window is closed.

Daily bars begin with the first local observation. The app never invents earlier daily usage that it has not observed.

## Install with an Agent

Paste the following into a Codex or ChatGPT agent that has terminal access:

```text
Install Codex Usage Menu Bar from https://github.com/rorschachwilpeng/codex-usage-menubar on this Mac.

Run the official installer below. Do not request, print, copy, or store any credentials. When finished, confirm that Codex Usage.app is running and that the menu bar shows the current remaining quota and reset date.

curl -fsSL https://raw.githubusercontent.com/rorschachwilpeng/codex-usage-menubar/main/scripts/install-from-github.sh | bash
```

The script downloads the source into your user Application Support folder, builds the app locally, installs it to `~/Applications/Codex Usage.app`, and starts it at login. It never asks for your Codex password.

### One-command install

If you prefer Terminal, run:

```bash
curl -fsSL https://raw.githubusercontent.com/rorschachwilpeng/codex-usage-menubar/main/scripts/install-from-github.sh | bash
```

The first run may require you to install Xcode Command Line Tools:

```bash
xcode-select --install
```

Then run the installer again.

### Download a release

Download `Codex-Usage-v*.app.zip` from [Releases](https://github.com/rorschachwilpeng/codex-usage-menubar/releases), unzip it, and move the app to `~/Applications`.

Release builds are ad-hoc signed, not Apple-notarized. If macOS blocks the first launch, open **System Settings > Privacy & Security** and choose **Open Anyway**.

## Requirements

- macOS 13 Ventura or later.
- Codex for macOS, or ChatGPT for macOS with Codex installed and signed in.
- Internet access for Codex to refresh its own usage information.

Both Apple Silicon and Intel Macs are supported. Release ZIPs are Universal binaries.

## Privacy

The app launches Codex's bundled local app-server and calls the read-only `account/rateLimits/read` method. It does not read, copy, or store authentication tokens.

It stores only local quota observations and reset timestamps in:

```text
~/Library/Application Support/CodexUsageMenuBar/
```

See [PRIVACY.md](PRIVACY.md) for the complete data statement.

## Troubleshooting

### No usage data appears

Open ChatGPT/Codex once and confirm that you are signed in. Then choose **Refresh Now** from the menu bar item or restart the app.

### "Codex executable not found"

Install ChatGPT/Codex in `/Applications`, or launch with an explicit path:

```bash
CODEX_EXECUTABLE="/custom/path/to/codex" "$HOME/Applications/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar"
```

### The app stopped after a Codex update

Codex's local app-server interface may change. Check [Issues](https://github.com/rorschachwilpeng/codex-usage-menubar/issues) for compatibility reports and include your macOS and Codex versions when filing a new one.

## Development

```bash
./scripts/test.sh
./scripts/test.sh --smoke  # Uses your real local Codex session
./scripts/build-app.sh
./scripts/verify-app.sh "build/Codex Usage.app"
```

Set `CODEX_BUILD_UNIVERSAL=1` when full Xcode is installed to build a Universal app:

```bash
CODEX_BUILD_UNIVERSAL=1 ./scripts/build-app.sh
```

## Uninstall

```bash
./scripts/uninstall.sh
```

## Compatibility note

This project uses an undocumented local Codex app-server method. It can break when Codex changes its bundled protocol. The app retains the last successful value and fails without accessing credentials, but compatibility is not guaranteed across future Codex releases.

## License

[MIT](LICENSE)
