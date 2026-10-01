#!/usr/bin/env python3
"""Replay real tool results from Claude Code transcripts through output
compressors and measure what each removes.

  python3 benchmarks/replay.py --out RESULT.json \
      --arm skinflint='sh /path/to/skinflint/hooks/run.sh compress' \
      --arm other='node /path/to/other/compress.js' \
      ~/.claude/projects

Every successful tool call in the transcripts becomes the PostToolUse payload
Claude Code would have sent (tool name, input, id, session, and the stored
tool result). Sessions are replayed in order, so duplicate detection sees
what it would have seen live. Each arm runs in its own throwaway config
directory, deleted afterwards. Only totals are written: no transcript text.

Size is measured as the JSON of the tool result before and after, and tokens
are estimated at 4 bytes each.

Results Claude Code saved to disk (`persistedOutputPath`) are left out for
every arm: the model was shown only a short preview of those, so the stored
text is not what it read, and counting it would credit an arm for cutting
bytes the model never received. The number left out is reported.
"""
import argparse, glob, json, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('--out', required=True)
ap.add_argument('--arm', action='append', required=True, help='name=command')
ap.add_argument('--workers', type=int, default=4)
ap.add_argument('--tools', default='Bash,PowerShell,Agent,Task,WebFetch,WebSearch,Grep,Glob')
ap.add_argument('dirs', nargs='+')
a = ap.parse_args()
arms = [x.split('=', 1) for x in a.arm]
tools = set(a.tools.split(','))

persisted = [0]

def payloads(path):
    uses, out = {}, []
    for line in open(path, encoding='utf-8', errors='replace'):
        try:
            d = json.loads(line)
        except Exception:
            continue
        msg = d.get('message') or {}
        content = msg.get('content') if isinstance(msg.get('content'), list) else []
        if d.get('type') == 'assistant':
            for b in content:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    uses[b.get('id')] = (b.get('name'), b.get('input'))
        elif d.get('type') == 'user' and 'toolUseResult' in d:
            for b in content:
                if not (isinstance(b, dict) and b.get('type') == 'tool_result') or b.get('is_error'):
                    continue
                name, inp = uses.get(b.get('tool_use_id'), (None, None))
                r = d['toolUseResult']
                if isinstance(r, dict) and 'persistedOutputPath' in r:
                    persisted[0] += 1
                    continue
                if name and (name in tools or name.startswith('mcp__')):
                    out.append({'session_id': d.get('sessionId', 'replay'), 'tool_name': name,
                                'tool_input': inp if isinstance(inp, dict) else {},
                                'tool_use_id': b.get('tool_use_id'), 'tool_response': d['toolUseResult'],
                                'hook_event_name': 'PostToolUse'})
    return out

def size(v):
    return len(json.dumps(v, ensure_ascii=False).encode('utf-8'))

def run_session(job):
    path = job
    items = payloads(path)
    res = {name: [0, 0, 0] for name, _ in arms}   # before, after, changed
    for name, cmd in arms:
        cfg = tempfile.mkdtemp(prefix='replay-')
        # chisle trims only while its on-flag file exists; skinflint is on by default.
        open(os.path.join(cfg, '.chisle-active'), 'w').write('on')
        env = dict(os.environ, CLAUDE_CONFIG_DIR=cfg, HOME=cfg)
        for p in items:
            before = size(p['tool_response'])
            r = subprocess.run(cmd, shell=True, input=json.dumps(p, ensure_ascii=False).encode(),
                               capture_output=True, env=env, cwd=cfg, timeout=60)
            after = before
            try:
                o = json.loads(r.stdout.decode('utf-8', 'replace'))['hookSpecificOutput']['updatedToolOutput']
                after = size(o)
            except Exception:
                pass
            res[name][0] += before; res[name][1] += after; res[name][2] += after < before
        shutil.rmtree(cfg, ignore_errors=True)
    return len(items), res

files = sorted(f for d in a.dirs for f in glob.glob(os.path.join(os.path.expanduser(d), '**', '*.jsonl'), recursive=True))
tot = {name: [0, 0, 0] for name, _ in arms}
n = 0
with ThreadPoolExecutor(a.workers) as ex:
    for i, (k, res) in enumerate(ex.map(run_session, files)):
        n += k
        for name in res:
            for j in range(3):
                tot[name][j] += res[name][j]
        if i % 50 == 0:
            print('%d/%d sessions, %d tool results' % (i + 1, len(files), n), file=sys.stderr)
summary = {'sessions': len(files), 'tool_results': n, 'persisted_left_out': persisted[0],
           'arms': {name: {'bytes_before': b, 'bytes_after': af, 'results_changed': c,
                           'saved_pct': round(100 * (1 - af / b), 1) if b else 0,
                           'tokens_saved_est': (b - af) // 4} for name, (b, af, c) in tot.items()}}
json.dump(summary, open(a.out, 'w'), indent=1)
print(json.dumps(summary, indent=1))
