#!/bin/sh
# Runs one skinflint hook with awk: activate (SessionStart), prompt
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
state=$dir/skinflint
[ -d "$state/spill" ] || mkdir -p "$state/sessions" "$state/spill" 2>/dev/null
[ -d "$state/sessions" ] && [ -w "$state/sessions" ] && SF_W=1
[ -d "$state/spill" ] && [ -w "$state/spill" ] && SF_WS=1
[ -e "$state/stats" ] && SF_STATS=1

cfg=${XDG_CONFIG_HOME:-${HOME:-}/.config}/skinflint/config.json
[ -f "$cfg" ] && [ -r "$cfg" ] && SF_CFG=$cfg
[ -f .claude/skinflint.json ] && [ -r .claude/skinflint.json ] && SF_PC=.claude/skinflint.json
[ -f .claude/settings.local.json ] && [ -r .claude/settings.local.json ] && SF_S1=.claude/settings.local.json
[ -f .claude/settings.json ] && [ -r .claude/settings.json ] && SF_S2=.claude/settings.json
[ -f "$dir/settings.json" ] && [ -r "$dir/settings.json" ] && SF_S3=$dir/settings.json

# busybox awk needs its big-string work done in pieces (see skinflint.awk). Found
# with builtins only: the first awk on PATH, compared by inode.
SF_BB=
oifs=$IFS; IFS=:
for d in $PATH; do
  if [ -x "${d:-.}/awk" ]; then
    { [ "${d:-.}/awk" -ef /bin/busybox ] || [ "${d:-.}/awk" -ef /usr/bin/busybox ]; } && SF_BB=1
    break
  fi
done
IFS=$oifs

SF_HOOK=$1 SF_ROOT=$root SF_STATE=$state SF_CLAUDE_DIR=$dir
export SF_HOOK SF_ROOT SF_STATE SF_CLAUDE_DIR SF_W SF_WS SF_STATS SF_CFG SF_PC SF_S1 SF_S2 SF_S3 SF_BB

if [ "${SKINFLINT_DEBUG:-}" = 1 ]; then awk -f "$root/hooks/lib/skinflint.awk"
else awk -f "$root/hooks/lib/skinflint.awk" 2>/dev/null; fi

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
