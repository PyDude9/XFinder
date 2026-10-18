#!/bin/zsh
# XFinder crew messaging (P7b, v2 verbs XF-T23). A crew member — a windowless Claude Code session XFinder runs — calls this
# from its shell. Nothing here waits for an answer (a shell call that waited for a whole turn would hit the agent's tool
# timeout); every verb writes one signed request into the crew's inbox and returns at once.
#
#   xfinder-crew who
#   xfinder-crew send <role|all> <message…>                                  (every crew)
# Lead Architect crews (the folder holds a `v2` marker) also have:
#   xfinder-crew send <role|all> --task "<what>" --criteria "<acceptance>" [--branch crew/…] [note…]
#   xfinder-crew status <role|all> <message…>                                (no answer expected)
#   xfinder-crew done --branch crew/… --tests "<what you ran>" [note…]       (a builder: this part is finished)
#   xfinder-crew verdict approved|rejected --branch crew/… --note "<file:line and why>"   (security, reviewer)
#   xfinder-crew conflict --branch crew/… --note "<file>"
#   xfinder-crew merge --branch crew/…                                       (the lead; XFinder refuses before both approvals)
#
# The sender is XFINDER_CREW_ROLE; the request is signed with the member's own token (XFINDER_CREW_TOKEN) and the token is
# never written to the shared inbox. v1: SHA-256 over file name, target, text, token. v2: SHA-256 over EVERY field, each as
# `tag:<utf-8 byte count>:<value>` joined by newlines, then the token — the same canonical form CrewV2.canonical builds.
emulate -L zsh
setopt no_unset 2>/dev/null

dir=${XFINDER_CREW_DIR:-}
token=${XFINDER_CREW_TOKEN:-}
me=${XFINDER_CREW_ROLE:-}
if [[ -z $dir || -z $token || -z $me || ! -d $dir/inbox || ! -r $dir/roster.txt ]]; then
  print -u2 "xfinder-crew: this session is not part of an XFinder crew."
  exit 1
fi
v2=0
[[ -e $dir/v2 ]] && v2=1

usage() {
  print -u2 "usage: xfinder-crew who"
  print -u2 "       xfinder-crew send <role|all> <message>"
  if (( v2 )); then
    print -u2 "       xfinder-crew send <role|all> --task \"<what>\" --criteria \"<acceptance>\" [--branch crew/...] [note]"
    print -u2 "       xfinder-crew status <role|all> <message>"
    print -u2 "       xfinder-crew done --branch crew/... --tests \"<what you ran>\" [note]"
    print -u2 "       xfinder-crew verdict approved|rejected --branch crew/... --note \"<file:line and why>\""
    print -u2 "       xfinder-crew conflict --branch crew/... --note \"<file>\""
    print -u2 "       xfinder-crew merge --branch crew/..."
  fi
  exit 1
}

roles=(${(f)"$(/usr/bin/cut -d' ' -f1 $dir/roster.txt)"})
lead=${roles[1]}

# Control characters out (C0 except newline, DEL). Trailing newlines go with the command substitution.
clean() { print -rn -- "${1-}" | LC_ALL=C /usr/bin/tr -d '\001-\011\013-\037\177'; }
# JSON escaping of backslash and quote; newlines become \n.
esc() { print -rn -- "${1-}" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | /usr/bin/awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'; }
# One signed field: tag, UTF-8 byte count, value. Braces everywhere — an unbraced $1:$n is a zsh history modifier.
fld() { local n; n=$(print -rn -- "${2-}" | /usr/bin/wc -c | /usr/bin/tr -d ' '); print -rn -- "${1}:${n}:${2-}"; }

check_role() {
  if [[ $1 != all && ${roles[(Ie)$1]} -eq 0 ]]; then
    print -u2 "xfinder-crew: no crewmate called \"$1\". The crew:"
    /bin/cat $dir/roster.txt >&2
    exit 1
  fi
}

too_long() {
  local s=${1-}
  if (( ${#s} > 8000 )); then
    print -u2 "xfinder-crew: a field is longer than 8000 characters (${#s}). Shorten it or point to a file."
    exit 1
  fi
}

paused_note() {
  if [[ -e $dir/paused ]]; then
    print "Sent to $1. The crew is paused; it will be delivered when the person resumes it."
  else
    print "Sent to $1. $2"
  fi
}

# v2: write one signed envelope. Arguments: to kind text task criteria branch verdict tests.
emit_v2() {
  local to=$1 kind=$2 text=$3 task=$4 criteria=$5 branch=$6 verdict=$7 tests=$8
  local name at tmp canon mac
  name="$(/bin/date +%s)-$$-$RANDOM.json"
  at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="${dir}/inbox/.${name}.tmp"
  canon="$(fld name "$name")"$'\n'"$(fld from "$me")"$'\n'"$(fld to "$to")"$'\n'"$(fld kind "$kind")"$'\n'"$(fld text "$text")"$'\n'"$(fld task "$task")"$'\n'"$(fld criteria "$criteria")"$'\n'"$(fld branch "$branch")"$'\n'"$(fld verdict "$verdict")"$'\n'"$(fld tests "$tests")"$'\n'"$(fld at "$at")"
  mac=$(print -rn -- "${canon}"$'\n'"${token}" | /usr/bin/shasum -a 256 | /usr/bin/cut -d' ' -f1)
  [[ ${#mac} -eq 64 ]] || exit 1
  print -rn -- "{\"v\":2,\"from\":\"$(esc "$me")\",\"to\":\"$(esc "$to")\",\"kind\":\"$(esc "$kind")\",\"text\":\"$(esc "$text")\",\"task\":\"$(esc "$task")\",\"criteria\":\"$(esc "$criteria")\",\"branch\":\"$(esc "$branch")\",\"verdict\":\"$(esc "$verdict")\",\"tests\":\"$(esc "$tests")\",\"at\":\"${at}\",\"mac\":\"${mac}\"}" > $tmp || exit 1
  /bin/mv -f $tmp "$dir/inbox/$name" || exit 1
}

verb=${1:-}
(( $# >= 1 )) && shift
typeset -A opts
zparseopts -D -E -A opts -- -task: -criteria: -branch: -tests: -note: 2>/dev/null
opt() { local v=${opts[$1]-}; print -rn -- "${v#=}"; }     # `--task=x` arrives as `=x`

case $verb in
  who)
    /bin/cat $dir/roster.txt
    exit 0
    ;;
  send)
    (( $# >= 1 )) || usage
    to=$1; shift
    check_role "$to"
    note=$(clean "$*")
    if (( v2 )); then
      task=$(clean "$(opt --task)"); criteria=$(clean "$(opt --criteria)"); branch=$(clean "$(opt --branch)")
      too_long "$note"; too_long "$task"; too_long "$criteria"
      if [[ -n ${task//[[:space:]]/} ]]; then
        if [[ -z ${criteria//[[:space:]]/} ]]; then
          print -u2 "xfinder-crew: a work request needs --criteria as well as --task (how it will be accepted)."
          exit 1
        fi
        [[ -z $branch || $branch == crew/* ]] || { print -u2 "xfinder-crew: --branch must start with crew/."; exit 1; }
        emit_v2 "$to" task "$note" "$task" "$criteria" "$branch" "" ""
        paused_note "$to" "XFinder hands it over in the TASK / CRITERIA / BRANCH format; the answer arrives later as a message starting with [crew]."
        exit 0
      fi
      if [[ -z ${note//[[:space:]]/} ]]; then print -u2 "xfinder-crew: the message is empty."; exit 1; fi
      emit_v2 "$to" question "$note" "" "" "" "" ""
      paused_note "$to" "The reply will arrive later as a message starting with [crew]."
      exit 0
    fi
    # v1 (every other crew): free text, unchanged.
    if [[ -z ${note//[[:space:]]/} ]]; then
      print -u2 "xfinder-crew: the message is empty."
      exit 1
    fi
    if (( ${#note} > 8000 )); then
      print -u2 "xfinder-crew: the message is longer than 8000 characters (${#note}). Shorten it or point to a file."
      exit 1
    fi
    name="$(/bin/date +%s)-$$-$RANDOM.json"
    tmp="$dir/inbox/.$name.tmp"
    mac=$(print -rn -- "$name"$'\n'"$to"$'\n'"$note"$'\n'"$token" | /usr/bin/shasum -a 256 | /usr/bin/cut -d' ' -f1)
    [[ ${#mac} -eq 64 ]] || exit 1
    print -rn -- "{\"from\":\"$(esc "$me")\",\"to\":\"$(esc "$to")\",\"text\":\"$(esc "$note")\",\"mac\":\"$mac\"}" > $tmp || exit 1
    /bin/mv -f $tmp "$dir/inbox/$name" || exit 1
    paused_note "$to" "The reply will arrive later as a message starting with [crew]."
    exit 0
    ;;
  status|done|verdict|conflict|merge)
    if (( ! v2 )); then
      print -u2 "xfinder-crew: this crew has no \"$verb\" verb — use: xfinder-crew send <role> <message>."
      exit 1
    fi
    branch=$(clean "$(opt --branch)")
    if [[ $verb != status && $branch != crew/* ]]; then
      print -u2 "xfinder-crew: $verb needs --branch crew/<...> (the branch it is about)."
      exit 1
    fi
    case $verb in
      status)
        (( $# >= 2 )) || usage
        to=$1; shift
        check_role "$to"
        text=$(clean "$*"); too_long "$text"
        [[ -n ${text//[[:space:]]/} ]] || { print -u2 "xfinder-crew: the message is empty."; exit 1; }
        emit_v2 "$to" status "$text" "" "" "" "" ""
        paused_note "$to" "No answer is expected."
        ;;
      done)
        tests=$(clean "$(opt --tests)"); text=$(clean "$*"); too_long "$tests"; too_long "$text"
        [[ -n ${tests//[[:space:]]/} ]] || { print -u2 "xfinder-crew: done needs --tests \"<what you ran and the result>\"."; exit 1; }
        emit_v2 "$lead" done "$text" "" "" "$branch" "" "$tests"
        paused_note "$lead" "XFinder now asks security and reviewer to judge the branch; their verdicts go to the lead."
        ;;
      verdict)
        (( $# >= 1 )) || usage
        v=$1; shift
        [[ $v == approved || $v == rejected ]] || { print -u2 "xfinder-crew: the verdict is approved or rejected."; exit 1; }
        note=$(clean "$(opt --note)"); too_long "$note"
        if [[ $v == rejected && -z ${note//[[:space:]]/} ]]; then
          print -u2 "xfinder-crew: a rejection needs --note with file:line and why."
          exit 1
        fi
        emit_v2 "$lead" verdict "$note" "" "" "$branch" "$v" ""
        paused_note "$lead" "The lead and, on a rejection, the builder are told."
        ;;
      conflict)
        note=$(clean "$(opt --note)"); too_long "$note"
        [[ -n ${note//[[:space:]]/} ]] || { print -u2 "xfinder-crew: conflict needs --note (the file or area)."; exit 1; }
        emit_v2 "$lead" conflict "$note" "" "" "$branch" "" ""
        paused_note "$lead" "The lead decides."
        ;;
      merge)
        emit_v2 all merge "" "" "" "$branch" "" ""
        paused_note all "XFinder answers in a [crew] message whether the merge is allowed; the git merge itself still asks the person."
        ;;
    esac
    exit 0
    ;;
  *)
    usage
    ;;
esac
