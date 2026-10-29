# ClaudeMeter

[![Build](https://github.com/springmusk026/ClaudeMeter/actions/workflows/build.yml/badge.svg)](https://github.com/springmusk026/ClaudeMeter/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A native macOS menu bar app that shows your **Claude Code** usage at a glance: how much of your plan limit is left, what's running right now, and where your tokens go.

It only reads files on your Mac. No network requests, no logins, no API keys.

<p align="center">
  <img src="docs/screenshots/now-dark.png" width="300" alt="Now tab: 5-hour limit, live sessions and today's usage">
  <img src="docs/screenshots/usage-dark.png" width="300" alt="Usage tab: cost chart and model breakdown">
</p>

<p align="center">
  <img src="docs/screenshots/menubar.png" width="640" alt="Menu bar icon states">
</p>

## Features

- **Plan limits**: your real 5-hour, weekly and per-model weekly (e.g. Sonnet only) usage and reset times, as reported by Claude Code. Kept fresh even with no session open.
- **Forecast**: "At this pace, out by 10:56 PM", from your pace over the last hour.
- **Limit history**: your peak 5-hour usage per hour or day over 30 days, how many windows you used and how often you hit the limit.
- **Menu bar meter**: a ring that fills with your 5-hour usage, with an inner ring for the weekly limit. A dot means Claude is working; **!** means a limit is reached.
- **Live sessions**: every open Claude Code session, whether it's working or idle, and how full its context window is (with a nudge to `/compact` near the end).
- **Usage history**: cost or tokens for today, 7 or 30 days, broken down by model, project and session. Costs are estimated at Anthropic API list prices.
- **Multiple accounts**: see each account's limits side by side and choose which one new `claude` sessions use. Accounts stay fully separate; ClaudeMeter never touches login credentials.
- **Alerts**: notifications at your warning and critical levels (80% and 95% by default) for every limit, when a 5-hour window resets, and for an optional daily budget.
- **Status line**: a matching Claude Code status line with model, context, limits and cost.
- **JSON output** for scripts, Raycast or SketchyBar: `ClaudeMeter --json`.
- **Settings that show state**: a live preview of each menu bar option, today's spend against your budget, when limits were last checked, whether notifications are allowed, and a setup checklist.
- **Copy Diagnostics** in Settings for bug reports, with no emails, account or project names.
- Follows the system light/dark appearance and respects Reduce Motion.

<p align="center">
  <img src="docs/screenshots/limits-dark.png" width="300" alt="Limits view: peak 5-hour usage per day">
  <img src="docs/screenshots/accounts-dark.png" width="300" alt="Accounts tab with two accounts">
</p>

## Settings

Open **Settings (⌘,)** from the gear in the panel. There are four tabs:

| Tab | What's there |
|---|---|
| General | What the menu bar shows (with a live preview of each option), the weekly inner ring, an optional daily budget, launch at login |
| Limits | Warning and critical levels (80% and 95% by default), limit checks with their last result, notifications |
| Accounts | Add, rename and remove accounts, choose the one new `claude` sessions use, install terminal commands |
| About | Version, a setup checklist (Claude Code, status line, terminal commands) and Copy Diagnostics |

<p align="center">
  <img src="docs/screenshots/settings-general-dark.png" width="400" alt="Settings, General tab: menu bar options with live previews and the daily budget">
  <img src="docs/screenshots/settings-limits-dark.png" width="400" alt="Settings, Limits tab: warning and critical levels, limit checks and notifications">
</p>

## Requirements

- macOS 14 Sonoma or later
- [Claude Code](https://claude.com/claude-code)
- `jq` for the status line (`brew install jq`)
- Xcode or the Xcode Command Line Tools (Swift 5.9+) to build it

## Install

There's no prebuilt download yet, so build it from source. It takes about a minute and needs only the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/springmusk026/ClaudeMeter.git
cd ClaudeMeter
./build.sh                       # builds, installs to ~/Applications and launches
./scripts/install-statusline.sh  # recommended: enables plan limits and live sessions
```

ClaudeMeter appears in the menu bar. Open **Settings › General** and turn on **Launch at login**.

`build.sh` signs the app ad hoc, which is all a local build needs. To sign with your own certificate, run `SIGN_IDENTITY="Apple Development: …" ./build.sh`. Run `./build.sh` again to update after a `git pull`.

Plan limits and live session data come from Claude Code's status line, so they appear after you install the status line and start (or restart) a Claude Code session. Without it, ClaudeMeter still shows usage and cost from the logs, with an estimated 5-hour window.

## How it works

| Data | Source |
|---|---|
| Tokens, cost, sessions, history | Claude Code's local logs in `~/.claude/projects/*.jsonl`, read incrementally |
| Plan limits, context fill, live sessions | Claude Code passes these to its status line; `statusline.sh` saves them to `~/.claude/claudemeter/live/` |
| Fresh and per-model limits | Every 5 minutes, and when you open the panel, the app runs `claude -p /usage --no-session-persistence` for each signed-in account. It's a local command: no model request, no cost, no session record. Turn it off in Settings › Limits. |
| Limit history | Readings saved to `~/Library/Application Support/ClaudeMeter/history/` (30 days) |
| Signed-in email and plan | The account profile in `~/.claude.json` (no tokens) |

The app watches those folders and updates within a second of Claude writing to them. It writes a small summary to `~/.claude/claudemeter.json` so the status line can show daily totals.

**Is this allowed?** ClaudeMeter only reads files Claude Code already writes on your machine and data Claude Code hands to status line scripts. It doesn't call Anthropic's servers, reuse your login, or scrape claude.ai.

### Multiple accounts

Each extra account gets its own Claude Code config folder (`~/.claude-<name>`), using Claude Code's `CLAUDE_CONFIG_DIR` setting, so each keeps its own login. Add accounts in **Settings › Accounts**, then click **Sign In** and run `/login` in the Terminal window that opens.

With **Terminal commands** installed (Settings › Accounts), plain `claude` starts whichever account is selected in the panel, and `claude-<name>` starts a specific one. Switching is always manual.

Please follow Anthropic's terms for your plan. Never share an account with another person.

## Development

```
Sources/
  App.swift            app entry, menu bar icon
  PanelView.swift      the panel: Now, Usage and Accounts tabs
  Design.swift         design system: tokens and components
  Theme.swift          spacing and semantic colors
  Format.swift         number and time formatting
  SettingsView.swift   settings: General, Limits, Accounts, About
  Store.swift          state, refresh, notifications, status line summary
  Stats.swift          usage summaries, 5-hour windows, forecasts
  LogReader.swift      incremental JSONL reader and folder watcher
  LiveData.swift       live data saved by the status line
  Accounts.swift       accounts, profiles, launching, shell commands
  Probe.swift          runs and parses `claude /usage`
  History.swift        saved limit readings and recent pace
  Export.swift         --json output and diagnostics
  Model.swift          pricing, records, formatting
  Snapshot.swift       render the UI to PNG for review
  Demo.swift           made-up data for screenshots
scripts/
  statusline.sh        the Claude Code status line
  install-statusline.sh
tools/make-icon.swift  renders the app icon
```

There's no Xcode project: `./build.sh` compiles `Sources/*.swift` with `swiftc` (targeting the minimum macOS in `Info.plist`) and assembles the app bundle. `./build.sh --no-install` only builds into `build/`, as CI does.

**Usage as JSON**, e.g. for a script or another menu bar tool:

```sh
~/Applications/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --json             # asks Claude Code for fresh limits first
~/Applications/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --json --no-probe  # logs and saved data only, instant
```

**Look at your changes.** Render every panel tab and Settings tab (light and dark), the Limits view and every menu bar icon state to PNG:

```sh
build/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --snapshot /tmp/shots          # your real data
build/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --snapshot /tmp/shots --demo   # made-up data
```

The README screenshots are made with `--demo`. See [CONTRIBUTING.md](CONTRIBUTING.md) for design rules and the change checklist.

## Disclaimer

ClaudeMeter is an independent project and is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic. Cost figures are estimates; subscription plans are not billed per token.

## License

[MIT](LICENSE)
