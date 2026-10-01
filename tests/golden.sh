#!/bin/sh
# Replays tests/cases/* through the POSIX hooks and compares stdout and the
# files left behind with each case's "expected" and "state". Needs only sh and
# the POSIX tools the hooks themselves use.
#   sh tests/golden.sh            check every case
#   sh tests/golden.sh --record   (re)write expected and state
#   sh tests/golden.sh NAME...    check only these cases
# Each case runs through the hook line from plugin.json with sh -c, as Claude
# Code runs it. Paths in output are normalised: the sandbox becomes <SB>, the
# plugin <ROOT>.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
record=0
[ "${1:-}" = --record ] && { record=1; shift; }

sh "$root/tools/stamp.sh" --check || exit 1

# The hooks must not see settings from the environment running the tests.
for v in $(env | sed -n 's/^\(SKINFLINT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset CLAUDE_PLUGIN_DATA

state_of() { # $1 = sandbox: one line per file under cfg/, sorted bytewise
  (cd "$1" && find cfg -type f | LC_ALL=C sort | while IFS= read -r f; do
    case $f in
      *.mode|*/stats) c=$(awk 'BEGIN { RS = "\001" } { gsub(/\n/, "\\n"); printf "%s", $0 }' "$f") ;;
      *) c= ;;
    esac
    printf '%s %s %s\n' "$f" "$(wc -c < "$f" | tr -d ' ')" "$c"
  done)
}

pass=0; fail=0
if [ $# -gt 0 ]; then list=$*; else list=$(cd "$here/cases" && ls); fi
for name in $list; do
  c=$here/cases/$name
  sb=$(mktemp -d)
  mkdir -p "$sb/cfg" "$sb/xdg" "$sb/work"
  [ -d "$c/setup" ] && cp -R "$c/setup/." "$sb/"
  out=$(
    export CLAUDE_CONFIG_DIR="$sb/cfg" XDG_CONFIG_HOME="$sb/xdg" CLAUDE_PLUGIN_ROOT="$root"
    if [ -f "$c/env" ]; then while IFS= read -r kv; do export "$kv"; done < "$c/env"; fi
    export CLAUDE_PLUGIN_DATA="$sb/data"
    cd "$sb/work" && sh -c "$(sh "$root/tools/stamp.sh" --line "$(cat "$c/hook")")" < "$c/input.json"
    printf x
  )
  out=${out%x}
  got=$(printf '%s' "$out" | sed "s|$sb|<SB>|g; s|$root|<ROOT>|g"; printf x); got=${got%x}
  # stats counts bytes saved, which depends on how long the sandbox path in
  # the output is: count it as if each occurrence were the 4 bytes of <SB>.
  n=$(printf '%s' "$out" | LC_ALL=C awk -v s="$sb" '{ while ((i = index($0, s))) { c++; $0 = substr($0, i + length(s)) } } END { print c + 0 }')
  d=$((n * ($(printf '%s' "$sb" | LC_ALL=C wc -c) - 4)))
  st=$(state_of "$sb" | LC_ALL=C awk -v d="$d" '/^cfg\/skinflint\/stats / { sub(/saved [0-9]+/, "saved " (substr($0, index($0, "saved ") + 6) + d)) } { print }'; printf x); st=${st%x}
  rm -rf "$sb"
  if [ $record = 1 ]; then
    printf '%s' "$got" > "$c/expected"
    printf '%s' "$st" > "$c/state"
    pass=$((pass + 1)); continue
  fi
  exp=$(cat "$c/expected"; printf x); exp=${exp%x}
  exs=$(cat "$c/state"; printf x); exs=${exs%x}
  if [ "$got" = "$exp" ] && [ "$st" = "$exs" ]; then pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL $name"
    [ "$got" = "$exp" ] || echo "  stdout differs"
    [ "$st" = "$exs" ] || { echo "  state differs:"; printf '%s' "$st" | sed 's/^/    got /'; printf '%s' "$exs" | sed 's/^/    exp /'; }
  fi
done
if [ $record = 1 ]; then echo "recorded $pass cases"; exit 0; fi
echo "$((pass + fail)) cases, $pass pass, $fail fail"
[ $fail = 0 ]
