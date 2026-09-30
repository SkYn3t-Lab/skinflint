#!/usr/bin/env python3
"""Time every hook of several Claude Code plugins, the way Claude Code runs them.

  python3 benchmarks/speed.py NAME=PLUGIN_DIR [NAME=PLUGIN_DIR ...]

Each plugin's own hook commands are read from its manifest and run with
`sh -c`, as Claude Code does on Linux and macOS, with the payload Claude Code
would send on stdin. Every call gets its own configuration directory, prepared
outside the timing: for prompt and subagent calls, a copy of the state the
plugin's own session-start hook left (so its mode is set, as in a real
session); for tool output, an empty one, so no plugin's duplicate detection
takes a shortcut. chisle's on-flag is set in both, since it trims only then.
Rounds are interleaved: each round runs every plugin once, in a rotating
order, so load on the machine falls on all of them alike. Prints the median in
milliseconds; "-" means the plugin has no hook for that event, and a trailing
"!" means the call failed. A hook that ran but printed nothing (by design,
for some plugins) is listed under the table.
"""
import json, os, re, shutil, statistics, subprocess, sys, tempfile, time

ROUNDS = int(os.environ.get('SPEED_ROUNDS', '15'))

def hooks_of(root):
    m = json.load(open(os.path.join(root, '.claude-plugin', 'plugin.json')))
    h = m.get('hooks')
    if isinstance(h, str):
        h = json.load(open(os.path.join(root, h)))
    if h is None:
        h = json.load(open(os.path.join(root, 'hooks', 'hooks.json')))
    return h.get('hooks', h)

def command_for(hooks, event, key):
    for entry in hooks.get(event, []):
        matcher = entry.get('matcher')
        if matcher in (None, '', '*') or re.fullmatch(matcher, key):
            return entry['hooks'][0]['command']
    return None

def log(n):
    return '\n'.join('2026-09-30T12:00:%02dZ INFO compiling module %d of the build: ok' % (i % 60, i) for i in range(n))

def tool(text, sid):
    return {'session_id': sid, 'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_use_id': 'toolu_' + sid,
            'tool_input': {'command': 'make'}, 'tool_response': {'stdout': text, 'stderr': ''}}

minjson = json.dumps([{'id': i, 'name': 'item %d' % i, 'tags': ['a', 'b', 'c'], 'ok': True} for i in range(2600)])
CASES = [  # column, event, matcher key, payload, must print something
    ('startup', 'SessionStart', 'startup', {'session_id': 's1', 'hook_event_name': 'SessionStart', 'source': 'startup'}, True),
    ('prompt', 'UserPromptSubmit', '', {'session_id': 's1', 'hook_event_name': 'UserPromptSubmit', 'prompt': 'how do I reverse a list in Python?'}, True),
    ('subagent', 'SubagentStart', '', {'session_id': 's1', 'hook_event_name': 'SubagentStart', 'agent_type': 'general-purpose'}, True),
    ('30 KB log', 'PostToolUse', 'Bash', tool(log(480), 's2'), False),
    ('150 KB log', 'PostToolUse', 'Bash', tool(log(2400), 's3'), False),
    ('150 KB JSON', 'PostToolUse', 'Bash', tool(minjson, 's4'), False),
]

TEMPLATES = {}

def template(name, root, data):
    # The state a session is in after the plugin's own SessionStart hook ran.
    if name not in TEMPLATES:
        t = tempfile.mkdtemp(prefix='speed-tpl-')
        open(os.path.join(t, '.chisle-active'), 'w').write('on')
        cmd = command_for(hooks_of(root), 'SessionStart', 'startup')
        if cmd:
            env = dict(os.environ, CLAUDE_CONFIG_DIR=t, HOME=t, CLAUDE_PLUGIN_ROOT=root, CLAUDE_PLUGIN_DATA=data,
                       CLAUDE_PROJECT_DIR=t)
            subprocess.run(['sh', '-c', cmd], input=json.dumps(CASES[0][3]).encode(), capture_output=True, env=env, cwd=t)
        TEMPLATES[name] = t
    return TEMPLATES[name]

def run(cmd, root, data, payload, start=None):
    cfg = tempfile.mkdtemp(prefix='speed-')
    if start:
        shutil.copytree(start, cfg, dirs_exist_ok=True)
    open(os.path.join(cfg, '.chisle-active'), 'w').write('on')
    env = dict(os.environ, CLAUDE_CONFIG_DIR=cfg, HOME=cfg, CLAUDE_PLUGIN_ROOT=root, CLAUDE_PLUGIN_DATA=data,
               CLAUDE_PROJECT_DIR=cfg)
    t = time.perf_counter()
    r = subprocess.run(['sh', '-c', cmd], input=payload, capture_output=True, env=env, cwd=cfg)
    ms = (time.perf_counter() - t) * 1000
    shutil.rmtree(cfg, ignore_errors=True)
    return ms, r

plugins = [a.split('=', 1) for a in sys.argv[1:]]
data = tempfile.mkdtemp(prefix='speed-data-')
table = {}
silent = []
for col, event, key, payload, must in CASES:
    body = json.dumps(payload).encode()
    cmds = {n: command_for(hooks_of(d), event, key) for n, d in plugins}
    live = [(n, d) for n, d in plugins if cmds[n]]
    start = {n: (template(n, d, data) if event in ('UserPromptSubmit', 'SubagentStart') else None) for n, d in live}
    samples = {n: [] for n, _ in live}
    bad = {}
    for n, d in live:                      # warm-up, and the correctness check
        _, r = run(cmds[n], d, data, body, start[n])
        bad[n] = r.returncode != 0
        if must and not r.stdout.strip():
            silent.append('%s %s' % (n, col))
        if os.environ.get('SPEED_SHOW'):
            print(n, col, 'rc', r.returncode, 'out', r.stdout[:120], file=sys.stderr)
    for rnd in range(ROUNDS):
        for j in range(len(live)):
            n, d = live[(j + rnd) % len(live)]
            samples[n].append(run(cmds[n], d, data, body, start[n])[0])
    for n, _ in plugins:
        table.setdefault(n, {})[col] = ('%.0f%s' % (statistics.median(samples[n]), '!' if bad[n] else '')) if n in samples else '-'
shutil.rmtree(data, ignore_errors=True)
for t in TEMPLATES.values():
    shutil.rmtree(t, ignore_errors=True)

cols = [c[0] for c in CASES]
print('| ms, median of %d | %s |' % (ROUNDS, ' | '.join(cols)))
print('|---|' + '--:|' * len(cols))
for n, _ in plugins:
    print('| %s | %s |' % (n, ' | '.join(table[n][c] for c in cols)))
if silent:
    print('\nRan but printed nothing: ' + ', '.join(silent))
