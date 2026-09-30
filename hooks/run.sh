#!/bin/sh
# Runs one token-miser hook with awk: activate (SessionStart), prompt
# (UserPromptSubmit), compress (PostToolUse) or subagent (SubagentStart).
# Everything here is a shell builtin except mkdir on first use and the two
# prune commands, so a hook costs one sh and one awk.

LC_ALL=C
export LC_ALL
umask 077

# Plugin root: set by Claude Code, else two levels up from this file.
root=${CLAUDE_PLUGIN_ROOT:-}
if [ -z "$root" ]; then
  case $0 in */*) root=${0%/*} ;; *) root=. ;; esac
  case $root in */hooks) root=${root%/hooks} ;; hooks) root=. ;; *) root=$root/.. ;; esac
fi

# Git Bash on Windows before the exe is built: the Windows loader builds it
# and runs this hook, so Windows has one implementation with or without Git
# Bash. (OSTYPE is set by bash, which Git's sh is.)
case ${OSTYPE:-} in
  msys*|cygwin*) exec powershell -NoProfile -ExecutionPolicy Bypass -File "$root/hooks/win/run.ps1" "$1" ;;
esac

dir=${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
while :; do case $dir in ?*/) dir=${dir%/} ;; *) break ;; esac; done
state=$dir/token-miser
[ -d "$state/spill" ] || mkdir -p "$state/sessions" "$state/spill" 2>/dev/null
[ -d "$state/sessions" ] && [ -w "$state/sessions" ] && TM_W=1
[ -d "$state/spill" ] && [ -w "$state/spill" ] && TM_WS=1
[ -e "$state/stats" ] && TM_STATS=1

cfg=${XDG_CONFIG_HOME:-${HOME:-}/.config}/token-miser/config.json
[ -f "$cfg" ] && [ -r "$cfg" ] && TM_CFG=$cfg
[ -f .claude/token-miser.json ] && [ -r .claude/token-miser.json ] && TM_PC=.claude/token-miser.json
[ -f .claude/settings.local.json ] && [ -r .claude/settings.local.json ] && TM_S1=.claude/settings.local.json
[ -f .claude/settings.json ] && [ -r .claude/settings.json ] && TM_S2=.claude/settings.json
[ -f "$dir/settings.json" ] && [ -r "$dir/settings.json" ] && TM_S3=$dir/settings.json

# busybox awk needs its big-string work done in pieces (see tm.awk). Found
# with builtins only: the first awk on PATH, compared by inode.
TM_BB=
oifs=$IFS; IFS=:
for d in $PATH; do
  if [ -x "${d:-.}/awk" ]; then
    { [ "${d:-.}/awk" -ef /bin/busybox ] || [ "${d:-.}/awk" -ef /usr/bin/busybox ]; } && TM_BB=1
    break
  fi
done
IFS=$oifs

TM_HOOK=$1 TM_ROOT=$root TM_STATE=$state TM_CLAUDE_DIR=$dir
export TM_HOOK TM_ROOT TM_STATE TM_CLAUDE_DIR TM_W TM_WS TM_STATS TM_CFG TM_PC TM_S1 TM_S2 TM_S3 TM_BB

if [ "${TOKEN_MISER_DEBUG:-}" = 1 ]; then awk -f "$root/hooks/lib/tm.awk"
else awk -f "$root/hooks/lib/tm.awk" 2>/dev/null; fi

case $? in
  3) # a spill file was written: keep the newest 40 once there are more than 60
    set -- "$state/spill/"*.txt
    if [ $# -gt 60 ]; then
      ls -1t "$state/spill" 2>/dev/null | sed -n '41,$p' | while IFS= read -r f; do
        case $f in *.txt) rm -f "$state/spill/$f" ;; esac
      done
    fi ;;
  4) find "$state/sessions" -type f -mtime +7 -exec rm -f {} + 2>/dev/null ;;
esac
exit 0
