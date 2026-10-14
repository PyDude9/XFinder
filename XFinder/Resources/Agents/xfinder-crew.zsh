#!/bin/zsh
# XFinder crew messaging (P7b). A crew member — a windowless Claude Code session XFinder runs — calls this from its shell:
#   xfinder-crew who
#   xfinder-crew send <role|all> <message…>
# `send` writes one request into the crew's inbox and returns at once; XFinder delivers it to the crewmate and brings the
# crewmate's answer back later as a message that starts with [crew]. Nothing here waits for an answer (a shell call that
# waited for a whole turn would hit the agent's tool timeout).
# The request names its sender (XFINDER_CREW_ROLE) and signs it with the member's own token (XFINDER_CREW_TOKEN): a
# SHA-256 over file name, target, text and token. The token itself is never written to the shared inbox.
emulate -L zsh
setopt no_unset 2>/dev/null

dir=${XFINDER_CREW_DIR:-}
token=${XFINDER_CREW_TOKEN:-}
me=${XFINDER_CREW_ROLE:-}
if [[ -z $dir || -z $token || -z $me || ! -d $dir/inbox || ! -r $dir/roster.txt ]]; then
  print -u2 "xfinder-crew: this session is not part of an XFinder crew."
  exit 1
fi

usage() {
  print -u2 "usage: xfinder-crew who"
  print -u2 "       xfinder-crew send <role|all> <message>"
  exit 1
}

roles=(${(f)"$(/usr/bin/cut -d' ' -f1 $dir/roster.txt)"})

case ${1:-} in
  who)
    /bin/cat $dir/roster.txt
    exit 0
    ;;
  send)
    (( $# >= 3 )) || usage
    to=$2; shift 2
    text="$*"
    if [[ $to != all && ${roles[(Ie)$to]} -eq 0 ]]; then
      print -u2 "xfinder-crew: no crewmate called \"$to\". The crew:"
      /bin/cat $dir/roster.txt >&2
      exit 1
    fi
    # Control characters out (C0, DEL), then JSON escaping of backslash and quote; newlines become \n.
    clean=$(print -rn -- "$text" | LC_ALL=C /usr/bin/tr -d '\001-\011\013-\037\177')
    if [[ -z ${clean//[[:space:]]/} ]]; then
      print -u2 "xfinder-crew: the message is empty."
      exit 1
    fi
    if (( ${#clean} > 8000 )); then
      print -u2 "xfinder-crew: the message is longer than 8000 characters (${#clean}). Shorten it or point to a file."
      exit 1
    fi
    esc() { print -rn -- "$1" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | /usr/bin/awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'; }
    name="$(/bin/date +%s)-$$-$RANDOM.json"
    tmp="$dir/inbox/.$name.tmp"
    mac=$(print -rn -- "$name"$'\n'"$to"$'\n'"$clean"$'\n'"$token" | /usr/bin/shasum -a 256 | /usr/bin/cut -d' ' -f1)
    [[ ${#mac} -eq 64 ]] || exit 1
    print -rn -- "{\"from\":\"$(esc $me)\",\"to\":\"$(esc $to)\",\"text\":\"$(esc $clean)\",\"mac\":\"$mac\"}" > $tmp || exit 1
    /bin/mv -f $tmp "$dir/inbox/$name" || exit 1
    if [[ -e $dir/paused ]]; then
      print "Sent to $to. The crew is paused; it will be delivered when the person resumes it."
    else
      print "Sent to $to. The reply will arrive later as a message starting with [crew]."
    fi
    exit 0
    ;;
  *)
    usage
    ;;
esac
