#!/bin/sh
# Stamps the Windows build id (first 12 hex digits of the SHA-256 of
# hooks/win/skinflint.cs) into hooks/win/run.ps1, writes the hook lines of
# .claude-plugin/plugin.json, and embeds hooks/lib/skinflint.awk in
# hooks/run.sh. Run after any change to the C# or the awk source; the golden
# tests (skinflint-tests) fail while the stamp is stale.
#   sh tools/stamp.sh              rewrite
#   sh tools/stamp.sh --check      exit 1 if anything would change
#   sh tools/stamp.sh --line HOOK  print one hook line as Claude Code runs it
set -eu
cd "$(dirname "$0")/.."
if command -v sha256sum >/dev/null 2>&1; then sum=$(sha256sum hooks/win/skinflint.cs)
else sum=$(shasum -a 256 hooks/win/skinflint.cs); fi
id=$(printf '%s' "$sum" | cut -c1-12)

# One hook line serves every platform. Claude Code runs it with sh (Git Bash
# on Windows), or with PowerShell on Windows without Git Bash.
#   sh:  line 1 is a no-op group (`true` given the string `" <# "`, with no
#        command substitution, so Git Bash does not fork a subshell for it;
#        Claude Code on Windows runs it intact from Git Bash and PowerShell);
#        line 2 runs the exe if Windows has built it; line 3 is Git Bash
#        before the exe is built, where the Windows loader builds it and
#        runs the hook, so Windows has one implementation with or without
#        Git Bash (OSTYPE is set by bash, which Git's sh is); line 4 runs
#        the POSIX hook. exec means sh never reads further.
#   PowerShell: line 1 is a script block literal (never run, so no command
#        is looked up); to PowerShell `"\"` is a whole string, so the `<#`
#        after it starts a block comment over lines 1-5; line 6 loads the
#        exe into the running PowerShell and calls it, then stops. Code in
#        -Command text is not a script file, so execution policy does not
#        apply. Only when the exe is not built yet does line 7 run, which
#        builds it and runs the hook.
line() {
  exe="\${CLAUDE_PLUGIN_DATA}/skinflint-$id.exe"
  printf '%s\n' '{ true "\" <# "; } >/dev/null'
  printf '%s\n' "[ -f \"$exe\" ] && exec \"$exe\" $1"
  printf '%s\n' "case \${OSTYPE:-} in msys*|cygwin*) exec powershell -NoProfile -ExecutionPolicy Bypass -File \"\${CLAUDE_PLUGIN_ROOT}/hooks/win/run.ps1\" $1 ;; esac"
  printf '%s\n' "exec sh \"\${CLAUDE_PLUGIN_ROOT}/hooks/run.sh\" $1"
  printf '%s\n' '#> } > $null'
  printf '%s\n' "if ([IO.File]::Exists(\"$exe\")) { [void][Reflection.Assembly]::LoadFile(\"$exe\"); [void][Skinflint.Hook]::Main([string[]]@(\"$1\")); break }"
  printf '%s' "powershell -NoProfile -ExecutionPolicy Bypass -File \"\${CLAUDE_PLUGIN_ROOT}/hooks/win/run.ps1\" $1"
}

if [ "${1:-}" = --line ]; then line "$2"; exit 0; fi

# JSON string body: escape backslash and quote, newlines become \n.
json() { line "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'; }

tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.ps1" "$tmp.sh"' EXIT
cat > "$tmp" <<EOF
{
  "name": "skinflint",
  "version": "0.3.2",
  "description": "Short answers, minimal code and shorter tool output for Claude Code, with nothing to install: POSIX sh and awk on Linux and macOS, a self-built exe on Windows.",
  "author": {
    "name": "Gr3yF0x87",
    "url": "https://github.com/Gr3yF0x87"
  },
  "homepage": "https://github.com/SkYn3t-Lab/skinflint",
  "repository": "https://github.com/SkYn3t-Lab/skinflint",
  "documentationUrl": "https://github.com/SkYn3t-Lab/skinflint#readme",
  "supportUrl": "https://github.com/SkYn3t-Lab/skinflint/issues",
  "privacyPolicyUrl": "https://github.com/SkYn3t-Lab/skinflint/blob/main/PRIVACY.md",
  "termsOfServiceUrl": "https://github.com/SkYn3t-Lab/skinflint/blob/main/TERMS.md",
  "license": "MIT",
  "keywords": ["tokens", "cost", "concise", "minimal code", "tool output"],
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact|fork",
        "hooks": [
          { "type": "command", "command": "$(json activate)", "timeout": 30, "statusMessage": "Loading skinflint..." }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "$(json prompt)", "timeout": 30 }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          { "type": "command", "command": "$(json subagent)", "timeout": 30 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell|Agent|WebFetch|WebSearch|Grep|Glob|mcp__.*",
        "hooks": [
          { "type": "command", "command": "$(json compress)", "timeout": 30 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$(json stop)", "timeout": 30 }
        ]
      }
    ]
  }
}
EOF
sed "s/skinflint-[A-Za-z0-9]*\\.exe'/skinflint-$id.exe'/" hooks/win/run.ps1 > "$tmp.ps1"
# hooks/run.sh with the awk program between its two marker lines: one
# single-quoted shell string, so every apostrophe in the source becomes '\''.
# skinflint: the program is one argument to awk, and Linux allows 128 KiB per
# argument; split the program if it ever grows past that.
[ "$(wc -c < hooks/lib/skinflint.awk)" -lt 120000 ] || { echo "skinflint.awk is too large to embed as one argument" >&2; exit 1; }
{
  sed -n '1,/^# BEGIN skinflint\.awk$/p' hooks/run.sh
  printf "prog='"
  sed "s/'/'\\\\''/g" hooks/lib/skinflint.awk
  printf "'\n"
  sed -n '/^# END skinflint\.awk$/,$p' hooks/run.sh
} > "$tmp.sh"

if [ "${1:-}" = --check ]; then
  cmp -s "$tmp" .claude-plugin/plugin.json && cmp -s "$tmp.ps1" hooks/win/run.ps1 && cmp -s "$tmp.sh" hooks/run.sh && exit 0
  echo "build stamp is stale: run sh tools/stamp.sh" >&2
  exit 1
fi
cp "$tmp" .claude-plugin/plugin.json
cp "$tmp.ps1" hooks/win/run.ps1
cp "$tmp.sh" hooks/run.sh
echo "stamped $id"
