#!/bin/bash
# Grade every answer in a run-arms.sh output directory with a separate
# `claude -p` judge that sees only the question and the answer, never which
# arm wrote it. Output: GRADES.json mapping cell name -> true/false, and
# OUTDIR/grades/<cell>.txt with the judge's one-line reason.
#
#   bash benchmarks/grade.sh RUNDIR GRADES.json [MODEL]
set -u
here=$(cd "$(dirname "$0")" && pwd)
run=${1:?usage: grade.sh RUNDIR GRADES.json [MODEL]}
res=${2:?usage: grade.sh RUNDIR GRADES.json [MODEL]}
model=${3:-claude-sonnet-5-5}
mkdir -p "$run/grades"
iso=$(mktemp -d)
trap 'rm -rf "$iso"' EXIT
cp "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" "$iso/"
chmod 600 "$iso/.credentials.json"

grade() { # cell json file
  local f=$1 name g
  name=$(basename "$f" .json); g="$run/grades/$name.txt"
  [ -s "$g" ] && return
  python3 - "$f" "$here/tasks.tsv" > "$iso/$name.prompt" <<'EOF'
import json, sys
f, tasks = sys.argv[1], sys.argv[2]
tid = f.rsplit('/', 1)[-1].split('__')[0]
q = next(l.rstrip('\n').split('\t')[3] for l in open(tasks) if l.startswith(tid + '\t'))
a = json.load(open(f))['result']
print('You are grading an answer from a coding assistant. Judge only correctness and completeness for what was asked, not length or style.\n')
print('QUESTION:\n' + q + '\n\nANSWER:\n' + a + '\n')
print('Is the answer technically correct, and does it give the user what they asked for (for code requests: working code that solves it)? '
      'Reply with exactly PASS or FAIL on the first line, then one sentence explaining why.')
EOF
  ( cd "$iso" && timeout 300 env HOME="$iso" CLAUDE_CONFIG_DIR="$iso" claude -p "$(cat "$iso/$name.prompt")" --model "$model" </dev/null ) > "$g.tmp" 2>/dev/null
  # Only a verdict counts: an error or limit message is not a grade.
  if head -1 "$g.tmp" 2>/dev/null | grep -qiE '^[[:space:]]*(PASS|FAIL)'; then mv "$g.tmp" "$g"
  else rm -f "$g.tmp"; echo "  failed $name"; fi
}

n=0
for f in "$run"/*__*__*.json; do
  grade "$f" &
  n=$((n + 1)); [ $((n % 5)) = 0 ] && wait
done
wait
python3 - "$run/grades" "$res" <<'EOF'
import glob, json, os, sys
g = {os.path.basename(f)[:-4]: open(f).read().lstrip().upper().startswith('PASS') for f in glob.glob(sys.argv[1] + '/*.txt')}
json.dump(g, open(sys.argv[2], 'w'), indent=1)
print('%d graded, %d pass' % (len(g), sum(g.values())))
EOF
