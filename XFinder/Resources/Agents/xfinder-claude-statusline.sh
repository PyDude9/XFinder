#!/bin/sh
# XFinder — Claude Code hands its usage limits (rate_limits: the 5-hour and 7-day used %) ONLY to its status line.
# This keeps that one object for the notch's AI usage tool, then runs the status line that was configured before
# XFinder's (saved at install), with the same input, so what Claude Code shows does not change. Installed and removed
# from XFinder ▸ Notch & Khay thả ▸ Agent AI; do not edit by hand (a reinstall overwrites it).
umask 077
# Drain stdin first, unconditionally: bailing out early would leave Claude Code writing into a closed pipe.
input=$(cat)
DIR="$HOME/Library/Application Support/XFinder/Agents/claude"
if [ -z "$XFINDER_STATUSLINE_ACTIVE" ]; then
  # A chain that leads back here (another tool later saved THIS script as its own previous status line) stops at
  # the second visit instead of looping: the variable is inherited by everything this run starts.
  XFINDER_STATUSLINE_ACTIVE=1
  export XFINDER_STATUSLINE_ACTIVE
  mkdir -p "$DIR" 2>/dev/null
  tmp="$DIR/.rate-limits.$$"
  # Only rate_limits is written (never cwd, transcript path or session id). Absent — API-key login, or before the
  # session's first reply — plutil fails and the last known value stays, dated by the file's modification time.
  if printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o "$tmp" -- - 2>/dev/null; then
    mv -f "$tmp" "$DIR/rate-limits.json"
  fi
  rm -f "$tmp" 2>/dev/null
  if [ -s "$DIR/statusline-before" ]; then
    printf '%s' "$input" | /bin/sh -c "$(cat "$DIR/statusline-before")"
    exit $?
  fi
fi
exit 0
