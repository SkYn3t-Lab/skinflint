#!/usr/bin/env python3
"""Analyse a run-arms.sh output directory.

  python3 benchmarks/analyze-arms.py RUNDIR [GRADES.json] [--json OUT.json]

Per arm, as a percentage of the no-plugin arm's output tokens (lower is
better): the total over all tasks, the average per task, the worst single
task, and backfires (tasks where the arm wrote MORE than no plugin). Also
split by kind (coding, explain) and by size (short, long), and per task.
With GRADES.json, the share of answers graded correct per arm.
"""
import glob, json, os, re, statistics as st, sys

rundir = sys.argv[1]
grades = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else {}
here = os.path.dirname(os.path.abspath(__file__))
tasks = {}
for line in open(os.path.join(here, 'tasks.tsv')):
    if line.strip():
        i, kind, size, prompt = line.rstrip('\n').split('\t')
        tasks[i] = (kind, size, prompt)

cells = {}   # (task, arm) -> list of output tokens
for f in glob.glob(os.path.join(rundir, '*__*__*.json')):
    t, arm, rep = os.path.basename(f)[:-5].split('__')
    d = json.load(open(f))
    if d.get('is_error'):
        continue
    cells.setdefault((t, arm), []).append(d['usage']['output_tokens'])
arms = sorted({a for _, a in cells}, key=lambda a: (a != 'none', a != 'token-miser', a))
base = {t: st.mean(cells[(t, 'none')]) for t in tasks if (t, 'none') in cells}

def mean(t, a): return st.mean(cells[(t, a)]) if (t, a) in cells else None

def stats(arm, sel):
    ts = [t for t in sel if t in base and mean(t, arm) is not None]
    if not ts:
        return None
    ratio = {t: mean(t, arm) / base[t] for t in ts}
    return {'n': len(ts), 'total_pct': round(100 * sum(mean(t, arm) for t in ts) / sum(base[t] for t in ts)),
            'avg_pct': round(100 * st.mean(ratio.values())), 'worst_pct': round(100 * max(ratio.values())),
            'worst_task': max(ratio, key=ratio.get), 'backfires': sum(r > 1 for r in ratio.values())}

out = {'arms': arms, 'overall': {}, 'by_kind': {}, 'by_size': {}, 'per_task': {}, 'correct': {}}
allt = list(tasks)
for a in arms:
    out['overall'][a] = stats(a, allt)
    for k in ('coding', 'explain'):
        out['by_kind'].setdefault(k, {})[a] = stats(a, [t for t in allt if tasks[t][0] == k])
    for s in ('short', 'long'):
        out['by_size'].setdefault(s, {})[a] = stats(a, [t for t in allt if tasks[t][1] == s])
    for kk in ('coding', 'explain'):
        for s in ('short', 'long'):
            out['by_size'].setdefault(kk + '/' + s, {})[a] = stats(a, [t for t in allt if tasks[t][0] == kk and tasks[t][1] == s])
    if grades:
        g = [v for key, v in grades.items() if key.split('__')[1] == a]
        out['correct'][a] = '%d/%d' % (sum(g), len(g))
for t in allt:
    out['per_task'][t] = {a: (round(100 * mean(t, a) / base[t]) if mean(t, a) is not None and t in base else None) for a in arms}
    out['per_task'][t]['baseline_tokens'] = round(base.get(t, 0))

def row(label, d):
    return '%-16s' % label + ''.join('%14s' % ('-' if d.get(a) is None else '%d%% w%d b%d' % (d[a]['total_pct'], d[a]['worst_pct'], d[a]['backfires'])) for a in arms)
print('%-16s' % '' + ''.join('%14s' % a for a in arms))
print(row('all', out['overall']))
for k in ('coding', 'explain', 'short', 'long', 'coding/short', 'coding/long', 'explain/short', 'explain/long'):
    print(row(k, out['by_kind'].get(k) or out['by_size'].get(k)))
print('\nper task (%% of none; baseline tokens):')
for t in allt:
    print('%-14s %5s  ' % (t, out['per_task'][t]['baseline_tokens']) + ''.join('%8s' % out['per_task'][t].get(a) for a in arms[1:]))
if grades:
    print('\ncorrect:', out['correct'])
if '--json' in sys.argv:
    json.dump(out, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
