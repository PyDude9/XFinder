#!/bin/zsh
# XFinder — coding-agent hook (N3 2026-10-13 for Claude Code; P5 2026-10-14 adds Codex). The agent runs this for
# every event of a session and pipes the event JSON to stdin. The first argument names the agent ("claude" when
# absent, so a hook installed before P5 keeps working). It appends ONE JSON line to XFinder's events log and, for a
# PermissionRequest, blocks until the notch writes a decision file (or XFinder is not running), then prints that
# decision. Claude Code and Codex document the same PermissionRequest output, so the decision is passed through as is.
#
# Design, each line measured or quoted from the mechanism OneNotch 2.0.5 uses (docs/ONENOTCH_EVIDENCE §7):
#   * tool_response is dropped (an image Read carries the whole image as base64 — 650 KB in one line), and so is
#     last_assistant_message (Codex's Stop carries the model's answer; XFinder promises not to read answers);
#   * liveness is measured on the AGENT process: the hook walks up its parents (at most 4) to the first process named
#     like the agent — for Claude Code that is the hook's parent (measured); if none is found, Claude falls back to
#     $PPID and other agents record no pid (a wrong pid — a `sh -c` that exits with the hook — would end the
#     session at once);
#   * waiting uses zsh's in-process zselect, so an hour of unanswered prompt forks nothing (a `sleep 0.25`
#     loop would spawn ~14 000 processes);
#   * if XFinder is gone the hook exits silently and the agent shows its own terminal prompt.
# Never prints anything except a decision; never exits non-zero (exit 2 would BLOCK the agent's action).
set +e
umask 077

agent="${1:-claude}"
case "$agent" in
  claude|codex) ;;
  *) exit 0 ;;
esac

dir="${XFINDER_AGENT_DIR:-$HOME/Library/Application Support/XFinder/Agents/$agent}"
mkdir -p "$dir/events" "$dir/decisions" >/dev/null 2>&1 || exit 0

payload="$(cat | tr -d '\n\r')"
[ -z "$payload" ] && payload='{}'

event=""; sid=""
if [ -x /usr/bin/jq ]; then
  event="$(printf '%s' "$payload" | /usr/bin/jq -r '.hook_event_name // ""' 2>/dev/null)"
  sid="$(printf '%s' "$payload" | /usr/bin/jq -r '.session_id // ""' 2>/dev/null)"
  compact="$(printf '%s' "$payload" | /usr/bin/jq -c 'del(.tool_response, .last_assistant_message)' 2>/dev/null)" && [ -n "$compact" ] && payload="$compact"
else
  event="$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name" *: *"\([A-Za-z]*\)".*/\1/p' | head -1)"
  sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id" *: *"\([0-9A-Za-z-]*\)".*/\1/p' | head -1)"
fi

# The session id becomes part of a decision FILE NAME: only letters, digits, - and _ (P5 review — a forged
# "../…" id escaped the decisions folder). An unsafe id gets no wait: the agent asks in its own terminal.
case "$sid" in
  ''|*[!A-Za-z0-9_-]*) safe_sid="" ;;
  *) safe_sid="$sid" ;;
esac
[ ${#safe_sid} -gt 128 ] && safe_sid=""

# XFINDER_ASSUME_RUNNING lets the test suite exercise the waiting path without the app (no agent sets it).
xfinder_running() { [ -n "${XFINDER_ASSUME_RUNNING:-}" ] || /usr/bin/pgrep -x XFinder >/dev/null 2>&1; }

# Find the agent process: $PPID, then its parents, until a process whose executable is named like the agent.
agent_pid=""; tty_name=""
pid=$PPID
for _ in 1 2 3 4; do
  line="$(/bin/ps -o ppid=,tty=,comm= -p "$pid" 2>/dev/null)"
  [ -z "$line" ] && break
  read -r parent tty_field comm_path <<< "$line"
  if [ "${comm_path:t}" = "$agent" ]; then
    agent_pid=$pid
    tty_name="$tty_field"
    break
  fi
  [ -z "$parent" ] || [ "$parent" -le 1 ] && break
  pid=$parent
done
if [ -z "$agent_pid" ] && [ "$agent" = "claude" ]; then
  agent_pid=$PPID
  tty_name="$(/bin/ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
fi
[ "$tty_name" = "??" ] && tty_name=""
[ -n "$tty_name" ] && tty_name="/dev/$tty_name"

# Every env value loses its control characters (P6 review): a newline in, say, $TMUX would split the event across two
# lines and both halves would be dropped. Then backslash and quote are escaped for the JSON string.
esc() { printf '%s' "$1" | LC_ALL=C tr -d '\001-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# P6: where a reply can be typed — kitty's window id + listen socket, tmux's server socket ($TMUX). None is a secret
# (KITTY_PUBLIC_KEY is deliberately not recorded).
env_json="$(printf '{"ppid":%d,"tty":"%s","term_program":"%s","bundle_id":"%s","entrypoint":"%s","iterm_session":"%s","tmux_pane":"%s","wezterm_pane":"%s","term_session":"%s","kitty_window":"%s","kitty_listen_on":"%s","tmux":"%s","windowless":"%s"}' \
  "${agent_pid:-0}" "$(esc "$tty_name")" "$(esc "${TERM_PROGRAM:-}")" "$(esc "${__CFBundleIdentifier:-}")" "$(esc "${CLAUDE_CODE_ENTRYPOINT:-}")" \
  "$(esc "${ITERM_SESSION_ID:-}")" "$(esc "${TMUX_PANE:-}")" "$(esc "${WEZTERM_PANE:-}")" "$(esc "${TERM_SESSION_ID:-}")" \
  "$(esc "${KITTY_WINDOW_ID:-}")" "$(esc "${KITTY_LISTEN_ON:-}")" "$(esc "${TMUX:-}")" "$(esc "${XFINDER_WINDOWLESS:-}")")"

if [ ${#payload} -gt 262144 ]; then
  payload="$(printf '{"hook_event_name":"%s","session_id":"%s","xfinder_dropped":true}' "$(esc "$event")" "$(esc "$sid")")"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
day="$(date -u +%Y-%m-%d)"
request_id="$(/usr/bin/uuidgen 2>/dev/null | tr 'A-Z' 'a-z')"
printf '{"received_at":"%s","request_id":"%s","agent":"%s","env":%s,"payload":%s}\n' "$now" "$request_id" "$agent" "$env_json" "$payload" \
  >> "$dir/events/events-$day.jsonl" 2>/dev/null

if [ "$event" = "PermissionRequest" ] && [ -n "$safe_sid" ] && [ -n "$request_id" ]; then
  xfinder_running || exit 0
  decision_file="$dir/decisions/$safe_sid-$request_id.json"
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
      xfinder_running || exit 0
      next_check=$(( SECONDS + 5 ))
    fi
    if zmodload -e zsh/zselect; then zselect -t 25; else sleep 0.25; fi
  done
fi
exit 0
