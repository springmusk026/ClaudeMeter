# Changelog

## Unreleased
- Redesigned Settings: General, Limits, Accounts and About tabs instead of one long page.
  - The menu bar option shows a live preview of each choice.
  - Warning and critical levels are shown on a single bar.
  - Shows when limits were last checked, whether notifications are allowed, today's spend against the budget, and setup status.
- Removed the desktop widget for now.

## 2.3
- Desktop widget in small and medium sizes: 5-hour ring, weekly and per-model limits, today's cost and tokens, and the forecast.
- Chart readouts update instantly while you scrub, instead of rolling through in-between values.

## 2.2
- Fresh limits even with no session open, and per-model weekly limits (e.g. Sonnet only), from Claude Code's local `/usage` command every 5 minutes.
- Limit history: saved readings for 30 days and a Limits view in the Usage tab (peak use per hour or day, windows used, limit hits).
- The forecast uses your pace over the last hour.
- Weekly limit as an inner ring in the menu bar icon.
- Adjustable warning and critical levels for colors, alerts and the status line.
- `--json` output and Copy Diagnostics.

## 2.1
- Menu bar icon redesigned as a ring meter that fills with 5-hour usage, with a working dot, an account initial, and a "!" at limits.
- Snapshot mode renders every menu bar icon state; `--demo` renders made-up data for docs.

## 2.0
- Full redesign: Now, Usage and Accounts tabs, a token-based design system, dotted progress tracks, a drawn line chart, hourly bars, and purposeful motion that respects Reduce Motion.
- `--snapshot` renders the UI to PNG for review.

## 1.5
- Shows live state: a status line (working, idle, limit reached) plus working and idle sessions.
- Account rows show the signed-in email and plan; click one to select it for new `claude` sessions.

## 1.4
- Multiple accounts, using separate Claude Code config folders.
- Per-account limits, alerts and status line.

## 1.3
- Official plan limits (5-hour and weekly) from Claude Code's status line, with alerts and forecasts.
- Live sessions with context fill. Week-over-week comparison.

## 1.2
- Native macOS menu style, a settings window, and an app icon.

## 1.1
- Incremental log reading, instant updates, a daily budget, notifications, and charts.

## 1.0
- First version: menu bar usage from local Claude Code logs.
