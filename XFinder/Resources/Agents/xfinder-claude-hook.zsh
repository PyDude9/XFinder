#!/bin/zsh
# XFinder — Claude Code hook (N3, 2026-10-13). Claude Code runs this for every event of a session and pipes
# the event JSON to stdin. It appends ONE JSON line to XFinder's events log and, for a PermissionRequest,
# blocks until the notch writes a decision file (or XFinder is not running), then prints that decision.
#
# Design, each line measured or quoted from the mechanism OneNotch 2.0.5 uses (docs/ONENOTCH_EVIDENCE §7):
#   * tool_response is dropped (an image Read carries the whole image as base64 — 650 KB in one line);
#   * the hook's parent is the claude process: $PPID is what liveness is measured on, and its tty is how the
#     notch finds the terminal later;
#   * waiting uses zsh's in-process zselect, so an hour of unanswered prompt forks nothing (a `sleep 0.25`
#     loop would spawn ~14 000 processes);
#   * if XFinder is gone the hook exits silently and Claude Code shows its own terminal prompt.
# Never prints anything except a decision; never exits non-zero (exit 2 would BLOCK Claude Code's action).
set +e
umask 077

dir="${XFINDER_AGENT_DIR:-$HOME/Library/Application Support/XFinder/Agents/claude}"
mkdir -p "$dir/events" "$dir/decisions" >/dev/null 2>&1 || exit 0

payload="$(cat | tr -d '\n\r')"
[ -z "$payload" ] && payload='{}'

event=""; sid=""
if [ -x /usr/bin/jq ]; then
  event="$(printf '%s' "$payload" | /usr/bin/jq -r '.hook_event_name // ""' 2>/dev/null)"
  sid="$(printf '%s' "$payload" | /usr/bin/jq -r '.session_id // ""' 2>/dev/null)"
  compact="$(printf '%s' "$payload" | /usr/bin/jq -c 'del(.tool_response)' 2>/dev/null)" && [ -n "$compact" ] && payload="$compact"
else
  event="$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name" *: *"\([A-Za-z]*\)".*/\1/p' | head -1)"
  sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id" *: *"\([0-9A-Za-z-]*\)".*/\1/p' | head -1)"
fi

tty_name="$(/bin/ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
[ "$tty_name" = "??" ] && tty_name=""
[ -n "$tty_name" ] && tty_name="/dev/$tty_name"

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
env_json="$(printf '{"ppid":%d,"tty":"%s","term_program":"%s","bundle_id":"%s","entrypoint":"%s","iterm_session":"%s","tmux_pane":"%s","wezterm_pane":"%s","term_session":"%s"}' \
  "$PPID" "$(esc "$tty_name")" "$(esc "${TERM_PROGRAM:-}")" "$(esc "${__CFBundleIdentifier:-}")" "$(esc "${CLAUDE_CODE_ENTRYPOINT:-}")" \
  "$(esc "${ITERM_SESSION_ID:-}")" "$(esc "${TMUX_PANE:-}")" "$(esc "${WEZTERM_PANE:-}")" "$(esc "${TERM_SESSION_ID:-}")")"

if [ ${#payload} -gt 262144 ]; then
  payload="$(printf '{"hook_event_name":"%s","session_id":"%s","xfinder_dropped":true}' "$(esc "$event")" "$(esc "$sid")")"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
day="$(date -u +%Y-%m-%d)"
request_id="$(/usr/bin/uuidgen 2>/dev/null | tr 'A-Z' 'a-z')"
printf '{"received_at":"%s","request_id":"%s","env":%s,"payload":%s}\n' "$now" "$request_id" "$env_json" "$payload" \
  >> "$dir/events/events-$day.jsonl" 2>/dev/null

if [ "$event" = "PermissionRequest" ] && [ -n "$sid" ] && [ -n "$request_id" ]; then
  /usr/bin/pgrep -x XFinder >/dev/null 2>&1 || exit 0
  decision_file="$dir/decisions/$sid-$request_id.json"
  find "$dir/decisions" -type f -mmin +60 -delete 2>/dev/null
  zmodload zsh/zselect 2>/dev/null
  typeset -F SECONDS
  SECONDS=0
  next_check=5
  while (( SECONDS < 3500 )); do          # under the hook's 3600 s timeout
    if [ -f "$decision_file" ]; then
      decision="$(cat "$decision_file" 2>/dev/null)"
      rm -f "$decision_file" 2>/dev/null
      if [ -n "$decision" ] && [ "$decision" != "skip" ]; then printf '%s\n' "$decision"; fi
      exit 0
    fi
    if (( SECONDS >= next_check )); then
      /usr/bin/pgrep -x XFinder >/dev/null 2>&1 || exit 0
      next_check=$(( SECONDS + 5 ))
    fi
    if zmodload -e zsh/zselect; then zselect -t 25; else sleep 0.25; fi
  done
fi
exit 0
