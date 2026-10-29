# Contributing

Thanks for helping improve ClaudeMeter. Issues and pull requests are welcome.

## Setup

```sh
./build.sh   # compile, install to ~/Applications, launch
```

`build.sh` replaces the installed app each time. Quit and relaunch to pick up Info.plist changes.

## Principles

- **Local only.** No network requests, no credential access. Data comes from Claude Code's logs, its status line input, and its profile file. Changes that need the network or login tokens won't be merged.
- **Honest numbers.** Costs are labeled as estimates. Forecasts stay hidden until there's enough data to mean something.
- **No new dependencies.** Plain Swift, SwiftUI and system frameworks.

## Design rules

The UI is built from the tokens and components in `Sources/Design.swift` and `Sources/Theme.swift`. Please reuse them rather than adding one-off styles.

- **Spacing** comes only from `Space` (4, 8, 12, 16, 20, 24, 32).
- **Color carries meaning:**
  - `claude`: the plan allowance
  - `cobalt`: history and analytics
  - `live`: running now
  - `caution` / `critical`: near or at a limit
  - Glows are soft, in one corner, with at most one featured glow per screen.
- **One primary number per screen.** Supporting values are smaller; times and metadata use `Typo.mono`.
- **Every state is visible**: working, idle, limit reached, not signed in, loading, empty, estimated, stale.
- **Motion has a purpose**, runs on appear or change only, and respects Reduce Motion. The only looping animation is the "working" indicator.
- The menu bar icon stays a monochrome template image.

## Before opening a pull request

1. `./build.sh` finishes with no errors or warnings.
2. Render snapshots and look at every one:
   ```sh
   build/ClaudeMeter.app/Contents/MacOS/ClaudeMeter --snapshot /tmp/shots --demo
   ```
   Check light and dark, every tab, the Limits view and `menubar.png`.
3. If you changed the UI, regenerate the README screenshots from `--demo` output into `docs/screenshots/`. Never commit screenshots of real accounts.
4. If you changed `scripts/statusline.sh`, test it with sample input:
   ```sh
   echo '{"session_id":"t","model":{"display_name":"Opus 5.5"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'$(( $(date +%s) + 3600 ))'}}}' \
     | CLAUDE_CONFIG_DIR=/tmp/cm-test scripts/statusline.sh
   ```
5. Add a line to [CHANGELOG.md](CHANGELOG.md).

## Pricing

Model prices live in `Sources/Model.swift` (`rates`). When Anthropic changes prices or ships a model, update the table; more specific model names must come before broader ones.
