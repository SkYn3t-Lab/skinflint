#!/bin/sh
# Status line: token-miser's mode for this session and the output it has saved.
#   "statusLine": {"type": "command", "command": "sh \"<plugin root>/hooks/statusline.sh\""}
# Prints only fixed text and digits read from our own state files, so nothing
# a file holds can reach the terminal as an escape sequence.

input=$(cat)
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/token-miser"

sid=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_-]\{1,128\}\)".*/\1/p' | head -n 1)
mode=
if [ -n "$sid" ] && [ -f "$dir/sessions/$sid.mode" ] && [ ! -L "$dir/sessions/$sid.mode" ]; then
  mode=$(head -c 8 "$dir/sessions/$sid.mode" | tr -cd 'onf')
fi
if [ "$mode" != on ] && [ "$mode" != off ]; then
  mode=$(printf '%s' "${TOKEN_MISER_DEFAULT_MODE:-on}" | tr 'A-Z' 'a-z')
  [ "$mode" = off ] || mode=on
fi

saved=
if [ -f "$dir/stats" ] && [ ! -L "$dir/stats" ]; then
  saved=$(sed -n 's/^saved \([0-9]\{1,15\}\)$/\1/p' "$dir/stats" | head -n 1)
fi
extra=
if [ -n "$saved" ]; then
  tok=$((saved / 4))
  if [ "$tok" -ge 1000000 ]; then extra=" saved ~$((tok / 1000000))M tok"
  elif [ "$tok" -ge 1000 ]; then extra=" saved ~$((tok / 1000))k tok"
  elif [ "$tok" -gt 0 ]; then extra=" saved ~$tok tok"; fi
fi

if [ "$mode" = on ]; then printf '\033[38;5;172m[TOKEN-MISER]\033[0m%s' "$extra"
else printf '\033[2m[token-miser off]\033[0m%s' "$extra"; fi
