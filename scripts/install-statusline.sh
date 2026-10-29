#!/bin/zsh
# Install ClaudeMeter's Claude Code status line.
#
# Copies scripts/statusline.sh to ~/.claude/statusline.sh and points Claude Code's
# statusLine setting at it. The status line shows model, context, plan limits and
# daily cost, and saves live data (context fill, plan limits) for the menu bar app.
#
# An existing different statusLine setting is left alone unless you pass --force.
set -euo pipefail
cd "${0:A:h}/.."

command -v jq >/dev/null || { echo "jq is required: brew install jq" >&2; exit 1; }

settings=~/.claude/settings.json
mkdir -p ~/.claude
[[ -f $settings ]] || echo '{}' > "$settings"

current=$(jq -r '.statusLine.command // empty' "$settings")
if [[ -n $current && $current != "~/.claude/statusline.sh" && ${1:-} != --force ]]; then
  echo "Your Claude Code settings already use another status line: $current"
  echo "Not changing it. Run again with --force to replace it (the old setting is backed up)."
  exit 1
fi

cp scripts/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

cp "$settings" "$settings.bak"
tmp=$(mktemp)
jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh", padding: 0}' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "Installed ~/.claude/statusline.sh (previous settings saved to $settings.bak)."
echo "Restart Claude Code to see it."
