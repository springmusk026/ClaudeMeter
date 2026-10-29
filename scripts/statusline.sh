#!/bin/zsh
# Claude Code status line:
#   model · context · plan limits · session · today · folder
#
# Also saves this session's live data (context fill, plan limits) to
# <account>/claudemeter/live/<session>.json for the ClaudeMeter menu bar app.
# Daily totals come back from <account>/claudemeter.json, which the app writes.
# <account> is this Claude account's config folder: CLAUDE_CONFIG_DIR, or ~/.claude.

input=$(cat)
base=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

# Every field gets a non-empty default: zsh collapses empty tab-separated fields
IFS=$'\t' read -r sid model model_id cost dur_ms dir transcript ctx_size ctx_pct five five_reset week week_reset <<<"$(jq -r '[
  (.session_id // "none"),
  (.model.display_name // .model.id // "Claude"),
  (.model.id // "none"),
  (.cost.total_cost_usd // 0),
  (.cost.total_duration_ms // 0),
  (.workspace.current_dir // .cwd // "none"),
  (.transcript_path // "none"),
  (.context_window.context_window_size // 0),
  (.context_window.used_percentage // -1),
  (.rate_limits.five_hour.used_percentage // -1),
  (.rate_limits.five_hour.resets_at // 0),
  (.rate_limits.seven_day.used_percentage // -1),
  (.rate_limits.seven_day.resets_at // 0)
] | @tsv' <<<"$input")"

# Hand live data to the menu bar app (atomic write so it never reads half a file)
if [[ $sid != none ]]; then
  live=$base/claudemeter/live
  mkdir -p "$live"
  jq -c --argjson now "$(date +%s)" '{
    session_id, updated: $now,
    model: (.model.display_name // .model.id),
    project: ((.workspace.current_dir // .cwd // "") | split("/") | last),
    context: .context_window,
    rate_limits
  }' <<<"$input" >"$live/.$sid.tmp" && mv "$live/.$sid.tmp" "$live/$sid.json"
fi

# Context %: use Claude Code's figure, or work it out from the transcript
if (( ctx_pct < 0 )); then
  if (( ctx_size == 0 )); then
    case "$model_id" in
      *haiku-4*|*sonnet-4-5*|*opus-4-5*|*opus-4-1*|*-3-*) ctx_size=200000 ;;
      *) ctx_size=1000000 ;;
    esac
  fi
  ctx=0
  if [[ -f "$transcript" ]]; then
    ctx=$(grep '"type":"assistant"' "$transcript" | tail -1 |
      jq -r '.message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null)
    [[ -z "$ctx" ]] && ctx=0
  fi
  ctx_pct=$(( ctx * 100 / ctx_size ))
fi

r=$'\e[0m'; dim=$'\e[2m'; green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'
sep=" ${dim}│${r} "
now=$(date +%s)

# Colour for a percentage: green, then yellow / red from the warn / critical levels
# (context uses 80 / 95; plan limits use the levels set in ClaudeMeter)
level() {
  local warn=${2:-80} crit=${3:-95}
  if (( $1 >= crit )); then print -n $red; elif (( $1 >= warn )); then print -n $yellow; else print -n $green; fi
}
left() { local m=$(( ($1 - now) / 60 )); (( m >= 60 )) && print -n "$(( m / 60 ))h$(( m % 60 ))m" || print -n "${m}m"; }

c=$(level $ctx_pct)
out="${c}✳ ${model}${r}${sep}ctx ${c}$(printf '%.0f' $ctx_pct)%${r}"

meter=$base/claudemeter.json
[[ -f $meter ]] && IFS=$'\t' read -r day tcost budget wend wcost accounts warn_at crit_at account <<<"$(jq -r '[.day, .today_cost, (.daily_budget // 0), (.window_end // 0), (.window_cost // 0), (.accounts // 1), (.warn_at // 80), (.critical_at // 95), (.account // "Default")] | @tsv' "$meter")"

# With several accounts, lead with this one's name
(( ${accounts:-1} > 1 )) && out="${account}${sep}${out}"

# Plan limits from Claude Code when available, else the app's estimated window cost
if (( five >= 0 && five_reset > now )); then
  out+="${sep}5h $(level $five $warn_at $crit_at)$(printf '%.0f' $five)%${r} ${dim}$(left $five_reset)${r}"
  (( week >= 0 && week_reset > now )) && out+=" ${dim}·${r} wk $(level $week $warn_at $crit_at)$(printf '%.0f' $week)%${r}"
elif (( ${wend:-0} > now )); then
  out+="${sep}5h \$$(printf '%.2f' $wcost) ${dim}$(left $wend) left${r}"
fi

out+="${sep}session \$$(printf '%.2f' $cost) ${dim}· $(( dur_ms / 60000 ))m${r}"

if [[ ${day:-} == $(date +%F) ]]; then
  tc=""
  if (( budget > 0 )); then
    if (( tcost >= budget )); then tc=$red; elif (( tcost >= budget * 0.8 )); then tc=$yellow; fi
  fi
  out+="${sep}today ${tc}\$$(printf '%.2f' $tcost)${r}"
fi

out+="${sep}${dim}${dir:t}${r}"
printf '%s' "$out"
